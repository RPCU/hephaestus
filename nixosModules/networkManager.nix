{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules.networkManager;

  vlanInterfaceType = lib.types.submodule {
    options = {
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

      vlans = lib.mkOption {
        type = lib.types.listOf vlanInterfaceType;
        default = [ ];
        description = "List of VLAN interfaces to configure";
        example = lib.literalExpression ''
          [
            {
              vlanId = 4000;
              privateAddress = "10.0.0.2";
              prefixLength = 24;
              mtu = 1400;
            }
            {
              vlanId = 4001;
              privateAddress = "10.1.0.2";
              prefixLength = 24;
            }
          ]
        '';
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

    (lib.mkIf (cfg.vswitch.enable && cfg.vswitch.vlans != [ ]) {
      networking = {
        vlans = lib.listToAttrs (
          map (vlan: {
            name = "${cfg.vswitch.interface}.${toString vlan.vlanId}";
            value = {
              id = vlan.vlanId;
              interface = cfg.vswitch.interface;
            };
          }) cfg.vswitch.vlans
        );

        interfaces = lib.listToAttrs (
          map (vlan: {
            name = "${cfg.vswitch.interface}.${toString vlan.vlanId}";
            value = {
              ipv4.addresses = [
                {
                  address = vlan.privateAddress;
                  prefixLength = vlan.prefixLength;
                }
              ];
              mtu = vlan.mtu;
            };
          }) cfg.vswitch.vlans
        );
      };
    })
  ];
}
