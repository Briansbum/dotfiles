# NixVim Configuration Entry Point
{ lib, ... }:
{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "vim-be-good"
    "vim-jack-in"
  ];

  imports = [
    ./options.nix
    ./keymaps.nix
    ./autocmds.nix
    ./plugins
    ./extraPlugins.nix
  ];

  # Enable providers
  withNodeJs = true;
  withPython3 = true;
  withRuby = true;

  # Vim aliases
  vimAlias = true;
  viAlias = true;
}
