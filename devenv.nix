{
  pkgs,
  lib,
  ...
}:
{
  packages = with pkgs; [
    go-task
    jq
    yq-go
    qemu
    docker
    colmena
    npins
  ];
  git-hooks.hooks = {
    # lint shell scripts
    shellcheck.enable = true;
    # execute example shell from Markdown files
    mdsh.enable = true;
    nixfmt-rfc-style.enable = true;
  };

  difftastic.enable = true;
  treefmt = {
    enable = true;
    config.programs = {
      nixfmt.enable = true;
    };
  };

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
  '';
}
