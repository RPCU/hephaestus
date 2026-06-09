# overlays/nixbook-compat.nix
# Provides packages required by nixbook's homeManagerModules that are
# not yet available in the nixos-26.05 channel.
# Pulls them from nixbook's pinned nixpkgs (nixos-unstable).
let
  sources = import ../npins;
  nixbookSources = import "${sources.nixbook}/npins";
  nixbookPkgs = import nixbookSources.nixpkgs {
    config.allowUnfree = true;
  };
in
final: prev: {
  inherit (nixbookPkgs) dgop;
}
