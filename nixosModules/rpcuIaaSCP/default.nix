{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules.rpcuIaaSCP;
  vars = import ./vars.nix;

  inherit (vars)
    kubeadmVersion
    kubeletVersion
    apiserverVip
    primaryInterface
    podCidr
    nodeLabels
    k8sAdminConf
    k8sSuperAdminConf
    k8sManifestsDir
    k8sBootstrapYaml
    k8sJoinYamlTpl
    k8sJoinYaml
    kubevipImage
    vrrpInterfaceSubnet
    vrrpInstanceName
    vrrpRouterId
    vrrpState
    virtualIpAddress
    kubeletBootstrapConf
    kubeletConf
    kubeletConfigYaml
    kubeletConfigDir
    ;

  # Cluster enablement flag
  isClusterEnabled = cfg.cluster.privateAddress != "";

  # Shell snippet: apply node labels

  # Kubelet arguments as a single string
  kubeletNodeLabelsString = lib.concatStringsSep "," nodeLabels;
  kubeletKubeconfigArgs = "--bootstrap-kubeconfig=${kubeletBootstrapConf} --kubeconfig=${kubeletConf} --node-ip=${cfg.cluster.privateAddress} --node-labels=${kubeletNodeLabelsString}";
  kubeletConfigArgs = "--config=${kubeletConfigYaml} --config-dir=${kubeletConfigDir}";

  # ========== Scripts ==========

  installKubevip = import ./scripts/installKubevip.nix {
    inherit
      pkgs
      k8sAdminConf
      k8sSuperAdminConf
      kubevipImage
      primaryInterface
      apiserverVip
      k8sManifestsDir
      ;
  };

  initKubeadm = import ./scripts/initKubeadm.nix {
    inherit
      pkgs
      k8sBootstrapYaml
      k8sAdminConf
      ;
  };

  joinCPKubeadm = import ./scripts/joinCPKubeadm.nix {
    inherit
      pkgs
      k8sJoinYamlTpl
      k8sJoinYaml
      k8sAdminConf
      ;
  };
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
      etc =
        let
          importedConfs = import ./confs {
            inherit
              lib
              cfg
              kubeadmVersion
              apiserverVip
              podCidr
              nodeLabels
              ;
          };
        in
        importedConfs.baseConfigs // (lib.optionalAttrs isClusterEnabled importedConfs.clusterConfigs);

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
