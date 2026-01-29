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
      settings = {
        user = {
          name = "Aimen Faidi";
          email = "aimenfaidi28@gmail.com";
        };
      };
    };
  };
}
