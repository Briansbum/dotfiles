# zk note-taking
{ ... }:
{
  plugins.zk = {
    enable = true;
    settings.picker = "telescope";
  };

  keymaps = [
    {
      mode = "n";
      key = "<leader>zn";
      action = "<cmd>ZkNew { title = vim.fn.input('Title: ') }<cr>";
      options = {
        desc = "New note";
      };
    }
    {
      mode = "n";
      key = "<leader>zf";
      action = "<cmd>ZkNotes { sort = { 'modified' } }<cr>";
      options = {
        desc = "Find notes";
      };
    }
    {
      mode = "n";
      key = "<leader>zt";
      action = "<cmd>ZkTags<cr>";
      options = {
        desc = "Browse notes by tag";
      };
    }
    {
      mode = "n";
      key = "<leader>zd";
      action = "<cmd>ZkNew { dir = 'journal' }<cr>";
      options = {
        desc = "Open today's journal note";
      };
    }
    {
      mode = "n";
      key = "<leader>zm";
      action = "<cmd>ZkNew { dir = 'music', title = vim.fn.input('Title: '), extra = { artist = vim.fn.input('Artist: ') } }<cr>";
      options = {
        desc = "New music note";
      };
    }
    {
      mode = "n";
      key = "<leader>zb";
      action = "<cmd>ZkBacklinks<cr>";
      options = {
        desc = "Backlinks to current note";
      };
    }
    {
      mode = "n";
      key = "<leader>zl";
      action = "<cmd>ZkLinks<cr>";
      options = {
        desc = "Links from current note";
      };
    }
    {
      mode = "v";
      key = "<leader>zi";
      action = ":'<,'>ZkInsertLinkAtSelection<cr>";
      options = {
        desc = "Insert link at selection";
      };
    }
  ];
}
