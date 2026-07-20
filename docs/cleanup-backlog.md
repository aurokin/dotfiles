# Cleanup backlog

Findings from a repo review (2026-07-19), updated as items resolve.

Done so far: deleted `fonts/` (install the Nerd Font via brew cask /
nerd-fonts release instead); untracked + gitignored karabiner
`automatic_backups/` (Karabiner has no setting to disable writing them);
deleted `dot_scripts/nix_uninstall.sh`; removed `find-agents-tmux.sh` +
`agents-popup.sh` (ported to agentscan; `agents` alias now runs
agentscan); adopted `~/.config/agentscan/config.toml` as a stow package.

Decided against: btop (no custom config to track); gh config (only
customization is the `co: pr checkout` alias — not worth it);
skills-manager config.json (living document owned by the Hermes agent,
not a good fit for static dotfiles).

## Extract into their own repos

Pattern to follow: `agentscan` / `tprompt` / `diffwarden` — own repo at
`github:aurokin/<tool>`, installed fleet-wide via the mise manifest here.
The tell that a script is a project: it has its own tests in `tests/`.

1. **Git worktree suite → trunkyard** — DONE. Extracted to
   github.com/aurokin/trunkyard (public, v0.1.0; dev copy
   `~/code/trunkyard`): one CLI (`trunkyard status|pull|new`),
   mise-installed via a pinned tarball release (bump the pin in
   mise config when cutting a release). Two audit rounds + soak
   passed; scripts, integration test, and docs/git-worktrees.md
   deleted from this repo. (wtct/wtrt live in twigsmux.)
2. **twigsmux** — DONE. Extracted to github.com/aurokin/twigsmux
   (public, tagged v1, pinned in .tmux.conf; dev copy `~/code/twigsmux`).
   Audit + runtime gate + koopa soak passed; script/test copies deleted
   from this repo. Note: `tmux-popup.sh` stays here (agentscan/tprompt
   binds use it) and has a byte-identical vendored twin in the plugin.
3. **super-claude** + `super-claude-menu` (389 lines, two test files).
   Client for a network service with its own state dir (`~/.super-claude`);
   actively evolving, so separate versioning pays off.

## Doesn't belong in dotfiles

- ComfyUI scripts (`dot_scripts/comfyui_install.sh`, `scripts/comfyui.sh`,
  `scripts/comfyui-install.sh`) and `dot_scripts/portless_service_install.sh`
  — app/service deployment, not environment config. Move next to infra
  docs or a machine-provisioning repo.

## On-host configs missing from dotfiles

- `~/.config/tprompt/prompts/` — blocked on a tprompt feature: need a
  lever to split which prompts sync publicly (this repo) vs privately
  (`~/.dotfiles-private` / work). File the feature request before moving.
- `~/.config/diffwarden/diffwarden.config.json` — deferred: it's a fluid,
  living config (skills toggled on/off on the live setup), so syncing a
  snapshot fights the workflow. Revisit if it settles.
