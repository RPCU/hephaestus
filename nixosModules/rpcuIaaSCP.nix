{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules.rpcuIaaSCP;

  kubeadmVersion = "v1.35.1";
  apiserverVip = "10.0.0.5";
  primaryInterface = "eno1";
  kubevipVersion = "v1.0.4";
  podCidr = "10.244.0.0/16";

  isClusterEnabled = cfg.cluster.privateAddress != "";

  installKubevip = pkgs.writeShellScriptBin "installKubevip" ''
    set -euo pipefail

    # Determine which config to use. Prefer admin.conf if it exists, 
    # but fall back to super-admin.conf for initial bootstrap.
    K8S_CONFIG="/etc/kubernetes/admin.conf"
    if [[ ! -f "$K8S_CONFIG" ]]; then
      K8S_CONFIG="/etc/kubernetes/super-admin.conf"
    fi

    echo "Using Kubernetes config: $K8S_CONFIG" >&2

    ctr image pull ghcr.io/kube-vip/kube-vip:${kubevipVersion} ;
    kubevip="ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:${kubevipVersion} vip /kube-vip"
    $kubevip manifest pod \
      --interface ${primaryInterface}.4000 \
      --address ${apiserverVip} \
      --controlplane --services --arp --leaderElection \
      --k8sConfigPath="$K8S_CONFIG" | \
      tee /etc/kubernetes/manifests/kube-vip.yaml
  '';

  initKubeadm = pkgs.writeShellScriptBin "initKubeadm" ''
    set -euo pipefail

    # 1. Help Menu Logic
    if [[ "$\{@:-}" == *"--help"* || "$\{@:-}" == *"-h"* ]]; then
      echo "Usage: initKubeadm"
      echo ""
      echo "Description:"
      echo "  - Deploys kubevip manifests for HA."
      echo "  - Initializes the Kubernetes cluster using bootstrap.yaml."
      echo "  - Filters output to display ONLY the join token and certificate key."
      exit 0
    fi

    # 2. Setup Static Pods
    installKubevip

    # 3. Run Init and Extract Credentials
    echo "Initializing cluster (this may take a minute)..." >&2
    OUTPUT=$(kubeadm init --config /etc/kubernetes/kubeadm/bootstrap.yaml --upload-certs)

    # Regenerate kubevip manifest with the now-existing admin.conf
    installKubevip

    TOKEN=$(echo "$OUTPUT" | grep -oP '(?<=--token )[^ ]+' | head -n 1)
    CERT_KEY=$(echo "$OUTPUT" | grep -oP '(?<=--certificate-key )[^ ]+' | head -n 1)

    echo "Configuring kubectl access..." >&2
    mkdir -p "$HOME/.kube"
    cp /etc/kubernetes/admin.conf "$HOME/.kube/config" 2>/dev/null
    sudo chown $(id -u):$(id -g) "$HOME/.kube/config"

    echo "--------------------------------------------------"
    echo "CLUSTER INITIALIZED SUCCESSFULLY"
    echo "--------------------------------------------------"

    echo "---"
    kubectl label --overwrite nodes --all openstack-control-plane=enabled
    kubectl label --overwrite nodes --all openstack-compute-node=enabled
    kubectl label --overwrite nodes --all openvswitch=enabled
    kubectl label --overwrite nodes --all linuxbridge=enabled
    kubectl get no -o wide --show-labels
    echo "---"
    echo ""
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
      echo "Usage: joinCPKubeadm <TOKEN> <CERTIFICATE_KEY>"
      echo ""
      echo "Arguments:"
      echo "  TOKEN              The bootstrap token (e.g., abcdef.1234567890abcdef)"
      echo "  CERTIFICATE_KEY    The hex encryption key for control-plane certificates"
      echo ""
      echo "Description:"
      echo "  This script populates the join.yaml template and joins the node to"
      echo "  the Kubernetes cluster as a control-plane member."
      exit 0
    fi

    TOKEN=$1
    CERT_KEY=$2

    echo "Populating join configuration..."
    sed -e "s/__TOKEN__/$TOKEN/g" \
        -e "s/__CERTIFICATE_KEY__/$CERT_KEY/g" \
        /etc/kubernetes/kubeadm/join.yaml.tpl > /etc/kubernetes/kubeadm/join.yaml

    echo "Joining cluster..."
    kubeadm join --config /etc/kubernetes/kubeadm/join.yaml
    installKubevip
    echo ""
    echo "Configuring kubectl access..." >&2
    mkdir -p "$HOME/.kube"
    cp /etc/kubernetes/admin.conf "$HOME/.kube/config" 2>/dev/null
    sudo chown $(id -u):$(id -g) "$HOME/.kube/config"
    echo "---"
    kubectl label --overwrite nodes --all openstack-control-plane=enabled
    kubectl label --overwrite nodes --all openstack-compute-node=enabled
    kubectl label --overwrite nodes --all openvswitch=enabled
    kubectl label --overwrite nodes --all linuxbridge=enabled
    kubectl get no -o wide --show-labels
    echo "---"
  '';
in
{
  options.customNixOSModules.rpcuIaaSCP = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "";
    };
    cluster = {
      privateAddress = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
      vlan4001Address = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
      macAddress = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
      priority = lib.mkOption {
        type = lib.types.int;
        default = 0;
      };
      otherNodes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      allNodeIps = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };
  };

  config = lib.mkIf cfg.enable {
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

    users.groups = {
      neutron = { };
      openvswitch.gid = 42424;
      libvirt-qemu.gid = 64055;
      nova.gid = 64060;
    };

    users.users = {
      neutron = {
        isSystemUser = true;
        group = "neutron";
      };
      openvswitch = {
        isSystemUser = true;
        group = "openvswitch";
        uid = 42424;
        description = "Open vSwitch service user";
      };
      libvirt-qemu = {
        isSystemUser = true;
        group = "libvirt-qemu";
        uid = 64055;
      };
      nova = {
        isSystemUser = true;
        group = "nova";
        uid = 64060;
        description = "OpenStack Nova User";
        home = "/var/lib/nova";
      };
    };

    environment = {
      etc = {
        "kubernetes/audit/policy.yaml".text = ''
          apiVersion: audit.k8s.io/v1
          kind: Policy
          omitStages:
            - "RequestReceived"
            - "ResponseStarted"
            - "ResponseComplete"
          rules:
            # 1. Capture 'create' and 'delete' for EVERYTHING
            - level: Metadata
              verbs: ["create", "delete"]
            # 2. Explicitly drop everything else (get, list, watch, patch, update)
            - level: None
        '';
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
      // (lib.optionalAttrs isClusterEnabled ({
        "kubernetes/kubelet/config.d/10-config.conf".text = ''
          kind: KubeletConfiguration
          apiVersion: kubelet.config.k8s.io/v1beta1
          address: "${cfg.cluster.privateAddress}"
        '';
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
      }));

      systemPackages = [
        pkgs.dnsmasq
      ]
      ++ (lib.optionals isClusterEnabled [
        installKubevip
        initKubeadm
        joinCPKubeadm
      ]);
    };

    systemd.tmpfiles.rules = [
      "d /run/openvswitch 0755 openvswitch openvswitch -"
    ];

    networking = {
      useDHCP = lib.mkDefault true;
    };

    services.netbird.enable = true;

    boot = {
      initrd = {
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
        kernelModules = [
          "dm_snapshot"
          "dm-thin-pool"
        ];
        services.lvm.enable = true;
      };
      kernelModules = [
        "kvm-intel"
        "rbd"
        "openvswitch"
        "gre"
        "vxlan"
        "bridge"
        "ip6_tables"
        "ebtables"
      ];
      loader.systemd-boot.enable = true;
      loader.efi.canTouchEfiVariables = true;
    };

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

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    hardware = {
      cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
      graphics = {
        enable = true;
        extraPackages = with pkgs; [
          vpl-gpu-rt
          intel-vaapi-driver
          intel-media-driver
        ];
      };
    };

    # Cluster-specific configs
    systemd.network.links."00-eno1" = lib.mkIf isClusterEnabled {
      matchConfig.PermanentMACAddress = cfg.cluster.macAddress;
      linkConfig.Name = "eno1";
    };

    systemd.services.kubelet.serviceConfig.Environment = lib.mkIf isClusterEnabled [
      ''KUBELET_KUBECONFIG_ARGS="--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf --node-ip=${cfg.cluster.privateAddress} --node-labels=openstack-control-plane=enabled,openstack-compute-node=enabled,openvswitch=enabled,linuxbridge=enabled"''
    ];

    services.keepalived = lib.mkIf isClusterEnabled {
      enable = true;
      vrrpInstances.VI_1 = {
        interface = "${primaryInterface}.4000";
        state = "BACKUP";
        virtualRouterId = 51;
        priority = cfg.cluster.priority;
        unicastSrcIp = cfg.cluster.privateAddress;
        unicastPeers = cfg.cluster.otherNodes;
        virtualIps = [
          {
            addr = "178.63.143.219/32";
            dev = "${primaryInterface}";
          }
        ];
      };
    };

    customNixOSModules = lib.mkIf isClusterEnabled {
      sysctlSecure.enable = true;
      networkManager = {
        enable = true;
        vswitch = {
          enable = true;
          interface = "${primaryInterface}";
          vlans = [
            {
              vlanId = 4000;
              privateAddress = cfg.cluster.privateAddress;
              prefixLength = 24;
              mtu = 1400;
            }
            {
              vlanId = 4001;
              privateAddress = cfg.cluster.vlan4001Address;
              prefixLength = 16;
              mtu = 1400;
            }
          ];
        };
      };
      kubernetes = {
        enable = true;
        version = {
          kubeadm = kubeadmVersion;
          kubelet = "v1.35.1";
        };
      };
      caCertificates.didactiklabs.enable = true;
      ginx.enable = true;
      chrony.enable = true;
    };
  };
}
