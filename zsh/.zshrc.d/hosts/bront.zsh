# OpenClaw completion was removed for startup speed; re-add if needed:
# source <(openclaw completion --shell zsh)

# Local-only npm global bin (e.g. OpenClaw installed outside mise).
# Keep it lower priority than mise-managed tools.
npm_global_bin="$HOME/.npm-global/bin"
if [[ -d "$npm_global_bin" ]]; then
  case ":$PATH:" in
    *":$npm_global_bin:"*) ;;
    *) export PATH="$PATH:$npm_global_bin" ;;
  esac
fi

export DISPLAY=:0
export XAUTHORITY="$HOME/.Xauthority"

# Legacy wrappers kept for muscle memory. Prefer `crs <source>`.
clip_bront() {
  crs haste "$@"
}

clip_haste() {
  crs haste "$@"
}

clip_luma() {
  crs luma "$@"
}
