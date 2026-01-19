return {
    'MeanderingProgrammer/render-markdown.nvim',
    dependencies = {
        'nvim-treesitter/nvim-treesitter',
        'nvim-tree/nvim-web-devicons',
    },
    ft = { 'markdown' },
    opts = {},
    keys = {
        {
            '<leader>md',
            '<cmd>RenderMarkdown toggle<cr>',
            desc = 'Toggle Render Markdown',
        },
    },
}
