# Editor Plugins
{ ... }:
{
  plugins = {
    # Telescope fuzzy finder
    telescope = {
      enable = true;
      extensions = {
        fzf-native.enable = true;
      };
      keymaps = {
        "<leader>pf" = {
          action = "find_files";
          options = {
            desc = "Find files";
          };
        };
        "<C-p>" = {
          action = "git_files";
          options = {
            desc = "Find git files";
          };
        };
        "<leader>ps" = {
          action = "grep_string";
          options = {
            desc = "Grep string";
          };
        };
      };
    };

    # Harpoon for file navigation
    harpoon = {
      enable = true;
    };

    # Undotree
    undotree = {
      enable = true;
      settings = {
        autoOpenDiff = true;
        focusOnToggle = true;
      };
    };

    # Trouble diagnostics
    trouble = {
      enable = true;
    };

    # Formatter
    formatter = {
      enable = true;
    };

    # Image clipboard
    image-clip = {
      enable = true;
    };

    # Vim-go for Go development
    vim-go = {
      enable = true;
    };

    # Conjure for Clojure
    conjure = {
      enable = true;
    };

    # CtrlP
    ctrlp = {
      enable = true;
    };

    # Vim-be-good
    vim-be-good = {
      enable = true;
    };

    # Startup time
    vim-startuptime = {
      enable = true;
    };
  };

  # Additional editor keymaps
  keymaps = [
    {
      mode = "n";
      key = "<leader>u";
      action = "<cmd>UndotreeToggle<cr>";
      options = {
        desc = "Toggle undotree";
      };
    }
    {
      mode = "n";
      key = "<leader>xx";
      action = "<cmd>Trouble diagnostics toggle<cr>";
      options = {
        desc = "Diagnostics (Trouble)";
      };
    }
    {
      mode = "n";
      key = "<leader>xX";
      action = "<cmd>Trouble diagnostics toggle filter.buf=0<cr>";
      options = {
        desc = "Buffer Diagnostics (Trouble)";
      };
    }
    {
      mode = "n";
      key = "<leader>cs";
      action = "<cmd>Trouble symbols toggle focus=false<cr>";
      options = {
        desc = "Symbols (Trouble)";
      };
    }
    {
      mode = "n";
      key = "<leader>cl";
      action = "<cmd>Trouble lsp toggle focus=false win.position=right<cr>";
      options = {
        desc = "LSP Definitions / references / ... (Trouble)";
      };
    }
    {
      mode = "n";
      key = "<leader>xL";
      action = "<cmd>Trouble loclist toggle<cr>";
      options = {
        desc = "Location List (Trouble)";
      };
    }
    {
      mode = "n";
      key = "<leader>xQ";
      action = "<cmd>Trouble qflist toggle<cr>";
      options = {
        desc = "Quickfix List (Trouble)";
      };
    }
    {
      mode = "n";
      key = "<leader>gi";
      action = "<cmd>GoImplements<cr>";
      options = {
        desc = "Go Implements";
      };
    }
    # Harpoon keymaps
    {
      mode = "n";
      key = "<leader>a";
      action.__raw = "function() require('harpoon'):list():add() end";
      options = {
        desc = "Harpoon add file";
      };
    }
    {
      mode = "n";
      key = "<C-e>";
      action.__raw = "function() require('harpoon').ui:toggle_quick_menu(require('harpoon'):list()) end";
      options = {
        desc = "Harpoon toggle menu";
      };
    }
    {
      mode = "n";
      key = "<C-h>";
      action.__raw = "function() require('harpoon'):list():select(1) end";
      options = {
        desc = "Harpoon file 1";
      };
    }
    {
      mode = "n";
      key = "<C-j>";
      action.__raw = "function() require('harpoon'):list():select(2) end";
      options = {
        desc = "Harpoon file 2";
      };
    }
    {
      mode = "n";
      key = "<C-k>";
      action.__raw = "function() require('harpoon'):list():select(3) end";
      options = {
        desc = "Harpoon file 3";
      };
    }
    {
      mode = "n";
      key = "<C-l>";
      action.__raw = "function() require('harpoon'):list():select(4) end";
      options = {
        desc = "Harpoon file 4";
      };
    }
  ];

  # Telescope integration with Trouble
  extraConfigLua = ''
    local actions = require("telescope.actions")
    local trouble = require("trouble.sources.telescope")

    require("telescope").setup({
      defaults = {
        mappings = {
          i = { ["<c-t>"] = trouble.open },
          n = { ["<c-t>"] = trouble.open },
        },
      },
    })
  '';
}
