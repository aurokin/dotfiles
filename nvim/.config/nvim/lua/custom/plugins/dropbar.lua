return {
    'Bekaboo/dropbar.nvim',
    dependencies = {
        {
            'nvim-telescope/telescope-fzf-native.nvim',
            build = 'make',
            cond = function()
                return vim.fn.executable 'make' == 1
            end,
        },
        'nvim-tree/nvim-web-devicons',
    },
    opts = {},
}
