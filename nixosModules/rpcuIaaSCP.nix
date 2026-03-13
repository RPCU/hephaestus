{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules.rpcuIaaSCP;

  # Kubernetes versioning
  kubeadmVersion = "v1.35.2";
  kubeletVersion = "v1.35.2";
  kubevipVersion = "v1.0.4";

  # Network configuration
  apiserverVip = "10.0.0.5";
  primaryInterface = "eno1";
  podCidr = "10.244.0.0/16";

  # Kubernetes paths
  k8sEtcDir = "/etc/kubernetes";
  k8sManifestsDir = "${k8sEtcDir}/manifests";
  k8sAdminConf = "${k8sEtcDir}/admin.conf";
  k8sSuperAdminConf = "${k8sEtcDir}/super-admin.conf";
  k8sBootstrapYaml = "${k8sEtcDir}/kubeadm/bootstrap.yaml";
  k8sJoinYamlTpl = "${k8sEtcDir}/kubeadm/join.yaml.tpl";
  k8sJoinYaml = "${k8sEtcDir}/kubeadm/join.yaml";

  # Docker image references
  kubevipImage = "ghcr.io/kube-vip/kube-vip:${kubevipVersion}";

  # Node labels (as a list for easier iteration)
  nodeLabels = [
    "openstack-control-plane=enabled"
    "openstack-compute-node=enabled"
    "openvswitch=enabled"
    "linuxbridge=enabled"
  ];

  # Cluster enablement flag
  isClusterEnabled = cfg.cluster.privateAddress != "";

  # Helper function to create label command string
  kubectlLabelCommand =
    labels: lib.concatMapStringsSep " " (label: "--overwrite nodes --all ${label}") labels;

  # Helper function to configure kubectl kubeconfig
  configureKubectl = ''
    echo "Configuring kubectl access..." >&2
    mkdir -p "$HOME/.kube"
    cp ${k8sAdminConf} "$HOME/.kube/config" 2>/dev/null
    sudo chown $(id -u):$(id -g) "$HOME/.kube/config"
  '';

  # Helper function to apply node labels
  applyNodeLabels = ''
    kubectl label ${kubectlLabelCommand nodeLabels}
    kubectl get no -o wide --show-labels
  '';

  # Keepalived VRRP configuration
  vrrpInterfaceSubnet = "${primaryInterface}.4000";
  vrrpInstanceName = "VI_1";
  vrrpRouterId = 51;
  vrrpState = "BACKUP";
  virtualIpAddress = "178.63.143.219/32";

  # Kubelet configuration paths
  kubeletBootstrapConf = "/etc/kubernetes/bootstrap-kubelet.conf";
  kubeletConf = "/etc/kubernetes/kubelet.conf";
  kubeletConfigYaml = "/var/lib/kubelet/config.yaml";
  kubeletConfigDir = "/etc/kubernetes/kubelet/config.d";

  # Kubelet arguments as a single string
  kubeletNodeLabelsString = lib.concatStringsSep "," nodeLabels;
  kubeletKubeconfigArgs = "--bootstrap-kubeconfig=${kubeletBootstrapConf} --kubeconfig=${kubeletConf} --node-ip=${cfg.cluster.privateAddress} --node-labels=${kubeletNodeLabelsString}";
  kubeletConfigArgs = "--config=${kubeletConfigYaml} --config-dir=${kubeletConfigDir}";

  installKubevip = pkgs.writeShellScriptBin "installKubevip" ''
    set -euo pipefail

    # Determine which config to use. Prefer admin.conf if it exists,
    # but fall back to super-admin.conf for initial bootstrap.
    K8S_CONFIG="${k8sAdminConf}"
    if [[ ! -f "$K8S_CONFIG" ]]; then
      K8S_CONFIG="${k8sSuperAdminConf}"
    fi

    echo "Using Kubernetes config: $K8S_CONFIG" >&2

    # Pull and configure kube-vip
    ctr image pull ${kubevipImage}
    kubevip="ctr run --rm --net-host ${kubevipImage} vip /kube-vip"

    $kubevip manifest pod \
      --interface ${primaryInterface}.4000 \
      --address ${apiserverVip} \
      --controlplane --services --arp --leaderElection \
      --k8sConfigPath="$K8S_CONFIG" | tee ${k8sManifestsDir}/kube-vip.yaml
  '';

  initKubeadm = pkgs.writeShellScriptBin "initKubeadm" ''
        set -euo pipefail

        # Display help menu
        if [[ "$\{@:-}" == *"--help"* || "$\{@:-}" == *"-h"* ]]; then
          cat << 'HELP'
    Usage: initKubeadm

    Description:
      - Deploys kubevip manifests for HA
      - Initializes the Kubernetes cluster using bootstrap.yaml
      - Filters output to display the join token and certificate key
    HELP
          exit 0
        fi

        # Setup static pods for kube-vip
        installKubevip

        # Initialize cluster and extract credentials
        echo "Initializing cluster (this may take a minute)..." >&2
        OUTPUT=$(kubeadm init --config ${k8sBootstrapYaml} --upload-certs)

        # Regenerate kube-vip manifest with admin.conf
        installKubevip

        # Extract join credentials from output
        TOKEN=$(echo "$OUTPUT" | grep -oP '(?<=--token )[^ ]+' | head -n 1)
        CERT_KEY=$(echo "$OUTPUT" | grep -oP '(?<=--certificate-key )[^ ]+' | head -n 1)

        # Configure kubectl access
        ${configureKubectl}

        # Display cluster initialization summary
        echo "--------------------------------------------------"
        echo "CLUSTER INITIALIZED SUCCESSFULLY"
        echo "--------------------------------------------------"
        echo ""

        # Apply node labels and show nodes
        echo "---"
        ${applyNodeLabels}
        echo "---"
        echo ""

        # Display join command if credentials extracted successfully
        if [[ -n "$TOKEN" && -n "$CERT_KEY" ]]; then
          echo "To join another Control Plane node, run:"
          echo ""
          echo "joinCPKubeadm $TOKEN $CERT_KEY"
        else
          echo "Error: Could not extract join credentials from kubeadm output."
          exit 1
        fi
  '';

  joinCPKubeadm = pkgs.writeShellScriptBin "joinCPKubeadm" ''
        set -euo pipefail

        # Display help if requested or if arguments are missing
        if [[ "$\{1:-}" == "--help" || "$\{1:-}" == "-h" || $# -lt 2 ]]; then
          cat << 'HELP'
    Usage: joinCPKubeadm <TOKEN> <CERTIFICATE_KEY>

    Arguments:
      TOKEN              The bootstrap token (e.g., abcdef.1234567890abcdef)
      CERTIFICATE_KEY    The hex encryption key for control-plane certificates

    Description:
      Populates the join.yaml template and joins the node to the Kubernetes
      cluster as a control-plane member.
    HELP
          exit 0
        fi

        TOKEN=$1
        CERT_KEY=$2

        # Populate join configuration from template
        echo "Populating join configuration..."
        sed -e "s/__TOKEN__/$TOKEN/g" \
            -e "s/__CERTIFICATE_KEY__/$CERT_KEY/g" \
            ${k8sJoinYamlTpl} > ${k8sJoinYaml}

        # Join cluster and setup kube-vip
        echo "Joining cluster..."
        kubeadm join --config ${k8sJoinYaml}
        installKubevip
        echo ""

        # Configure kubectl and apply labels
        ${configureKubectl}
        echo "---"
        ${applyNodeLabels}
        echo "---"
  '';
in
{
  options.customNixOSModules.rpcuIaaSCP = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the RPCU IaaS Control Plane module for Kubernetes cluster setup";
    };

    cluster = lib.mkOption {
      type = lib.types.submodule {
        options = {
          privateAddress = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Private IP address for the cluster node (enables cluster mode when set)";
          };

          primaryMacAddress = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "MAC address of the primary network interface (eno1)";
          };

          openstackMacAddress = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "MAC address of the OpenStack network interface (enp3s0)";
          };

          priority = lib.mkOption {
            type = lib.types.int;
            default = 0;
            description = "VRRP priority for keepalived cluster failover (higher = preferred)";
          };

          otherNodes = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "List of other control plane node IP addresses for cluster communication";
          };

          allNodeIps = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "List of all node IPs for API server certificate SANs";
          };
        };
      };
      default = { };
      description = "Kubernetes cluster configuration options";
    };
  };

  config = lib.mkIf cfg.enable {
    # ========== Security & User Management ==========

    security.sudo.extraRules = [
      {
        users = [ "neutron" ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    # System groups for OpenStack services
    users.groups = {
    };

    # System users for OpenStack and virtualization services
    users.users = {
    };

    # ========== Kubernetes Configuration ==========

    environment = {
      etc = {
        # Kubernetes audit policy for API server logging
        "kubernetes/audit/policy.yaml".text = ''
          apiVersion: audit.k8s.io/v1
          kind: Policy
          omitStages:
            - "RequestReceived"
            - "ResponseStarted"
            - "ResponseComplete"
          rules:
            # Capture 'create' and 'delete' operations for all resources
            - level: Metadata
              verbs: ["create", "delete"]
            # Explicitly drop all other operations (get, list, watch, patch, update)
            - level: None
        '';

        # Common kubelet configuration (all nodes)
        "kubernetes/kubelet/config.d/00-config.conf".text = ''
          kind: KubeletConfiguration
          apiVersion: kubelet.config.k8s.io/v1beta1
          maxPods: 200
          rotateCertificates: true
          imageMaximumGCAge: 720h
          imageGCLowThresholdPercent: 70
          imageGCHighThresholdPercent: 85
          featureGates:
            SidecarContainers: true
          cgroupDriver: systemd
          systemReservedCgroup: /system.slice
          enforceNodeAllocatable:
            - pods
            - system-reserved
          systemReserved:
            cpu: "1"
            memory: "2Gi"
            ephemeral-storage: "2Gi"
          evictionHard:
            memory.available: "500Mi"
            nodefs.available: "10%"
            imagefs.available: "15%"
        '';
      }
      // (lib.optionalAttrs isClusterEnabled {
        # Cluster-specific kubelet configuration (cluster nodes only)
        "kubernetes/kubelet/config.d/10-config.conf".text = ''
          kind: KubeletConfiguration
          apiVersion: kubelet.config.k8s.io/v1beta1
          address: "${cfg.cluster.privateAddress}"
        '';

        # Kubeadm bootstrap configuration for cluster initialization
        "kubernetes/kubeadm/bootstrap.yaml".text = ''
          apiVersion: kubeadm.k8s.io/v1beta3
          kind: ClusterConfiguration
          clusterName: 'openstack'
          networking:
            serviceSubnet: '10.96.0.0/20'
            podSubnet: '${podCidr}'
            dnsDomain: 'openstack.local'
          kubernetesVersion: '${kubeadmVersion}'
          controlPlaneEndpoint: '${apiserverVip}'
          apiServer:
            certSANs:
              - 'openstack.rpcu.lan'
              - '${apiserverVip}'
              ${lib.concatMapStringsSep "\n              " (ip: "- '${ip}'") cfg.cluster.allNodeIps}
            extraArgs:
              enable-admission-plugins: DefaultTolerationSeconds
              audit-policy-file: '/etc/kubernetes/audit/policy.yaml'
              audit-log-path: '/var/log/kubernetes_audit.log'
              audit-log-maxsize: '100'
              audit-log-maxbackup: '10'
              audit-log-mode: 'batch'
              audit-log-batch-max-size: '5'
            extraVolumes:
              - name: auditpolicy
                hostPath: /etc/kubernetes/audit/policy.yaml
                mountPath: /etc/kubernetes/audit/policy.yaml
          ---
          apiVersion: kubeadm.k8s.io/v1beta3
          kind: InitConfiguration
          skipPhases:
            - addon/kube-proxy
          localAPIEndpoint:
            advertiseAddress: '${cfg.cluster.privateAddress}'
            bindPort: 6443
          nodeRegistration:
            taints: []
        '';

        # Kubeadm join configuration template (cluster-specific)
        "kubernetes/kubeadm/join.yaml.tpl".text = ''
          apiVersion: kubeadm.k8s.io/v1beta3
          kind: JoinConfiguration
          nodeRegistration:
            taints: []
          controlPlane:
            localAPIEndpoint:
              advertiseAddress: '${cfg.cluster.privateAddress}'
              bindPort: 6443
            certificateKey: '__CERTIFICATE_KEY__'
          discovery:
            bootstrapToken:
              token: '__TOKEN__'
              unsafeSkipCAVerification: true
              apiServerEndpoint: "${apiserverVip}:6443"
        '';
      });

      # System packages for Kubernetes and networking
      systemPackages = [
        pkgs.dnsmasq # DNS/DHCP server
      ]
      ++ (lib.optionals isClusterEnabled [
        installKubevip
        initKubeadm
        joinCPKubeadm
      ]);
    };

    # ========== System Configuration ==========

    # Network configuration
    networking = {
      useDHCP = lib.mkDefault true;
    };

    # Enable Netbird for secure network connectivity
    services.netbird.enable = true;

    # ========== Boot Configuration ==========

    boot = {
      # Initial RAM disk configuration
      initrd = {
        # Storage and USB device support
        availableKernelModules = [
          "nvme"
          "xhci_pci"
          "usb_storage"
          "uhci_hcd"
          "ehci_pci"
          "ata_piix"
          "megaraid_sas"
          "usbhid"
          "sd_mod"
          "virtio_pci"
          "virtio_scsi"
          "sr_mod"
        ];
        # Device mapper modules for LVM
        kernelModules = [
          "dm_snapshot"
          "dm-thin-pool"
        ];
        services.lvm.enable = true;
      };

      # Kernel modules for virtualization and networking
      kernelModules = [
        "kvm-intel" # Intel KVM support
        "rbd" # Ceph RADOS block device
        "openvswitch" # Software switch for OpenStack
        "gre" # Generic Routing Encapsulation tunneling
        "vxlan" # VXLAN overlay networking
        "bridge" # Linux bridge support
        "ip6_tables" # IPv6 firewall support
        "ebtables" # Ethernet bridge filtering
      ];

      loader.systemd-boot.enable = true;
      loader.efi.canTouchEfiVariables = true;
    };

    # ========== Storage Configuration ==========

    fileSystems = {
      "/" = {
        device = "/dev/disk/by-label/ROOT";
        fsType = "ext4";
      };
      "/boot" = {
        device = "/dev/disk/by-label/BOOT";
        fsType = "vfat";
      };
      "/var" = {
        device = "/dev/disk/by-label/VAR";
        fsType = "ext4";
      };
      "/nix" = {
        device = "/dev/disk/by-label/NIX";
        fsType = "ext4";
      };
    };

    # ========== Hardware & Platform Configuration ==========

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

    hardware = {
      # Intel microcode updates
      cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

      # GPU and media acceleration
      graphics = {
        enable = true;
        extraPackages = with pkgs; [
          vpl-gpu-rt # Intel video performance library
          intel-vaapi-driver # Intel VAAPI driver
          intel-media-driver # Intel media driver
        ];
      };
    };
    systemd = {
      network = {
        links = {
          # ========== Cluster-Specific Configuration ==========
          # These configurations are only applied when a cluster private address is configured

          # Network interface naming by MAC address
          "00-eno1" = lib.mkIf isClusterEnabled {
            matchConfig.PermanentMACAddress = cfg.cluster.primaryMacAddress;
            linkConfig.Name = "eno1";
          };
          "01-enp3s0" = lib.mkIf isClusterEnabled {
            matchConfig.PermanentMACAddress = cfg.cluster.openstackMacAddress;
            linkConfig.Name = "enp3s0";
          };
        };
      };

      # Kubelet service environment variables for cluster nodes
      services.kubelet.serviceConfig.Environment = lib.mkIf isClusterEnabled (
        lib.mkForce [
          ''KUBELET_KUBECONFIG_ARGS="${kubeletKubeconfigArgs}"''
          ''KUBELET_CONFIG_ARGS="${kubeletConfigArgs}"''
        ]
      );
    };

    # Keepalived configuration for API server virtual IP (HA cluster)
    services.keepalived = lib.mkIf isClusterEnabled {
      enable = true;
      vrrpInstances."${vrrpInstanceName}" = {
        interface = vrrpInterfaceSubnet;
        state = vrrpState;
        virtualRouterId = vrrpRouterId;
        inherit (cfg.cluster) priority;
        unicastSrcIp = cfg.cluster.privateAddress;
        unicastPeers = cfg.cluster.otherNodes;
        virtualIps = [
          {
            addr = virtualIpAddress;
            dev = primaryInterface;
          }
        ];
      };
    };

    # Custom NixOS module configurations for cluster
    customNixOSModules = lib.mkIf isClusterEnabled {
      # Secure sysctl settings
      sysctlSecure.enable = true;

      # Network management and virtual switching
      networkManager = {
        enable = true;
        vswitch = {
          enable = true;
          interface = primaryInterface;
          vlans = [
            {
              vlanId = 4000;
              inherit (cfg.cluster) privateAddress;
              prefixLength = 24;
              mtu = 1400;
            }
          ];
        };
      };

      # Kubernetes deployment configuration
      kubernetes = {
        enable = true;
        version = {
          kubeadm = kubeadmVersion;
          kubelet = kubeletVersion;
        };
      };

      # Certificates and security
      caCertificates.didactiklabs.enable = true;

      # Web server and time synchronization
      ginx.enable = true;
      chrony.enable = true;
    };
  };
}
