{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules.rpcuIaaSCP;
in
{
  options.customNixOSModules.rpcuIaaSCP = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "";
    };
  };
  config = lib.mkIf cfg.enable {
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
      };
    };
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
  };
}
