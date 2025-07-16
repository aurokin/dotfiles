return {
    "folke/trouble.nvim",
    branch = "main", -- v3
    opts = {},
    config = function()
        local trouble = require("trouble");
        trouble.setup({});

        -- vim.keymap.set('n', '<leader>tt', function()
        --     vim.cmd("Trouble diagnostics toggle")
        -- end, { desc = 'Trouble diagnostics toggle' })
    end
}
