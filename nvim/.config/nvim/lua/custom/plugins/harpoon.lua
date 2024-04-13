return {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
        local harpoon = require('harpoon');
        local conf = require("telescope.config").values
        local function toggle_telescope(harpoon_files)
            local file_paths = {}
            for _, item in ipairs(harpoon_files.items) do
                table.insert(file_paths, item.value)
            end

            require("telescope.pickers").new({}, {
                prompt_title = "Harpoon",
                finder = require("telescope.finders").new_table({
                    results = file_paths,
                }),
                previewer = conf.file_previewer({}),
                sorter = conf.generic_sorter({}),
            }):find()
        end

        harpoon:setup();

        vim.keymap.set("n", "<leader><F1>", function() harpoon:list():add() end, { desc = "Harpoon File" });
        vim.keymap.set("n", "<leader>h", function() toggle_telescope(harpoon:list()) end, { desc = "Open [H]arpoon" });
        vim.keymap.set("n", "<leader>1", function() harpoon:list():select(1) end, { desc = "Select Harpoon #1" });
        vim.keymap.set("n", "<leader>2", function() harpoon:list():select(2) end, { desc = "Select Harpoon #2" });
        vim.keymap.set("n", "<leader>3", function() harpoon:list():select(3) end, { desc = "Select Harpoon #3" });
        vim.keymap.set("n", "<leader>4", function() harpoon:list():select(4) end, { desc = "Select Harpoon #4" });
        vim.keymap.set("n", "<leader>5", function() harpoon:list():select(5) end, { desc = "Select Harpoon #5" });
        vim.keymap.set("n", "<leader><F2>", function() harpoon:list():clear() end, { desc = "Clear Harpoon" });
    end
}
