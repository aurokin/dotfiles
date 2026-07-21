# Cleanup backlog

Findings from a repo review (2026-07-19), updated as items resolve.

## Open follow-ups

- **tprompt prompts move**: DONE (2026-07-20, tprompt v0.7.0 / AUR-702).
  `tprompt/` stow package (config.toml + 3 public prompts) active
  fleet-wide; `~/.dotfiles-private/tprompt/prompts/` is the (empty)
  private overlay source. mise pins v0.7.0 (minimum_release_age).
  Gotcha for dev sessions: the tmux popup resolves tprompt via
  resolve-bin.sh, which prefers dogfood copies in ~/.cargo/bin and
  ~/.local/bin over the mise shim — run `make undogfood` in
  ~/code/tprompt when done, or the popup pins to the last dev build
  (a stale v0.5.1 copy shadowed v0.7.0 on koopa at activation).
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
- `~/.config/diffwarden/diffwarden.config.json` — DONE (2026-07-21,
  diffwarden v0.5.0 / AUR-703): base+overlay split fleet-wide. The base
  config is fully portable (whole reviewer catalog, droid machineId
  stripped) and synced via the dotfiles-private fieldmap; each host's
  `diffwarden.config.local.json` overlay carries only droid-sdk's
  machineId (plus any future per-host enabled overrides) and is never
  synced. Identical base sha256 on all 6 hosts is the drift detector
  (`diffwarden doctor` shows overlay identity). haste was unreachable
  (dual-boot) — apply the same split there when it's next up.
