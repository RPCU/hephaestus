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
      privateAddress = "10.0.0.3";
      vlan4001Address = "10.10.0.3";
      macAddress = "30:9c:23:d3:51:37";
      priority = 99;
      otherNodes = [
        "10.0.0.2" # lucy
        "10.0.0.4" # quinn
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
