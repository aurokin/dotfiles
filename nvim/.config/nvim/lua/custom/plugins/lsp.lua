return {
    -- LSP Configuration & Plugins
    'neovim/nvim-lspconfig',
    dependencies = {
        -- Automatically install LSPs to stdpath for neovim
        { 'mason-org/mason.nvim', opts = {} },
        'mason-org/mason-lspconfig.nvim',
        'WhoIsSethDaniel/mason-tool-installer.nvim',

        -- Useful status updates for LSP
        -- NOTE: `opts = {}` is the same as calling `require('fidget').setup({})`
        { 'j-hui/fidget.nvim', opts = {} },
        -- Allows extra capabilities provided by blink.cmp
        'saghen/blink.cmp',
    },
    config = function()
        -- [[ Configure LSP ]]
        --  This function gets run when an LSP connects to a particular buffer.
        vim.diagnostic.config { virtual_text = true }
        vim.api.nvim_create_autocmd('LspAttach', {
            group = vim.api.nvim_create_augroup('auro-lsp-attach', { clear = true }),

            callback = function(event)
                local bufnr = event.buf
                -- NOTE: Remember that lua is a real programming language, and as such it is possible
                -- to define small helper and utility functions so you don't have to repeat yourself
                -- many times.
                --
                -- In this case, we create a function that lets us more easily define mappings specific
                -- for LSP related items. It sets the mode, buffer and description for us each time.
                local nmap = function(keys, func, desc)
                    if desc then
                        desc = 'LSP: ' .. desc
                    end

                    vim.keymap.set('n', keys, func, { buffer = bufnr, desc = desc })
                end

                nmap('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
                nmap('<leader>ca', function()
                    vim.lsp.buf.code_action { context = { only = { 'quickfix', 'refactor', 'source' } } }
                end, '[C]ode [A]ction')

                nmap('gd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')
                nmap('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')
                nmap('gi', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')
                nmap('<leader>ld', require('telescope.builtin').lsp_type_definitions, 'Type [D]efinition')
                nmap('<leader>ls', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
                nmap('<leader>lw', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

                -- Lesser used LSP functionality
                nmap('<leader>lg', vim.lsp.buf.declaration, '[G]oto Declaration')
                nmap('<leader>`', vim.lsp.buf.hover, '[L]sp [H]over')
                nmap('<leader>lh', vim.lsp.buf.signature_help, 'Signature Documentation')
                nmap('<leader>wa', vim.lsp.buf.add_workspace_folder, '[W]orkspace [A]dd Folder')
                nmap('<leader>wr', vim.lsp.buf.remove_workspace_folder, '[W]orkspace [R]emove Folder')
                nmap('<leader>wl', function()
                    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
                end, '[W]orkspace [L]ist Folders')
            end,
        })

        -- LSP Servers
        local vue_language_server_path = vim.fn.expand '$MASON/packages' .. '/vue-language-server' .. '/node_modules/@vue/language-server'
        vim.lsp.config('rust_analyzer', {
            settings = {
                ['rust-analyzer'] = {
                    cargo = { allFeatures = true },
                },
            },
        })
        vim.lsp.config('html', { filetypes = { 'html', 'twig', 'hbs' } })
        vim.lsp.config('lua_ls', {
            settings = {
                Lua = {
                    workspace = { checkThirdParty = false },
                    telemetry = { enable = false },
                },
            },
        })
        vim.lsp.config('vtsls', {
            settings = {
                typescript = {
                    inlayHints = {
                        parameterNames = { enabled = 'literals' },
                        parameterTypes = { enabled = true },
                        variableTypes = { enabled = true },
                        propertyDeclarationTypes = { enabled = true },
                        functionLikeReturnTypes = { enabled = true },
                        enumMemberValues = { enabled = true },
                    },
                    preferences = {
                        importModuleSpecifier = 'non-relative',
                    },
                },
                vtsls = {
                    tsserver = {
                        globalPlugins = {
                            {
                                name = '@vue/typescript-plugin',
                                location = vue_language_server_path,
                                languages = { 'vue' },
                                configNamespace = 'typescript',
                            },
                        },
                    },
                },
            },
            filetypes = { 'typescript', 'javascript', 'javascriptreact', 'typescriptreact', 'vue' },
        })
        vim.lsp.config('eslint', {
            settings = {
                format = false,
                workingDirectory = { mode = 'auto' },
            },
        })
        local lsp_servers = {
            'rust_analyzer',
            'html',
            'jsonls',
            'cssls',
            'lua_ls',
            'bashls',
            'vtsls',
            'vue_ls',
            'eslint',
        }
        local tools = {
            'stylua',
            'swiftformat',
            'shfmt',
            'prettierd',
            'prettier',
        }
        local ensure_installed = vim.list_extend(vim.deepcopy(lsp_servers), tools)

        -- Ensure the LSP servers and formatter CLIs above are installed.
        require('mason').setup()
        require('mason-lspconfig').setup { automatic_enable = false }
        require('mason-tool-installer').setup { ensure_installed = ensure_installed }

        for _, server_name in ipairs(lsp_servers) do
            vim.lsp.enable(server_name)
        end
    end,
}
