{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.hetznerKeepalived;

  keepalivedConfig = pkgs.writeText "keepalived.conf" ''
    global_defs {
      router_id ${cfg.routerId}
    }

    vrrp_instance VI_1 {
      state ${if cfg.isMaster then "MASTER" else "BACKUP"}
      interface ${cfg.interface}
      virtual_router_id ${toString cfg.virtualRouterId}
      priority ${toString cfg.priority}
      advert_int 1

      virtual_ipaddress {
        178.68.143.219/32
      }

      ${cfg.extraConfig}
    }
  '';
in
{
  options.services.hetznerKeepalived = {
    enable = mkEnableOption "Keepalived VRRP";

    routerId = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "Router ID pour Keepalived";
    };

    interface = mkOption {
      type = types.str;
      default = "eth0";
      description = "Interface réseau";
    };

    virtualRouterId = mkOption {
      type = types.int;
      default = 51;
      description = "Virtual Router ID (identique sur tous les nœuds)";
    };

    priority = mkOption {
      type = types.int;
      description = "Priorité du nœud (100 master, 99/98 backup)";
    };

    isMaster = mkOption {
      type = types.bool;
      default = false;
      description = "Master initial";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Configuration supplémentaire";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.keepalived ];

    systemd.services.hetzner-keepalived = {
      description = "Keepalived VRRP";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.keepalived}/bin/keepalived --dont-fork --log-console --vrrp -f ${keepalivedConfig}";
        Restart = "always";
        RestartSec = "5s";
        AmbientCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
          "CAP_NET_BROADCAST"
        ];
      };
    };
  };
}
