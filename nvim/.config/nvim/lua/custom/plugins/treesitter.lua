local parsers = {
    'c',
    'cpp',
    'go',
    'lua',
    'python',
    'rust',
    'tsx',
    'javascript',
    'typescript',
    'vimdoc',
    'vim',
    'bash',
    'vue',
    'css',
    'scss',
    'html',
}

local treesitter_filetypes = {
    'bash',
    'c',
    'cpp',
    'css',
    'go',
    'html',
    'javascript',
    'javascriptreact',
    'lua',
    'python',
    'rust',
    'scss',
    'sh',
    'typescript',
    'typescriptreact',
    'vim',
    'vimdoc',
    'vue',
}

local install_dir = vim.fn.stdpath('data') .. '/site'

local function set_textobject_keymaps()
    local select = require('nvim-treesitter-textobjects.select')
    local move = require('nvim-treesitter-textobjects.move')
    local swap = require('nvim-treesitter-textobjects.swap')

    vim.keymap.set({ 'x', 'o' }, 'aa', function()
        select.select_textobject('@parameter.outer', 'textobjects')
    end)
    vim.keymap.set({ 'x', 'o' }, 'ia', function()
        select.select_textobject('@parameter.inner', 'textobjects')
    end)
    vim.keymap.set({ 'x', 'o' }, 'af', function()
        select.select_textobject('@function.outer', 'textobjects')
    end)
    vim.keymap.set({ 'x', 'o' }, 'if', function()
        select.select_textobject('@function.inner', 'textobjects')
    end)
    vim.keymap.set({ 'x', 'o' }, 'ac', function()
        select.select_textobject('@class.outer', 'textobjects')
    end)
    vim.keymap.set({ 'x', 'o' }, 'ic', function()
        select.select_textobject('@class.inner', 'textobjects')
    end)

    vim.keymap.set({ 'n', 'x', 'o' }, ']m', function()
        move.goto_next_start('@function.outer', 'textobjects')
    end)
    vim.keymap.set({ 'n', 'x', 'o' }, ']]', function()
        move.goto_next_start('@class.outer', 'textobjects')
    end)
    vim.keymap.set({ 'n', 'x', 'o' }, ']M', function()
        move.goto_next_end('@function.outer', 'textobjects')
    end)
    vim.keymap.set({ 'n', 'x', 'o' }, '][', function()
        move.goto_next_end('@class.outer', 'textobjects')
    end)
    vim.keymap.set({ 'n', 'x', 'o' }, '[m', function()
        move.goto_previous_start('@function.outer', 'textobjects')
    end)
    vim.keymap.set({ 'n', 'x', 'o' }, '[[', function()
        move.goto_previous_start('@class.outer', 'textobjects')
    end)
    vim.keymap.set({ 'n', 'x', 'o' }, '[M', function()
        move.goto_previous_end('@function.outer', 'textobjects')
    end)
    vim.keymap.set({ 'n', 'x', 'o' }, '[]', function()
        move.goto_previous_end('@class.outer', 'textobjects')
    end)

    vim.keymap.set('n', '<leader>a', function()
        swap.swap_next('@parameter.inner')
    end)
    vim.keymap.set('n', '<leader>A', function()
        swap.swap_previous('@parameter.inner')
    end)
end

return {
    -- Highlight, edit, and navigate code
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false,
    build = function()
        local treesitter = require('nvim-treesitter')

        treesitter.setup { install_dir = install_dir }
        treesitter.install(parsers, { summary = true }):wait(300000)
        treesitter.update(parsers, { summary = true }):wait(300000)
    end,
    dependencies = {
        { 'nvim-treesitter/nvim-treesitter-textobjects', branch = 'main' },
    },
    config = function()
        require('nvim-treesitter').setup { install_dir = install_dir }

        vim.api.nvim_create_autocmd('FileType', {
            pattern = treesitter_filetypes,
            callback = function()
                pcall(vim.treesitter.start)
                vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
            end,
        })

        require('nvim-treesitter-textobjects').setup {
            select = {
                lookahead = true,
            },
            move = {
                set_jumps = true,
            },
        }
        set_textobject_keymaps()
    end,
}
