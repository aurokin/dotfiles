# Host-specific non-interactive environment for saur.
# Keep Linuxbrew and mise-managed tools visible for SSH-launched agents and scripts.
linuxbrew_bin="/home/linuxbrew/.linuxbrew/bin"
linuxbrew_sbin="/home/linuxbrew/.linuxbrew/sbin"
mise_shims="$HOME/.local/share/mise/shims"
local_bin="$HOME/.local/bin"
grok_bin="$HOME/.grok/bin"
for path_entry in "$grok_bin" "$local_bin" "$mise_shims" "$linuxbrew_sbin" "$linuxbrew_bin"; do
  if [[ -d "$path_entry" ]]; then
    case ":$PATH:" in
      *":$path_entry:"*) ;;
      *) export PATH="$path_entry:$PATH" ;;
    esac
  fi
done
unset linuxbrew_bin linuxbrew_sbin mise_shims local_bin grok_bin path_entry
