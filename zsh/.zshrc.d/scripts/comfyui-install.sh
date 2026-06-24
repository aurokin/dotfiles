#!/usr/bin/env bash

set -euo pipefail

dotfiles_dir="${DOTFILES_DIR:-$HOME/.dotfiles}"
installer="$dotfiles_dir/dot_scripts/comfyui_install.sh"

if [[ ! -x "$installer" ]]; then
  echo "ComfyUI installer is not executable at $installer." >&2
  exit 1
fi

exec "$installer" "$@"
