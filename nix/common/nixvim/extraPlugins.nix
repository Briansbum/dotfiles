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
    # Pinned to commit a82e243 from 2025-06-28
    # To update: change rev to new commit SHA and run:
    #   nix-prefetch-url --unpack https://github.com/gruntwork-io/terragrunt-ls/archive/<NEW_SHA>.tar.gz
    #   nix hash convert --to base64 <hash_output>
    (pkgs.vimUtils.buildVimPlugin {
      name = "terragrunt-ls";
      src = pkgs.fetchFromGitHub {
        owner = "gruntwork-io";
        repo = "terragrunt-ls";
        rev = "a82e24338bae87e5a3d1e8cf81179ce8a848ae3e";
        sha256 = "sha256-Ni9TccTLbixtczJvKDUJqgGwFCj9TRNX0zp6421BaYY=";
      };
    })

    # CodeCompanion Copilot Enterprise extension
    # Pinned to commit 2e5edc4 from 2025-09-01
    # To update: change rev to new commit SHA and run:
    #   nix-prefetch-url --unpack https://github.com/dyamon/codecompanion-copilot-enterprise.nvim/archive/<NEW_SHA>.tar.gz
    #   nix hash convert --to base64 <hash_output>
    (pkgs.vimUtils.buildVimPlugin {
      name = "codecompanion-copilot-enterprise-nvim";
      doCheck = false; # Skip require checks - plugin depends on codecompanion-nvim at runtime
      src = pkgs.fetchFromGitHub {
        owner = "dyamon";
        repo = "codecompanion-copilot-enterprise.nvim";
        rev = "2e5edc4fd32775dfff578c283624ed97334a9372";
        sha256 = "sha256-io9xsiLGzsGlBfRyfc792gDRN75W329S/b2+n7gRRKg=";
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
