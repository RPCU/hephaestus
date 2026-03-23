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
    privateAddress = "10.0.0.3";
    primaryMacAddress = "30:9c:23:d3:51:37";
    openstackMacAddress = "6c:b3:11:5d:26:26";
    cluster = {
      priority = 99;
      otherNodes = [
        "10.0.0.2" # lucy
        "10.0.0.4" # quinn
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
