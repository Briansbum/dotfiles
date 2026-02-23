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

    # 99 - ThePrimeagen's AI agent plugin
    # Pinned to commit 9d77c03 from 2026-02-23
    # To update: change rev to new commit SHA and run:
    #   nix-prefetch-url --unpack https://github.com/ThePrimeagen/99/archive/<NEW_SHA>.tar.gz
    #   nix hash convert --to sri --hash-algo sha256 <hash_output>
    (pkgs.vimUtils.buildVimPlugin {
      name = "99-nvim";
      doCheck = false;
      src = pkgs.fetchFromGitHub {
        owner = "ThePrimeagen";
        repo = "99";
        rev = "9d77c036d1170fb7cb346aa1f1a802cde8dd3bb6";
        sha256 = "sha256-jPNptf5snX9AyDBbXZchfSQ/yQlgYanTBeAxpkusbTA=";
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
    -- 99 configuration (ThePrimeagen AI agent)
    local _99 = require("99")
    _99.setup({
      provider = _99.Providers.ClaudeCodeProvider,
      model = "claude-opus-4-6",
      tmp_dir = vim.fn.stdpath("data") .. "/99",
    })
    vim.fn.mkdir(vim.fn.stdpath("data") .. "/99", "p")
    -- Core
    vim.keymap.set("v", "<leader>9v", _99.visual, { desc = "99: Send selection to AI" })
    vim.keymap.set("n", "<leader>9s", _99.search, { desc = "99: AI search" })
    vim.keymap.set("n", "<leader>9x", _99.stop_all_requests, { desc = "99: Stop all requests" })
    vim.keymap.set("n", "<leader>9c", _99.clear_previous_requests, { desc = "99: Clear request history" })
    vim.keymap.set("n", "<leader>9m", _99.clear_all_marks, { desc = "99: Clear all marks" })

    -- Logs
    vim.keymap.set("n", "<leader>9l", _99.view_logs, { desc = "99: View logs" })
    vim.keymap.set("n", "<leader>9[", _99.prev_request_logs, { desc = "99: Previous request logs" })
    vim.keymap.set("n", "<leader>9]", _99.next_request_logs, { desc = "99: Next request logs" })
    vim.keymap.set("n", "<leader>9i", _99.info, { desc = "99: Info" })

    -- Worker (iterative dev workflow)
    local worker = _99.Extensions.Worker
    vim.keymap.set("n", "<leader>9ws", worker.set_work, { desc = "99: Set work item" })
    vim.keymap.set("n", "<leader>9wu", worker.updated_work, { desc = "99: Update work item" })
    vim.keymap.set("n", "<leader>9ww", worker.work, { desc = "99: Run work search" })
    vim.keymap.set("n", "<leader>9wr", worker.last_search_results, { desc = "99: Last work results (qfix)" })

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
