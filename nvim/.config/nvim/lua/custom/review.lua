local M = {}
local uv = vim.uv or vim.loop
local path_clipboard = require 'custom.path_clipboard'

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

local function open_file_history(args)
    local ok, err = pcall(vim.api.nvim_cmd, { cmd = 'DiffviewFileHistory', args = args or {} }, {})
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

local function current_diffview()
    local ok, lib = pcall(require, 'diffview.lib')
    if not ok then
        return nil
    end

    return lib.get_current_view()
end

local function current_diffview_panel_item(view)
    if not view or not view.panel or not view.panel.is_focused or not view.panel.get_item_at_cursor then
        return nil
    end

    if not view.panel:is_focused() then
        return nil
    end

    local ok, item = pcall(view.panel.get_item_at_cursor, view.panel)
    if not ok then
        return nil
    end

    return item
end

local function is_diffview_file_entry(item)
    return item
        and item.path
        and item.path ~= ''
        and item.files == nil
        and type(item.collapsed) ~= 'boolean'
end

local function current_diffview_focused_file(view)
    if not view or not view.cur_layout or not view.cur_layout.windows then
        return nil
    end

    for _, win in ipairs(view.cur_layout.windows) do
        if win
            and win.is_focused
            and win:is_focused()
            and win.file
            and not win.file.nulled
            and win.file.path
            and win.file.path ~= ''
            and win.file.path ~= 'null'
        then
            return win.file
        end
    end

    return nil
end

local current_review_rev

local function is_file_history_view(view)
    return view
        and view.panel
        and view.panel.get_log_options
        and view.panel.find_entry
        and view.infer_cur_file
        and not (view.left and view.right)
end

local function current_review_root()
    local view = current_diffview()
    if view and view.adapter and view.adapter.ctx and view.adapter.ctx.toplevel then
        return normalize_path(view.adapter.ctx.toplevel)
    end

    return git_root()
end

local function current_review_entry(view)
    if not view then
        return nil
    end

    if view.panel then
        if type(view.panel.cur_file) == 'table' and view.panel.cur_file.path and view.panel.cur_file.path ~= 'null' then
            return view.panel.cur_file
        end

        if view.panel.cur_item and view.panel.cur_item[2] and view.panel.cur_item[2].path and view.panel.cur_item[2].path ~= 'null' then
            return view.panel.cur_item[2]
        end
    end

    if view.cur_file then
        local ok, entry = pcall(view.cur_file, view)
        if ok and entry and entry.path then
            return entry
        end
    end

    return nil
end

local function current_review_side()
    local view = current_diffview()
    local focused_file = current_diffview_focused_file(view)
    if not focused_file or not focused_file.symbol then
        return nil
    end

    return ({
        a = 'left',
        b = 'right',
        c = 'c',
        d = 'd',
    })[focused_file.symbol] or focused_file.symbol
end

local function current_review_file()
    local view = current_diffview()
    local entry = current_review_entry(view)
    if entry and entry.path and entry.path ~= '' and entry.path ~= 'null' then
        return entry.path
    end

    local focused_file = current_diffview_focused_file(view)
    if focused_file then
        return focused_file.path
    end

    local panel_item = current_diffview_panel_item(view)
    if panel_item ~= nil then
        if is_diffview_file_entry(panel_item) then
            return panel_item.path
        end

        -- Commit rows intentionally do not imply a file selection unless the
        -- history view already narrows them to a single tracked file.
        if not (is_file_history_view(view) and view.panel and view.panel.single_file) then
            return nil
        end
    end

    if view and view.infer_cur_file then
        local ok, file = pcall(view.infer_cur_file, view)
        if ok and is_diffview_file_entry(file) then
            return file.path
        end
    end

    return path_clipboard.preferred_buf_path(0)
end

local function append_review_history_option_args(args, log_options)
    if not log_options then
        return
    end

    local boolean_flags = {
        { 'follow', '--follow' },
        { 'first_parent', '--first-parent' },
        { 'show_pulls', '--show-pulls' },
        { 'reflog', '--reflog' },
        { 'walk_reflogs', '--walk-reflogs' },
        { 'all', '--all' },
        { 'merges', '--merges' },
        { 'no_merges', '--no-merges' },
        { 'reverse', '--reverse' },
        { 'cherry_pick', '--cherry-pick' },
        { 'left_only', '--left-only' },
        { 'right_only', '--right-only' },
    }

    for _, item in ipairs(boolean_flags) do
        local key, flag = item[1], item[2]
        if log_options[key] then
            table.insert(args, flag)
        end
    end

    local valued_flags = {
        { 'rev_range', '--range=' },
        { 'base', '--base=' },
        { 'max_count', '--max-count=' },
        { 'diff_merges', '--diff-merges=' },
        { 'author', '--author=' },
        { 'grep', '--grep=' },
        { 'after', '--after=' },
        { 'before', '--before=' },
    }

    for _, item in ipairs(valued_flags) do
        local key, prefix = item[1], item[2]
        local value = log_options[key]
        if value ~= nil and value ~= '' then
            table.insert(args, prefix .. value)
        end
    end

    if log_options.G and log_options.G ~= '' then
        table.insert(args, '-G' .. log_options.G)
    end

    if log_options.S and log_options.S ~= '' then
        table.insert(args, '-S' .. log_options.S)
    end

    if log_options.L then
        for _, trace in ipairs(log_options.L) do
            if trace and trace ~= '' then
                table.insert(args, '-L' .. trace)
            end
        end
    end
end

local function extend_review_history_args(args)
    local view = current_diffview()
    if is_file_history_view(view) then
        append_review_history_option_args(args, view.panel:get_log_options())
        return
    end

    local rev = current_review_rev()
    if rev and rev ~= '' then
        table.insert(args, '--range=' .. rev)
    end
end

current_review_rev = function()
    local view = current_diffview()
    if not view then
        return nil
    end

    if view.left and view.right and view.adapter and view.adapter.rev_to_pretty_string then
        if view.rev_arg and view.rev_arg ~= '' then
            return view.rev_arg
        end

        local ok, rev = pcall(view.adapter.rev_to_pretty_string, view.adapter, view.left, view.right)
        if ok then
            return trim(rev)
        end

        return nil
    end

    if view.panel and view.panel.find_entry and view.infer_cur_file then
        local panel_item = current_diffview_panel_item(view)
        if panel_item and panel_item.commit and panel_item.commit.hash then
            return panel_item.commit.hash .. '^!'
        end

        local ok, file = pcall(view.infer_cur_file, view)
        if ok and is_diffview_file_entry(file) then
            local ok_entry, entry = pcall(view.panel.find_entry, view.panel, file)
            if ok_entry and entry and entry.commit and entry.commit.hash then
                return entry.commit.hash .. '^!'
            end
        end

        if view.panel.get_log_options then
            local log_options = view.panel:get_log_options()
            if log_options and log_options.rev_range and log_options.rev_range ~= '' then
                return log_options.rev_range
            end
        end
    end

    return nil
end

local function current_review_line()
    local filetype = vim.bo.filetype
    local bufname = vim.api.nvim_buf_get_name(0)

    if filetype == 'DiffviewFiles' or filetype == 'DiffviewFileHistory' then
        return nil
    end

    if bufname:match '^diffview:///panels/' or bufname:match '^diffview://.*/log/%d+/' then
        return nil
    end

    return vim.api.nvim_win_get_cursor(0)[1]
end

local function format_review_reference(opts)
    opts = opts or {}

    local root = current_review_root()
    local file = current_review_file()
    local rev = current_review_rev()
    local entry = current_review_entry(current_diffview())
    local side = opts.with_line and file and current_review_side() or nil
    local line = opts.with_line and file and current_review_line() or nil

    if not root and not file and not rev then
        return nil
    end

    local parts = {}
    if root and root ~= '' then
        table.insert(parts, ('repo=%s'):format(root))
    end
    if rev and rev ~= '' then
        table.insert(parts, ('rev=%s'):format(rev))
    end
    if file and file ~= '' then
        if line then
            file = ('%s:%d'):format(file, line)
        end
        table.insert(parts, ('file=%s'):format(file))
    end
    if entry and entry.oldpath and entry.oldpath ~= '' and entry.oldpath ~= entry.path then
        table.insert(parts, ('old_file=%s'):format(entry.oldpath))
    end
    if side and side ~= '' then
        table.insert(parts, ('side=%s'):format(side))
    end

    return table.concat(parts, ' ')
end

local function format_review_summary()
    local view = current_diffview()
    local rev = current_review_rev()
    if rev and rev ~= '' then
        local commit = rev:match('^(.+)%^!$')
        if commit then
            return ('reviewing commit %s'):format(commit)
        end

        local from, to = rev:match('^(.+)%.%.%.(.+)$')
        if from and to then
            return ('reviewing branch %s -> %s'):format(from, to)
        end

        from, to = rev:match('^(.+)%.%.(.+)$')
        if from and to then
            return ('reviewing branch %s -> %s'):format(from, to)
        end

        return ('reviewing rev %s'):format(rev)
    end

    local root = current_review_root()
    if view and view.panel and view.panel.get_log_options then
        local file = current_review_file()
        if file and file ~= '' then
            return ('reviewing history for %s'):format(file)
        end

        if root then
            local ref = current_ref(root)
            if ref and ref ~= '' then
                return ('reviewing branch %s history'):format(ref)
            end
        end
    end

    if root then
        local ref = current_ref(root)
        if ref and ref ~= '' then
            return ('reviewing uncommitted changes on %s'):format(ref)
        end
    end

    return nil
end

local function copy_to_clipboard(text)
    if not text or text == '' then
        notify('No review context', vim.log.levels.WARN)
        return
    end

    vim.fn.setreg('+', text)
    notify(text)
end

local function copy_review_summary()
    copy_to_clipboard(format_review_summary())
end

local function copy_review_reference(opts)
    copy_to_clipboard(format_review_reference(opts))
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

function M.review_commit()
    local root, err = current_review_root()
    if not root then
        notify(err ~= '' and err or 'Not inside a git repository', vim.log.levels.WARN)
        return
    end

    local ok_builtin, builtin = pcall(require, 'telescope.builtin')
    local ok_actions, actions = pcall(require, 'telescope.actions')
    local ok_state, action_state = pcall(require, 'telescope.actions.state')
    if not ok_builtin or not ok_actions or not ok_state then
        notify('telescope.nvim is not available', vim.log.levels.ERROR)
        return
    end

    builtin.git_commits {
        cwd = root,
        prompt_title = 'Review Commits',
        attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
                local selection = action_state.get_selected_entry()
                actions.close(prompt_bufnr)

                if not selection or not selection.value or selection.value == '' then
                    notify('No commit selected', vim.log.levels.WARN)
                    return
                end

                open_diffview(selection.value .. '^!')
            end)

            return true
        end,
    }
end

function M.review_history()
    local root, err = current_review_root()
    if not root then
        notify(err ~= '' and err or 'Not inside a git repository', vim.log.levels.WARN)
        return
    end

    local args = { '-C' .. root }
    extend_review_history_args(args)
    open_file_history(args)
end

function M.review_file_history()
    local root, err = current_review_root()
    if not root then
        notify(err ~= '' and err or 'Not inside a git repository', vim.log.levels.WARN)
        return
    end

    local file = current_review_file()
    if not file or file == '' then
        notify('No file selected', vim.log.levels.WARN)
        return
    end

    local args = { '-C' .. root }
    extend_review_history_args(args)
    table.insert(args, file)

    open_file_history(args)
end

function M.copy_review_reference()
    copy_review_reference { with_line = false }
end

function M.copy_review_reference_with_line()
    copy_review_reference { with_line = true }
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
    vim.keymap.set('n', '<leader>zg', M.review_commit, { desc = 'Review Commit' })
    vim.keymap.set('n', '<leader>zh', M.review_history, { desc = 'Review History' })
    vim.keymap.set('n', '<leader>zH', M.review_file_history, { desc = 'Review File History' })
    vim.keymap.set('n', '<leader>zp', copy_review_summary, { desc = 'Put Review Summary' })
    vim.keymap.set('n', '<leader>zP', M.copy_review_reference_with_line, { desc = 'Put Review Detail' })
    vim.keymap.set('n', '<leader>zv', M.preview_hunk, { desc = 'Preview Hunk' })
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
