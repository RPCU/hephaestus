# Lean systems (kaas VM images): drop laptop tooling and documentation. The
# images are stored raw in Glance and downloaded by every compute node, so
# every GB counts. User environments are switched separately through
# mkUser's `lean` override (nixosModules/userConfig.nix).
{
  config,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules.lean;
in
{
  options.customNixOSModules.lean.enable = lib.mkEnableOption "a lean system without laptop tooling and documentation";

  config = lib.mkIf cfg.enable {
    # Minimal fastfetch (nixbook's fastfetchConfig installs it for every user)
    nixpkgs.overlays = [ (import ../overlays/server.nix) ];
    documentation = {
      enable = false;
      man.enable = false;
      info.enable = false;
      doc.enable = false;
      nixos.enable = false;
    };
  };
}
