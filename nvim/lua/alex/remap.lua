vim.keymap.set("n", "<leader>pv", vim.cmd.Ex)

vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]])
vim.keymap.set("n", "<leader>Y", [["+Y]])

vim.keymap.set("n", "<leader>p", [["+p]])
vim.keymap.set("n", "<leader>P", [["+P]])

vim.keymap.set("n", "<leader>ee", "oif err != nil {<cr>}<esc>Oreturn fmt.Errorf(\"%w\", err)<esc>")
