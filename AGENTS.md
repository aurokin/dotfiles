# AGENTS.md

This file defines repository-specific instructions for automation and agents.

## Structure
- Top-level stow packages: `agent-modes`, `agentscan`, `alacritty`, `bat`, `codex`, `git`, `ghostty`, `hammerspoon`, `idea`, `karabiner`, `lazygit`, `mise`, `nvim`, `starship`, `tmux`, `wezterm`, `worktrunk`, `zsh`.
- Packages that map to `~/.config`: `agent-modes/.config`, `agentscan/.config`, `alacritty/.config`, `bat/.config`, `ghostty/.config`, `karabiner/.config`, `lazygit/.config`, `mise/.config`, `nvim/.config`, `starship/.config`, `wezterm/.config`, `worktrunk/.config`.
- Other key mappings: `git/.gitconfig`, `hammerspoon/.hammerspoon`, `idea/.ideavimrc`, `tmux/.tmux.conf`, `zsh/.zshrc`.
- `codex/` stows single files into `~/.codex` (live agent state lives there, so it is stowed `--no-folding`); it holds launch-time overlays like `vanilla.config.toml`, not the main `config.toml`.
- `dot_scripts/` holds setup and install scripts (brew/apt/osx/linux/etc.) and is not stowed.

## Conventions
- Manage dotfiles with GNU Stow; each top-level package is stowed explicitly.
- Use `link.sh` as the entry point to (re)stow packages; update it when adding or removing packages.
- `link.sh` also rebuilds the bat cache; keep that behavior intact unless explicitly changed.
- Ghostty config lives in `ghostty/.config/ghostty/config`. On macOS, Ghostty prefers `~/Library/Application Support/com.mitchellh.ghostty/config`, so this repo stows a small shim there that loads the XDG config.
- Keep shell scripts called from zsh aliases in `zsh/.zshrc.d/scripts`.
- Vanilla agent modes (`vcc`/`lvcc`, `vgpt`/`lvgpt`) are launch-time overlays only: `agent-modes/.config/agent-modes/claude-vanilla.json` and `codex/.codex/vanilla.config.toml`. Never switch modes by installing/removing skills.
- Zsh config lives in `zsh/.zshrc`; aliases should reference scripts under `~/.zshrc.d/scripts` (not `~/.scripts`).
- Per-machine zsh config: `zsh/.zshrc.d/hosts/<short-hostname>.zsh`, auto-sourced by `.zshrc` against the domain-stripped `uname -n` (e.g. `koopa`). Use for host-specific PATH/env (tools installed outside mise); follow the guarded-`PATH` idiom in existing host files.
- Env that must also reach non-interactive shells (`ssh <host> <cmd>` reads only `.zshenv`): `zsh/.zshrc.d/hosts/<short-hostname>.env.zsh`, auto-sourced by `zsh/.zshenv`; keep it env/PATH-only and fast.
- If a script is meant to be run, ensure it is executable and referenced explicitly from aliases or functions.
- Neovim config: keep `nvim/.config/nvim/init.lua` as an entrypoint; put non-plugin config in `nvim/.config/nvim/lua/custom/` (e.g. `options.lua`, `keymaps.lua`, `autocmds.lua`) and keep plugin specs in `nvim/.config/nvim/lua/custom/plugins/`.

## Scripts
- Place new setup or install helpers in `dot_scripts/` with descriptive filenames.
