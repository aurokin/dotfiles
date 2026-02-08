#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Back-compat wrapper (kept for older keybinds / muscle memory).
# Prefer calling:
#   ~/.zshrc.d/scripts/tmux-workspace.sh reorder '#{client_tty}' '#{pane_id}'

script_dir="$(
  cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd -P
)"

exec "$script_dir/tmux-workspace.sh" reorder "$@"

