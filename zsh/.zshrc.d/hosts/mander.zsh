# Host config for mander, the Proxmox Ubuntu VM used for local N64 work.

export N64_WORKSPACE="$HOME/code"
export RETROARCH_BIN="$N64_WORKSPACE/RetroArch/retroarch"
export RETROARCH_BASE_CONFIG="$N64_WORKSPACE/RetroArch/retroarch.cfg"
export PARALLEL_N64_CORE="$N64_WORKSPACE/parallel-n64/parallel_n64_libretro.so"
export PAPER_MARIO_ROM="$N64_WORKSPACE/n64_roms/Paper Mario (USA).zip"
export PAPER_MARIO_LEGACY_HTS="$N64_WORKSPACE/parallel-n64/assets/PAPER MARIO_HIRESTEXTURES.hts"
export PAPER_MARIO_PHRB="$N64_WORKSPACE/parallel-n64/artifacts/hts2phrb-review/local-pm64-zero-config/package.phrb"
export N64_RUN_ROOT="$N64_WORKSPACE/parallel-n64/artifacts/local-runs"

# Sunshine is intentionally left on X11 capture + software x264 for this VM.
# KMS + VAAPI works on the passed-through AMD iGPU, but the headless/virtual
# output has no KMS cursor plane, so Moonlight loses the pointer. RetroArch
# itself still renders on RADV/Vulkan through the AMD iGPU.
export SUNSHINE_DISPLAY="${SUNSHINE_DISPLAY:-:0}"

# The AMD Raphael iGPU is passed through to this VM. Leave Vulkan ICD selection
# to Mesa by default so RADV is preferred; opt into lavapipe only for deterministic
# software-render smoke checks.
use_lavapipe() {
  export VK_DRIVER_FILES="/usr/share/vulkan/icd.d/lvp_icd.json"
}

# Desktop sessions normally provide these. Keep SSH/tmux shells pointed at the
# local graphical seat and user session bus so Sunshine/RetroArch can be launched
# manually from a remote shell.
if [[ -z "${DISPLAY:-}" ]]; then
  export DISPLAY="${SUNSHINE_DISPLAY:-:0}"
fi

if [[ -f "$HOME/.Xauthority" && -z "${XAUTHORITY:-}" ]]; then
  export XAUTHORITY="$HOME/.Xauthority"
fi

if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

if [[ -S "$XDG_RUNTIME_DIR/bus" && -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi

if [[ -S "$XDG_RUNTIME_DIR/pulse/native" && -z "${PULSE_SERVER:-}" ]]; then
  export PULSE_SERVER="unix:$XDG_RUNTIME_DIR/pulse/native"
fi

n64-paper-mario() {
  "$HOME/.local/bin/n64-paper-mario" "$@"
}

n64-paper-mario-smoke() {
  "$HOME/.local/bin/n64-paper-mario-smoke" "$@"
}

n64-monitor() {
  "$HOME/.local/bin/n64-monitor" "$@"
}
