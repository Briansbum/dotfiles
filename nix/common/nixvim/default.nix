# NixVim Configuration Entry Point
{ ... }:
{
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
