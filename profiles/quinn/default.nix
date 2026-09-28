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
    # 8c/63Gi: VMs 32Gi / 8 vCPU on ~3 cores, host ~3Gi/1c → pods ~25.6Gi / 4c
    # (72h Mimir, 2026-09-28). Keep in sync with the argus nova placement
    # budget (infrastructure/yaook/nova-placement-reservation.yaml).
    hostPartition = {
      systemReservedCpu = "4";
      systemReservedMemory = "36Gi";
      vmCpuWeight = 118;
    };
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
