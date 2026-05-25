#!/usr/bin/env bash

# Twigsmux - tmux session switcher
# Runs inside tmux display-popup (no throwaway session needed)
#
# Keybinds for .tmux.conf:
#   bind-key t display-popup -E -w 50% -h 50% "~/.zshrc.d/scripts/twigsmux.sh"
#   bind-key y display-popup -E -w 50% -h 50% -d "#{pane_current_path}" "~/.zshrc.d/scripts/twigsmux.sh --prefix-current --run-wtct-on-create"
#   bind-key L switch-client -l

default_window="editor"
default_session="default"
initial_query=""
new_session_dir="$HOME"
prefix_current=0
run_wtct_on_create=0

if [[ "${1-}" == "--start-worktree-session" ]]; then
    if [[ -z "${TWIGSMUX_WORKTREE_BRANCH-}" ]]; then
        echo "twigsmux: TWIGSMUX_WORKTREE_BRANCH is required" >&2
        exec zsh -i
    fi

    exec zsh -lic 'wtct --branch "$1" --select-window ai; exec zsh -i' zsh "$TWIGSMUX_WORKTREE_BRANCH"
fi

worktree_target_for_selected_session() {
    local session="$1"
    local session_id=""
    local target=""

    session_id="$(session_id_for_session "$session")"
    if [[ -n "$session_id" ]]; then
        target="$(tmux show-option -qv -t "$session_id" @twigsmux_worktree_branch 2>/dev/null || true)"
    fi
    if [[ -n "$target" ]]; then
        printf '%s\n' "$target"
        return 0
    fi

    if worktree_session_paths_disagree "$session"; then
        printf '%s\n' "$session"
        return 0
    fi

    if worktree_session_path_conflicts_with_name "$session"; then
        target="$(worktree_target_from_session_name "$session")"
        if [[ -n "$target" ]]; then
            printf '%s\n' "$target"
            return 0
        fi
        printf '%s\n' "$session"
        return 0
    fi

    target="$(worktree_target_from_session_path "$session")"
    if [[ -n "$target" ]]; then
        printf '%s\n' "$target"
        return 0
    fi

    target="$(worktree_target_from_session_name "$session")"
    if [[ -n "$target" && "$target" != "$session" ]]; then
        printf '%s\n' "$target"
        return 0
    fi

    printf '%s\n' "$session"
}

worktree_target_from_session_name() {
    local session="$1"
    local target=""

    if [[ "$session" =~ ^[a-z][a-z0-9]*-[a-z][a-z0-9]*-[0-9]+$ ]]; then
        printf '%s\n' "${session#*-}"
        return 0
    fi

    target="$(strip_project_prefix_for_session "$session" "$session")"
    printf '%s\n' "$target"
}

session_id_for_session() {
    local session="$1"

    tmux display-message -p -t "=$session:" '#{session_id}' 2>/dev/null || true
}

session_option_value() {
    local session="$1"
    local option="$2"
    local session_id=""

    session_id="$(session_id_for_session "$session")"
    [[ -n "$session_id" ]] || return 1

    tmux show-option -qv -t "$session_id" "$option" 2>/dev/null || true
}

session_recorded_branch() {
    local session="$1"

    session_option_value "$session" @twigsmux_worktree_branch
}

session_path_value() {
    local session="$1"
    local format="$2"
    local value=""
    local session_name=""
    local session_path=""

    value="$(tmux display-message -p -t "=$session:" "$format" 2>/dev/null || true)"
    if [[ -n "$value" ]]; then
        printf '%s\n' "$value"
        return 0
    fi

    if [[ "$format" == '#{pane_current_path}' ]]; then
        tmux list-panes -t "=$session" -F '#{pane_current_path}' 2>/dev/null | sed -n '1p'
        return 0
    fi

    if [[ "$format" == '#{session_path}' ]]; then
        while IFS=$'\t' read -r session_name session_path; do
            [[ "$session_name" == "$session" ]] || continue
            printf '%s\n' "$session_path"
            return 0
        done < <(tmux list-sessions -F '#{session_name}	#{session_path}' 2>/dev/null || true)
    fi
}

abs_existing_dir() {
    local path="$1"

    [[ -n "$path" ]] || return 1
    (
        cd "$path" 2>/dev/null || exit 1
        pwd -P
    )
}

git_main_worktree_from_path() {
    local path="$1"
    local path_abs=""
    local line=""
    local main_worktree=""
    local top_level=""

    path_abs="$(abs_existing_dir "$path")"
    [[ -n "$path_abs" ]] || return 1

    while IFS= read -r line; do
        if [[ "$line" == worktree\ * ]]; then
            main_worktree="${line#worktree }"
            break
        fi
    done < <(git -C "$path_abs" worktree list --porcelain 2>/dev/null || true)

    if [[ -n "$main_worktree" ]]; then
        abs_existing_dir "$main_worktree"
        return $?
    fi

    top_level="$(git -C "$path_abs" rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "$top_level" ]] || return 1
    abs_existing_dir "$top_level"
}

git_branch_for_worktree_path() {
    local path="$1"
    local path_abs=""
    local line=""
    local current_worktree=""
    local branch=""

    path_abs="$(abs_existing_dir "$path")"
    [[ -n "$path_abs" ]] || return 1

    while IFS= read -r line; do
        if [[ "$line" == worktree\ * ]]; then
            current_worktree="$(abs_existing_dir "${line#worktree }" 2>/dev/null || true)"
            branch=""
            continue
        fi

        if [[ "$line" == branch\ refs/heads/* ]]; then
            branch="${line#branch refs/heads/}"
            if [[ -n "$current_worktree" && ( "$path_abs" == "$current_worktree" || "$path_abs" == "$current_worktree"/* ) ]]; then
                printf '%s\n' "$branch"
                return 0
            fi
        fi
    done < <(git -C "$path_abs" worktree list --porcelain 2>/dev/null || true)

    return 1
}

worktree_cwd_from_session_path() {
    local session="$1"
    local path=""
    local cwd=""

    if worktree_session_paths_disagree "$session"; then
        return 1
    fi

    path="$(session_path_value "$session" '#{pane_current_path}')"
    cwd="$(git_main_worktree_from_path "$path" 2>/dev/null || true)"
    if [[ -n "$cwd" ]]; then
        printf '%s\n' "$cwd"
        return 0
    fi

    path="$(session_path_value "$session" '#{session_path}')"
    cwd="$(git_main_worktree_from_path "$path" 2>/dev/null || true)"
    if [[ -n "$cwd" ]]; then
        printf '%s\n' "$cwd"
        return 0
    fi

    return 1
}

worktree_session_paths_disagree() {
    local session="$1"
    local pane_path=""
    local session_path=""
    local pane_target=""
    local pane_cwd=""
    local session_target=""
    local session_cwd=""

    pane_path="$(session_path_value "$session" '#{pane_current_path}')"
    session_path="$(session_path_value "$session" '#{session_path}')"
    [[ -n "$pane_path" && -n "$session_path" && "$pane_path" != "$session_path" ]] || return 1

    pane_target="$(worktree_path_slug_from_path "$pane_path" 2>/dev/null || true)"
    pane_cwd="$(git_main_worktree_from_path "$pane_path" 2>/dev/null || true)"
    session_target="$(worktree_path_slug_from_path "$session_path" 2>/dev/null || true)"
    session_cwd="$(git_main_worktree_from_path "$session_path" 2>/dev/null || true)"

    if [[ -n "$pane_cwd" && -n "$session_cwd" && "$pane_cwd" != "$session_cwd" ]]; then
        return 0
    fi

    if [[ -n "$pane_target" && -n "$session_target" && "$pane_target" != "$session_target" ]]; then
        return 0
    fi

    return 1
}

worktree_cwd_for_selected_session() {
    local session="$1"
    local recorded_target=""
    local path_project=""
    local path_target=""
    local session_prefix=""
    local cwd=""

    cwd="$(session_option_value "$session" @twigsmux_worktree_cwd)"
    cwd="$(abs_existing_dir "$cwd" 2>/dev/null || true)"
    if [[ -n "$cwd" ]]; then
        printf '%s\n' "$cwd"
        return 0
    fi

    recorded_target="$(session_recorded_branch "$session")"
    if [[ -n "$recorded_target" ]]; then
        path_target="$(worktree_target_from_session_path "$session" 2>/dev/null || true)"
        [[ "$path_target" == "$recorded_target" ]] || return 1

        path_project="$(worktree_project_from_session_path "$session" 2>/dev/null || true)"
        if [[ "$session" == *-"$recorded_target" ]]; then
            session_prefix="${session%-"$recorded_target"}"
            session_prefix="${session_prefix%-}"
            [[ -z "$path_project" || "$session_prefix" == "$path_project" ]] || return 1
        elif [[ "$session" != "$recorded_target" && "$session" == *-* ]]; then
            return 1
        fi
    fi

    if worktree_session_path_conflicts_with_name "$session"; then
        return 1
    fi

    worktree_cwd_from_session_path "$session"
}

worktree_session_path_conflicts_with_name() {
    local session="$1"
    local recorded_target=""
    local path_slug=""
    local path_project=""
    local path_target=""
    local name_target=""
    local session_prefix=""

    recorded_target="$(session_option_value "$session" @twigsmux_worktree_branch)"
    [[ -z "$recorded_target" ]] || return 1

    path_slug="$(worktree_path_slug_from_session_path "$session" 2>/dev/null || true)"
    [[ -n "$path_slug" ]] || return 1
    path_target="$(worktree_target_from_session_path "$session" 2>/dev/null || true)"
    [[ -n "$path_target" ]] || path_target="$path_slug"
    path_project="$(worktree_project_from_session_path "$session" 2>/dev/null || true)"

    if [[ -n "$path_project" ]]; then
        if [[ "$session" == *-"$path_slug" ]]; then
            session_prefix="${session%-"$path_slug"}"
            session_prefix="${session_prefix%-}"
            [[ -n "$session_prefix" && "$session_prefix" != "$path_project" ]] && return 0
        elif [[ "$path_target" != "$path_slug" && "$session" == *-"$path_target" ]]; then
            session_prefix="${session%-"$path_target"}"
            session_prefix="${session_prefix%-}"
            [[ -n "$session_prefix" && "$session_prefix" != "$path_project" ]] && return 0
        fi
    fi

    name_target="$(worktree_target_from_session_name "$session")"
    if [[ -z "$name_target" || "$name_target" == "$session" ]]; then
        case "$session" in
            *-"$path_slug"|*-"$path_target")
                return 1
                ;;
            *-*)
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    fi

    [[ "$path_target" != "$name_target" && "$path_slug" != "$name_target" ]]
}

worktree_project_from_path() {
    local path="$1"
    local path_abs=""
    local worktrees_abs=""
    local rel=""
    local project=""

    path_abs="$(abs_existing_dir "$path")"
    [[ -n "$path_abs" ]] || return 1

    worktrees_abs="$(abs_existing_dir "$HOME/worktrees")"
    [[ -n "$worktrees_abs" ]] || return 1
    [[ "$path_abs" == "$worktrees_abs"/* ]] || return 1

    rel="${path_abs#"$worktrees_abs"/}"
    [[ "$rel" == */* ]] || return 1
    project="${rel%%/*}"
    [[ -n "$project" ]] || return 1

    printf '%s\n' "$project"
}

worktree_project_from_session_path() {
    local session="$1"
    local path=""
    local project=""

    path="$(session_path_value "$session" '#{pane_current_path}')"
    project="$(worktree_project_from_path "$path" 2>/dev/null || true)"
    if [[ -n "$project" ]]; then
        printf '%s\n' "$project"
        return 0
    fi

    path="$(session_path_value "$session" '#{session_path}')"
    project="$(worktree_project_from_path "$path" 2>/dev/null || true)"
    if [[ -n "$project" ]]; then
        printf '%s\n' "$project"
        return 0
    fi

    return 1
}

worktree_path_slug_from_path() {
    local path="$1"
    local path_abs=""
    local worktrees_abs=""
    local rel=""
    local target=""

    path_abs="$(abs_existing_dir "$path")"
    [[ -n "$path_abs" ]] || return 1

    worktrees_abs="$(abs_existing_dir "$HOME/worktrees")"
    [[ -n "$worktrees_abs" ]] || return 1
    [[ "$path_abs" == "$worktrees_abs"/* ]] || return 1

    rel="${path_abs#"$worktrees_abs"/}"
    [[ "$rel" == */* ]] || return 1
    rel="${rel#*/}"
    target="${rel%%/*}"
    [[ -n "$target" ]] || return 1

    printf '%s\n' "$target"
}

worktree_target_from_path() {
    local path="$1"
    local slug=""
    local branch=""

    slug="$(worktree_path_slug_from_path "$path" 2>/dev/null || true)"
    [[ -n "$slug" ]] || return 1

    branch="$(git_branch_for_worktree_path "$path" 2>/dev/null || true)"
    if [[ -n "$branch" ]]; then
        printf '%s\n' "$branch"
        return 0
    fi

    printf '%s\n' "$slug"
}

worktree_path_slug_from_session_path() {
    local session="$1"
    local path=""
    local target=""

    path="$(session_path_value "$session" '#{pane_current_path}')"
    target="$(worktree_path_slug_from_path "$path" 2>/dev/null || true)"
    if [[ -n "$target" ]]; then
        printf '%s\n' "$target"
        return 0
    fi

    path="$(session_path_value "$session" '#{session_path}')"
    target="$(worktree_path_slug_from_path "$path" 2>/dev/null || true)"
    if [[ -n "$target" ]]; then
        printf '%s\n' "$target"
        return 0
    fi

    return 1
}

worktree_target_from_session_path() {
    local session="$1"
    local path=""
    local target=""

    path="$(session_path_value "$session" '#{pane_current_path}')"
    target="$(worktree_target_from_path "$path" 2>/dev/null || true)"
    if [[ -n "$target" ]]; then
        printf '%s\n' "$target"
        return 0
    fi

    path="$(session_path_value "$session" '#{session_path}')"
    target="$(worktree_target_from_path "$path" 2>/dev/null || true)"
    if [[ -n "$target" ]]; then
        printf '%s\n' "$target"
        return 0
    fi

    return 1
}

project_prefixes_for_session() {
    local session="$1"
    local path=""
    local path_abs=""
    local worktrees_abs=""
    local rel=""
    local git_root=""
    local prefix=""
    local printed=""
    local format=""

    for format in '#{pane_current_path}' '#{session_path}'; do
        path="$(session_path_value "$session" "$format")"
        path_abs="$(abs_existing_dir "$path")"
        [[ -n "$path_abs" ]] || continue

        worktrees_abs="$(abs_existing_dir "$HOME/worktrees")"
        if [[ -n "$worktrees_abs" && "$path_abs" == "$worktrees_abs"/* ]]; then
            rel="${path_abs#"$worktrees_abs"/}"
            if [[ "$rel" == */* ]]; then
                prefix="${rel%%/*}"
                if [[ -n "$prefix" && "$printed" != *$'\n'"$prefix"$'\n'* ]]; then
                    printf '%s\n' "$prefix"
                    printed+=$'\n'"$prefix"$'\n'
                fi
            fi

            continue
        fi

        git_root="$(git_main_worktree_from_path "$path_abs" 2>/dev/null || true)"
        if [[ -n "$git_root" ]]; then
            prefix="$(basename "$git_root")"
        else
            prefix="$(basename "$path_abs")"
        fi
        if [[ -n "$prefix" && "$printed" != *$'\n'"$prefix"$'\n'* ]]; then
            printf '%s\n' "$prefix"
            printed+=$'\n'"$prefix"$'\n'
        fi
    done
}

strip_project_prefix_for_session() {
    local session="$1"
    local value="$2"
    local prefix=""

    while IFS= read -r prefix; do
        [[ -n "$prefix" ]] || continue
        if [[ "$value" == "$prefix"-* ]]; then
            printf '%s\n' "${value#"$prefix"-}"
            return 0
        fi
    done < <(project_prefixes_for_session "$session")

    printf '%s\n' "$value"
}

worktree_target_for_query() {
    local query_value="$1"
    local stripped_prefix=0

    if [[ "$prefix_current" -eq 1 && "$query_value" == "$current_session"-* ]]; then
        query_value="${query_value#"$current_session"-}"
        stripped_prefix=1
    fi

    if [[ "$stripped_prefix" -eq 0 && "$query_value" =~ ^[a-z][a-z0-9]*-[a-z][a-z0-9]*-[0-9]+$ ]]; then
        printf '%s\n' "${query_value#*-}"
        return 0
    fi

    if [[ "$stripped_prefix" -eq 0 ]]; then
        query_value="$(strip_project_prefix_for_session "$current_session" "$query_value")"
    fi

    printf '%s\n' "$query_value"
}

# shellcheck disable=SC2317
if [[ "${TWIGSMUX_SOURCE_ONLY-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix-current)
            prefix_current=1
            new_session_dir="${PWD:-$HOME}"
            shift
            ;;
        --run-wtct-on-create)
            run_wtct_on_create=1
            shift
            ;;
        *)
            echo "twigsmux: unknown option: $1" >&2
            exit 2
            ;;
    esac
done

current_session=$(tmux display-message -p '#S' 2>/dev/null)
if [[ "$prefix_current" -eq 1 ]]; then
    initial_query="${current_session}-"
fi

# Outside tmux: attach or create
if [[ -z "$TMUX" ]]; then
    if tmux list-sessions >/dev/null 2>&1; then
        exec tmux attach
    fi

    exec tmux new-session -s "$default_session" -n "$default_window" -c ~
fi

result=$(tmux ls -F '#{session_name}' \
    | fzf --print-query \
        --query="$initial_query" \
        --prompt="switch> " \
        --header="enter=select, ctrl-n=new, ctrl-k=kill, ctrl-r=remove worktree" \
        --expect=ctrl-n,ctrl-k,ctrl-r)
fzf_exit=$?
(( fzf_exit > 1 )) && exit 0

query=$(sed -n '1p' <<< "$result")
key=$(sed -n '2p' <<< "$result")
selected=$(sed -n '3p' <<< "$result")

if [[ "$key" == "ctrl-k" ]]; then
    [[ -n "$selected" && "$selected" != "$current_session" ]] && tmux kill-session -t "=$selected"
    exit 0
fi

if [[ "$key" == "ctrl-r" ]]; then
    remove_cwd=""
    if [[ -n "$selected" && "$selected" == "$current_session" ]]; then
        exit 0
    elif [[ -n "$selected" ]]; then
        if worktree_session_paths_disagree "$selected"; then
            echo "twigsmux: selected session paths point at different worktrees; refusing to remove" >&2
            sleep 3
            exit 1
        fi
        if worktree_session_path_conflicts_with_name "$selected"; then
            echo "twigsmux: selected session path conflicts with session name; refusing to remove" >&2
            sleep 3
            exit 1
        fi
        remove_target="$(worktree_target_for_selected_session "$selected")"
        remove_cwd="$(worktree_cwd_for_selected_session "$selected" 2>/dev/null || true)"
        if [[ -n "$(session_recorded_branch "$selected")" && -z "$remove_cwd" ]]; then
            echo "twigsmux: selected session has a recorded worktree branch but no trusted repo context; refusing to remove" >&2
            sleep 3
            exit 1
        fi
    elif [[ -n "$query" ]]; then
        remove_target="$(worktree_target_for_query "$query")"
        remove_cwd="$(worktree_cwd_for_selected_session "$current_session" 2>/dev/null || true)"
    else
        exit 0
    fi

    current_worktree_target="$(worktree_target_for_selected_session "$current_session")"
    current_worktree_cwd="$(worktree_cwd_for_selected_session "$current_session" 2>/dev/null || true)"
    [[ -n "$remove_target" ]] || exit 0
    if [[ "$remove_target" == "$current_worktree_target" ]]; then
        [[ -n "$remove_cwd" && -n "$current_worktree_cwd" && "$remove_cwd" != "$current_worktree_cwd" ]] || exit 0
    fi

    if [[ -n "$remove_cwd" ]]; then
        remove_status=0
        if [[ -n "${selected-}" ]]; then
            zsh -lic 'wtrt --cwd "$1" --session "$2" "$3"' zsh "$remove_cwd" "$selected" "$remove_target" || remove_status=$?
        else
            zsh -lic 'wtrt --cwd "$1" "$2"' zsh "$remove_cwd" "$remove_target" || remove_status=$?
        fi
    else
        remove_status=0
        if [[ -n "${selected-}" ]]; then
            zsh -lic 'wtrt --session "$1" "$2"' zsh "$selected" "$remove_target" || remove_status=$?
        else
            zsh -lic 'wtrt "$1"' zsh "$remove_target" || remove_status=$?
        fi
    fi

    if [[ "$remove_status" -ne 0 ]]; then
        echo "twigsmux: failed to remove worktree '$remove_target'" >&2
        sleep 3
        exit 1
    fi

    exit 0
fi

if [[ "$key" == "ctrl-n" && -n "$query" ]]; then
    target="$query"
elif [[ -n "$selected" ]]; then
    target="$selected"
elif [[ -n "$query" ]]; then
    target="$query"
else
    exit 0
fi

if ! tmux has-session -t "=$target" 2>/dev/null; then
    if [[ "$run_wtct_on_create" -eq 1 ]]; then
        new_session_id=""
        worktree_branch="$target"
        worktree_cwd="$(git_main_worktree_from_path "$new_session_dir" 2>/dev/null || true)"
        [[ -n "$worktree_cwd" ]] || worktree_cwd="$(abs_existing_dir "$new_session_dir" 2>/dev/null || true)"
        if [[ "$prefix_current" -eq 1 && "$target" == "$current_session"-* ]]; then
            worktree_branch="${target#"$current_session"-}"
        fi
        [[ -n "$worktree_branch" ]] || exit 0
        new_session_id="$(tmux new-session -P -F '#{session_id}' -e TWIGSMUX_WORKTREE_BRANCH="$worktree_branch" -ds "$target" -n "$default_window" -c "$new_session_dir" "$HOME/.zshrc.d/scripts/twigsmux.sh" --start-worktree-session)"
        tmux set-option -q -t "$new_session_id" @twigsmux_worktree_branch "$worktree_branch"
        [[ -n "$worktree_cwd" ]] && tmux set-option -q -t "$new_session_id" @twigsmux_worktree_cwd "$worktree_cwd"
    else
        tmux new-session -ds "$target" -n "$default_window" -c "$new_session_dir"
    fi
fi
tmux switch-client -t "=$target"
