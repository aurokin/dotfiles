return {
    'wojciech-kulik/xcodebuild.nvim',
    dependencies = {
        'nvim-telescope/telescope.nvim',
        'MunifTanjim/nui.nvim',
        'nvim-tree/nvim-tree.lua',
    },
    config = function()
        local os = vim.env.OS
        if os == 'darwin' then
            require('xcodebuild').setup {
                code_coverage = {
                    enabled = false,
                },
                integrations = {
                    xcode_build_server = {
                        enabled = false,
                    },
                },
            }

            vim.keymap.set('n', '<leader>x<space>', '<cmd>XcodebuildPicker<cr>', { desc = 'Show All Xcodebuild Actions' })
            vim.keymap.set('n', '<leader>xl', '<cmd>XcodebuildToggleLogs<cr>', { desc = 'Toggle Xcodebuild Logs' })
            vim.keymap.set('n', '<leader>xb', '<cmd>XcodebuildBuild<cr>', { desc = 'Build Project' })
            vim.keymap.set('n', '<leader>xr', '<cmd>XcodebuildBuildRun<cr>', { desc = 'Build & Run Project' })
            vim.keymap.set('n', '<leader>xt', '<cmd>XcodebuildTest<cr>', { desc = 'Run Tests' })
            vim.keymap.set('n', '<leader>xT', '<cmd>XcodebuildTestClass<cr>', { desc = 'Run This Test Class' })
            vim.keymap.set('n', '<leader>xd', '<cmd>XcodebuildSelectDevice<cr>', { desc = 'Select Device' })
            vim.keymap.set('n', '<leader>xp', '<cmd>XcodebuildSelectTestPlan<cr>', { desc = 'Select Test Plan' })
            vim.keymap.set('n', '<leader>xq', '<cmd>Telescope quickfix<cr>', { desc = 'Show QuickFix List' })
        end
    end,
}
