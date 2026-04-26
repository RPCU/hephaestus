{
  lib,
  cfg,
  pkgs,
  config,
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
  brexVrrpInstanceName,
  brexVrrpRouterId,
  brexVrrpInterface,
  brexVirtualIpAddress,
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
      importedConfs.baseConfigs // (lib.optionalAttrs cfg.enable importedConfs.clusterConfigs);
    systemPackages = [
      pkgs.dnsmasq # DNS/DHCP server
    ]
    ++ (lib.optionals cfg.enable [
      installKubevip
      initKubeadm
      joinCPKubeadm
    ]);
  };
  networking = {
    useDHCP = lib.mkDefault true;
    interfaces.enp3s0.mtu = 9000;
  };
  networking.nat = {
    enable = true;
    externalInterface = "eno1";
    internalIPs = [ "172.16.0.0/12" ]; # for internet access in vms
  };
  systemd.slices.system.sliceConfig = {
    MemoryMax = "10G";
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
  # virtualisation.libvirtd.enable = true;
  # # Enable KVM (recommended)
  # virtualisation.libvirtd.qemu = {
  #   package = pkgs.qemu_kvm;
  #   runAsRoot = true;
  # };
  users = {
    groups = {
      operator.gid = 2500000;
      keystone.gid = 2500001;
      ceilometer.gid = 2500002;
      cinder.gid = 2500003;
      glance.gid = 2500004;
      gnocchi.gid = 2500005;
      horizon.gid = 2500006;
      neutron.gid = 2500007;
      nova.gid = 2500008;
      libvirt.gid = 2500009;
      mariadb.gid = 2500010;
      rabbitmq.gid = 2500011;
      barbican.gid = 2500012;
      tempest.gid = 2500014;
      "ssl-terminator".gid = 2500015;
      ovn.gid = 2500016;
      placement.gid = 2500017;
      designate.gid = 2500018;
      octavia.gid = 2500019;
    };
    users = {
      operator = {
        uid = 2500000;
        group = "operator";
        isSystemUser = true;
      };
      keystone = {
        uid = 2500001;
        group = "keystone";
        isSystemUser = true;
      };
      ceilometer = {
        uid = 2500002;
        group = "ceilometer";
        isSystemUser = true;
      };
      cinder = {
        uid = 2500003;
        group = "cinder";
        isSystemUser = true;
      };
      glance = {
        uid = 2500004;
        group = "glance";
        isSystemUser = true;
      };
      gnocchi = {
        uid = 2500005;
        group = "gnocchi";
        isSystemUser = true;
      };
      horizon = {
        uid = 2500006;
        group = "horizon";
        isSystemUser = true;
      };
      neutron = {
        uid = 2500007;
        group = "neutron";
        isSystemUser = true;
      };
      nova = {
        uid = 2500008;
        group = "nova";
        isSystemUser = true;
      };
      libvirt = {
        uid = 2500009;
        group = "libvirt";
        isSystemUser = true;
      };
      mariadb = {
        uid = 2500010;
        group = "mariadb";
        isSystemUser = true;
      };
      rabbitmq = {
        uid = 2500011;
        group = "rabbitmq";
        isSystemUser = true;
      };
      barbican = {
        uid = 2500012;
        group = "barbican";
        isSystemUser = true;
      };
      tempest = {
        uid = 2500014;
        group = "tempest";
        isSystemUser = true;
      };
      "ssl-terminator" = {
        uid = 2500015;
        group = "ssl-terminator";
        isSystemUser = true;
      };
      ovn = {
        uid = 2500016;
        group = "ovn";
        isSystemUser = true;
      };
      placement = {
        uid = 2500017;
        group = "placement";
        isSystemUser = true;
      };
      designate = {
        uid = 2500018;
        group = "designate";
        isSystemUser = true;
      };
      octavia = {
        uid = 2500019;
        group = "octavia";
        isSystemUser = true;
      };
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
        "00-eno1" = lib.mkIf cfg.enable {
          matchConfig.PermanentMACAddress = cfg.primaryMacAddress;
          linkConfig.Name = "eno1";
        };
        "01-enp3s0" = lib.mkIf cfg.enable {
          matchConfig.PermanentMACAddress = cfg.openstackMacAddress;
          linkConfig.Name = "enp3s0";
        };
      };
    };
    services.kubelet.serviceConfig.Environment = lib.mkIf cfg.enable (
      lib.mkForce [
        ''KUBELET_KUBECONFIG_ARGS="${kubeletKubeconfigArgs}"''
        ''KUBELET_CONFIG_ARGS="${kubeletConfigArgs}"''
      ]
    );
  };
  services.keepalived = lib.mkIf cfg.enable {
    enable = true;
    vrrpInstances."${vrrpInstanceName}" = {
      interface = vrrpInterfaceSubnet;
      state = vrrpState;
      virtualRouterId = vrrpRouterId;
      inherit (cfg.cluster) priority;
      unicastSrcIp = cfg.privateAddress;
      unicastPeers = cfg.cluster.otherNodes;
      virtualIps = [
        {
          addr = virtualIpAddress;
          dev = primaryInterface;
        }
      ];
    };
    vrrpInstances."${brexVrrpInstanceName}" = {
      interface = vrrpInterfaceSubnet;
      state = vrrpState;
      virtualRouterId = brexVrrpRouterId;
      inherit (cfg.cluster) priority;
      unicastSrcIp = cfg.privateAddress;
      unicastPeers = cfg.cluster.otherNodes;
      virtualIps = [
        {
          addr = brexVirtualIpAddress;
          dev = brexVrrpInterface;
        }
      ];
    };
  };
}
