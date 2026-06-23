# Env for ALL haste shells, including non-interactive ssh execs (sourced from
# ~/.zshenv). Interactive-only config belongs in haste.zsh.

path_prepend_once() {
  local path_entry="$1"
  [[ -d "$path_entry" ]] || return 0
  case ":$PATH:" in
    *":$path_entry:"*) ;;
    *) export PATH="$path_entry:$PATH" ;;
  esac
}

# Linuxbrew owns the shell baseline tools on Haste (mise, stow, tmux, neovim,
# starship, zoxide, etc.). Non-interactive `ssh haste <cmd>` only reads
# ~/.zshenv, so keep Homebrew reachable here too.
export HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
export HOMEBREW_CELLAR="$HOMEBREW_PREFIX/Cellar"
export HOMEBREW_REPOSITORY="$HOMEBREW_PREFIX/Homebrew"
path_prepend_once "/home/linuxbrew/.linuxbrew/sbin"
path_prepend_once "/home/linuxbrew/.linuxbrew/bin"
path_prepend_once "$HOME/.local/bin"
path_prepend_once "$HOME/.bin"


# Haste keeps a real KDE Wayland desktop running for headed browser/agent tasks.
# Non-interactive SSH sessions do not inherit graphical session variables, so
# expose the live desktop only when the sockets/auth files are present and the
# caller has not already selected a display.
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

# Make mise-managed CLIs available to non-interactive ssh commands too.
# Interactive shells use the full `mise activate zsh` hook from ~/.zshrc.
if [[ ! -o interactive ]] && command -v mise >/dev/null 2>&1; then
  eval "$(mise hook-env -s zsh)"
fi

unset -f path_prepend_once
