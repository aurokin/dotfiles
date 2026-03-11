return {
    'folke/which-key.nvim',
    event = 'VeryLazy',
    opts = {
        preset = 'modern',
        delay = function(ctx)
            local leader = vim.g.mapleader or '\\'
            if vim.startswith(ctx.keys, leader) then
                return 100
            end

            return ctx.plugin and 0 or 200
        end,
        spec = {
            { '<leader>c', group = 'Code' },
            { '<leader>f', group = 'Files' },
            { '<leader>g', group = 'Git Search' },
            { '<leader>l', group = 'LSP / Path' },
            { '<leader>L', group = 'Path with Line' },
            { '<leader>m', group = 'Misc' },
            { '<leader>n', group = 'Notifications' },
            { '<leader>q', group = 'Quickfix' },
            { '<leader>r', group = 'Refactor' },
            { '<leader>s', group = 'Search' },
            { '<leader>t', group = 'Trouble' },
            { '<leader>w', proxy = '<c-w>', group = 'Windows / Workspace' },
            { '<leader>y', group = 'Clipboard' },
            { '<leader>z', group = 'Review' },
        },
        replace = {
            desc = {
                { '^LSP:%s*', '' },
                { '%[(.)%]', '%1' },
                { '<Plug>%(?(.*)%)?', '%1' },
                { '^%+', '' },
                { '<[cC]md>', '' },
                { '<[cC][rR]>', '' },
                { '<[sS]ilent>', '' },
                { '^lua%s+', '' },
                { '^call%s+', '' },
                { '^:%s*', '' },
            },
        },
        show_help = true,
        show_keys = false,
    },
    keys = {
        {
            '<leader>?',
            function()
                require('which-key').show { global = false }
            end,
            desc = 'Buffer Local Keymaps (which-key)',
        },
    },
}
