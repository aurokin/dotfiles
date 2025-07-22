return {
    'MunifTanjim/prettier.nvim',
    dependencies = {
        'neovim/nvim-lspconfig',
        'stevearc/conform.nvim',
    },
    config = function()
        local prettier = require 'prettier'

        prettier.setup {
            bin = 'prettierd', -- npm install -g @fsouza/prettierd
            cli_options = {
                tab_width = 4,
                use_tabs = false,
            },
        }

        local conform = require 'conform'
        conform.setup {
            formatters_by_ft = {
                lua = { 'stylua' },
                swift = { 'swiftformat' },
                sh = { 'beautysh' },
            },
            log_level = vim.log.levels.ERROR,
        }

        local format = function()
            local filetype = vim.bo.filetype
            if prettier.config_exists() then
                vim.cmd 'Prettier'
            elseif filetype == 'swift' or filetype == 'sh' or filetype == 'lua' then
                conform.format {
                    lsp_fallback = false,
                    async = false,
                    timeout_ms = 500,
                }
            elseif vim.fn.exists ':Format' > 0 and filetype ~= 'vue' then
                vim.cmd 'Format'
            end

            vim.cmd 'norm! zz'
        end

        vim.keymap.set('n', '<leader>fd', format, { desc = '[F]ormat [D]ocument' })
        vim.api.nvim_create_autocmd('BufWritePre', {
            group = vim.api.nvim_create_augroup('autoformat', { clear = true }),
            callback = format,
        })
    end,
}
