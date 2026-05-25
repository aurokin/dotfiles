wtrt() {
    local script_name="wtrt"
    local cwd kill_session target current_session session match_count match
    local -a matches

    cwd=""
    kill_session=""
    target=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cwd)
                [[ -n ${2-} ]] || {
                    echo "$script_name: --cwd requires a path" >&2
                    return 2
                }
                cwd="$2"
                shift 2
                ;;
            --session)
                [[ -n ${2-} ]] || {
                    echo "$script_name: --session requires a tmux session name" >&2
                    return 2
                }
                kill_session="$2"
                shift 2
                ;;
            --)
                shift
                break
            ;;
            -*)
                echo "$script_name: unknown option: $1" >&2
                return 2
                ;;
            *)
                break
                ;;
        esac
    done

    if [[ $# -eq 1 ]]; then
        target="$1"
        shift
    fi

    [[ -n "$target" && $# -eq 0 ]] || {
        echo "$script_name: usage: $script_name [--cwd <repo-path>] [--session <tmux-session>] <worktree>" >&2
        return 2
    }

    command -v wt >/dev/null 2>&1 || {
        echo "$script_name: wt is required" >&2
        return 1
    }

    if [[ -n "$cwd" ]]; then
        (
            cd "$cwd" 2>/dev/null || {
                echo "$script_name: cwd does not exist: $cwd" >&2
                exit 1
            }
            wt remove "$target"
        ) || return
    else
        wt remove "$target" || return
    fi

    command -v tmux >/dev/null 2>&1 || return 0
    tmux list-sessions >/dev/null 2>&1 || return 0

    current_session="$(tmux display-message -p '#S' 2>/dev/null || true)"

    if [[ -n "$kill_session" ]]; then
        [[ "$kill_session" != "$current_session" ]] || return 0
        tmux kill-session -t "=$kill_session"
        return $?
    fi

    matches=()

    while IFS= read -r session; do
        [[ -n "$session" ]] || continue
        if [[ "$session" == "$target" || "$session" == *-"$target" ]]; then
            matches+=("$session")
        fi
    done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null)

    match_count="${#matches[@]}"
    [[ "$match_count" -eq 1 ]] || return 0

    match="${matches[1]}"
    [[ -n "$match" && "$match" != "$current_session" ]] || return 0

    tmux kill-session -t "=$match"
}
