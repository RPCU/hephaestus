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
        url = "https://dthezntil550i.cloudfront.net/we/latest/we1612010932593930001162693/1280_960/6cc3c829-5e88-470c-bcbd-600bb30cec53.png";
        sha256 = "sha256-yZs4/XKHSuLgcWo9DNI3YLBrhzgRgl0s7MPt67J1Gl0=";
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
