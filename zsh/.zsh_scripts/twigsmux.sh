#!/bin/bash

record_session() {
    rm ~/.twigsmux
    echo $1 > ~/.twigsmux
}

tmux_running=$(pgrep tmux)
tmux_active=$(echo $TMUX)
is_kill="";
is_last="";
if [[ $1 == "k" ]]; then
    is_kill=true;
fi
if [[ $1 == "l" ]]; then
    is_last=true;
fi
if [[ $1 == "r" ]]; then
    current_session=$(tmux display-message -p '#S')
    record_session;
    exit 0;
fi

if [[ -z $tmux_active ]]; then
    if [[ $tmux_running ]]; then
        $(tmux a);
    else
        $(tmux new -s default);
    fi
fi

if [[ $tmux_running ]]; then
    current_session=$(tmux display-message -p '#S')

    if [[ $is_last ]]; then
        last_session=$(cat ~/.twigsmux)

        if tmux has-session -t=$last_session 2> /dev/null && [[ $last_session != "twigsmux" ]] && [[ $current_session != "twigsmux" ]]; then
            record_session $current_session
            tmux switch-client -t $last_session
        fi
        exit 0;
    fi

    if [[ $current_session != "twigsmux" ]]; then
        record_session $current_session

        tmux kill-session -t twigsmux;
        tmux new-session -ds twigsmux -c ~
        tmux switch-client -t twigsmux

        if [[ $is_kill = true ]]; then
            tmux send-keys -t twigsmux "source ~/.zsh_scripts/twigsmux.sh k" enter
        else
            tmux send-keys -t twigsmux "source ~/.zsh_scripts/twigsmux.sh" enter
        fi
        exit 0;
    fi

    s=$(tmux ls | awk '{print $1}' | fzf --print-query | tail -1)

    if [[ -z $s ]]; then
        tmux kill-session -t twigsmux;
        exit 0;
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

    tmux kill-session -t twigsmux
fi
