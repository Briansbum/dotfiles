require("alex")

vim.g.netrw_liststyle = 0
vim.g.netrw_browse_split = 0
vim.g.netrw_banner = 0
vim.g.netrw_winsize = 25

vim.opt.guicursor = ""

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable", -- latest stable release
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup(
    {
        {
            "folke/tokyonight.nvim",
            lazy = false,    -- make sure we load this during startup if it is your main colorscheme
            priority = 1000, -- make sure to load this before all the other start plugins
            config = function()
                vim.cmd([[colorscheme tokyonight-moon]])

                vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
                vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })

                vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
                vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
                vim.api.nvim_set_hl(0, 'LineNrAbove', { fg = '#51B3EC', bold = true })
                vim.api.nvim_set_hl(0, 'LineNr', { fg = 'white', bold = true })
                vim.api.nvim_set_hl(0, 'LineNrBelow', { fg = '#FB508F', bold = true })
                vim.api.nvim_set_hl(0, 'SignColumn', { bg = "none" })

                vim.cmd('highlight Comment guifg=#FFFFFF')
            end,
        },
        {
            "nvim-telescope/telescope.nvim",
            dependencies = { "nvim-lua/plenary.nvim" },
        },
        {
            "nvim-tree/nvim-web-devicons",
        },
        {
            "nvim-treesitter/nvim-treesitter",
            config = function()
                vim.cmd([[TSUpdate]])
            end,
        },
        {
            "nvim-treesitter/playground",
        },
        {
            "theprimeagen/harpoon",
        },
        {
            "mbbill/undotree",
        },
        {
            "tpope/vim-fugitive",
        },
        {
            "VonHeikemen/lsp-zero.nvim",
            branch = "v2.x",
            dependencies = {
                "neovim/nvim-lspconfig",
                {
                    "williamboman/mason.nvim",
                    run = function()
                        vim.cmd([[MasonUpdate]])
                    end,
                },
                "williamboman/mason-lspconfig.nvim",
                "hrsh7th/nvim-cmp",
                "hrsh7th/cmp-nvim-lsp",
                "L3MON4D3/LuaSnip",
            },
        },
        {
            "nvim-lualine/lualine.nvim",
            dependencies = { "nvim-tree/nvim-web-devicons" },
            config = function()
                require("lualine").setup({ theme = "tokyonight" })
            end,
        },
        {
            "github/copilot.vim",
        },
        {
            "mhartington/formatter.nvim",
        },
        {
            "ellisonleao/glow.nvim",
            config = function()
                require("glow").setup()
            end,
        },
        {
            "folke/which-key.nvim",
            config = function()
                vim.opt.timeout = true
            end,
        },
        {
            "lukas-reineke/indent-blankline.nvim",
        },
        {
            "HiPhish/rainbow-delimiters.nvim",
        },
        {
            "fatih/vim-go",
        },
        {
            "folke/trouble.nvim",
            opts = {}, -- for default options, refer to the configuration section for custom setup.
            dependencies = { "nvim-tree/nvim-web-devicons" },
            cmd = "Trouble",
            keys = {
                {
                    "<leader>xx",
                    "<cmd>Trouble diagnostics toggle<cr>",
                    desc = "Diagnostics (Trouble)",
                },
                {
                    "<leader>xX",
                    "<cmd>Trouble diagnostics toggle filter.buf=0<cr>",
                    desc = "Buffer Diagnostics (Trouble)",
                },
                {
                    "<leader>cs",
                    "<cmd>Trouble symbols toggle focus=false<cr>",
                    desc = "Symbols (Trouble)",
                },
                {
                    "<leader>cl",
                    "<cmd>Trouble lsp toggle focus=false win.position=right<cr>",
                    desc = "LSP Definitions / references / ... (Trouble)",
                },
                {
                    "<leader>xL",
                    "<cmd>Trouble loclist toggle<cr>",
                    desc = "Location List (Trouble)",
                },
                {
                    "<leader>xQ",
                    "<cmd>Trouble qflist toggle<cr>",
                    desc = "Quickfix List (Trouble)",
                },
            },
        },
        {
            "ctrlpvim/ctrlp.vim",
        },
    }
)
