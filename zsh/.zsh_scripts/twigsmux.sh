#!/bin/bash

# This script expects you to be called in a tmux session called twigsmux, other than initial entry into tmux.
# I recommend setting these keybinds in your .tmux.conf
# bind-key t new-session -A -s twigsmux 'source ~/.zsh_scripts/twigsmux.sh d' \; 
# bind-key k new-session -A -s twigsmux 'source ~/.zsh_scripts/twigsmux.sh k' \;
# bind-key L new-session -A -s twigsmux 'source ~/.zsh_scripts/twigsmux.sh l' \;

# If you are not inside tmux, calling the script will attach you to your tmux server, or create a server with a session specified below
# Change these variables according to your preferences
default_window="editor"
default_session="default"
# end

record_session() {
    rm ~/.twigsmux
    echo $1 > ~/.twigsmux
}
go_to_last_session() {
    last_session=$(cat ~/.twigsmux)

    if tmux has-session -t=$last_session 2> /dev/null && [[ $last_session != "twigsmux" ]] && [[ $1 != "twigsmux" ]]; then
        record_session $1
        tmux switch-client -t $last_session
    fi

    tmux kill-session -t twigsmux;
    return 0;
}

tmux_running=$(pgrep tmux)
tmux_active=$(echo $TMUX)
is_default="";
is_kill="";
is_last="";

if [[ $1 == "k" ]]; then
    is_kill=true;
elif [[ $1 == "l" ]]; then
    is_last=true;
elif [[ $1 == "d" ]]; then
    is_default=true;
fi

if [[ -z $tmux_active ]]; then
    if [[ $tmux_running ]]; then
        $(tmux a);
    else
        $(tmux new -s $default_session -n $default_window -c ~);
    fi
fi

if [[ -z $1 ]]; then
    return 0;
fi

if [[ $tmux_running ]]; then
    running_session=$(tmux display-message -p '#S')
    current_session=$(tmux display-message -p '#{client_last_session}')

    if [[ $running_session != "twigsmux" ]]; then
        tmux kill-session -t twigsmux;
        return 0;
    fi

    if [[ $is_last ]]; then
        go_to_last_session $current_session
    fi

    s=$(tmux ls | awk '{print $1}' | fzf --print-query | tail -1)

    if [[ -z $s ]]; then
        tmux switch-client -t $current_session;
        tmux kill-session -t twigsmux;
        return 0;
    fi

    if [[ $current_session != "twigsmux" ]]; then
        record_session $current_session
    fi

    s_cut=$(echo $s | rg -o -m 1 "^\w*")

    if [[ $is_default ]]; then
        if ! tmux has-session -t=$s_cut 2> /dev/null; then
            tmux new-session -ds $s_cut -n $default_window -c ~
        fi

        tmux switch-client -t $s_cut
    elif [[ $is_kill ]]; then
        if tmux has-session -t=$s_cut 2> /dev/null; then
            tmux kill-session -t $s_cut
            go_to_last_session $current_session
        fi
    fi

    tmux kill-session -t twigsmux
    return 0;
fi
