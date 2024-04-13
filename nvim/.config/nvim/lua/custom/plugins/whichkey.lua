return {
    'folke/which-key.nvim',
    opts = {},
    config = function()
        -- document existing key chains
        require('which-key').register {
        }
        -- register which-key VISUAL mode
        -- required for visual <leader>hs (hunk stage) to work
        require('which-key').register({
            ['<leader>'] = { name = 'VISUAL <leader>' },
            -- ['<leader>h'] = { 'Git [H]unk' },
        }, { mode = 'v' })
    end
};
