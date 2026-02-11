# Deferred zsh reload across tmux panes.

: "${ZSH_TMUX_RELOAD_LAST_TOKEN:=}"

_zsh_tmux_reload_source() {
    source "$HOME/.zshrc"
}

_zsh_tmux_reload_check() {
    [[ -n ${TMUX-} ]] || return 0
    command -v tmux >/dev/null 2>&1 || return 0

    local line token
    line="$(tmux show-environment -g ZSH_RELOAD_TOKEN 2>/dev/null || true)"
    [[ "$line" == ZSH_RELOAD_TOKEN=* ]] || return 0

    token="${line#ZSH_RELOAD_TOKEN=}"
    [[ -n "$token" ]] || return 0
    [[ "$token" != "$ZSH_TMUX_RELOAD_LAST_TOKEN" ]] || return 0

    ZSH_TMUX_RELOAD_LAST_TOKEN="$token"
    _zsh_tmux_reload_source
}

_zsh_tmux_reload_accept_line() {
    _zsh_tmux_reload_check
    zle .accept-line
}

if [[ -o interactive ]] && (( ${+widgets} )); then
    if [[ "${widgets[accept-line]-}" != user:_zsh_tmux_reload_accept_line ]]; then
        zle -N accept-line _zsh_tmux_reload_accept_line
    fi
fi

zshrd() {
    if [[ -z ${TMUX-} ]]; then
        _zsh_tmux_reload_source
        return 0
    fi

    command -v tmux >/dev/null 2>&1 || {
        _zsh_tmux_reload_source
        return 0
    }

    local token
    token="$(date +%s).$RANDOM"

    tmux set-environment -g ZSH_RELOAD_TOKEN "$token" 2>/dev/null || {
        _zsh_tmux_reload_source
        return 0
    }

    ZSH_TMUX_RELOAD_LAST_TOKEN="$token"
    _zsh_tmux_reload_source
}
