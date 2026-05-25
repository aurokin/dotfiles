#!/usr/bin/env bash
set -euo pipefail
#
# tmux-popup.sh — launch a tmux popup running a command, with named geometry
# presets. Centralizes the `display-popup -E` + geometry + version-gate
# boilerplate the popup keybindings would otherwise repeat (and the fragile
# nested quoting of wrapping display-popup inside run-shell).
#
# Keybindings call this via run-shell so tmux formats (#{client_tty}, ...) are
# expanded into argv before the popup launches.
#
# Usage:
#   tmux-popup.sh <size> [-d <start-dir>] -- <command> [args...]
#
# Sizes:
#   half     -w 50%  -h 50%            (centered)
#   full     -w 100% -h 100%           (centered; "mobile" mode, max space)
#   scan     -x R -y 0 -w 65% -h 20    (top-right; agentscan picker)
#   default  no geometry               (tmux's own default popup size)

size="${1:-}"; shift || true

start_dir=""
if [[ "${1:-}" == "-d" ]]; then
  start_dir="${2:-}"; shift 2 || true
fi

if [[ "${1:-}" != "--" ]]; then
  echo "tmux-popup.sh: expected '--' before the command" >&2
  exit 2
fi
shift  # drop the --

if [[ $# -eq 0 ]]; then
  echo "tmux-popup.sh: no command given" >&2
  exit 2
fi

# display-popup exists since tmux 3.2, but passing a command as multiple argv
# entries (args_to_vector) only works from 3.3 on; on 3.2 it took a single
# shell-command string. Since this helper forwards "$@" as argv, gate on >= 3.3.
# Reuse tmux's own version comparison so we never parse `tmux -V` by hand.
if [[ "$(tmux display-message -p '#{?#{>=:#{version},3.3},1,0}' 2>/dev/null)" != "1" ]]; then
  tmux display-message "popup needs tmux >= 3.3"
  exit 0
fi

geom=()
case "$size" in
  half)    geom=(-w 50% -h 50%) ;;
  full)    geom=(-w 100% -h 100%) ;;
  scan)    geom=(-x R -y 0 -w 65% -h 20) ;;
  default) geom=() ;;
  *) echo "tmux-popup.sh: unknown size '$size'" >&2; exit 2 ;;
esac

dir=()
[[ -n "$start_dir" ]] && dir=(-d "$start_dir")

exec tmux display-popup -E "${geom[@]}" "${dir[@]}" "$@"
