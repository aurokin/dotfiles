return {
    'stevearc/conform.nvim',
    config = function()
        require('conform').setup {
            formatters_by_ft = {
                lua = { 'stylua' },
                swift = { 'swiftformat' },
                sh = { 'shfmt' },
                javascript = { 'prettierd', 'prettier', stop_after_first = true },
                javascriptreact = { 'prettierd', 'prettier', stop_after_first = true },
                typescript = { 'prettierd', 'prettier', stop_after_first = true },
                typescriptreact = { 'prettierd', 'prettier', stop_after_first = true },
                json = { 'prettierd', 'prettier', stop_after_first = true },
                css = { 'prettierd', 'prettier', stop_after_first = true },
                scss = { 'prettierd', 'prettier', stop_after_first = true },
                html = { 'prettierd', 'prettier', stop_after_first = true },
                vue = { 'prettierd', 'prettier', stop_after_first = true },
            },
            log_level = vim.log.levels.ERROR,
            format_on_save = {
                -- These options will be passed to conform.format()
                timeout_ms = 500,
                lsp_format = 'fallback',
            },
        }
    end,
}
