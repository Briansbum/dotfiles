# Git Plugins
{ ... }:
{
  plugins = {
    # Fugitive for Git integration
    fugitive = {
      enable = true;
    };

    # Mini.diff for inline diff viewing
    mini = {
      enable = true;
      modules = {
        diff = {
          source = {
            __raw = "require('mini.diff').gen_source.none()";
          };
        };
      };
    };
  };

  # Git keymaps
  keymaps = [
    {
      mode = "n";
      key = "<leader>gs";
      action = "<cmd>Git<cr>";
      options = {
        desc = "Git status";
      };
    }
  ];
}
