# Cleanup backlog

Findings from a repo review (2026-07-19). Done already: deleted `fonts/`
(68 MB of TTFs; install the Nerd Font via brew cask or the nerd-fonts
release instead) and stopped tracking `karabiner/automatic_backups/`
(now gitignored; Karabiner has no setting to disable writing them).

## Extract into their own repos

Pattern to follow: `agentscan` / `tprompt` / `diffwarden` — own repo at
`github:aurokin/<tool>`, installed fleet-wide via the mise manifest here.
The tell that a script is a project: it has its own tests in `tests/`.

1. **Git worktree suite** (~2,900 lines): `git-workspace.sh`,
   `git-new-worktree.sh`, `git-worktree-paths.sh`, `wtct.zsh`, `wtrt.zsh`,
   plus `docs/git-worktrees.md` and three test files. Largest and
   cleanest-bounded — extract first.
2. **`find-agents-tmux.sh`** (1,279 lines) + `agents-popup.sh` +
   `agentscan-popup.sh`. Overlaps with agentscan — fold in or make a
   sibling repo.
3. **twigsmux** (~1,200 lines with `tmux-workspace.sh`, `tmux-kick.sh`,
   `tmux-pane-utils.sh`, `tmux-popup.sh`; has a unit test). Only coupling
   is `.tmux.conf` keybind paths.
4. **super-claude** + `super-claude-menu` (389 lines, two test files).
   Client for a network service with its own state dir (`~/.super-claude`);
   actively evolving, so separate versioning pays off.

## Doesn't belong in dotfiles

- ComfyUI scripts (`dot_scripts/comfyui_install.sh`, `scripts/comfyui.sh`,
  `scripts/comfyui-install.sh`) and `dot_scripts/portless_service_install.sh`
  — app/service deployment, not environment config. Move next to infra
  docs or a machine-provisioning repo.
- `dot_scripts/nix_uninstall.sh` — one-time migration artifact; confirm
  and drop.

## On-host configs missing from dotfiles

- `~/.config/btop/` — btop is on the README utilities list but untracked.
- `~/.config/agentscan/config.toml`, `~/.config/diffwarden/*.json`, and
  especially `~/.config/tprompt/prompts/` — binaries are mise-versioned
  fleet-wide but their configs/prompts exist only on koopa.
- `~/.config/skills-manager/config.json` — the fleet doc calls koopa's
  copy "the reference copy"; belongs in `~/.dotfiles-private` (references
  private repo names).
- `~/.config/gh/config.yml` — settings only; never `hosts.yml` (tokens).
