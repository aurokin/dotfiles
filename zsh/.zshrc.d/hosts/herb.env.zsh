# Env for ALL Herb shells, including non-interactive ssh execs (sourced from
# ~/.zshenv). Interactive-only config belongs in herb.zsh.

path_prepend_once() {
  local path_entry="$1"
  [[ -d "$path_entry" ]] || return 0
  case ":$PATH:" in
    *":$path_entry:"*) ;;
    *) export PATH="$path_entry:$PATH" ;;
  esac
}

# Keep the Linuxbrew-backed fleet toolchain available to non-interactive SSH.
export HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
export HOMEBREW_CELLAR="$HOMEBREW_PREFIX/Cellar"
export HOMEBREW_REPOSITORY="$HOMEBREW_PREFIX/Homebrew"
path_prepend_once "/home/linuxbrew/.linuxbrew/sbin"
path_prepend_once "/home/linuxbrew/.linuxbrew/bin"
path_prepend_once "$HOME/.local/bin"
path_prepend_once "$HOME/.bin"

# The npm:browse tool currently resolves to pino 9.14.0, which mise/aube
# correctly blocks because that backport lost the trusted-publisher evidence
# present on pino 10. Keep Herb on agent-browser rather than bypassing the
# supply-chain downgrade check. Diffwarden's aube install also aborts without a
# useful trust result here, so Herb uses Auro's source checkout instead.
export MISE_DISABLE_TOOLS="npm:browse,npm:diffwarden"

# Herb keeps a real KDE Wayland desktop running for CRT gaming and headed agent
# tasks. Expose the live desktop to SSH-launched tools only when its sockets and
# authorization files exist and the caller has not selected another display.
if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "/run/user/$(id -u)" ]]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
  if [[ -z "${WAYLAND_DISPLAY:-}" && -S "$XDG_RUNTIME_DIR/wayland-0" ]]; then
    export WAYLAND_DISPLAY="wayland-0"
  fi

  if [[ -z "${XAUTHORITY:-}" ]]; then
    for xauth_file in "$XDG_RUNTIME_DIR"/xauth_*(N.om[1]); do
      export XAUTHORITY="$xauth_file"
      break
    done
  fi
fi

if [[ -z "${DISPLAY:-}" && -S "/tmp/.X11-unix/X0" ]]; then
  export DISPLAY=":0"
fi

# Make mise-managed CLIs available to non-interactive SSH commands too.
# Interactive shells use the full `mise activate zsh` hook from ~/.zshrc.
if [[ ! -o interactive ]] && command -v mise >/dev/null 2>&1; then
  eval "$(mise hook-env -s zsh)"
fi

unset -f path_prepend_once
