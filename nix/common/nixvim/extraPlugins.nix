# Extra plugins not in nixpkgs or needing custom configuration
{ pkgs, ... }:
let
  # Terragrunt LSP - source pinned to commit db8c2af from 2026-05-05
  # New since a82e243: rename, references, go-to-definition for locals (#141).
  # To update: change rev to new commit SHA and run:
  #   nix-prefetch-url --unpack https://github.com/gruntwork-io/terragrunt-ls/archive/<NEW_SHA>.tar.gz
  #   nix hash convert --to sri --hash-algo sha256 <hash_output>
  # vendorHash: set to pkgs.lib.fakeHash, rebuild, copy "got:" hash from error.
  terragrunt-ls-src = pkgs.fetchFromGitHub {
    owner = "gruntwork-io";
    repo = "terragrunt-ls";
    rev = "db8c2af";
    sha256 = "sha256-POdvFZH6a6tcUrGez8lmi+BOAdkLpvjENTT/50cwmVQ=";
  };

  terragrunt-ls-bin = pkgs.buildGoModule {
    pname = "terragrunt-ls";
    version = "db8c2af";
    src = terragrunt-ls-src;
    vendorHash = "sha256-wqQPMVP2822N55m5A0/EiCzgVPITJkfrKlHwQWvSte0=";
  };
in
{
  extraPlugins = with pkgs.vimPlugins; [
    # CodeCompanion and dependencies
    codecompanion-nvim
    plenary-nvim

    # Vim dispatch for Clojure
    vim-dispatch
    vim-dispatch-neovim
    vim-jack-in

    (pkgs.vimUtils.buildVimPlugin {
      name = "terragrunt-ls";
      src = terragrunt-ls-src;
    })

    # 99 - ThePrimeagen's AI agent plugin
    # Pinned to commit 4d22914 from 2026-05-02
    # New since 9d77c03: visual context bounds fixes (#171), test coverage.
    # To update: change rev to new commit SHA and run:
    #   nix-prefetch-url --unpack https://github.com/ThePrimeagen/99/archive/<NEW_SHA>.tar.gz
    #   nix hash convert --to sri --hash-algo sha256 <hash_output>
    (pkgs.vimUtils.buildVimPlugin {
      name = "99-nvim";
      doCheck = false;
      src = pkgs.fetchFromGitHub {
        owner = "ThePrimeagen";
        repo = "99";
        rev = "4d22914";
        sha256 = "sha256-LQb5jqzTNWVyFNKlICjhnk25fTAmyC38s8/mrOKp//M=";
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
      name = "claude-code",
      formatted_name = "Claude Code",
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
          "claude",
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

    -- Terragrunt LSP: lazy-init on first hcl buffer.
    -- Avoids calling vim.lsp.start_client at startup (deprecation warning in
    -- nvim 0.11+ — upstream plugin uses it; we cannot suppress without patching).
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'hcl',
      callback = function(args)
        local tg = require 'terragrunt-ls'
        if not tg.client then
          tg.setup {
            cmd = { '${terragrunt-ls-bin}/bin/terragrunt-ls' },
            cmd_env = {
              TG_LS_LOG = vim.fn.expand '/tmp/terragrunt-ls.log',
            },
          }
        end
        if tg.client then
          vim.lsp.buf_attach_client(args.buf, tg.client)
        end
      end,
    })
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
