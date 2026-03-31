let
  sources = import ./npins;
in
{
  pkgs,
  lib,
  ...
}:
{
  imports = [ "${sources.nixbook}/devenvModules/devenv.nix" ];

  packages = with pkgs; [
    go-task
    jq
    yq-go
    qemu
    docker
    colmena
    npins
  ];

  treefmt.config.programs.prettier.excludes = [
    "assets/dms/plugins/**/translations.js"
  ];

  env.PATH = lib.mkForce "$PWD/scripts:$PATH";

  scripts = {
    # https://devenv.sh/scripts/
    build-iso.exec = ''
      nix-build default.nix -A buildIso "$@"
    '';
    build-qcow2.exec = ''
      nix-build default.nix -A buildQcow2 "$@"
    '';
    build-oci-qcow2.exec = ''
      nix-build default.nix -A ociQcow2 "$@"
    '';
    test-iso.exec = ''
      nix-build default.nix -A buildIso "$@" && \
      qemu-system-x86_64 -m 2048 -cdrom ./result/iso/*.iso
    '';
    update-machines.description = "Deploy NixOS configuration to all RPCU cluster nodes via Colmena";
    update-machines.exec = ''
      colmena apply --on @rpcu
    '';
    show-k8s-pins.description = "Display already available Kubernetes nixpkgs pins via npins";
    show-k8s-pins.exec = ''
      ${pkgs.npins}/bin/npins show | grep 'nixpkgs-k8s-'
    '';
    add-k8s-pin.description = "Pin a nixpkgs revision for a specific Kubernetes version via npins";
    add-k8s-pin.exec = ''
      if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Usage: add-k8s-nixpkgs-pin <K8S_VERSION> <NIXPKGS_REV>"
        echo "Example: add-k8s-nixpkgs-pin v1.35.2 24f4544180242cd80bb2492ce6907243bc716e08"
        exit 1
      fi

      K8S_VERSION="$1"
      NIXPKGS_REV="$2"
      NIXPKGS_URL="https://github.com/NixOS/nixpkgs/archive/$NIXPKGS_REV.tar.gz" # Construct URL from revision
      PIN_NAME="nixpkgs-k8s-$K8S_VERSION"

      echo "Adding pin for $PIN_NAME with URL $NIXPKGS_URL and revision $NIXPKGS_REV..."
      ${pkgs.npins}/bin/npins add github NixOS nixpkgs \
        --name "$PIN_NAME" \
        --branch "master" --frozen \
        --at "$NIXPKGS_REV"
      echo "Nixpkgs pin for Kubernetes $K8S_VERSION added and frozen in npins."
      echo "Remember to add corresponding 'kubeadm-$K8S_VERSION' and 'kubelet-$K8S_VERSION' entries if you haven't already."
    '';
  };

  enterShell = ''
    echo ""
    echo "🔧 Hephaestus development environment loaded"
    echo ""
    echo "Available tools:"
    ${lib.concatStringsSep "\n    " (
      map (pkg: "echo \"  • ${pkg.name or pkg.pname or "unknown"} - ${pkg.meta.description or ""}\"") (
        with pkgs;
        [
          go-task
          jq
          yq-go
          qemu
          docker
          colmena
          npins
        ]
      )
    )}
    echo ""
    echo "Available build scripts:"
    echo ""
    echo "  build-iso       - Build bootable NixOS installation ISO image"
    echo "                    Output: ./result/iso/"
    echo "                    Variables: cloud, partition, disk"
    echo "                    Available partitions: $(ls -1 installer/partitions/*.nix 2>/dev/null | xargs -n1 basename | sed 's/.nix//' | tr '\n' ',' | sed 's/,$//')"
    echo "                    Example: build-iso --arg cloud true --argstr partition default70G"
    echo ""
    echo "  build-qcow2     - Build compressed QCOW2 disk image for VM/cloud use"
    echo "                    Output: ./result/nixos.qcow2"
    echo "                    Variables: profile"
    PROFILES=$(ls -1 profiles/ 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    echo "                    Available profiles: $PROFILES"
    echo "                    Example: build-qcow2 --argstr profile kaas"
    echo ""
    echo "  build-oci-qcow2 - Build OCI container image with embedded QCOW2"
    echo "                    Output: Docker layer with disk/{profile}.qcow2"
    echo "                    Variables: profile"
    echo "                    Available profiles: $PROFILES"
    echo "                    Example: build-oci-qcow2 --argstr profile kaas"
    echo ""
    echo "  test-iso        - Build ISO and boot it in QEMU (2GB RAM)"
    echo "                    Variables: cloud, partition, disk"
    echo "                    Example: test-iso --arg cloud true"
    echo ""
    echo "  update-machines - Deploy NixOS configuration to all RPCU cluster nodes via Colmena"
    echo "                    Example: update-machines"
    echo ""
    echo "  show-k8s-pins   - Display already available Kubernetes nixpkgs pins"
    echo "                    Example: show-k8s-pins"
    echo ""
    echo "  add-k8s-pin     - Pin a nixpkgs revision for a specific Kubernetes version"
    echo "                    Usage: add-k8s-pin <K8S_VERSION> <NIXPKGS_REV>"
    echo "                    Example: add-k8s-pin v1.35.2 24f4544180242cd80bb2492ce6907243bc716e08"
    echo ""
  '';
}
