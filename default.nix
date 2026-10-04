{
  cloud ? "false",
  partition ? "root",
  disk ? null,
  profile ? "kaas",
  bootloader ? "systemd-boot",
  repoUrl ? "https://github.com/RPCU/hephaestus",
  repoBranch ? "main",
  # Overrides the profile's customNixOSModules.kubernetes.version (kubeadm and
  # kubelet), e.g. "1.37.1". Needs a matching nixpkgs-k8s-<version> npins pin.
  kubernetesVersion ? null,
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
  profileModules = [
    ./profiles/${profile}/configuration.nix
  ]
  ++ lib.optional (kubernetesVersion != null) {
    customNixOSModules.kubernetes.version = lib.mapAttrs (_: lib.mkForce) {
      kubeadm = lib.removePrefix "v" kubernetesVersion;
      kubelet = lib.removePrefix "v" kubernetesVersion;
    };
  };
  nixosSystem = import (sources.nixpkgs + "/nixos") {
    configuration.imports = profileModules;
  };
  # Same system with the git metadata in /etc/nixos/version blanked out, so its
  # toplevel path only changes when the OS itself changes (not on every commit).
  # Used to decide whether a new Glance image is needed.
  nixosSystemNoRev = import (sources.nixpkgs + "/nixos") {
    configuration = {
      imports = profileModules;
      environment.etc."nixos/version".source = lib.mkForce (builtins.toFile "projectGit.json" "{}");
    };
  };
  # Disk layout of the images. Glance stores them raw (the whole virtual
  # disk), so keep the slack small: the root partition and filesystem grow to
  # the VM's disk on first boot (boot.growPartition, autoResize).
  diskImageSettings = {
    diskSize = "auto";
    partitionTableType = "efi";
    additionalSpace = "256M";
    # No nixpkgs channel copy: nix.settings.nix-path already points at the
    # pinned sources (base.nix), which are in the closure
    copyChannel = false;
  };
  makeDiskImage =
    format:
    import <nixpkgs/nixos/lib/make-disk-image.nix> (
      diskImageSettings
      // {
        inherit lib pkgs format;
        inherit (nixosSystem) config;
        configFile = ./profiles/${profile}/configuration.nix;
      }
    );
  buildQcow2 = makeDiskImage "qcow2-compressed";
  inherit (pkgs) lib;
in
{
  imports = [ <nixpkgs/nixos/modules/installer/cd-dvd/channel.nix> ];
  inherit
    lib
    nixosSystem
    buildQcow2
    ;
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
    # OS (toplevel without git metadata) + disk layout: either changing
    # publishes a new image.
    fingerprint =
      builtins.unsafeDiscardStringContext (
        builtins.baseNameOf nixosSystemNoRev.config.system.build.toplevel.outPath
      )
      + "-"
      + builtins.substring 0 8 (builtins.hashString "sha256" (builtins.toJSON diskImageSettings));
  };
  # Kubernetes versions to publish Glance images for: the latest patch of the
  # two newest minors that have a nixpkgs-k8s-<x.y.z> pin, newest first.
  supportedKubernetesVersions =
    let
      versions = lib.sort (a: b: builtins.compareVersions a b > 0) (
        lib.concatMap (
          pin:
          let
            m = builtins.match "nixpkgs-k8s-([0-9]+\\.[0-9]+\\.[0-9]+)" pin;
          in
          lib.optional (m != null) (builtins.head m)
        ) (builtins.attrNames sources)
      );
      minors = lib.take 2 (lib.unique (map lib.versions.majorMinor versions));
    in
    map (minor: lib.findFirst (v: lib.versions.majorMinor v == minor) null versions) minors;
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
