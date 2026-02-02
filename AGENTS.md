# AGENTS.md

This file defines repository-specific instructions for automation and agents.

## Structure
- Top-level stow packages: `alacritty`, `bat`, `fonts`, `git`, `idea`, `karabiner`, `lazygit`, `nvim`, `tmux`, `zsh`.
- Packages that map to `~/.config`: `alacritty/.config`, `bat/.config`, `karabiner/.config`, `lazygit/.config`, `nvim/.config`.
- Other key mappings: `fonts/.fonts`, `git/.gitconfig`, `idea/.ideavimrc`, `tmux/.tmux.conf`, `zsh/.zshrc`.
- `dot_scripts/` holds setup and install scripts (brew/nix/osx/linux/etc.) and is not stowed.

## Conventions
- Manage dotfiles with GNU Stow; each top-level package is stowed explicitly.
- Use `link.sh` as the entry point to (re)stow packages; update it when adding or removing packages.
- `link.sh` also rebuilds the bat cache; keep that behavior intact unless explicitly changed.
- Keep shell scripts called from zsh aliases in `zsh/.zsh_scripts`.
- Zsh config lives in `zsh/.zshrc`; aliases should reference scripts under `~/.zsh_scripts` (not `~/.scripts`).
- If a script is meant to be run, ensure it is executable and referenced explicitly from aliases or functions.

## Scripts
- Place new setup or install helpers in `dot_scripts/` with descriptive filenames.
