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
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      vpl-gpu-rt # for newer GPUs on NixOS >24.05 or unstable
      intel-vaapi-driver
      intel-media-driver
    ];
  };
  hardware.enableRedistributableFirmware = lib.mkDefault true;
  boot = {
    tmp.cleanOnBoot = true;
    supportedFilesystems = [ "nfs" ];
    kernelParams = [
      "consoleblank=0"
      "console=ttyS0,115200n8"
    ];
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 0;
      };
      efi.canTouchEfiVariables = true;
      grub.device = lib.mkDefault "/dev/vda";
    };
    growPartition = true;
  };
  networking = {
    hostName = lib.mkForce "";
  };
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/nixos";
      autoResize = true;
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-label/ESP";
      fsType = "vfat";
      options = [
        "fmask=0077"
        "dmask=0077"
        "nofail"
        "x-systemd.device-timeout=5s"
      ];
    };
  };
  networking = {
    useDHCP = false;
    dhcpcd.enable = false;
  };
  environment = {
    etc = {
      "kubernetes/kubelet/config.d/00-config.conf".text = ''
        kind: KubeletConfiguration
        apiVersion: kubelet.config.k8s.io/v1beta1
        allowedUnsafeSysctls:
          - net.ipv4.conf.all.src_valid_mark
      '';
    };
  };

  systemd.services = {
    qemu-guest-agent = {
      path = [ pkgs.cloud-init ];
    };
  };

  services = {
    qemuGuest = {
      enable = lib.mkForce true;
    };
    cloud-init = {
      enable = true;
      network.enable = true;
    };
    resolved = {
      enable = true;
      llmnr = "false"; # allow shotdns resolution in kubevirt
      extraConfig = ''
        ResolveUnicastSingleLabel=true # allow shotdns resolution in kubevirt
      '';
    };
  };
  security = {
    polkit.enable = true;
  };
  systemd = {
    network = {
      networks = {
        "00-enp1s0" = {
          matchConfig = {
            Name = "en*";
          };
          networkConfig = {
            DHCP = "yes";
          };
        };
      };
    };
  };
  customNixOSModules = {
    kubernetes = {
      enable = true;
      version = {
        kubeadm = "1.35.4";
        kubelet = "1.35.4";
      };
    };
    caCertificates = {
      didactiklabs.enable = true;
    };
    ginx.enable = false;
    chrony = {
      enable = true;
      vmconfig = true;
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
    <nixpkgs/nixos/modules/profiles/qemu-guest.nix>
  ];
}
