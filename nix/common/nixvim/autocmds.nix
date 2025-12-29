# Autocommands
{ ... }:
{
  autoCmd = [
    # Fish LSP autocmd
    {
      event = "FileType";
      pattern = "fish";
      callback = {
        __raw = ''
          function()
            vim.lsp.start({
              name = 'fish-lsp',
              cmd = { 'fish-lsp', 'start' },
              cmd_env = { fish_lsp_show_client_popups = false },
            })
          end
        '';
      };
    }

    # Go format and organize imports on save
    {
      event = "BufWritePre";
      pattern = "*.go";
      callback = {
        __raw = ''
          function()
            vim.lsp.buf.format()
            vim.lsp.buf.code_action({ context = { only = { 'source.organizeImports' } }, apply = true })
            vim.cmd([[ silent ! go mod tidy ]])
            vim.cmd([[ silent LspRestart ]])
            vim.cmd([[ silent w ]])
            vim.cmd([[ silent w ]])
            vim.cmd([[ silent w ]])
          end
        '';
      };
    }
  ];
}
