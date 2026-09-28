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
    # 12c/63Gi: VMs 32Gi / 12 vCPU on ~4 cores, host ~3Gi/1c → pods ~25.7Gi / 7c
    # (72h Mimir, 2026-09-28). Keep in sync with the argus nova placement
    # budget (infrastructure/yaook/nova-placement-reservation.yaml).
    hostPartition = {
      systemReservedCpu = "5";
      systemReservedMemory = "36Gi";
      vmCpuWeight = 196;
    };
    cluster = {
      priority = 99;
      otherNodes = [
        "10.0.0.2" # lucy
        "10.0.0.4" # quinn
      ];
    };
  };
  networking = {
    interfaces.br-ex = {
      ipv4.addresses = [
        {
          address = "172.16.0.2"; # for vm internet access
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
