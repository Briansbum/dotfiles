# Extra plugins not in nixpkgs or needing custom configuration
{ pkgs, ... }:
{
  extraPlugins = with pkgs.vimPlugins; [
    # CodeCompanion and dependencies
    codecompanion-nvim
    plenary-nvim

    # Vim dispatch for Clojure
    vim-dispatch
    vim-dispatch-neovim
    vim-jack-in

    # Terragrunt LSP - build from GitHub
    (pkgs.vimUtils.buildVimPlugin {
      name = "terragrunt-ls";
      src = pkgs.fetchFromGitHub {
        owner = "gruntwork-io";
        repo = "terragrunt-ls";
        rev = "main";  # Using main branch - can pin to specific commit if needed
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";  # Will be fixed by nix on first build
      };
    })

    # CodeCompanion Copilot Enterprise extension
    (pkgs.vimUtils.buildVimPlugin {
      name = "codecompanion-copilot-enterprise-nvim";
      src = pkgs.fetchFromGitHub {
        owner = "dyamon";
        repo = "codecompanion-copilot-enterprise.nvim";
        rev = "main";
        sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
    })
  ];

  extraConfigLua = ''
    -- CodeCompanion configuration
    require("codecompanion").setup({
      name = "opencode",
      formatted_name = "OpenCode",
      type = "acp",
      roles = {
        llm = "assistant",
        user = "user",
      },
      opts = {
        vision = false,
      },
      commands = {
        default = {
          "opencode",
          "acp",
        },
      },
      defaults = {
        timeout = 60000,
      },
      parameters = {
        protocolVersion = 1,
        clientInfo = {
          name = "CodeCompanion.nvim",
          version = "1.0.0",
        },
      },
    })

    -- Terragrunt LSP configuration
    local terragrunt_ls = require 'terragrunt-ls'
    terragrunt_ls.setup {
      cmd_env = {
        TG_LS_LOG = vim.fn.expand '/tmp/terragrunt-ls.log',
      },
    }
    if terragrunt_ls.client then
      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'hcl',
        callback = function()
          vim.lsp.buf_attach_client(0, terragrunt_ls.client)
        end,
      })
    end
  '';

  # Keymaps for CodeCompanion
  keymaps = [
    {
      mode = [ "n" "v" ];
      key = "<leader>]";
      action = ":Gen<CR>";
      options = {
        desc = "Open CodeCompanion";
      };
    }
  ];
}
