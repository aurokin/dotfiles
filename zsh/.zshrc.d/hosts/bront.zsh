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

clip_haste() {
  ssh auro@192.168.50.20 'schtasks /Run /TN clip_haste_push'
}
