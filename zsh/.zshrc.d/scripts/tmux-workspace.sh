#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

script_name="$(basename "$0")"

WORKSPACE_PRIORITY=(editor git query ai)

usage() {
  cat <<EOF
Usage:
  $script_name reorder [client_tty] [pane_id]
  $script_name scaffold [client_tty] [pane_id]

Notes:
  - Designed to be called from tmux keybinds via run-shell, passing:
      '#{client_tty}' '#{pane_id}'
EOF
}

die() {
  echo "$script_name: $*" >&2
  exit 1
}

have_tmux() {
  command -v tmux >/dev/null 2>&1
}

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

resolve_pane_id() {
  local pane_id="${1:-${TMUX_PANE:-}}"
  if [[ -n "$pane_id" ]]; then
    printf '%s' "$pane_id"
    return 0
  fi

  if [[ -z "${TMUX:-}" ]]; then
    return 1
  fi

  tmux display-message -p '#{pane_id}' 2>/dev/null || true
}

resolve_session_from_pane() {
  local pane_id="$1"
  tmux display-message -p -t "$pane_id" '#S' 2>/dev/null || true
}

resolve_base_index() {
  local session="$1"
  local base=""

  # If base-index is only set at the global scope, `show-option -t` may return
  # empty. Fall back to the global default so we honor `set -g base-index 1`.
  base="$(tmux show-option -t "$session" -qv base-index 2>/dev/null || true)"
  if [[ -z "$base" ]]; then
    base="$(tmux show-option -gqv base-index 2>/dev/null || true)"
  fi

  base="${base:-1}"
  if [[ ! "$base" =~ ^[0-9]+$ ]]; then
    base=1
  fi
  printf '%s' "$base"
}

resolve_workspace_base_index() {
  local session="$1"
  local base

  base="$(resolve_base_index "$session")"

  # Workspace windows (editor/git/query/ai) should start at 1 even if the
  # session's base-index is 0 (for example, older sessions or a scratch window
  # at index 0).
  if (( base < 1 )); then
    base=1
  fi

  printf '%s' "$base"
}

set_session_working_dir() {
  local session="$1"
  local start_dir="$2"

  # tmux 3.x no longer has a `default-path` option. Use attach-session -c to
  # set the session working directory, which controls where plain `new-window`
  # commands (for example prefix + c) start.
  tmux attach-session -t "$session" -c "$start_dir" 2>/dev/null || true
}

list_windows() {
  local session="$1"
  tmux list-windows -t "$session" -F '#{window_id}|#{window_index}|#{window_name}'
}

win_id_by_name() {
  local session="$1"
  local name="$2"
  list_windows "$session" | awk -F'|' -v name="$name" '$3 == name { print $1; exit }'
}

win_id_at_index() {
  local session="$1"
  local idx="$2"
  list_windows "$session" | awk -F'|' -v idx="$idx" '$2 == idx { print $1; exit }'
}

win_index_by_id() {
  local session="$1"
  local id="$2"
  list_windows "$session" | awk -F'|' -v id="$id" '$1 == id { print $2; exit }'
}

reorder_windows() {
  local session="$1"
  local base_index="$2"
  shift 2
  local -a priority=("$@")

  local did_any=0
  local i name desired_idx src_id src_idx dst_id

  for i in "${!priority[@]}"; do
    name="${priority[$i]}"
    desired_idx=$((base_index + i))

    src_id="$(win_id_by_name "$session" "$name" || true)"
    [[ -z "$src_id" ]] && continue

    src_idx="$(win_index_by_id "$session" "$src_id" || true)"
    [[ -z "$src_idx" ]] && continue
    [[ "$src_idx" -eq "$desired_idx" ]] && continue

    dst_id="$(win_id_at_index "$session" "$desired_idx" || true)"
    if [[ -n "$dst_id" ]]; then
      tmux swap-window -s "$src_id" -t "$dst_id" 2>/dev/null || true
      did_any=1
      continue
    fi

    if tmux move-window -s "$src_id" -t "$session:$desired_idx" 2>/dev/null; then
      did_any=1
      continue
    fi

    # If indices changed underneath us, fall back to a swap.
    dst_id="$(win_id_at_index "$session" "$desired_idx" || true)"
    if [[ -n "$dst_id" ]]; then
      tmux swap-window -s "$src_id" -t "$dst_id" 2>/dev/null || true
      did_any=1
    fi
  done

  printf '%s' "$did_any"
}

ensure_window() {
  local session="$1"
  local name="$2"
  local start_dir="$3"
  if [[ -n "$(win_id_by_name "$session" "$name" || true)" ]]; then
    return 0
  fi

  # Keep behavior consistent with tmux binds (prefix + g opens lazygit).
  if [[ "$name" == "git" ]]; then
    tmux new-window -d -S -t "$session:" -n "$name" -c "$start_dir" 'lazygit'
  else
    tmux new-window -d -S -t "$session:" -n "$name" -c "$start_dir"
  fi
}

scaffold_workspace() {
  local client_tty="$1"
  local invoking_pane_id="$2"
  local session="$3"
  local start_dir="$4"

  set_session_working_dir "$session" "$start_dir"

  # Create missing windows in this directory.
  local name
  for name in "${WORKSPACE_PRIORITY[@]}"; do
    ensure_window "$session" "$name" "$start_dir"
  done

  # Put tabs in the preferred order.
  local base_index
  base_index="$(resolve_workspace_base_index "$session")"
  reorder_windows "$session" "$base_index" "${WORKSPACE_PRIORITY[@]}" >/dev/null

  # Return to the pane you invoked from (it may not always be under "editor").
  tmux_focus_pane "$client_tty" "$invoking_pane_id"

  tmux_msg "$client_tty" "Scaffolded workspace in: $start_dir"
}

main() {
  have_tmux || die "tmux is not installed"

  local subcmd="${1:-}"
  case "$subcmd" in
    reorder|scaffold)
      shift
      ;;
    -h|--help|"")
      usage
      exit 0
      ;;
    *)
      die "unknown command: $subcmd"
      ;;
  esac

  local client_tty="${1:-}"
  local pane_id
  pane_id="$(resolve_pane_id "${2:-}")"
  [[ -n "$pane_id" ]] || die "couldn't determine pane id"

  local session
  session="$(resolve_session_from_pane "$pane_id")"
  [[ -n "$session" ]] || die "couldn't determine session (pane: $pane_id)"

  case "$subcmd" in
    reorder)
      local base_index did_any
      base_index="$(resolve_workspace_base_index "$session")"
      did_any="$(reorder_windows "$session" "$base_index" "${WORKSPACE_PRIORITY[@]}")"
      tmux_focus_pane "$client_tty" "$pane_id"
      if [[ "$did_any" -eq 1 ]]; then
        local priority_str
        priority_str="$(IFS=' '; printf '%s' "${WORKSPACE_PRIORITY[*]}")"
        tmux_msg "$client_tty" "Reordered windows: $priority_str"
      else
        tmux_msg "$client_tty" "No windows to reorder"
      fi
      ;;
    scaffold)
      local start_dir
      start_dir="$(tmux display-message -p -t "$pane_id" '#{pane_current_path}' 2>/dev/null || true)"
      start_dir="${start_dir:-$HOME}"
      scaffold_workspace "$client_tty" "$pane_id" "$session" "$start_dir"
      ;;
  esac
}

main "$@"
