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
