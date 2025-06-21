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

vim.api.nvim_create_autocmd('FileType', {
    pattern = 'fish',
    callback = function()
        vim.lsp.start({
            name = 'fish-lsp',
            cmd = { 'fish-lsp', 'start' },
            cmd_env = { fish_lsp_show_client_popups = false },
        })
    end,
})

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
            lazy = false,
            build = ':TSUpdate',
            config = function()
                require('nvim-treesitter.configs').setup({
                    -- A list of parser names, or "all"
                    ensure_installed = { "c", "lua", "vim", "vimdoc", "query", "javascript", "typescript", "rust", "go", "gomod", "gosum", "bash" },

                    -- Install parsers synchronously (only applied to `ensure_installed`)
                    sync_install = false,

                    -- Automatically install missing parsers when entering buffer
                    auto_install = true,

                    highlight = {
                        enable = true,
                    }
                })
            end,
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
            "neovim/nvim-lspconfig",
        },
        {
            "williamboman/mason.nvim",
            run = function()
                vim.cmd([[MasonUpdate]])
            end,
        },
        {
            "williamboman/mason-lspconfig.nvim",
        },
        {
            "hrsh7th/nvim-cmp",
        },
        {
            "hrsh7th/cmp-nvim-lsp",
        },
        {
            "L3MON4D3/LuaSnip",
        },
        {
            "nvim-lualine/lualine.nvim",
            dependencies = { "nvim-tree/nvim-web-devicons" },
            config = function()
                require("lualine").setup({ theme = "tokyonight" })
            end,
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
        {
            'ThePrimeagen/vim-be-good',
        },
        {
            'dstein64/vim-startuptime',
        },
        {
            "David-Kunz/gen.nvim",
            opts = {
                model = "deepseek-r1:14b", -- The default model to use.
                quit_map = "q",            -- set keymap to close the response window
                retry_map = "<c-r>",       -- set keymap to re-send the current prompt
                accept_map = "<c-cr>",     -- set keymap to replace the previous selection with the last result
                host = "localhost",        -- The host running the Ollama service.
                port = "11434",            -- The port on which the Ollama service is listening.
                display_mode = "float",    -- The display mode. Can be "float" or "split" or "horizontal-split".
                show_prompt = true,        -- Shows the prompt submitted to Ollama. Can be true (3 lines) or "full".
                show_model = true,         -- Displays which model you are using at the beginning of your chat session.
                no_auto_close = false,     -- Never closes the window automatically.
                file = false,              -- Write the payload to a temporary file to keep the command short.
                hidden = false,            -- Hide the generation window (if true, will implicitly set `prompt.replace = true`), requires Neovim >= 0.10
                init = function(options) pcall(io.popen, "ollama serve > /dev/null 2>&1 &") end,
                -- Function to initialize Ollama
                command = function(options)
                    local body = { model = options.model, stream = true }
                    return "curl --silent --no-buffer -X POST http://" ..
                        options.host .. ":" .. options.port .. "/api/chat -d $body"
                end,
                -- The command for the Ollama service. You can use placeholders $prompt, $model and $body (shellescaped).
                -- This can also be a command string.
                -- The executed command must return a JSON object with { response, context }
                -- (context property is optional).
                -- list_models = '<omitted lua function>', -- Retrieves a list of model names
                result_filetype = "markdown", -- Configure filetype of the result buffer
                debug = false                 -- Prints errors and the command which is run.
            }
        },
    }
)
