# overlays/nixbook-compat.nix
# Provides packages required by nixbook's homeManagerModules:
# - `pkgs.customPkgs.*`, nixbook's own packages (ginx, witr...), which its
#   modules use since nixbook moved them to an overlay. Home Manager runs
#   with useGlobalPkgs (nixosModules/userConfig.nix), so the overlay must be
#   on the system's pkgs: nixbook's own `nixpkgs.overlays` would be ignored.
# - packages not yet available in the nixos-26.05 channel, pulled from
#   nixbook's pinned nixpkgs (nixos-unstable).
let
  sources = import ../npins;
  nixbookSources = import "${sources.nixbook}/npins";
  nixbookPkgs = import nixbookSources.nixpkgs {
    config.allowUnfree = true;
  };
  customPkgs = import "${sources.nixbook}/customPkgs";
in
final: prev:
customPkgs final prev
// {
  inherit (nixbookPkgs) dgop;
}
