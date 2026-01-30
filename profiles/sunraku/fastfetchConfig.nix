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
        url = "https://i.pinimg.com/736x/f5/ca/67/f5ca6704fd9ad9a57bdffb1c5fa16bf0.jpg";
        sha256 = "sha256-s0cmEdqdjNT4rf7fECUgyxakmjq1qn5AkTlxaEJuTjU=";
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
