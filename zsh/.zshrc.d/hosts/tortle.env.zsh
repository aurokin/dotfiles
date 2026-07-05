# Host-specific non-interactive environment for tortle.
# Keep Linuxbrew tools visible for SSH-launched agents and scripts.
linuxbrew_bin="/home/linuxbrew/.linuxbrew/bin"
linuxbrew_sbin="/home/linuxbrew/.linuxbrew/sbin"
if [[ -d "$linuxbrew_bin" ]]; then
  case ":$PATH:" in
    *":$linuxbrew_bin:"*) ;;
    *) export PATH="$linuxbrew_bin:$linuxbrew_sbin:$PATH" ;;
  esac
fi
unset linuxbrew_bin linuxbrew_sbin
