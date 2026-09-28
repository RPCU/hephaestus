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
    # 12c/126Gi: VMs 72Gi / 12 vCPU on ~3 cores, host ~5Gi/1c → pods ~46.7Gi / 8c
    # (72h Mimir, 2026-09-28). Keep in sync with the argus nova placement
    # budget (infrastructure/yaook/nova-placement-reservation.yaml).
    hostPartition = {
      systemReservedCpu = "4";
      systemReservedMemory = "78Gi";
      vmCpuWeight = 157;
    };
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
          address = "172.16.0.1"; # for vm internet access
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
