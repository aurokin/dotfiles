# AGENTS.md

This file defines repository-specific instructions for automation and agents.

## Structure
- Top-level stow packages: `alacritty`, `bat`, `codex`, `fonts`, `git`, `ghostty`, `hammerspoon`, `idea`, `karabiner`, `lazygit`, `mise`, `nvim`, `opencode`, `tmux`, `zsh`.
- Packages that map to `~/.config`: `alacritty/.config`, `bat/.config`, `ghostty/.config`, `karabiner/.config`, `lazygit/.config`, `mise/.config`, `nvim/.config`, `opencode/.config`.
- Other key mappings: `codex/.codex`, `fonts/.fonts`, `git/.gitconfig`, `hammerspoon/.hammerspoon`, `idea/.ideavimrc`, `tmux/.tmux.conf`, `zsh/.zshrc`.
- `dot_scripts/` holds setup and install scripts (brew/apt/osx/linux/etc.) and is not stowed.

## Conventions
- Manage dotfiles with GNU Stow; each top-level package is stowed explicitly.
- Use `link.sh` as the entry point to (re)stow packages; update it when adding or removing packages.
- `link.sh` also rebuilds the bat cache; keep that behavior intact unless explicitly changed.
- Ghostty config lives in `ghostty/.config/ghostty/config`. On macOS, Ghostty prefers `~/Library/Application Support/com.mitchellh.ghostty/config`, so this repo stows a small shim there that loads the XDG config.
- Keep shell scripts called from zsh aliases in `zsh/.zshrc.d/scripts`.
- Zsh config lives in `zsh/.zshrc`; aliases should reference scripts under `~/.zshrc.d/scripts` (not `~/.scripts`).
- If a script is meant to be run, ensure it is executable and referenced explicitly from aliases or functions.
- Neovim config: keep `nvim/.config/nvim/init.lua` as an entrypoint; put non-plugin config in `nvim/.config/nvim/lua/custom/` (e.g. `options.lua`, `keymaps.lua`, `autocmds.lua`) and keep plugin specs in `nvim/.config/nvim/lua/custom/plugins/`.

## Scripts
- Place new setup or install helpers in `dot_scripts/` with descriptive filenames.
