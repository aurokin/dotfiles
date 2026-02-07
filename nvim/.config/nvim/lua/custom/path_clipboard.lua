local M = {}

local function normalize_path(path)
    path = vim.fn.fnamemodify(path, ':p')
    local real = vim.loop.fs_realpath(path)
    if real ~= nil then
        path = real
    end
    path = path:gsub('/+$', '')
    if path == '' then
        path = '/'
    end
    return path
end

local function strip_root(path, root)
    root = root:gsub('/+$', '')
    if root == '' then
        return nil
    end
    if path:sub(1, #root + 1) == root .. '/' then
        return path:sub(#root + 2)
    end
    return nil
end

function M.preferred_buf_path(bufnr)
    bufnr = bufnr or 0
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if bufname == nil or bufname == '' then
        return nil
    end

    -- Ignore non-file buffers like term://, fugitive://, etc.
    if bufname:match('^%w+://') then
        return nil
    end

    local abs = normalize_path(bufname)
    local dir = vim.fn.fnamemodify(abs, ':h')

    local git_root = nil
    local git_dir = vim.fn.finddir('.git', dir .. ';')
    if git_dir ~= '' then
        git_root = vim.fn.fnamemodify(git_dir, ':h')
    else
        local git_file = vim.fn.findfile('.git', dir .. ';')
        if git_file ~= '' then
            git_root = vim.fn.fnamemodify(git_file, ':h')
        end
    end

    if git_root ~= nil and git_root ~= '' then
        local rel = strip_root(abs, normalize_path(git_root))
        if rel ~= nil and rel ~= '' then
            return rel
        end
    end

    local rel_cwd = strip_root(abs, normalize_path(vim.fn.getcwd()))
    if rel_cwd ~= nil and rel_cwd ~= '' then
        return rel_cwd
    end

    return abs
end

function M.copy_buf_location(opts)
    opts = opts or {}
    local with_line = opts.with_line or false
    local bufnr = opts.bufnr or 0
    local win = opts.win or 0

    local path = M.preferred_buf_path(bufnr)
    if path == nil then
        vim.notify 'No file path'
        return
    end

    local text = path
    if with_line then
        local line = vim.api.nvim_win_get_cursor(win)[1]
        text = ('%s:%d'):format(path, line)
    end

    vim.fn.setreg('+', text)
    vim.notify(text)
end

return M
