{
  pkgs,
  sources,
  lib,
  overrides ? { },
}:
let
  defaultConfig = {
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    customHomeManagerModules = {
      gitConfig.enable = true;
      sshConfig.enable = true;
      fastfetchConfig.enable = true;
      zshConfig.enable = true;
    };
    imports = [ ];
    # Server home-manager modules instead of nixbook's laptop zsh/git
    # (homeManagerModules/server.nix), set by lean profiles (kaas).
    lean = false;
  };

  mergedConfig = lib.recursiveUpdate defaultConfig overrides;

  mkUser =
    {
      username,
      userImports ? [ ],
      authorizedKeys ? [ ],
    }:
    {
      programs.zsh.enable = true;
      users.users."${username}" = {
        shell = pkgs.zsh;
        inherit (mergedConfig) extraGroups;
        isNormalUser = true;
        description = "${username}";
        openssh.authorizedKeys.keys = authorizedKeys;
      };
      home-manager = {
        useUserPackages = true;
        useGlobalPkgs = true;
        backupFileExtension = "rebuild";
        users.${username} = {
          config = {
            inherit (mergedConfig) customHomeManagerModules;
            programs.zsh.initContent = ''
              fastfetch
            '';
            home = {
              stateVersion = "24.05";
              username = "${username}";
              homeDirectory = "/home/${username}";
              sessionVariables = {
                NIXPKGS_ALLOW_UNFREE = 1;
              };
            };
            programs.home-manager.enable = true;
          };
          imports = lib.concatLists [
            mergedConfig.imports
            [
              ./nixbook-hm-compat.nix
            ]
            # Same position as nixbook's zsh/git: module order decides how
            # lists (home.packages, zsh init) merge.
            (
              if mergedConfig.lean then
                [ ../homeManagerModules/server.nix ]
              else
                [
                  (import "${sources.nixbook}//homeManagerModules/zshConfig.nix")
                  (import "${sources.nixbook}//homeManagerModules/gitConfig.nix")
                ]
            )
            [
              (import "${sources.nixbook}//homeManagerModules/sshConfig.nix")
              (import "${sources.nixbook}//homeManagerModules/fastfetchConfig.nix")
            ]
            userImports
          ];
        };
      };
    };
in
{
  inherit mkUser;
}
