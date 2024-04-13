return {
    "folke/tokyonight.nvim",
    config = function()
        require("tokyonight").setup({
            style = "night",
            light_style = "dark",
            transparent = true,
            on_colors = function(colors) end,
            on_highlights = function(highlights, colors) end,
        });

        vim.cmd("colorscheme tokyonight-night")
    end,
}
