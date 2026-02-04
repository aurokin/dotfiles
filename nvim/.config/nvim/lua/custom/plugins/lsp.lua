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
        vim.diagnostic.config { virtual_text = true }
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
            end,
        })

        -- LSP Servers
        local vue_language_server_path = vim.fn.expand '$MASON/packages' .. '/vue-language-server' .. '/node_modules/@vue/language-server'
        vim.lsp.config('rust_analyzer', {
            cargo = { allFeatures = true },
        })
        vim.lsp.config('html', { filetypes = { 'html', 'twig', 'hbs' } })
        vim.lsp.config('lua_ls', { Lua = { workspace = { checkThirdParty = false }, telemetry = { enable = false } } })
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
        vim.lsp.config('vue_ls', {
            on_init = function(client)
                client.handlers['tsserver/request'] = function(_, result, context)
                    local clients = vim.lsp.get_clients { bufnr = context.bufnr, name = 'vtsls' }
                    if #clients == 0 then
                        vim.notify('Could not find `vtsls` lsp client, `vue_ls` would not work without it.', vim.log.levels.ERROR)
                        return
                    end
                    local ts_client = clients[1]

                    local param = unpack(result)
                    local id, command, payload = unpack(param)
                    ts_client:exec_cmd({
                        title = 'vue_request_forward', -- You can give title anything as it's used to represent a command in the UI, `:h Client:exec_cmd`
                        command = 'typescript.tsserverRequest',
                        arguments = {
                            command,
                            payload,
                        },
                    }, { bufnr = context.bufnr }, function(_, r)
                        local response_data = { { id, r.body } }
                        ---@diagnostic disable-next-line: param-type-mismatch
                        client:notify('tsserver/response', response_data)
                    end)
                end
            end,
        })
        local servers = {
            'rust_analyzer',
            'html',
            'jsonls',
            'cssls',
            'lua_ls',
            'bashls',
            'vtsls',
            'vue_ls',
            'stylua',
            'eslint',
            'eslint_d',
        }
        local masonOnly = {
            'stylua',
            'eslint',
            'eslint_d',
        }

        -- Ensure the servers above are installed
        require('mason').setup()
        require('mason-lspconfig').setup { automatic_enable = false }
        require('mason-tool-installer').setup { ensure_installed = servers }

        for _, serverName in pairs(servers) do
            if not masonOnly[serverName] then
                vim.lsp.enable(serverName)
            end
        end
    end,
}
