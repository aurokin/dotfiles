# Env for ALL luma shells, including non-interactive ssh execs (sourced from
# ~/.zshenv). Interactive-only config stays in luma.zsh.

homebrew_bin="/opt/homebrew/bin"
if [[ -d "$homebrew_bin" ]]; then
  case ":$PATH:" in
    *":$homebrew_bin:"*) ;;
    *) export PATH="$homebrew_bin:$PATH" ;;
  esac
fi
unset homebrew_bin

if [[ -f "$HOME/.cargo/env" ]]; then
  source "$HOME/.cargo/env"
fi
