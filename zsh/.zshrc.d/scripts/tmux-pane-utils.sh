#!/usr/bin/env bash

tmux_msg() {
  local client_tty="$1"
  shift
  local msg="$*"
  if [[ -n "$client_tty" ]]; then
    tmux display-message -c "$client_tty" "$msg" 2>/dev/null || true
  else
    tmux display-message "$msg" 2>/dev/null || true
  fi
}

tmux_pane_exists() {
  local pane_id="$1"
  [[ -n "$pane_id" ]] || return 1
  tmux display-message -p -t "$pane_id" '#{pane_id}' >/dev/null 2>&1
}

tmux_focus_pane() {
  local client_tty="$1"
  local pane_id="$2"
  if [[ -z "$pane_id" ]]; then
    return 0
  fi

  # -Z keeps zoom if the target is a pane.
  if [[ -n "$client_tty" ]]; then
    tmux switch-client -Z -c "$client_tty" -t "$pane_id" 2>/dev/null \
      || tmux switch-client -c "$client_tty" -t "$pane_id" 2>/dev/null \
      || true
  else
    tmux switch-client -Z -t "$pane_id" 2>/dev/null \
      || tmux switch-client -t "$pane_id" 2>/dev/null \
      || true
  fi
}
