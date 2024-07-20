-- vim.cmd("Copilot enable")

vim.keymap.set('i', '<C-]>', 'copilot#Accept("")', {
    expr = true,
    replace_keycodes = false
})
vim.g.copilot_no_tab_map = true

vim.keymap.set('i', '<C-j>', 'copilot#Reject("")', {
    expr = true,
    replace_keycodes = false
})
