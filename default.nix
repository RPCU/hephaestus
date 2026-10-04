{
  cloud ? "false",
  partition ? "root",
  disk ? null,
  profile ? "kaas",
  bootloader ? "systemd-boot",
  repoUrl ? "https://github.com/RPCU/hephaestus",
  repoBranch ? "main",
  ...
}:
let
  sources = import ./npins;
  pkgs = import sources.nixpkgs { };
  disko = import sources.disko { inherit (pkgs) lib; };

  isoInstall = import "${pkgs.path}/nixos/lib/eval-config.nix" {
    system = "x86_64-linux";
    modules = [
      ./installer/live-configuration.nix
    ];
    specialArgs = {
      inherit
        disko
        partition
        cloud
        disk
        bootloader
        repoUrl
        repoBranch
        ;
    };
  };
  nixosSystem = import (sources.nixpkgs + "/nixos") {
    configuration = ./profiles/${profile}/configuration.nix;
  };
  # Same system with the git metadata in /etc/nixos/version blanked out, so its
  # toplevel path only changes when the OS itself changes (not on every commit).
  # Used to decide whether a new Glance image is needed.
  nixosSystemNoRev = import (sources.nixpkgs + "/nixos") {
    configuration = {
      imports = [ ./profiles/${profile}/configuration.nix ];
      environment.etc."nixos/version".source = lib.mkForce (builtins.toFile "projectGit.json" "{}");
    };
  };
  buildQcow2 = import <nixpkgs/nixos/lib/make-disk-image.nix> {
    inherit lib pkgs;
    inherit (nixosSystem) config;
    diskSize = "auto";
    format = "qcow2-compressed";
    configFile = ./profiles/${profile}/configuration.nix;
    partitionTableType = "efi";
    additionalSpace = "1G";
  };
  inherit (pkgs) lib;
in
{
  imports = [ <nixpkgs/nixos/modules/installer/cd-dvd/channel.nix> ];
  inherit lib nixosSystem buildQcow2;
  buildIso =
    (isoInstall.extendModules {
      modules = [
        "${pkgs.path}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        {
          isoImage.squashfsCompression = null;
        }
      ];
    }).config.system.build.isoImage;
  # Glance image naming for CAPO: hephaestus-<profile>[-<rev>]-<nixos release>-v<k8s>
  # (e.g. hephaestus-kaas-26.05-v1.36.1). See scripts/uploadGlanceImage.
  imageInfo = {
    name = "hephaestus-${profile}";
    release = nixosSystem.config.system.nixos.release;
    kubernetesVersion = "v${nixosSystem.config.customNixOSModules.kubernetes.version.kubeadm}";
    fingerprint = builtins.unsafeDiscardStringContext (
      builtins.baseNameOf nixosSystemNoRev.config.system.build.toplevel.outPath
    );
  };
  ociQcow2 = pkgs.dockerTools.buildLayeredImage {
    name = "${profile}-${nixosSystem.config.customNixOSModules.kubernetes.version.kubeadm}";
    includeStorePaths = false;
    fakeRootCommands = ''
      mkdir -p ./disk
      cp -L ${buildQcow2}/nixos.qcow2 ./disk/${profile}.qcow2
    '';
  };

  devShell = pkgs.mkShell {
    packages = with pkgs; [
      go-task
      jq
      yq-go
      colmena
      npins
      sbomnix
    ];
    shellHook = ''
      echo "Hephaestus development shell (minimal)"
      echo "For the full environment, use: devenv shell"
    '';
  };
}
