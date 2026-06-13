# Env for ALL luma shells, including non-interactive ssh execs (sourced from
# ~/.zshenv). Interactive-only config stays in luma.zsh.

if [[ -f "$HOME/.cargo/env" ]]; then
  source "$HOME/.cargo/env"
fi
