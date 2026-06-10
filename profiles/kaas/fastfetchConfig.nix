{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  logo =
    let
      image = pkgs.fetchurl {
        url = "https://cdna.artstation.com/p/assets/images/images/073/622/688/large/danna-ottino-cassiopeia.jpg?1710104097";
        sha256 = "sha256-Z1ojQa6d8G/eDZ2D38un7rDqf94ETYEy1TKEuSKU+co=";
      };
    in
    "${image}";
in
{
  config = lib.mkIf cfg.fastfetchConfig.enable {
    home.file.".config/fastfetch/logo" = {
      source = lib.mkForce logo;
    };
  };
}
