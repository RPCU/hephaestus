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
  environment = {
    etc = {
      "kubernetes/kubelet/config.d/00-config.conf".text = ''
        kind: KubeletConfiguration
        apiVersion: kubelet.config.k8s.io/v1beta1
        maxPods: 200
      '';
    };
  };
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
    kernelModules = [ "kvm-intel" ];
    extraModulePackages = [ ];

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
  swapDevices = [ ];
  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware = {
    cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    graphics = {
      enable = true;
      extraPackages = with pkgs; [
        vpl-gpu-rt # for newer GPUs on NixOS >24.05 or unstable
        intel-vaapi-driver
        intel-media-driver
      ];
    };
  };
  customNixOSModules = {
    networkManager.enable = true;
    kubernetes = {
      enable = true;
      version = {
        kubeadm = "v1.35.0";
        kubelet = "v1.35.0";
      };
    };
    caCertificates = {
      didactiklabs.enable = true;
    };
    ginx.enable = true;
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
