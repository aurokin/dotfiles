vim.g.mapleader = ','
vim.g.maplocalleader = ' '

-- [[ Install `lazy.nvim` plugin manager ]]
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system {
        'git',
        'clone',
        '--filter=blob:none',
        'https://github.com/folke/lazy.nvim.git',
        '--branch=stable', -- latest stable release
        lazypath,
    }
end
vim.opt.rtp:prepend(lazypath)

-- [[ Configure plugins ]]
require('lazy').setup({
    { import = 'custom.plugins' },
}, {})

local twigsmux = require 'twigsmux'

-- [[ Auro Setting options ]]
vim.wo.numberwidth = 5
vim.wo.relativenumber = true
vim.wo.signcolumn = 'number'
vim.wo.scrolloff = 999

-- Tab Key Settings
vim.opt.autoindent = true
vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4

vim.opt.laststatus = 3

-- [[ Setting options ]]
vim.o.hlsearch = false
vim.wo.number = true
vim.o.mouse = 'a'
vim.o.breakindent = true
vim.o.undofile = true
vim.o.ignorecase = true
vim.o.smartcase = true
vim.wo.signcolumn = 'yes'
vim.o.updatetime = 250
vim.o.timeoutlen = 300
vim.o.completeopt = 'menuone,noselect'
vim.o.termguicolors = true

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
vim.keymap.set({ 'n', 'v' }, '<leader>yq', function()
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
vim.keymap.set({ 'n', 'v', 'i' }, '<C-t>', function()
    twigsmux.switch()
end, { desc = 'Twigsmux' })
-- [[ Basic Keymaps ]]
vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })
vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

-- [[ Highlight on yank ]]
local highlight_group = vim.api.nvim_create_augroup('YankHighlight', { clear = true })
vim.api.nvim_create_autocmd('TextYankPost', {
    callback = function()
        vim.highlight.on_yank()
    end,
    group = highlight_group,
    pattern = '*',
})
