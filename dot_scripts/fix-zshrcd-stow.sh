#!/usr/bin/env bash
set -euo pipefail

# Convert ~/.zshrc.d from a legacy symlink to a directory so multiple GNU Stow
# repos can populate it (for example: dotfiles + dotfiles-private).

zshrcd="$HOME/.zshrc.d"

if [[ -L "$zshrcd" ]]; then
  link_target="$(readlink "$zshrcd" 2>/dev/null || true)"
  backup="$zshrcd.symlink.$(date +%Y%m%d%H%M%S)"

  echo "fix-zshrcd-stow: moving symlink $zshrcd -> $backup" >&2
  [[ -n "$link_target" ]] && echo "fix-zshrcd-stow:   symlink target: $link_target" >&2

  mv "$zshrcd" "$backup"
fi

if [[ -e "$zshrcd" && ! -d "$zshrcd" ]]; then
  echo "fix-zshrcd-stow: ERROR: $zshrcd exists but is not a directory." >&2
  exit 1
fi

mkdir -p "$zshrcd"
echo "fix-zshrcd-stow: OK: $zshrcd is a directory." >&2

