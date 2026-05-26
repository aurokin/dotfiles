return {
    'mfussenegger/nvim-lint',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
        local lint = require 'lint'

        lint.linters_by_ft = {
            javascript = { 'eslint_d' },
            javascriptreact = { 'eslint_d' },
            typescript = { 'eslint_d' },
            typescriptreact = { 'eslint_d' },
        }

        lint.linters.eslint_d.cmd = function()
            local local_binary = vim.fs.find('node_modules/.bin/eslint_d', {
                path = vim.api.nvim_buf_get_name(0),
                upward = true,
                type = 'file',
            })[1]
            local mason_binary = vim.fn.stdpath 'data' .. '/mason/bin/eslint_d'

            if local_binary then
                return local_binary
            elseif vim.fn.executable(mason_binary) == 1 then
                return mason_binary
            end

            return 'eslint_d'
        end

        local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })

        vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost', 'InsertLeave', 'TextChanged' }, {
            group = lint_augroup,
            callback = function()
                require('lint').try_lint()
            end,
        })

        vim.keymap.set('n', '<leader>ml', function()
            require('lint').try_lint()
        end, { desc = 'Lint file' })
    end,
}
