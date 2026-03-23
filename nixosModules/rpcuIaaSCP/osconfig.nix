{
  lib,
  cfg,
  pkgs,
  config,
  isClusterEnabled,
  installKubevip,
  initKubeadm,
  joinCPKubeadm,
  kubeadmVersion,
  apiserverVip,
  podCidr,
  nodeLabels,
  kubeletKubeconfigArgs,
  kubeletConfigArgs,
  vrrpInstanceName,
  vrrpInterfaceSubnet,
  vrrpState,
  vrrpRouterId,
  virtualIpAddress,
  primaryInterface,
  allNodeIps,
}:
{
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
            allNodeIps
            ;
        };
      in
      importedConfs.baseConfigs // (lib.optionalAttrs isClusterEnabled importedConfs.clusterConfigs);
    systemPackages = [
      pkgs.dnsmasq # DNS/DHCP server
    ]
    ++ (lib.optionals isClusterEnabled [
      installKubevip
      initKubeadm
      joinCPKubeadm
    ]);
  };
  networking = {
    useDHCP = lib.mkDefault true;
  };
  services.netbird.enable = true;
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
      kernelModules = [
        "dm_snapshot"
        "dm-thin-pool"
      ];
      services.lvm.enable = true;
    };
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
    services.kubelet.serviceConfig.Environment = lib.mkIf isClusterEnabled (
      lib.mkForce [
        ''KUBELET_KUBECONFIG_ARGS="${kubeletKubeconfigArgs}"''
        ''KUBELET_CONFIG_ARGS="${kubeletConfigArgs}"''
      ]
    );
  };
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
}
