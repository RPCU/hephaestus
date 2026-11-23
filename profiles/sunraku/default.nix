{
  config,
  pkgs,
  lib,
  sources,
  ...
}:
let
  overrides = {
    customHomeManagerModules = { };
    imports = [ ./fastfetchConfig.nix ];
  };
in
{
  services.netbird.enable = true;
  virtualisation.docker.enable = true;
  systemd = {
    network = {
      enable = false;
      networks = {
        "00-lan" = {
          matchConfig.Name = "enp7s0"; # either ens3 or enp1s0, check 'ip addr'
          networkConfig.DHCP = "ipv4";
        };
        "00-wan" = {
          matchConfig.Name = "enp1s0"; # either ens3 or enp1s0, check 'ip addr'
          networkConfig.DHCP = "ipv4";
          address = [
            # replace this subnet with the one assigned to your instance
            "2a01:4f8:1c1b:889d::/64"
          ];
          routes = [
            { Gateway = "fe80::1"; }
          ];
        };
      };
    };
  };
  boot = {
    loader = {
      efi.canTouchEfiVariables = true;
      grub = {
        enable = true;
        device = "/dev/sda";
      };
    };
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
    ];
  };
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/ROOT";
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-label/BOOT";
      fsType = "ext4";
    };
  };
  swapDevices = [ ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware = {
    cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
  customNixOSModules = {
    sysctlSecure.enable = true;
    ginx.enable = true;
    caCertificates = {
      didactiklabs.enable = true;
    };
    chrony.enable = true;
    # tandem's co-op relay, a lone replica: players reach UDP 27460 on
    # sunraku's public addresses; /healthz and /metrics stay on loopback.
    # Hosts' tokens, optional (the relay runs open): /etc/tandem-relay/host-tokens (by hand, root 0600).
    tandemRelay = {
      enable = true;
      # zot.rpcu.io/public/tandem-relay, published by RPCU/tandem's CI
      # (image.yaml): the commit's first 8 hex digits, or a version tag.
      tag = "d2101fc5";
      # Fetched by Nix, loaded into Docker: Docker can't pull anonymously
      # from zot (see the module's imageDigest).
      imageDigest = "sha256:4262e55cb63fe67d8f2e131b1b52b55303634124e4f27206682e10fca33901d6";
      imageHash = "sha256-T4GcelgN1oB6t9S5tQnfVE3ro5WrciAeoWRle4g6RxM=";
    };
  };
  imports = [
    (import ../../users/rpcu {
      inherit
        config
        pkgs
        lib
        sources
        overrides
        ;
    })
  ];
}
