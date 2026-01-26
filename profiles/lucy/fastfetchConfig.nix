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
        url = "https://i.pinimg.com/736x/13/e7/86/13e786c6bb16585f4ca6fbb32239790d.jpg";
        sha256 = "sha256-ZARX3k6X0acgGQU5P4MPpQgRAWRvTrtuSI+CbGNISs4=";
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
