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
        --header="enter=select, ctrl-n=new, ctrl-k=kill" \
        --expect=ctrl-n,ctrl-k)
fzf_exit=$?
(( fzf_exit > 1 )) && exit 0

query=$(sed -n '1p' <<< "$result")
key=$(sed -n '2p' <<< "$result")
selected=$(sed -n '3p' <<< "$result")

if [[ "$key" == "ctrl-k" ]]; then
    [[ -n "$selected" && "$selected" != "$current_session" ]] && tmux kill-session -t "=$selected"
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
        tmux new-session -ds "$target" -n "$default_window" -c "$new_session_dir" 'zsh -lic "wtct --select-window ai; exec zsh -i"'
    else
        tmux new-session -ds "$target" -n "$default_window" -c "$new_session_dir"
    fi
fi
tmux switch-client -t "=$target"
