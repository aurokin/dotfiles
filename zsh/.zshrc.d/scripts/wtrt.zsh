wtrt() {
    local script_name="wtrt"
    local target current_session session match_count match
    local -a matches

    [[ $# -eq 1 ]] || {
        echo "$script_name: usage: $script_name <worktree>" >&2
        return 2
    }

    target="$1"

    command -v wt >/dev/null 2>&1 || {
        echo "$script_name: wt is required" >&2
        return 1
    }

    wt remove "$target" || return

    command -v tmux >/dev/null 2>&1 || return 0
    tmux list-sessions >/dev/null 2>&1 || return 0

    current_session="$(tmux display-message -p '#S' 2>/dev/null || true)"
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
