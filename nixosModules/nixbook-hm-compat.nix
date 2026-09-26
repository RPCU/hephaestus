# nixosModules/nixbook-hm-compat.nix
# Home Manager shim for nixbook's homeManagerModules, which track
# home-manager master while hephaestus pins release-26.05.
#
# nixbook's zshConfig.nix sets `programs.fzf.historyWidget.zsh.command = ""`
# (hand Ctrl-R to atuin). release-26.05 has no `historyWidget` option, so
# evaluation fails. Declare it here and reproduce master's behaviour
# (FZF_CTRL_R_COMMAND="" disables fzf's Ctrl-R binding, fzf >= 0.66).
#
# DELETE this module once the home-manager pin ships `programs.fzf.historyWidget`
# (evaluation will fail with "option already declared" as a reminder).
{ config, lib, ... }:
let
  cfg = config.programs.fzf.historyWidget;
in
{
  options.programs.fzf.historyWidget = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
    default = { };
    description = "Compat stub for home-manager master's per-shell fzf history widget options.";
  };

  config = lib.mkIf (config.programs.fzf.enable && cfg ? zsh && cfg.zsh ? command) {
    programs.zsh.sessionVariables.FZF_CTRL_R_COMMAND = cfg.zsh.command;
  };
}
