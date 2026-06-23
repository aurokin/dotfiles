# Env for ALL metapod shells, including non-interactive ssh execs (sourced from
# ~/.zshenv). Interactive-only config stays in metapod.zsh.

path_prepend_once() {
  local path_entry="$1"
  [[ -d "$path_entry" ]] || return 0
  case ":$PATH:" in
    *":$path_entry:"*) ;;
    *) export PATH="$path_entry:$PATH" ;;
  esac
}

path_prepend_once "/opt/homebrew/sbin"
path_prepend_once "/opt/homebrew/bin"
path_prepend_once "/opt/homebrew/opt/gnu-sed/libexec/gnubin"
path_prepend_once "/opt/homebrew/opt/coreutils/libexec/gnubin"
path_prepend_once "$HOME/.local/bin"
path_prepend_once "/Applications/Codex.app/Contents/Resources"

unset -f path_prepend_once

# Load the regular host config too so remote Codex shells get the same N64
# workspace variables as interactive shells.
metapod_host_file="$HOME/.zshrc.d/hosts/metapod.zsh"
if [[ -f "$metapod_host_file" ]]; then
  source "$metapod_host_file"
fi
unset metapod_host_file
