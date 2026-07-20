# Cleanup backlog

Findings from a repo review (2026-07-19), updated as items resolve.

## Open follow-ups

- **Notify a Hermes agent** (they manage their own docs) that these
  `~/.hermes/internal/` maps look stale after the super-claude
  extraction: `workspace-repo-index.md`, `pending-setup.md`,
  `service-index.md`, and `coding-agent-provider-map.md` still say the
  repo lives at `~/workspace/super-claude` with no remote — it moved to
  `~/code/super-claude` and has a private remote
  (github.com/aurokin/super-claude); the client scripts also moved out
  of dotfiles into its `client/`.
- **tprompt prompts move**: blocked on Linear AUR-702 (public/private
  prompt-source split — mechanics exist via subdir recursion +
  additional_prompts_dirs; issue asks to bless/document the workflow
  and name both paths in collision errors). Move the prompts once it
  lands.
- **pass-cli session staleness**: 5 of 7 hosts had silently expired
  sessions within days of bootstrap (2026-07-19 rollout). If it
  persists, consider auto-running `secrets-bootstrap` on session
  failure in the launcher or `secrets.zsh`.

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
3. **super-claude** — DONE. Never public (client is inseparable from a
   private gateway); folded into github.com/aurokin/super-claude
   (private, `~/code/super-claude`, `client/`) alongside the gateway
   deployment. Audit + live gateway checks + koopa soak passed; scripts
   and tests deleted from this repo, aliases repoint to the clone.
   `lcc.sh` stays here (env-var coupling only). Decision doc in that
   repo's `docs/`.

## Doesn't belong in dotfiles

- ComfyUI scripts — DELETED (one-time setup, recreatable; decided
  2026-07-19).
- `dot_scripts/portless_service_install.sh` — STAYS (dotfiles is the one
  folder on every host). It's the only service-install script, so no
  subdirectory reorg yet; revisit if a second one appears.

## On-host configs missing from dotfiles

(Deferred as a group: revisit once the extraction work is finished.)

- `~/.config/tprompt/prompts/` — feature request filed (Linear AUR-702);
  move the prompts once the split workflow lands.
- `~/.config/diffwarden/diffwarden.config.json` — HANDLED (2026-07-19):
  fieldmap + intent added to dotfiles-private (portable keys sync;
  reviewer catalog stays host-owned because entries embed per-host
  enabled toggles and droid machineId). Native overlay split requested
  as Linear AUR-703; revisit the fieldmap when it lands.
