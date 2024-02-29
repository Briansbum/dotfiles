vim.opt.background = "dark"
vim.cmd("colorscheme oxocarbon")

vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
vim.api.nvim_set_hl(0, 'LineNrAbove', { fg = '#51B3EC', bold = true })
vim.api.nvim_set_hl(0, 'LineNr', { fg = 'white', bold = true })
vim.api.nvim_set_hl(0, 'LineNrBelow', { fg = '#FB508F', bold = true })
vim.api.nvim_set_hl(0, 'SignColumn', { bg = "none" })

vim.cmd('highlight Comment guifg=#BD00FF')
