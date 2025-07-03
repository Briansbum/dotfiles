require("alex")

vim.g.netrw_liststyle = 0
vim.g.netrw_browse_split = 0
vim.g.netrw_banner = 0
vim.g.netrw_winsize = 25

vim.opt.guicursor = ""

-- Add filetypes
vim.filetype.add({ extension = { tf = 'terraform' } })

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable",
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

require("lazy").setup({
    -- Colorscheme (needs to load early)
    {
        "folke/tokyonight.nvim",
        lazy = false,
        priority = 1000,
        config = function()
            vim.cmd([[colorscheme tokyonight-moon]])
            vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
            vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
            vim.api.nvim_set_hl(0, 'LineNrAbove', { fg = '#51B3EC', bold = true })
            vim.api.nvim_set_hl(0, 'LineNr', { fg = 'white', bold = true })
            vim.api.nvim_set_hl(0, 'LineNrBelow', { fg = '#FB508F', bold = true })
            vim.api.nvim_set_hl(0, 'SignColumn', { bg = "none" })
            vim.cmd('highlight Comment guifg=#FFFFFF')
        end,
    },

    -- Telescope (lazy loaded)
    {
        "nvim-telescope/telescope.nvim",
        lazy = true,
        cmd = "Telescope",
        dependencies = { "nvim-lua/plenary.nvim" },
        keys = {
            { '<leader>pf', function() require('telescope.builtin').find_files() end },
            { '<C-p>', function() require('telescope.builtin').git_files() end },
            { '<leader>ps', function()
                require('telescope.builtin').grep_string({ search = vim.fn.input("Grep > ") })
            end },
        },
        config = function()
            local actions = require("telescope.actions")
            local trouble = require("trouble.sources.telescope")
            
            require("telescope").setup({
                defaults = {
                    mappings = {
                        i = { ["<c-t>"] = trouble.open },
                        n = { ["<c-t>"] = trouble.open },
                    },
                },
            })
        end,
    },

    -- Icons (lazy loaded)
    {
        "nvim-tree/nvim-web-devicons",
        lazy = true,
        config = function()
            require'nvim-web-devicons'.setup {
                override = {
                    zsh = {
                        icon = "",
                        color = "#428850",
                        cterm_color = "65",
                        name = "Zsh"
                    }
                },
                color_icons = true,
                default = true,
                strict = true,
                override_by_filename = {
                    [".gitignore"] = {
                        icon = "",
                        color = "#f1502f",
                        name = "Gitignore"
                    }
                },
                override_by_extension = {
                    ["log"] = {
                        icon = "",
                        color = "#81e043",
                        name = "Log"
                    }
                },
            }
        end,
    },

    -- Treesitter 
    {
        "nvim-treesitter/nvim-treesitter",
        lazy = false, -- As requested, though it could be: event = { "BufReadPost", "BufNewFile" }
        branch = 'master',
        build = ':TSUpdate',
        config = function()
            require 'nvim-treesitter.configs'.setup {
                ensure_installed = {
                    "c", "lua", "vim", "vimdoc", "query",
                    "javascript", "typescript", "rust", "go",
                    "gomod", "gosum", "bash", "markdown", "markdown_inline"
                },
                sync_install = true,
                auto_install = true,
                highlight = { enable = true },
            }
        end,
    },

    -- Treesitter playground (lazy loaded)
    {
        "nvim-treesitter/playground",
        lazy = true,
        cmd = "TSPlaygroundToggle",
    },

    -- Harpoon (lazy loaded)
    {
        "theprimeagen/harpoon",
        lazy = true,
        keys = {
            { "<leader>a", function() require("harpoon.mark").add_file() end },
            { "<C-e>", function() require("harpoon.ui").toggle_quick_menu() end },
            { "<C-h>", function() require("harpoon.ui").nav_file(1) end },
            { "<C-j>", function() require("harpoon.ui").nav_file(2) end },
            { "<C-k>", function() require("harpoon.ui").nav_file(3) end },
            { "<C-l>", function() require("harpoon.ui").nav_file(4) end },
        },
    },

    -- Undotree (lazy loaded)
    {
        "mbbill/undotree",
        lazy = true,
        cmd = "UndotreeToggle",
        keys = {
            { '<leader>u', vim.cmd.UndotreeToggle },
        },
    },

    -- Fugitive (lazy loaded)
    {
        "tpope/vim-fugitive",
        lazy = true,
        cmd = { "Git", "G" },
        keys = {
            { "<leader>gs", vim.cmd.Git },
        },
    },

    -- LSP Config (lazy loaded on file open)
    {
        "neovim/nvim-lspconfig",
        lazy = true,
        event = { "BufReadPre", "BufNewFile" },
        dependencies = {
            "williamboman/mason.nvim",
            "williamboman/mason-lspconfig.nvim",
            "hrsh7th/nvim-cmp",
            "hrsh7th/cmp-nvim-lsp",
            "L3MON4D3/LuaSnip",
        },
        config = function()
            -- Mason setup
            require("mason").setup()
            
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
            cmp.setup({
                sources = {
                    {name = 'nvim_lsp'},
                },
                mapping = {
                    ['<tab>'] = cmp.mapping.select_prev_item(cmp_select),
                    ['<S-tab>'] = cmp.mapping.select_next_item(cmp_select),
                    ['<C-y>'] = cmp.mapping.confirm({ select = true }),
                    ["<C-Space>"] = cmp.mapping.complete(),
                },
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
                'ansiblels', 'bashls', 'dockerls', 'docker_compose_language_service',
                'dotls', 'eslint', 'gopls', 'html', 'helm_ls', 'jsonls',
                'lua_ls', 'pylsp', 'rust_analyzer', 'terraformls', 'tflint'
            })

            -- LSP keymaps
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

            -- Special Go format autocmd
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
        end,
    },

    -- Lualine (lazy loaded after UI)
    {
        "nvim-lualine/lualine.nvim",
        lazy = true,
        event = "VeryLazy",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
            -- Bubbles theme
            local colors = {
                blue   = '#80a0ff',
                cyan   = '#79dac8',
                black  = '#080808',
                white  = '#c6c6c6',
                red    = '#ff5189',
                violet = '#d183e8',
                grey   = '#303030',
            }

            local bubbles_theme = {
                normal = {
                    a = { fg = colors.black, bg = colors.violet },
                    b = { fg = colors.white, bg = colors.grey },
                    c = { fg = colors.black, bg = colors.black },
                },
                insert = { a = { fg = colors.black, bg = colors.blue } },
                visual = { a = { fg = colors.black, bg = colors.cyan } },
                replace = { a = { fg = colors.black, bg = colors.red } },
                inactive = {
                    a = { fg = colors.white, bg = colors.black },
                    b = { fg = colors.white, bg = colors.black },
                    c = { fg = colors.black, bg = colors.black },
                },
            }

            require('lualine').setup {
                options = {
                    theme = bubbles_theme,
                    component_separators = '|',
                    section_separators = { left = '', right = '' },
                },
                sections = {
                    lualine_a = {
                        { 'mode', separator = { left = '' }, right_padding = 2 },
                    },
                    lualine_b = { 'filename', 'branch' },
                    lualine_c = { 'fileformat' },
                    lualine_x = {},
                    lualine_y = { 'filetype', 'progress' },
                    lualine_z = {
                        { 'location', separator = { right = '' }, left_padding = 2 },
                    },
                },
                inactive_sections = {
                    lualine_a = { 'filename' },
                    lualine_b = {},
                    lualine_c = {},
                    lualine_x = {},
                    lualine_y = {},
                    lualine_z = { 'location' },
                },
                tabline = {},
                extensions = {},
            }
        end,
    },

    -- Formatter (lazy loaded)
    {
        "mhartington/formatter.nvim",
        lazy = true,
        cmd = { "Format", "FormatWrite" },
    },

    -- Glow (lazy loaded)
    {
        "ellisonleao/glow.nvim",
        lazy = true,
        cmd = "Glow",
        config = function()
            require("glow").setup()
        end,
    },

    -- Which-key (lazy loaded)
    {
        "folke/which-key.nvim",
        lazy = true,
        event = "VeryLazy",
        config = function()
            vim.opt.timeout = true
            vim.opt.timeoutlen = 300
            require("which-key").setup()
        end,
    },

    -- Indent Blankline (lazy loaded)
    {
        "lukas-reineke/indent-blankline.nvim",
        lazy = true,
        event = { "BufReadPost", "BufNewFile" },
        config = function()
            local highlight = {
                "RainbowRed", "RainbowYellow", "RainbowBlue",
                "RainbowOrange", "RainbowGreen", "RainbowViolet", "RainbowCyan",
            }
            local hooks = require "ibl.hooks"
            
            hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
                vim.api.nvim_set_hl(0, "RainbowRed", { fg = "#E06C75" })
                vim.api.nvim_set_hl(0, "RainbowYellow", { fg = "#E5C07B" })
                vim.api.nvim_set_hl(0, "RainbowBlue", { fg = "#61AFEF" })
                vim.api.nvim_set_hl(0, "RainbowOrange", { fg = "#D19A66" })
                vim.api.nvim_set_hl(0, "RainbowGreen", { fg = "#98C379" })
                vim.api.nvim_set_hl(0, "RainbowViolet", { fg = "#C678DD" })
                vim.api.nvim_set_hl(0, "RainbowCyan", { fg = "#56B6C2" })
            end)

            vim.g.rainbow_delimiters = { highlight = highlight }
            require("ibl").setup { scope = { highlight = highlight } }
            
            hooks.register(hooks.type.SCOPE_HIGHLIGHT, hooks.builtin.scope_highlight_from_extmark)
        end,
    },

    -- Rainbow Delimiters (lazy loaded)
    {
        "HiPhish/rainbow-delimiters.nvim",
        lazy = true,
        event = { "BufReadPost", "BufNewFile" },
    },

    -- Vim-go (lazy loaded for Go files)
    {
        "fatih/vim-go",
        lazy = true,
        ft = { "go", "gomod" },
        keys = {
            { '<leader>gi', function() vim.cmd([[ GoImplements ]]) end },
        },
    },

    -- Trouble (already has lazy config)
    {
        "folke/trouble.nvim",
        lazy = true,
        dependencies = { "nvim-tree/nvim-web-devicons" },
        cmd = "Trouble",
        keys = {
            { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics (Trouble)" },
            { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer Diagnostics (Trouble)" },
            { "<leader>cs", "<cmd>Trouble symbols toggle focus=false<cr>", desc = "Symbols (Trouble)" },
            { "<leader>cl", "<cmd>Trouble lsp toggle focus=false win.position=right<cr>", desc = "LSP Definitions / references / ... (Trouble)" },
            { "<leader>xL", "<cmd>Trouble loclist toggle<cr>", desc = "Location List (Trouble)" },
            { "<leader>xQ", "<cmd>Trouble qflist toggle<cr>", desc = "Quickfix List (Trouble)" },
        },
        opts = {},
    },

    -- CtrlP (lazy loaded)
    {
        "ctrlpvim/ctrlp.vim",
        lazy = true,
        cmd = "CtrlP",
    },

    -- Vim Be Good (lazy loaded)
    {
        'ThePrimeagen/vim-be-good',
        lazy = true,
        cmd = "VimBeGood",
    },

    -- Startup time (lazy loaded)
    {
        'dstein64/vim-startuptime',
        lazy = true,
        cmd = "StartupTime",
    },

    -- McpHub (lazy loaded)
    {
        'ravitemer/mcphub.nvim',
        lazy = true,
        cmd = { "McpHub", "McpHubToggle" },
        dependencies = {
            "nvim-lua/plenary.nvim",
        },
        build = "npm install -g mcp-hub@latest",
        config = function()
            require("mcphub").setup({
                config = vim.fn.expand("~/.config/mcphub/servers.json"),
                port = 37373,
                shutdown_delay = 60 * 10 * 1000,
                use_bundled_binary = false,
                mcp_request_timeout = 60000,
                auto_approve = false,
                auto_toggle_mcp_servers = true,
                extensions = {},
                native_servers = {},
                ui = {
                    window = {
                        width = 0.8,
                        height = 0.8,
                        align = "center",
                        relative = "editor",
                        zindex = 50,
                        border = "rounded",
                    },
                    wo = {
                        winhl = "Normal:MCPHubNormal,FloatBorder:MCPHubBorder",
                    },
                },
                on_ready = function(hub) end,
                on_error = function(err) end,
                log = {
                    level = vim.log.levels.WARN,
                    to_file = false,
                    file_path = nil,
                    prefix = "MCPHub",
                },
            })
        end
    },

    -- Img-clip (lazy loaded)
    {
        "HakonHarnes/img-clip.nvim",
        lazy = true,
        cmd = { "PasteImage" },
        opts = {
            filetypes = {
                codecompanion = {
                    prompt_for_file_name = false,
                    template = "[Image]($FILE_PATH)",
                    use_absolute_path = true,
                },
            },
        },
    },

    -- Mini.diff (lazy loaded)
    {
        "echasnovski/mini.diff",
        lazy = true,
        event = { "BufReadPost", "BufNewFile" },
        config = function()
            local diff = require("mini.diff")
            diff.setup({
                source = diff.gen_source.none(),
            })
        end,
    },

    -- Render Markdown (lazy loaded for markdown)
    {
        "MeanderingProgrammer/render-markdown.nvim",
        lazy = true,
        ft = { "markdown", "codecompanion" },
    },

    -- CodeCompanion (PROPERLY LAZY LOADED!)
    {
        "olimorris/codecompanion.nvim",
        lazy = true,
        cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions" },
        keys = {
            { '<leader>]', ':Gen<CR>', mode = { 'n', 'v' } }, -- Gen keymap
            -- Add more CodeCompanion keymaps here
        },
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-treesitter/nvim-treesitter",
            'ravitemer/mcphub.nvim',
        },
        config = function()
            require("codecompanion").setup({
                extensions = {
                    mcphub = {
                        callback = "mcphub.extensions.codecompanion",
                        opts = {
                            make_vars = true,
                            make_slash_commands = true,
                            show_result_in_chat = true
                        }
                    }
                },
                adapters = {
                    anthropic = function ()
                        return require("codecompanion.adapters").extend("anthropic", {
                            env = {
                                api_key = "INSERT API KEY"
                            },
                        })
                    end,
                },
            })
        end
    },

    -- Copilot GitHub (lazy loaded on InsertEnter)
    {
        "github/copilot.vim",
        lazy = true,
        event = "InsertEnter",
        config = function()
            vim.keymap.set('i', '<C-]>', 'copilot#Accept("")', {
                expr = true,
                replace_keycodes = false
            })
            vim.g.copilot_no_tab_map = true
            
            vim.keymap.set('i', '<C-j>', 'copilot#Reject("")', {
                expr = true,
                replace_keycodes = false
            })
        end,
    },
}, {
    -- Lazy.nvim options
    defaults = {
        lazy = true, -- Make all plugins lazy by default
    },
    performance = {
        rtp = {
            -- Disable some rtp plugins
            disabled_plugins = {
                "gzip",
                "tarPlugin",
                "tohtml",
                "tutor",
                "zipPlugin",
            },
        },
    },
})
