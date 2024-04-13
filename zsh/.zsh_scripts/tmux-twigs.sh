#!/bin/bash

tmux_running=$(pgrep tmux)
tmux_active=$(echo $TMUX)
is_kill="";
is_cd=""
if [[ $1 == "k" ]]; then
    is_kill=true;
fi
if [[ $1 == "cd" ]]; then
    is_cd=true;
fi

if [[ -z $tmux_active ]]; then
    if [[ $tmux_running ]]; then
        $(tmux a);
    else
        $(tmux new -s default);
    fi
fi

if [[ $tmux_running ]]; then
    if [[ $is_cd ]]; then
        current_session=$(tmux display-message -p '#S')
        current_window=$(tmux display-message -p '#W')
        # current_dir=$(pwd)
        # tmux send-prefix -t $current_session:$current_window
        # tmux send-keys -t $current_session:$current_window "^-b" ":attach -c $current_dir -t $current_session"
        tmux a -c $current_dir -t $current_session
        return;
    fi
    
    s=$(tmux ls | awk '{print $1}' | fzf --print-query | tail -1)

    if [[ -z $s ]]; then
        return;
    fi

    s_cut=$(echo $s | rg -o -m 1 "^\w*")

    if [[ -z $is_kill ]]; then
        if ! tmux has-session -t=$s_cut 2> /dev/null; then
            tmux new-session -ds $s_cut -c ~
        fi

        tmux switch-client -t $s_cut
    else
        if tmux has-session -t=$s_cut 2> /dev/null; then
            tmux kill-session -t $s_cut
        fi
    fi
fi
