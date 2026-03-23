{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customNixOSModules.ginx;
  sources = import ../npins;
  ginx = import "${sources.nixbook}//customPkgs/ginx.nix" { inherit pkgs; };
  osupdate = pkgs.writeShellScriptBin "osupdate" ''
    set -euo pipefail
    echo last applied revisions: $(${pkgs.jq}/bin/jq .rev /etc/nixos/version)
    echo applying revision: "$(${pkgs.git}/bin/git ls-remote https://github.com/didactiklabs/nixbook HEAD | awk '{print $1}')"...

    echo Running ginx...
    ${ginx}/bin/ginx --source https://github.com/didactiklabs/nixbook -b main --now -- /run/wrappers/bin/sudo ${pkgs.colmena}/bin/colmena apply-local
  '';
in
{
  options.customNixOSModules.ginx = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Ginx is a cli tool that watch a remote repository and run an arbitrary command on changes/updates.
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    security = {
      polkit = {
        enable = true;
        extraConfig = ''
          polkit.addRule(function(action, subject) {
            if (action.id == "org.freedesktop.systemd1.manage-units" &&
                action.lookup("unit") == "ginx.service")) {
              return polkit.Result.YES;
            }
          });
        '';
      };
    };
    environment = {
      systemPackages = [
        pkgs.colmena
        osupdate
        ginx
      ];
    };

    systemd = {
      services = {
        ginx = {
          enable = true;
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.writeShellScript "nixos-upgrade-wrapper" ''
              export NIXPKGS_ALLOW_UNFREE=1
              export PATH=$PATH:${
                lib.makeBinPath [
                  pkgs.git
                  pkgs.jq
                  pkgs.colmena
                  ginx
                  osupdate
                ]
              }
              exec ginx --source https://github.com/RPCU/hephaestus -b main -n 60 -- colmena apply-local
            ''}";
            StandardOutput = "journal";
            StandardError = "journal";
          };
        };
      };
    };
  };
}
