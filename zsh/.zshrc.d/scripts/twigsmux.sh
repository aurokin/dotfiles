#!/usr/bin/env bash

# Twigsmux - tmux session switcher
# Runs inside tmux display-popup (no throwaway session needed)
#
# Keybinds for .tmux.conf:
#   bind-key t display-popup -E -w 50% -h 50% "~/.zshrc.d/scripts/twigsmux.sh switch '#{session_name}'"
#   bind-key L switch-client -l

default_window="editor"
default_session="default"

mode="$1"
current_session="${2:-$(tmux display-message -p '#S' 2>/dev/null)}"

# Outside tmux: attach or create
if [[ -z "$TMUX" ]]; then
    if pgrep -q tmux; then
        exec tmux attach
    else
        exec tmux new-session -s "$default_session" -n "$default_window" -c ~
    fi
fi

result=$(tmux ls -F '#{session_name}' \
    | fzf --print-query \
        --prompt="switch> " \
        --header="enter=select, ctrl-n=new, ctrl-k=kill" \
        --expect=ctrl-n,ctrl-k)

query=$(sed -n '1p' <<< "$result")
key=$(sed -n '2p' <<< "$result")
selected=$(sed -n '3p' <<< "$result")

if [[ "$key" == "ctrl-k" && -n "$selected" && "$selected" != "$current_session" ]]; then
    tmux kill-session -t "=$selected"
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
    tmux new-session -ds "$target" -n "$default_window" -c ~
fi
tmux switch-client -t "=$target"
