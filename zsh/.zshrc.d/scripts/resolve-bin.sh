# Sourceable helper: resolve a dogfooded binary to an absolute path.
#
# Prefer a local ~/.cargo/bin build so dev builds win for dogfooding, then a
# user-local install, then the mise shim for the released install. Absolute
# paths mean callers do not depend on the tmux server's PATH or shell
# activation.
#
# Usage:
#   source "$script_dir/resolve-bin.sh"
#   exec "$(resolve_bin agentscan)" "$@"
resolve_bin() {
  local name="$1"
  if [[ -x "$HOME/.cargo/bin/$name" ]]; then
    printf '%s\n' "$HOME/.cargo/bin/$name"
  elif [[ -x "$HOME/.local/bin/$name" ]]; then
    printf '%s\n' "$HOME/.local/bin/$name"
  else
    printf '%s\n' "$HOME/.local/share/mise/shims/$name"
  fi
}
