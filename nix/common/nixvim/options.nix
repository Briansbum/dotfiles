# Vim options (vim.opt.*)
{ ... }:
{
  opts = {
    # Line numbers
    number = true;
    relativenumber = true;

    # Tabs and indentation
    tabstop = 4;
    softtabstop = 4;
    shiftwidth = 4;
    expandtab = true;
    smartindent = true;

    # Line wrapping
    wrap = false;

    # File handling
    swapfile = false;
    backup = false;
    undofile = true;

    # Search
    hlsearch = false;
    incsearch = true;

    # UI
    termguicolors = true;
    scrolloff = 8;
    signcolumn = "yes";
    colorcolumn = "80";

    # Cursor
    guicursor = "";
  };

  globals = {
    mapleader = " ";
    maplocalleader = ";";

    # Netrw settings
    netrw_liststyle = 0;
    netrw_browse_split = 0;
    netrw_banner = 0;
    netrw_winsize = 25;
  };

  # Filetype detection
  filetype = {
    extension = {
      tf = "terraform";
    };
  };
}
