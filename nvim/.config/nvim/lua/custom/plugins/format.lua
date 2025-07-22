return {
    'stevearc/conform.nvim',
    config = function()
        require('conform').setup {
            formatters_by_ft = {
                lua = { 'stylua' },
                swift = { 'swiftformat' },
                sh = { 'beautysh' },
                javascript = { 'prettierd', 'prettier', stop_after_first = true },
                typescript = { 'prettierd', 'prettier', stop_after_first = true },
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
