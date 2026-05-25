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

    session_id="$(tmux display-message -p -t "=$session" '#{session_id}' 2>/dev/null || true)"
    if [[ -n "$session_id" ]]; then
        target="$(tmux show-option -qv -t "$session_id" @twigsmux_worktree_branch 2>/dev/null || true)"
    fi
    if [[ -n "$target" ]]; then
        printf '%s\n' "$target"
        return 0
    fi

    if [[ "$session" =~ ^[a-z][a-z0-9]*-[a-z][a-z0-9]*-[0-9]+$ ]]; then
        printf '%s\n' "${session#*-}"
        return 0
    fi

    printf '%s\n' "$session"
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

    printf '%s\n' "$query_value"
}

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
    if [[ -n "$selected" && "$selected" == "$current_session" ]]; then
        exit 0
    elif [[ -n "$selected" ]]; then
        remove_target="$(worktree_target_for_selected_session "$selected")"
    elif [[ -n "$query" ]]; then
        remove_target="$(worktree_target_for_query "$query")"
    else
        exit 0
    fi

    current_worktree_target="$(worktree_target_for_selected_session "$current_session")"
    [[ -n "$remove_target" ]] || exit 0
    [[ "$remove_target" != "$current_worktree_target" ]] || exit 0

    if ! zsh -lic 'wtrt "$1"' zsh "$remove_target"; then
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
        if [[ "$prefix_current" -eq 1 && "$target" == "$current_session"-* ]]; then
            worktree_branch="${target#"$current_session"-}"
        fi
        [[ -n "$worktree_branch" ]] || exit 0
        new_session_id="$(tmux new-session -P -F '#{session_id}' -e TWIGSMUX_WORKTREE_BRANCH="$worktree_branch" -ds "$target" -n "$default_window" -c "$new_session_dir" "$HOME/.zshrc.d/scripts/twigsmux.sh" --start-worktree-session)"
        tmux set-option -q -t "$new_session_id" @twigsmux_worktree_branch "$worktree_branch"
    else
        tmux new-session -ds "$target" -n "$default_window" -c "$new_session_dir"
    fi
fi
tmux switch-client -t "=$target"
