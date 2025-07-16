return {
    -- LSP Configuration & Plugins
    'neovim/nvim-lspconfig',
    dependencies = {
        -- Automatically install LSPs to stdpath for neovim
        { 'williamboman/mason.nvim', config = true },
        'williamboman/mason-lspconfig.nvim',
        'WhoIsSethDaniel/mason-tool-installer.nvim',

        -- Useful status updates for LSP
        -- NOTE: `opts = {}` is the same as calling `require('fidget').setup({})`
        { 'j-hui/fidget.nvim', opts = {} },
        -- Allows extra capabilities provided by blink.cmp
        'saghen/blink.cmp',
        {
            'folke/lazydev.nvim',
            ft = 'lua', -- only load on lua files
            opts = {
                library = {
                    -- See the configuration section for more details
                    -- Load luvit types when the `vim.uv` word is found
                    { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
                },
            },
        },
    },
    config = function()
        -- [[ Configure LSP ]]
        --  This function gets run when an LSP connects to a particular buffer.
        vim.api.nvim_create_autocmd('LspAttach', {
            group = vim.api.nvim_create_augroup('auro-lsp-attach', { clear = true }),

            callback = function(event)
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

                local function client_supports_method(client, method, bufnr)
                    if vim.fn.has 'nvim-0.11' == 1 then
                        return client:supports_method(method, bufnr)
                    else
                        return client.supports_method(method, { bufnr = bufnr })
                    end
                end
            end,
        })

        require('mason').setup()
        require('mason-lspconfig').setup()

        local npmModulesPath = vim.env.GLOBAL_NODE_MODULES
        -- LSP Servers
        local servers = {
            -- clangd = {},
            -- gopls = {},
            -- pyright = {},
            rust_analyzer = {
                cargo = {
                    allFeatures = true,
                },
            },
            ts_ls = {
                init_options = {
                    hostInfo = 'neovim',
                    preferences = {
                        importModuleSpecifierPreference = 'non-relative',
                    },
                    plugins = {
                        {
                            name = '@vue/typescript-plugin',
                            -- npm install -g @vue/typescript-plugin
                            location = string.format('%s%s', npmModulesPath, '/@vue/typescript-plugin'),
                            languages = { 'javascript', 'typescript', 'vue' },
                        },
                    },
                },
                filetypes = {
                    'javascript',
                    'typescript',
                    'vue',
                },
            },
            html = { filetypes = { 'html', 'twig', 'hbs' } },
            jsonls = {},
            cssls = {},
            lua_ls = {
                Lua = {
                    workspace = { checkThirdParty = false },
                    telemetry = { enable = false },
                    -- NOTE: toggle below to ignore Lua_LS's noisy `missing-fields` warnings
                    -- diagnostics = { disable = { 'missing-fields' } },
                },
            },
            bashls = {},
            stylua = {},
            -- volar = {},
        }

        if vim.env.OS == 'darwin' then
            require('lspconfig').sourcekit.setup {}
        end

        if vim.env.JDTLS_ENABLED == 'true' then
            servers.jdtls = {}
        end

        local capabilities = require('blink.cmp').get_lsp_capabilities()

        -- Ensure the servers above are installed
        require('mason-tool-installer').setup { ensure_installed = vim.tbl_keys(servers) }
        local mason_lspconfig = require 'mason-lspconfig'

        mason_lspconfig.setup {
            ensure_installed = {},
            handlers = {
                function(server_name)
                    local server = servers[server_name] or {}
                    server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})
                    require('lspconfig')[server_name].setup(server)
                end,
            },
        }
    end,
}
