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
        url = "https://static.wikia.nocookie.net/champions-of-power-fanfiction-series/images/e/ee/Quinn_Ergon.png";
        sha256 = "sha256-U1SNCwKNDnfOX6bpZbwWDfXkD8EnqruQC8LZWtDBf8A=";
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
