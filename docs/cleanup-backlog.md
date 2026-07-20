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

1. **Git worktree suite** (~2,900 lines): `git-workspace.sh`,
   `git-new-worktree.sh`, `git-worktree-paths.sh`, `wtct.zsh`, `wtrt.zsh`,
   plus `docs/git-worktrees.md` and three test files. Largest and
   cleanest-bounded — extract first.
2. **twigsmux** — SOAKING ON KOOPA. Extracted as a TPM plugin
   (github.com/aurokin/twigsmux, private; dev copy `~/code/twigsmux`);
   full audit + runtime gate passed; koopa flipped to the plugin
   (SSH-form @plugin line while private). Script copies stay here until
   soak completes. Remaining: soak 3-7 days -> fleet rollout (verify
   linuxbrew wt on one Linux host) -> tag v1, pin @plugin, switch the
   line to 'aurokin/twigsmux', make repo public, copy design doc into
   the plugin's docs/, then delete the script/test copies here.
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
