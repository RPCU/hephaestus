{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.gitConfig;
in
{
  config = lib.mkIf cfg.enable {
    programs.git = {
      userName = "Aimen Faidi";
      userEmail = "aimenfaidi28@gmail.com";
    };
  };
}
