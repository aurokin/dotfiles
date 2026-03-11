local M = {}
local uv = vim.uv or vim.loop

local state = {
    last_branch_target = nil,
    last_worktree_target = nil,
}

local initialized = false

local function notify(message, level)
    vim.notify(message, level or vim.log.levels.INFO, { title = 'Review' })
end

local function trim(value)
    if not value then
        return ''
    end
    return vim.trim(value)
end

local function git(args, cwd)
    local command = { 'git' }
    if cwd and cwd ~= '' then
        vim.list_extend(command, { '-C', cwd })
    end
    vim.list_extend(command, args)

    local output = vim.fn.systemlist(command)
    if vim.v.shell_error ~= 0 then
        return nil, trim(table.concat(output, '\n'))
    end

    return output
end

local function current_context_dir()
    local current_file = vim.api.nvim_buf_get_name(0)
    if current_file == '' then
        return vim.fn.getcwd()
    end

    return vim.fn.fnamemodify(current_file, ':p:h')
end

local function git_root()
    local output, err = git({ 'rev-parse', '--show-toplevel' }, current_context_dir())
    if not output or not output[1] then
        return nil, err
    end

    return trim(output[1])
end

local function normalize_path(path)
    if not path or path == '' then
        return nil
    end

    local expanded = vim.fn.fnamemodify(vim.fn.expand(path), ':p')
    return (uv and uv.fs_realpath(expanded)) or expanded
end

local function current_ref(root)
    local branch = git({ 'symbolic-ref', '--quiet', '--short', 'HEAD' }, root)
    if branch and branch[1] then
        return trim(branch[1])
    end

    local commit = git({ 'rev-parse', '--short', 'HEAD' }, root)
    if commit and commit[1] then
        return trim(commit[1])
    end

    return 'HEAD'
end

local function default_base_ref(root)
    if state.last_branch_target and state.last_branch_target ~= '' then
        return state.last_branch_target
    end

    local origin_head = git({ 'symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD' }, root)
    if origin_head and origin_head[1] then
        return trim(origin_head[1])
    end

    return ''
end

local function parse_worktrees(root)
    local lines, err = git({ 'worktree', 'list', '--porcelain' }, root)
    if not lines then
        return nil, err
    end

    local worktrees = {}
    local current = nil

    for _, line in ipairs(lines) do
        if line == '' then
            if current then
                table.insert(worktrees, current)
                current = nil
            end
        elseif vim.startswith(line, 'worktree ') then
            current = {
                path = trim(line:sub(#'worktree ' + 1)),
            }
        elseif current and vim.startswith(line, 'HEAD ') then
            current.head = trim(line:sub(#'HEAD ' + 1))
        elseif current and vim.startswith(line, 'branch ') then
            current.branch = trim(line:sub(#'branch ' + 1))
            current.branch_short = current.branch:gsub('^refs/heads/', '')
        elseif current and line == 'detached' then
            current.detached = true
        elseif current and line == 'bare' then
            current.bare = true
        end
    end

    if current then
        table.insert(worktrees, current)
    end

    for _, worktree in ipairs(worktrees) do
        worktree.normalized_path = normalize_path(worktree.path)
        worktree.basename = vim.fn.fnamemodify(worktree.path, ':t')
    end

    return worktrees
end

local function resolve_worktree(root, input)
    local worktrees, err = parse_worktrees(root)
    if not worktrees then
        return nil, err
    end

    local query = trim(input)
    local normalized_query = normalize_path(query)
    local matches = {}

    for _, worktree in ipairs(worktrees) do
        local matched = false
        if query == worktree.path or query == worktree.basename or query == worktree.branch_short then
            matched = true
        elseif normalized_query and worktree.normalized_path and normalized_query == worktree.normalized_path then
            matched = true
        end

        if matched then
            table.insert(matches, worktree)
        end
    end

    if #matches == 0 then
        return nil, ('No worktree matched "%s"'):format(query)
    end

    if #matches > 1 then
        local choices = {}
        for _, match in ipairs(matches) do
            table.insert(choices, match.branch_short or match.path)
        end
        return nil, ('Ambiguous worktree target "%s": %s'):format(query, table.concat(choices, ', '))
    end

    return matches[1]
end

local function open_diffview(range)
    local ok, err
    if range and range ~= '' then
        ok, err = pcall(vim.api.nvim_cmd, { cmd = 'DiffviewOpen', args = { range } }, {})
    else
        ok, err = pcall(vim.api.nvim_cmd, { cmd = 'DiffviewOpen' }, {})
    end

    if not ok then
        notify(err, vim.log.levels.ERROR)
    end
end

local function prompt(options, on_confirm)
    vim.ui.input(options, function(input)
        local value = trim(input)
        if value == '' then
            return
        end

        on_confirm(value)
    end)
end

function M.review_uncommitted()
    open_diffview()
end

function M.review_file()
    local ok, err = pcall(vim.api.nvim_cmd, { cmd = 'Gdiffsplit' }, {})
    if not ok then
        notify(err, vim.log.levels.ERROR)
    end
end

function M.preview_hunk()
    local ok, gitsigns = pcall(require, 'gitsigns')
    if not ok then
        notify('gitsigns.nvim is not available', vim.log.levels.ERROR)
        return
    end

    gitsigns.preview_hunk()
end

function M.blame_line()
    local ok, gitsigns = pcall(require, 'gitsigns')
    if not ok then
        notify('gitsigns.nvim is not available', vim.log.levels.ERROR)
        return
    end

    gitsigns.blame_line { full = true }
end

function M.compare_branch(exact)
    local root, err = git_root()
    if not root then
        notify(err ~= '' and err or 'Not inside a git repository', vim.log.levels.WARN)
        return
    end

    prompt({
        prompt = exact and 'Compare against branch/rev (exact): ' or 'Compare against branch/rev: ',
        default = default_base_ref(root),
    }, function(target)
        state.last_branch_target = target

        local separator = exact and '..' or '...'
        open_diffview(('%s%sHEAD'):format(target, separator))
    end)
end

function M.compare_worktree()
    local root, err = git_root()
    if not root then
        notify(err ~= '' and err or 'Not inside a git repository', vim.log.levels.WARN)
        return
    end

    prompt({
        prompt = 'Compare against worktree path/name: ',
        default = state.last_worktree_target or '',
    }, function(target)
        local worktree, resolve_err = resolve_worktree(root, target)
        if not worktree then
            notify(resolve_err, vim.log.levels.WARN)
            return
        end

        local current_root = normalize_path(root)
        if current_root and worktree.normalized_path == current_root then
            notify('Target worktree is the current worktree', vim.log.levels.WARN)
            return
        end

        local target_ref = worktree.branch_short or worktree.head
        if not target_ref or target_ref == '' then
            notify(('Could not resolve a branch or commit for "%s"'):format(target), vim.log.levels.WARN)
            return
        end

        state.last_worktree_target = target
        open_diffview(('%s...%s'):format(target_ref, current_ref(root)))
    end)
end

function M.close_review()
    local ok = pcall(vim.api.nvim_cmd, { cmd = 'DiffviewClose' }, {})
    if ok then
        return
    end

    if vim.wo.diff then
        vim.cmd 'diffoff!'
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            local buffer = vim.api.nvim_win_get_buf(win)
            local name = vim.api.nvim_buf_get_name(buffer)
            if name:match '^fugitive://' then
                vim.api.nvim_win_close(win, true)
                break
            end
        end
        return
    end

    notify('No active review view', vim.log.levels.INFO)
end

function M.setup()
    if initialized then
        return
    end
    initialized = true

    vim.keymap.set('n', '<leader>zu', M.review_uncommitted, { desc = 'Review Uncommitted' })
    vim.keymap.set('n', '<leader>zf', M.review_file, { desc = 'Review File Diff' })
    vim.keymap.set('n', '<leader>zp', M.preview_hunk, { desc = 'Preview Hunk' })
    vim.keymap.set('n', '<leader>zb', M.blame_line, { desc = 'Blame Line' })
    vim.keymap.set('n', '<leader>zc', function()
        M.compare_branch(false)
    end, { desc = 'Compare Branch' })
    vim.keymap.set('n', '<leader>zC', function()
        M.compare_branch(true)
    end, { desc = 'Compare Branch Exact' })
    vim.keymap.set('n', '<leader>zw', M.compare_worktree, { desc = 'Compare Worktree' })
    vim.keymap.set('n', '<leader>zq', M.close_review, { desc = 'Close Review' })
end

return M
