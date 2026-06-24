#!/bin/bash

set -euo pipefail

install_root="${COMFYUI_INSTALL_ROOT:-$HOME/workspace}"
comfy_dir="${COMFYUI_DIR:-$install_root/ComfyUI}"
models_dir="${COMFYUI_MODELS_DIR:-$install_root/comfy-models}"
venv_dir="$comfy_dir/.venv"
python_version="${COMFYUI_PYTHON_VERSION:-3.13}"

ensure_tool_path() {
  if command -v uv >/dev/null 2>&1; then
    return 0
  fi

  if command -v mise >/dev/null 2>&1; then
    eval "$(mise env -s bash)"
  fi
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
}

clone_or_update() {
  local repo="$1"
  local target="$2"

  if [[ -d "$target/.git" ]]; then
    echo "Updating $target..."
    git -C "$target" pull --ff-only
  elif [[ -e "$target" ]]; then
    echo "$target exists but is not a git checkout; refusing to overwrite it." >&2
    exit 1
  else
    echo "Cloning $repo into $target..."
    git clone "$repo" "$target"
  fi
}

yaml_single_quote() {
  local value="$1"
  local escaped="${value//\'/\'\'}"
  printf "'%s'" "$escaped"
}

venv_matches_python_version() {
  local current_version

  current_version="$("$venv_dir/bin/python" - <<'PY'
import sys

print(".".join(str(part) for part in sys.version_info[:3]))
PY
)"

  [[ "$current_version" == "$python_version" || "$current_version" == "$python_version".* ]]
}

write_extra_model_paths() {
  local config_file="$comfy_dir/extra_model_paths.yaml"
  local quoted_models_dir

  mkdir -p \
    "$models_dir/models/checkpoints" \
    "$models_dir/models/clip" \
    "$models_dir/models/clip_vision" \
    "$models_dir/models/configs" \
    "$models_dir/models/controlnet" \
    "$models_dir/models/diffusion_models" \
    "$models_dir/models/embeddings" \
    "$models_dir/models/loras" \
    "$models_dir/models/text_encoders" \
    "$models_dir/models/upscale_models" \
    "$models_dir/models/vae"

  if [[ -f "$config_file" ]]; then
    echo "Keeping existing $config_file"
    return 0
  fi

  quoted_models_dir="$(yaml_single_quote "$models_dir")"

  cat >"$config_file" <<YAML
workspace_models:
  base_path: $quoted_models_dir
  checkpoints: models/checkpoints
  clip: models/clip
  clip_vision: models/clip_vision
  configs: models/configs
  controlnet: models/controlnet
  diffusion_models: models/diffusion_models
  embeddings: models/embeddings
  loras: models/loras
  text_encoders: models/text_encoders
  upscale_models: models/upscale_models
  vae: models/vae
YAML
}

ensure_tool_path
require_command git
require_command uv

mkdir -p "$install_root"
clone_or_update "https://github.com/Comfy-Org/ComfyUI.git" "$comfy_dir"

echo "Ensuring Python $python_version is available through uv..."
uv python install "$python_version"

if [[ ! -x "$venv_dir/bin/python" ]]; then
  echo "Creating virtual environment at $venv_dir..."
  uv venv --python "$python_version" "$venv_dir"
elif ! venv_matches_python_version; then
  echo "Recreating virtual environment at $venv_dir for Python $python_version..."
  uv venv --clear --python "$python_version" "$venv_dir"
fi

# shellcheck disable=SC1091
source "$venv_dir/bin/activate"

echo "Installing ComfyUI Python dependencies..."
uv pip install -U pip setuptools wheel
# Apple Silicon PyTorch wheels include Metal/MPS support.
uv pip install -U torch torchvision torchaudio
uv pip install -r "$comfy_dir/requirements.txt"

manager_dir="$comfy_dir/custom_nodes/comfyui-manager"
clone_or_update "https://github.com/Comfy-Org/ComfyUI-Manager.git" "$manager_dir"
uv pip install -r "$manager_dir/requirements.txt"

write_extra_model_paths

cat <<EOF

ComfyUI is installed at:
  $comfy_dir

Models directory:
  $models_dir

Launch with:
  $venv_dir/bin/python $comfy_dir/main.py --listen 127.0.0.1 --port 8188

After relinking dotfiles, you can also run:
  comfyui
EOF
