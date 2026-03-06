{
  config,
  pkgs,
  lib,
  sources,
  ...
}:
let
  overrides = {
    customHomeManagerModules = { };
    imports = [ ./fastfetchConfig.nix ];
  };
in
{
  customNixOSModules.rpcuIaaSCP = {
    enable = true;
    cluster = {
      privateAddress = "10.0.0.4";
      primaryMacAddress = "4c:52:62:0a:82:93";
      openstackMacAddress = "6c:b3:11:5d:25:e9";
      priority = 98;
      otherNodes = [
        "10.0.0.2" # lucy
        "10.0.0.3" # makise
      ];
      allNodeIps = [
        "10.0.0.2"
        "10.0.0.3"
        "10.0.0.4"
      ];
    };
  };

  imports = [
    (import ../../users/rpcu {
      inherit
        config
        pkgs
        lib
        sources
        overrides
        ;
    })
  ];
}
