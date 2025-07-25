return {
    'utilyre/barbecue.nvim',
    name = 'barbecue',
    version = '*',
    dependencies = {
        'SmiteshP/nvim-navic',
        'nvim-tree/nvim-web-devicons', -- optional dependency
    },
    opts = {
        -- configurations go here
    },
    config = function()
        vim.g.navic_silence = true
        require('barbecue').setup {
            theme = 'tokyonight',
            -- attach_navic = false,
        }
    end,
}
