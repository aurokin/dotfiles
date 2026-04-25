wtct() {
    local script_name="wtct"
    local session branch client_tty pane_id select_window target_window_id

    select_window=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --select-window)
                [[ -n ${2-} ]] || {
                    echo "$script_name: --select-window requires a window name" >&2
                    return 2
                }
                select_window="$2"
                shift 2
                ;;
            *)
                echo "$script_name: unknown option: $1" >&2
                return 2
                ;;
        esac
    done

    command -v tmux >/dev/null 2>&1 || {
        echo "$script_name: tmux is required" >&2
        return 1
    }

    [[ -n ${TMUX-} ]] || {
        echo "$script_name: must be run inside tmux" >&2
        return 1
    }

    command -v wt >/dev/null 2>&1 || {
        echo "$script_name: wt is required" >&2
        return 1
    }

    session="$(tmux display-message -p '#S' 2>/dev/null || true)"
    [[ -n "$session" ]] || {
        echo "$script_name: couldn't determine tmux session name" >&2
        return 1
    }

    branch="$session"
    if [[ ! "$branch" =~ '^[a-z][a-z0-9]*-[a-z][a-z0-9]*-[0-9]+$' ]]; then
        echo "$script_name: session '$session' does not match required branch pattern '<project>-<ticket-key>-<number>'" >&2
        return 1
    fi

    wt switch --create --base=@ "$branch" || return

    pane_id="$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)"
    [[ -n "$pane_id" ]] || pane_id="${TMUX_PANE-}"

    client_tty="$(tmux display-message -p '#{client_tty}' 2>/dev/null || true)"

    "$HOME/.zshrc.d/scripts/tmux-workspace.sh" scaffold "$client_tty" "$pane_id"

    if [[ -n "$select_window" ]]; then
        target_window_id="$(tmux list-windows -t "=$session" -F '#{window_id}|#{window_name}' 2>/dev/null | awk -F'|' -v name="$select_window" '$2 == name { print $1; exit }')"
        [[ -n "$target_window_id" ]] || {
            echo "$script_name: couldn't find tmux window '$select_window' after scaffold" >&2
            return 1
        }

        if [[ -n "$client_tty" ]]; then
            tmux switch-client -c "$client_tty" -t "$target_window_id"
        else
            tmux select-window -t "$target_window_id"
        fi
    fi
}
