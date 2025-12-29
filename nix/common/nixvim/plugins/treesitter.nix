# Treesitter configuration
{ ... }:
{
  plugins = {
    treesitter = {
      enable = true;
      settings = {
        highlight = {
          enable = true;
        };
        indent = {
          enable = true;
        };
        ensure_installed = [
          "c"
          "lua"
          "vim"
          "vimdoc"
          "query"
          "javascript"
          "typescript"
          "rust"
          "go"
          "gomod"
          "gosum"
          "bash"
          "markdown"
          "markdown_inline"
        ];
      };
    };

    # Treesitter playground
    treesitter-playground.enable = true;
  };
}
