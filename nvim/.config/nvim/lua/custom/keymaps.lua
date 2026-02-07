-- [[ Auro Keymaps ]]
vim.keymap.set('n', 'vv', '<C-v>')
vim.keymap.set({ 'n', 'v' }, '<C-w>v', '<C-w>v<C-w>l')
vim.keymap.set({ 'n', 'v' }, '<C-h>', '<C-w>h')
vim.keymap.set({ 'n', 'v' }, '<C-j>', '<C-w>j')
vim.keymap.set({ 'n', 'v' }, '<C-k>', '<C-w>k')
vim.keymap.set({ 'n', 'v' }, '<C-l>', '<C-w>l')
vim.keymap.set({ 'n', 'v' }, '<C-v>', '<C-w>v<C-w>l')
vim.keymap.set({ 'n', 'v' }, '<C-s>', '<C-w>S<C-w>j')
vim.keymap.set({ 'n', 'v' }, '<leader>6', '<C-^>')
vim.keymap.set({ 'n', 'v' }, '<leader>qc', function()
    vim.cmd 'cexpr []'
end, { desc = 'Clear Quickfix List' })
vim.keymap.set({ 'n', 'v' }, '<leader>yp', function()
    local default_reg_contents = vim.fn.getreg '"'
    vim.fn.setreg('+', default_reg_contents)
end, { desc = 'Copy to Clipboard from Register' })
vim.keymap.set({ 'n', 'v' }, '<leader>yy', function()
    local clip_contents = vim.fn.getreg '+'
    vim.fn.setreg('"', clip_contents)
end, { desc = 'Copy from Clipboard to Register' })

local path_clipboard = require('custom.path_clipboard')
vim.keymap.set('n', '<leader>lp', function()
    path_clipboard.copy_buf_location { with_line = false }
end, { desc = 'Path Paste' })
vim.keymap.set('n', '<leader>Lp', function()
    path_clipboard.copy_buf_location { with_line = true }
end, { desc = 'Lines Paste' })

vim.keymap.set('n', '<leader>fb', function()
    vim.cmd 'Ex'
end, { desc = '[F]ile Browser (Netrw)' })

-- [[ Basic Keymaps ]]
vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })
vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })
