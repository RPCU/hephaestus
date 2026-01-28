{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules.networkManager;
  vlanName = "${cfg.vswitch.interface}.${toString cfg.vswitch.vlanId}";
in
{
  options.customNixOSModules.networkManager = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable network configuration";
    };

    vswitch = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Hetzner vSwitch configuration with VLAN support";
      };

      interface = lib.mkOption {
        type = lib.types.str;
        default = "eno1";
        description = "Parent network interface for vSwitch";
      };

      vlanId = lib.mkOption {
        type = lib.types.int;
        default = 4000;
        description = "VLAN ID (range 4000-4091 for Hetzner vSwitch)";
      };

      privateAddress = lib.mkOption {
        type = lib.types.str;
        description = "Private IP address for the VLAN interface (e.g., 10.0.0.1)";
      };

      prefixLength = lib.mkOption {
        type = lib.types.int;
        default = 24;
        description = "Network prefix length";
      };

      mtu = lib.mkOption {
        type = lib.types.int;
        default = 1400;
        description = "MTU size for VLAN interface (recommended 1400 for Hetzner vSwitch)";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      networking = {
        useDHCP = false;
        dhcpcd.enable = false;
        useNetworkd = true;

        interfaces.${cfg.vswitch.interface}.useDHCP = lib.mkDefault true;
      };

      systemd.network.enable = true;
    })

    (lib.mkIf cfg.vswitch.enable {
      networking = {
        vlans.${vlanName} = {
          id = cfg.vswitch.vlanId;
          interface = cfg.vswitch.interface;
        };

        interfaces.${vlanName} = {
          ipv4.addresses = [
            {
              address = cfg.vswitch.privateAddress;
              prefixLength = cfg.vswitch.prefixLength;
            }
          ];
          mtu = cfg.vswitch.mtu;
        };
      };
    })
  ];
}
