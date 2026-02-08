#!/usr/bin/env bash
set -euo pipefail

dotfiles_dir="$(
  cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd -P
)"

cd "$dotfiles_dir"

# Stow can't manage ~/.zshrc.d if it's a symlink (common legacy setup).
# Keep link.sh simple: fail fast and tell the user how to fix it.
zshrcd="$HOME/.zshrc.d"
if [[ -L "$zshrcd" ]]; then
  echo "link.sh: ERROR: $zshrcd is a symlink; stow cannot manage it." >&2
  echo "link.sh:        Run: $dotfiles_dir/dot_scripts/fix-zshrcd-stow.sh" >&2
  exit 1
fi
if [[ -e "$zshrcd" && ! -d "$zshrcd" ]]; then
  echo "link.sh: ERROR: $zshrcd exists but is not a directory; stow cannot manage it." >&2
  echo "link.sh:        Fix it (or remove it), then rerun link.sh." >&2
  exit 1
fi

stow -R --no-folding zsh
stow -R tmux git alacritty nvim karabiner lazygit idea bat fonts hammerspoon mise

# Keep this behavior: rebuilding the bat cache is part of linking.
bat cache --build
