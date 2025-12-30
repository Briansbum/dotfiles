# UI Plugins
{ pkgs, ... }:
{
  plugins = {
    # Colorscheme
    colorschemes.rose-pine = {
      enable = true;
    };

    # Statusline
    lualine = {
      enable = true;
    };

    # Which-key for keybinding help
    which-key = {
      enable = true;
    };

    # Web devicons
    web-devicons.enable = true;

    # Indent guides with rainbow colors
    indent-blankline = {
      enable = true;
      settings = {
        scope = {
          enabled = true;
        };
      };
    };

    # Rainbow delimiters
    rainbow-delimiters.enable = true;

    # Render markdown
    render-markdown.enable = true;

    # Glow for markdown preview
    glow.enable = true;
  };

  colorscheme = "rose-pine";

  # Additional UI configuration
  extraConfigLua = ''
    -- Custom colors
    vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
    vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
    vim.api.nvim_set_hl(0, 'LineNrAbove', { fg = '#51B3EC', bold = true })
    vim.api.nvim_set_hl(0, 'LineNr', { fg = 'white', bold = true })
    vim.api.nvim_set_hl(0, 'LineNrBelow', { fg = '#FB508F', bold = true })
    vim.api.nvim_set_hl(0, 'SignColumn', { bg = "none" })
    vim.cmd('highlight Comment guifg=#FFFFFF')

    -- Lualine bubbles theme configuration
    local colors = {
      blue   = '#80a0ff',
      cyan   = '#79dac8',
      black  = '#080808',
      white  = '#c6c6c6',
      red    = '#ff5189',
      violet = '#d183e8',
      grey   = '#303030',
    }

    local bubbles_theme = {
      normal = {
        a = { fg = colors.black, bg = colors.violet },
        b = { fg = colors.white, bg = colors.grey },
        c = { fg = colors.black, bg = colors.black },
      },
      insert = { a = { fg = colors.black, bg = colors.blue } },
      visual = { a = { fg = colors.black, bg = colors.cyan } },
      replace = { a = { fg = colors.black, bg = colors.red } },
      inactive = {
        a = { fg = colors.white, bg = colors.black },
        b = { fg = colors.white, bg = colors.black },
        c = { fg = colors.black, bg = colors.black },
      },
    }

    require('lualine').setup {
      options = {
        theme = bubbles_theme,
        component_separators = '|',
        section_separators = { left = "", right = "" },
      },
      sections = {
        lualine_a = {
          { 'mode', separator = { left = "" }, right_padding = 2 },
        },
        lualine_b = { 'filename', 'branch' },
        lualine_c = { 'fileformat' },
        lualine_x = {},
        lualine_y = { 'filetype', 'progress' },
        lualine_z = {
          { 'location', separator = { right = "" }, left_padding = 2 },
        },
      },
      inactive_sections = {
        lualine_a = { 'filename' },
        lualine_b = {},
        lualine_c = {},
        lualine_x = {},
        lualine_y = {},
        lualine_z = { 'location' },
      },
      tabline = {},
      extensions = {},
    }

    -- Rainbow indent-blankline setup
    local highlight = {
      "RainbowRed", "RainbowYellow", "RainbowBlue",
      "RainbowOrange", "RainbowGreen", "RainbowViolet", "RainbowCyan",
    }
    local hooks = require "ibl.hooks"

    hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
      vim.api.nvim_set_hl(0, "RainbowRed", { fg = "#E06C75" })
      vim.api.nvim_set_hl(0, "RainbowYellow", { fg = "#E5C07B" })
      vim.api.nvim_set_hl(0, "RainbowBlue", { fg = "#61AFEF" })
      vim.api.nvim_set_hl(0, "RainbowOrange", { fg = "#D19A66" })
      vim.api.nvim_set_hl(0, "RainbowGreen", { fg = "#98C379" })
      vim.api.nvim_set_hl(0, "RainbowViolet", { fg = "#C678DD" })
      vim.api.nvim_set_hl(0, "RainbowCyan", { fg = "#56B6C2" })
    end)

    vim.g.rainbow_delimiters = { highlight = highlight }
    require("ibl").setup { scope = { highlight = highlight } }

    hooks.register(hooks.type.SCOPE_HIGHLIGHT, hooks.builtin.scope_highlight_from_extmark)

    -- Web devicons configuration
    require 'nvim-web-devicons'.setup {
      override = {
        zsh = {
          icon = "",
          color = "#428850",
          cterm_color = "65",
          name = "Zsh"
        }
      },
      color_icons = true,
      default = true,
      strict = true,
      override_by_filename = {
        [".gitignore"] = {
          icon = "",
          color = "#f1502f",
          name = "Gitignore"
        }
      },
      override_by_extension = {
        ["log"] = {
          icon = "",
          color = "#81e043",
          name = "Log"
        }
      },
    }
  '';
}
