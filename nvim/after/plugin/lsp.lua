-- Reserve space in the gutter
vim.opt.signcolumn = 'yes'

-- Add borders to floating windows
vim.lsp.handlers['textDocument/hover'] = vim.lsp.with(
  vim.lsp.handlers.hover, {border = 'rounded'}
)
vim.lsp.handlers['textDocument/signatureHelp'] = vim.lsp.with(
  vim.lsp.handlers.signature_help, {border = 'rounded'}
)

-- Configure diagnostic display
vim.diagnostic.config({
  virtual_text = false,
  severity_sort = true,
  float = {
    style = 'minimal',
    border = 'rounded',
    header = '',
    prefix = '',
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

-- Setup CMP for completion
local cmp = require('cmp')
local cmp_select = { behavior = cmp.SelectBehavior.Select }
local cmp_mappings = {
  ['<tab>'] = cmp.mapping.select_prev_item(cmp_select),
  ['<S-tab>'] = cmp.mapping.select_next_item(cmp_select),
  ['<C-y>'] = cmp.mapping.confirm({ select = true }),
  ["<C-Space>"] = cmp.mapping.complete(),
}

cmp.setup({
  sources = {
    {name = 'nvim_lsp'},
  },
  mapping = cmp_mappings,
  snippet = {
    expand = function(args)
      vim.snippet.expand(args.body)
    end,
  },
})

-- Add LSP capabilities to lspconfig defaults
local lspconfig_defaults = require('lspconfig').util.default_config
lspconfig_defaults.capabilities = vim.tbl_deep_extend(
  'force',
  lspconfig_defaults.capabilities,
  require('cmp_nvim_lsp').default_capabilities()
)

-- Create LSP configurations
vim.lsp.config['lua_ls'] = {
  cmd = { 'lua-language-server' },
  filetypes = { 'lua' },
  root_markers = { '.luarc.json', '.luarc.jsonc' },
  settings = {
    Lua = {
      diagnostics = {
        globals = { 'vim' }
      }
    }
  }
}

vim.lsp.config['ansiblels'] = {
  cmd = { 'ansible-language-server', '--stdio' },
  filetypes = { 'yaml.ansible' },
  root_markers = { 'ansible.cfg', '.ansible-lint' }
}

vim.lsp.config['bashls'] = {
  cmd = { 'bash-language-server', 'start' },
  filetypes = { 'sh', 'bash' }
}

vim.lsp.config['dockerls'] = {
  cmd = { 'docker-langserver', '--stdio' },
  filetypes = { 'dockerfile' }
}

vim.lsp.config['docker_compose_language_service'] = {
  cmd = { 'docker-compose-langserver', '--stdio' },
  filetypes = { 'yaml', 'docker-compose' }
}

vim.lsp.config['dotls'] = {
  cmd = { 'dot-language-server', '--stdio' },
  filetypes = { 'dot' }
}

vim.lsp.config['eslint'] = {
  cmd = { 'vscode-eslint-language-server', '--stdio' },
  filetypes = { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact' }
}

vim.lsp.config['gopls'] = {
  cmd = { 'gopls' },
  filetypes = { 'go', 'gomod', 'gowork', 'gotmpl' },
  root_markers = { 'go.mod', 'go.work', '.git' }
}

vim.lsp.config['html'] = {
  cmd = { 'vscode-html-language-server', '--stdio' },
  filetypes = { 'html' }
}

vim.lsp.config['helm_ls'] = {
  cmd = { 'helm_ls', 'serve' },
  filetypes = { 'helm' }
}

vim.lsp.config['jsonls'] = {
  cmd = { 'vscode-json-language-server', '--stdio' },
  filetypes = { 'json', 'jsonc' }
}

vim.lsp.config['pylsp'] = {
  cmd = { 'pylsp' },
  filetypes = { 'python' },
  root_markers = { 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', 'Pipfile' }
}

vim.lsp.config['rust_analyzer'] = {
  cmd = { 'rust-analyzer' },
  filetypes = { 'rust' },
  root_markers = { 'Cargo.toml' }
}

vim.lsp.config['terraformls'] = {
  cmd = { 'terraform-ls', 'serve' },
  filetypes = { 'terraform', 'tf' },
  root_markers = { '.terraform', '.git' }
}

vim.lsp.config['tflint'] = {
  cmd = { 'tflint', '--langserver' },
  filetypes = { 'terraform', 'tf' },
  root_markers = { '.tflint.hcl' }
}

-- Enable all configured LSP servers
vim.lsp.enable({
  'ansiblels',
  'bashls',
  'dockerls',
  'docker_compose_language_service',
  'dotls',
  'eslint',
  'gopls',
  'html',
  'helm_ls',
  'jsonls',
  'lua_ls',
  'pylsp',
  'rust_analyzer',
  'terraformls',
  'tflint'
})

-- Preserve all your custom keymaps with LspAttach
vim.api.nvim_create_autocmd('LspAttach', {
  desc = 'LSP actions',
  callback = function(event)
    local opts = { buffer = event.buf, remap = false }

    vim.keymap.set("n", "gd", function() vim.lsp.buf.definition() end, opts)
    vim.keymap.set("n", "K", function() vim.lsp.buf.hover() end, opts)
    vim.keymap.set("n", "<leader>vws", function() vim.lsp.buf.workspace_symbol() end, opts)
    vim.keymap.set("n", "<leader>vd", function() vim.diagnostic.open_float() end, opts)
    vim.keymap.set("n", "[d", function() vim.diagnostic.goto_next() end, opts)
    vim.keymap.set("n", "]d", function() vim.diagnostic.goto_prev() end, opts)
    vim.keymap.set("n", "<leader>vca", function() vim.lsp.buf.code_action() end, opts)
    vim.keymap.set("n", "<leader>vrr", function() vim.lsp.buf.references() end, opts)
    vim.keymap.set("n", "<leader>vrn", function() vim.lsp.buf.rename() end, opts)
    vim.keymap.set("i", "<C-h>", function() vim.lsp.buf.signature_help() end, opts)
    vim.keymap.set('n', '<leader>f', function() vim.lsp.buf.format() end, opts)
  end
})

-- Preserve your special Go format autocmd
vim.api.nvim_create_autocmd('BufWritePre', {
  pattern = '*.go',
  callback = function()
    vim.lsp.buf.format()
    vim.lsp.buf.code_action({ context = { only = { 'source.organizeImports' } }, apply = true })
    vim.cmd([[ silent ! go mod tidy ]])
    vim.cmd([[ silent LspRestart ]])
    vim.cmd([[ silent w ]])
    vim.cmd([[ silent w ]])
    vim.cmd([[ silent w ]])
  end
})
