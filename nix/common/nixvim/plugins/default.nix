# Plugin modules aggregator
{ ... }:
{
  imports = [
    ./lsp.nix
    ./treesitter.nix
    ./ui.nix
    ./editor.nix
    ./git.nix
  ];
}
