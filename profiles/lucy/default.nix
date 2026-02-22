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
      privateAddress = "10.0.0.2";
      vlan4001Address = "10.10.0.2";
      macAddress = "b4:2e:99:cd:02:76";
      priority = 100;
      otherNodes = [
        "10.0.0.3" # makise
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
