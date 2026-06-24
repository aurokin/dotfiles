#!/usr/bin/env bash

set -euo pipefail

install_root="${COMFYUI_INSTALL_ROOT:-$HOME/workspace}"
comfy_dir="${COMFYUI_DIR:-$install_root/ComfyUI}"
python_bin="$comfy_dir/.venv/bin/python"
listen="${COMFYUI_LISTEN:-127.0.0.1}"
port="${COMFYUI_PORT:-8188}"

if [[ ! -x "$python_bin" ]]; then
  echo "ComfyUI is not installed at $comfy_dir." >&2
  echo "Run: $HOME/.zshrc.d/scripts/comfyui-install.sh" >&2
  exit 1
fi

cd "$comfy_dir"
exec "$python_bin" main.py --listen "$listen" --port "$port" "$@"
