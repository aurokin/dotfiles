return {
    "nvim-tree/nvim-tree.lua",
    dependencies = {
        "nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
    },
    config = function()
        vim.opt.termguicolors = true
        vim.keymap.set('n', '<leader>fb', function()
            vim.cmd('Ex');
        end, { desc = "[F]ile Browser (Netrw)" })
        vim.keymap.set('n', '<leader>fo', function()
                vim.cmd('NvimTreeOpen');
                vim.cmd('NvimTreeFindFile!')
            end,
            { desc = "[F]ile Tree [O]pen (NvimTree)" });
        vim.keymap.set('n', '<leader>fc', function()
                vim.cmd('NvimTreeClose');
            end,
            { desc = "[F]ile [C]lose Browser (NvimTree)" });
        require("nvim-tree").setup({ ["hijack_netrw"] = false })
    end
}
