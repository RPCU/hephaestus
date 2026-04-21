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
    privateAddress = "10.0.0.4";
    primaryMacAddress = "4c:52:62:0a:82:93";
    openstackMacAddress = "6c:b3:11:5d:25:e9";
    cluster = {
      priority = 98;
      otherNodes = [
        "10.0.0.2" # lucy
        "10.0.0.3" # makise
      ];
    };
  };

  networking = {
    interfaces.br-ex = {
      ipv4.addresses = [
        {
          address = "172.16.0.3"; # for vm internet access
          prefixLength = 16;
        }
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
