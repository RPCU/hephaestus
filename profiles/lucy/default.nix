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
    privateAddress = "10.0.0.2";
    primaryMacAddress = "b4:2e:99:cd:02:76";
    openstackMacAddress = "6c:b3:11:5d:26:7a";
    cluster = {
      priority = 100;
      otherNodes = [
        "10.0.0.3" # makise
        "10.0.0.4" # quinn
      ];
    };
  };

  networking = {
    interfaces.br-ex = {
      ipv4.addresses = [
        {
          address = "172.24.0.1"; # for vm internet access
          prefixLength = 24;
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
