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
    # Disable NFSv4 directory delegations — NFS-Ganesha (V5.9 in ceph
    # v19.2.3) replies OP_ILLEGAL instead of NOTSUPP to GET_DIR_DELEGATION,
    # which Linux >= 6.11 kernels send on repeated directory access. The
    # client maps that to EREMOTEIO, breaking non-root directory listings
    # (Jellyfin/Radarr "Remote I/O error", July 2026 production incident).
    # Re-evaluate when a ganesha release ships the NOTSUPP fix.
    extraModprobeConfig = "options nfsv4 directory_delegations=0";
    initrd.kernelModules = [ "nfsv4" ];
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 0;
      };
      efi.canTouchEfiVariables = true;
    };
    growPartition = true;
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

  system.nssModules = lib.mkForce [ ]; # required to effectively disable nscd
  services = {
    nscd.enable = false; # avoids RR dns on all NIC IP for hostname local resolution
    qemuGuest = {
      enable = lib.mkForce true;
    };
    cloud-init = {
      enable = true;
      network.enable = true;
      settings = {
      };
    };
    resolved = {
      enable = true;
      settings.Resolve = {
        LLMNR = false; # allow shortdns resolution in kubevirt
        ResolveUnicastSingleLabel = true; # allow shortdns resolution in kubevirt
      };
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
          linkConfig.RequiredForOnline = "routable";
          networkConfig = {
            DHCP = "yes";
          };
          dhcpV4Config = {
            UseDNS = true;
            UseDomains = true;
            UseHostname = true;
          };
        };
      };
    };
  };
  customNixOSModules = {
    kubernetes = {
      enable = true;
      version = {
        kubeadm = "1.36.1";
        kubelet = "1.36.1";
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
