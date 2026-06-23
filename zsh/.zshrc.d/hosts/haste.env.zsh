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

# Linuxbrew owns the interactive shell baseline tools on Haste (mise, stow,
# tmux, neovim, starship, zoxide, etc.). Non-interactive `ssh haste <cmd>` only
# reads ~/.zshenv, so keep Homebrew reachable here too.
path_prepend_once "/home/linuxbrew/.linuxbrew/sbin"
path_prepend_once "/home/linuxbrew/.linuxbrew/bin"
path_prepend_once "$HOME/.local/bin"
path_prepend_once "$HOME/.bin"

unset -f path_prepend_once
