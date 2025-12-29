# Keymaps
{ ... }:
{
  keymaps = [
    # Leader key mappings from remap.lua
    {
      mode = "n";
      key = "<leader>pv";
      action = "<cmd>Ex<cr>";
      options = {
        desc = "Open file explorer";
      };
    }

    # Clipboard mappings
    {
      mode = [ "n" "v" ];
      key = "<leader>y";
      action = "\"+y";
      options = {
        desc = "Yank to system clipboard";
      };
    }
    {
      mode = "n";
      key = "<leader>Y";
      action = "\"+Y";
      options = {
        desc = "Yank line to system clipboard";
      };
    }
    {
      mode = "n";
      key = "<leader>p";
      action = "\"+p";
      options = {
        desc = "Paste from system clipboard";
      };
    }
    {
      mode = "n";
      key = "<leader>P";
      action = "\"+P";
      options = {
        desc = "Paste before from system clipboard";
      };
    }

    # Go error handling snippet
    {
      mode = "n";
      key = "<leader>ee";
      action = "oif err != nil {<cr>}<esc>Oreturn <esc>";
      options = {
        desc = "Insert Go error handling";
      };
    }
  ];
}
