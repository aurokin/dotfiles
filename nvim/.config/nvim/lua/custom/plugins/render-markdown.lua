return {
    'MeanderingProgrammer/render-markdown.nvim',
    dependencies = {
        'nvim-treesitter/nvim-treesitter',
        'nvim-tree/nvim-web-devicons',
    },
    ft = { 'markdown' },
    init = function()
        -- Temporary override for the stock markdown injections query:
        -- with Neovim 0.12.0 plus the currently pinned treesitter stack,
        -- the upstream `#set-lang-from-info-string!` directive crashes on
        -- fenced code blocks like ```lua when render-markdown parses the
        -- buffer. Use a direct `@injection.language` capture instead so
        -- render-markdown can stay enabled by default. Remove this once the
        -- pinned Neovim/treesitter/render-markdown versions are aligned.
        vim.treesitter.query.set('markdown', 'injections', [[
(fenced_code_block
  (info_string
    (language) @injection.language)
  (code_fence_content) @injection.content)

((html_block) @injection.content
  (#set! injection.language "html")
  (#set! injection.combined)
  (#set! injection.include-children))

((minus_metadata) @injection.content
  (#set! injection.language "yaml")
  (#offset! @injection.content 1 0 -1 0)
  (#set! injection.include-children))

((plus_metadata) @injection.content
  (#set! injection.language "toml")
  (#offset! @injection.content 1 0 -1 0)
  (#set! injection.include-children))
]])
    end,
    opts = {},
    keys = {
        {
            '<leader>md',
            '<cmd>RenderMarkdown toggle<cr>',
            desc = 'Toggle Render Markdown',
        },
    },
}
