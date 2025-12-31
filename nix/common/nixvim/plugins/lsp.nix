# LSP Configuration
{ pkgs, ... }:
{
  plugins = {
    # LSP
    lsp = {
      enable = true;

      servers = {
        bashls = {
          enable = true;
          filetypes = [ "sh" "bash" ];
        };
        dockerls = {
          enable = true;
          filetypes = [ "dockerfile" ];
        };
        docker_compose_language_service = {
          enable = true;
          filetypes = [ "yaml" "docker-compose" ];
        };
        dotls = {
          enable = true;
          filetypes = [ "dot" ];
        };
        eslint = {
          enable = true;
          filetypes = [ "javascript" "javascriptreact" "typescript" "typescriptreact" ];
        };
        gopls = {
          enable = true;
          filetypes = [ "go" "gomod" "gowork" "gotmpl" ];
          rootMarkers = [ "go.mod" "go.work" ".git" ];
        };
        helm_ls = {
          enable = true;
          filetypes = [ "helm" ];
        };
        html = {
          enable = true;
          filetypes = [ "html" ];
        };
        jsonls = {
          enable = true;
          filetypes = [ "json" "jsonc" ];
        };
        lua_ls = {
          enable = true;
          filetypes = [ "lua" ];
          rootMarkers = [ ".luarc.json" ".luarc.jsonc" ];
          settings = {
            Lua = {
              diagnostics = {
                globals = [ "vim" ];
              };
            };
          };
        };
        pylsp = {
          enable = true;
          filetypes = [ "python" ];
          rootMarkers = [ "pyproject.toml" "setup.py" "setup.cfg" "requirements.txt" "Pipfile" ];
        };
        rust_analyzer = {
          enable = true;
          installCargo = false;
          installRustc = false;
          filetypes = [ "rust" ];
          rootMarkers = [ "Cargo.toml" ];
        };
        terraformls = {
          enable = true;
          filetypes = [ "terraform" "tf" ];
          rootMarkers = [ ".terraform" ".git" ];
        };
        tflint = {
          enable = true;
          filetypes = [ "terraform" "tf" ];
          rootMarkers = [ ".tflint.hcl" ];
        };
      };

      keymaps = {
        diagnostic = {
          "[d" = "goto_next";
          "]d" = "goto_prev";
          "<leader>vd" = "open_float";
        };
        lspBuf = {
          "gd" = "definition";
          "K" = "hover";
          "<leader>vws" = "workspace_symbol";
          "<leader>vca" = "code_action";
          "<leader>vrr" = "references";
          "<leader>vrn" = "rename";
          "<leader>f" = "format";
        };
      };
    };

    # Completion
    cmp = {
      enable = true;
      settings = {
        sources = [
          { name = "nvim_lsp"; }
          { name = "luasnip"; }
          { name = "path"; }
          { name = "buffer"; }
        ];
        mapping = {
          "<Tab>" = "cmp.mapping.select_prev_item()";
          "<S-Tab>" = "cmp.mapping.select_next_item()";
          "<C-y>" = "cmp.mapping.confirm({ select = true })";
          "<C-Space>" = "cmp.mapping.complete()";
        };
        snippet = {
          expand = ''
            function(args)
              require('luasnip').lsp_expand(args.body)
            end
          '';
        };
      };
    };

    # Snippets
    luasnip.enable = true;
    cmp_luasnip.enable = true;
    cmp-nvim-lsp.enable = true;
    cmp-path.enable = true;
    cmp-buffer.enable = true;
  };

  # LSP server packages
  extraPackages = with pkgs; [
    # Language servers
    bash-language-server
    docker-compose-language-service
    docker-language-server
    dot-language-server
    gopls
    helm-ls
    lua-language-server
    python3Packages.python-lsp-server
    rust-analyzer
    terraform-ls
    tflint
    fish-lsp
    vscode-langservers-extracted  # Provides eslint, html, json, css
  ];

  # Additional LSP configuration
  extraConfigLua = ''
    -- Reserve space in the gutter
    vim.opt.signcolumn = 'yes'

    -- Add borders to floating windows
    vim.lsp.handlers['textDocument/hover'] = vim.lsp.with(
      vim.lsp.handlers.hover, { border = 'rounded' }
    )
    vim.lsp.handlers['textDocument/signatureHelp'] = vim.lsp.with(
      vim.lsp.handlers.signature_help, { border = 'rounded' }
    )

    -- Configure diagnostic display
    vim.diagnostic.config({
      virtual_text = false,
      severity_sort = true,
      float = {
        style = 'minimal',
        border = 'rounded',
        header = ''',
        prefix = ''',
      },
      signs = {
        text = {
          [vim.diagnostic.severity.ERROR] = '✘',
          [vim.diagnostic.severity.WARN] = '▲',
          [vim.diagnostic.severity.HINT] = '⚑',
          [vim.diagnostic.severity.INFO] = '»',
        }
      }
    })

    -- LSP keymaps for signature help in insert mode
    vim.api.nvim_create_autocmd('LspAttach', {
      desc = 'LSP additional keymaps',
      callback = function(event)
        local opts = { buffer = event.buf, remap = false }
        vim.keymap.set("i", "<C-h>", function() vim.lsp.buf.signature_help() end, opts)
      end
    })
  '';
}
