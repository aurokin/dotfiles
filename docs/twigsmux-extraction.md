# twigsmux Extraction: Final Recommended Packaging Shape

## Chosen Shape

**Winner: Proposal 2 — "self-locating TPM plugin: functions stay functions, the plugin bootstraps its own popup environment."** Two of three judges ranked it first; the dissenting judge's winner (P3) explicitly drops interactive cd-on-create, which is a muscle-memory break with no compensating benefit. P2 wins on the decisive axis: **it changes nothing about interactive behavior** — wtct/wtrt remain sourced zsh functions with untouched bodies, so migration risk to the daily workflow is near zero — while still killing `zsh -lic` on the popup side via an explicit, deterministic bootstrap (`run-fn.zsh`).

**Grafted from other proposals:**

- **From P3:** `lib/resolve-wt.zsh` as a single named wt-discovery helper (`command -v wt` → `$TWIGSMUX_WT` → brew dirs → mise shims → `~/.local/bin` → `mise which wt` → loud error; brew dirs added at build time because wt is brew-installed on the fleet, not mise) instead of inline logic in run-fn.zsh; and the property that **all seven keybinds live in `twigsmux.tmux`** so an uninstalled plugin means unbound keys, never dangling `run-shell` errors.
- **From P4:** pin the plugin — `set -g @plugin 'hsadler/twigsmux#v1'` — for rollback; the broken-zshrc smoke test as a migration gate; keep the popup-side call path CLI-shaped so a future mise-package extraction stays mechanical.
- **From P1:** the guarded one-line .zshrc integration (silent no-op on hosts where TPM hasn't fetched); document the fd-3 `TWIGSMUX_PRINT_CD` cd-relay protocol in the README as the *designated future path* if functions ever become executables — do not build it now.
- **From P2's own migration list (kept):** the `env -i` bare-environment test and the post-burn-in stow re-run to purge stale symlinks.

**Explicitly rejected:** server-start PATH capture (P1's `TWIGSMUX_PATH`) — snapshot-at-load goes stale across mise upgrades and fails far from its cause; call-time resolution via resolve-wt.zsh avoids the whole class. Also rejected: P4's reimplementation of worktree-path resolution via `wt list` (reimplements worktrunk's contract; wtct's `$PWD`-after-hook mechanism is verified working and stays verbatim).

## Final Repo File Tree

```
twigsmux/                          (TPM clones to ~/.tmux/plugins/twigsmux)
├── twigsmux.tmux                  # TPM entry: resolves CURRENT_DIR, reads @twigsmux-* options,
│                                  #   binds ALL of t/T/y, O, F6/S-F6/Y through vendored popup.sh
├── scripts/
│   ├── twigsmux.sh                # the switcher; self-locates via BASH_SOURCE, no ~/.zshrc.d paths
│   ├── tmux-workspace.sh          # scaffold/reorder
│   ├── tmux-kick.sh               # client detach picker
│   ├── tmux-pane-utils.sh         # sourced lib
│   └── tmux-popup.sh              # VENDORED copy (dotfiles keeps its own for tprompt/agentscan)
├── shell/
│   ├── init.zsh                   # interactive entry: TWIGSMUX_ROOT, sources functions/, twm alias
│   ├── run-fn.zsh                 # popup-side runner: bootstraps wt + worktrunk hook, sources init, "$@"
│   ├── resolve-wt.zsh             # wt discovery chain (grafted from P3/P4)
│   └── functions/
│       ├── wtct.zsh               # body unchanged except workspace path -> $TWIGSMUX_ROOT/scripts/
│       └── wtrt.zsh               # body unchanged
├── tests/
│   ├── twigsmux-unit.sh
│   ├── wtct-unit.zsh
│   └── wtrt-unit.zsh
└── README.md                      # documents fd-3 cd-protocol as future path, TWIGSMUX_WT escape hatch
```

## Shell Integration (exact dotfiles residue)

`zsh/.zshrc` — replaces the `twm` alias (line 105) and both wtct/wtrt source blocks (lines 160–166):

```zsh
[[ -f "$HOME/.tmux/plugins/twigsmux/shell/init.zsh" ]] && \
    source "$HOME/.tmux/plugins/twigsmux/shell/init.zsh"
```

`tmux/.tmux.conf` — replaces keybind lines 65–67, 84, 124–126, placed with the other `@plugin` lines:

```tmux
set -g @plugin 'hsadler/twigsmux#v1'
```

Everything else in dotfiles is untouched: `worktrunk.zsh`'s `eval "$(wt config shell init zsh)"` stays (init.zsh defers to it with a `(( ! $+functions[wt] ))` guard), `tmux-popup.sh` stays for tprompt/agentscan, gwt/gws stay.

`init.zsh` does exactly: (a) `TWIGSMUX_ROOT=${${(%):-%x}:A:h:h}`; (b) source `functions/wtct.zsh` + `functions/wtrt.zsh`; (c) `alias twm="$TWIGSMUX_ROOT/scripts/twigsmux.sh"`; (d) guarded worktrunk hook eval only when no `wt` function exists.

## Popup-Side Invocation Design

All three `zsh -lic 'wtct/wtrt ...'` sites in twigsmux.sh (lines 24, 642–651) become direct argv calls into the runner — no quoting relay, no login shell, no user rc files:

```
zsh "$PLUGIN_ROOT/shell/run-fn.zsh" wtct --branch "$branch" --select-window ai
zsh "$PLUGIN_ROOT/shell/run-fn.zsh" wtrt --cwd "$remove_cwd" --session "$selected" "$remove_target"
```

`run-fn.zsh` constructs exactly the two things `-lic` was smuggling in, explicitly:

1. **wt on PATH** — via `resolve-wt.zsh`: `command -v wt` → `$TWIGSMUX_WT` (dir of) → `~/.local/share/mise/shims` → `mise which wt` → fail loudly (surfaced by the existing sleep-3 stderr pattern in the popup).
2. **worktrunk cd hook** — `eval "$(wt config shell init zsh)"` so `wt switch --create` cd's the runner process and wtct's `start_dir="$PWD"` (wtct.zsh:61–62) keeps working verbatim.

Then it sources `init.zsh` and calls `"$@"`. Resolution is at call time, per invocation — nothing snapshotted at server start, so mise upgrades can't strand a stale path. The `--start-worktree-session` pane bootstrap becomes `run-fn.zsh wtct ...; exec zsh -i`, and the line-684 self-reference uses `$SCRIPT_DIR`.

## Config Surface

Ship **defaults-only day one** (per judge 2: the option surface in P1/P3 was speculative for a single-user fleet). Reserve and document, implement lazily:

- `@twigsmux-bindings on|off` (default on) — the only option worth shipping immediately, as the escape hatch for bind conflicts
- `TWIGSMUX_WT` env var — wt discovery escape hatch for exotic installs
- Future, add-when-needed: `@twigsmux-worktrees-dir`, per-key overrides

## Degradation Story

| State | Behavior |
|---|---|
| Plugin installed, .zshrc line absent | Full tmux fidelity: t/T switch, y create, ctrl-r remove, O scaffold, F6/Y kick — popup path never touches the user's zshrc. Missing only: interactive `wtct`/`wtrt`/`twm`. |
| .zshrc line present, plugin not TPM-installed | File-existence guard → silent no-op; zsh startup unaffected. |
| Plugin not installed at all | No twigsmux binds exist (all binds live in twigsmux.tmux) → keys fall back to tmux defaults; no broken run-shell references — strictly better than today. |
| `wt` missing/undiscoverable | Plain session switch/create/kill fully work; wtct/wtrt fail fast with the existing "wt is required" error in the popup. |
| Broken user ~/.zshrc | Popup path is immune (this is the point of killing `-lic`). |

## Migration Plan (smallest safe steps, soak points)

1. **Create the repo** with the tree above: move `twigsmux.sh`, `tmux-workspace.sh`, `tmux-kick.sh`, `tmux-pane-utils.sh` into `scripts/`, `wtct.zsh`/`wtrt.zsh` into `shell/functions/`, vendor `tmux-popup.sh`, port the three tests. Verify: all three test files pass with updated paths.
2. **Path surgery**: twigsmux.sh self-locates; replace the three `-lic` sites and the line-684 self-path; wtct.zsh:69 → `$TWIGSMUX_ROOT/scripts/tmux-workspace.sh`. Write `twigsmux.tmux`, `init.zsh`, `run-fn.zsh`, `resolve-wt.zsh`.
3. **Verification gate (mandatory, before touching dotfiles):**
   - `env -i HOME=$HOME PATH=/usr/bin:/bin TMUX=$TMUX zsh shell/run-fn.zsh wtct --branch test-branch` creates worktree + scaffold from a bare environment;
   - full create/remove round-trip from the popup **with a deliberately broken ~/.zshrc** — proves the `-lic` dependency is dead;
   - confirm `eval "$(wt config shell init zsh)"` behaves identically in non-interactive zsh (the one unverified assumption all judges flagged).
4. **Dotfiles PR** on one host only: add the pinned `@plugin` line, delete keybind lines 65–67/84/124–126, replace .zshrc lines 105/160–166 with the guarded source, delete the moved scripts. `prefix+I`, reload, smoke: t, T, y (including landing cd'd in the worktree), ctrl-r, O, F6, and interactive `wtct`/`wtrt`/`twm` in a fresh shell.
5. **Soak 3–7 days on that host.** This is the rollback point — reverting is one dotfiles commit.
6. **Fleet rollout**: push dotfiles; each host pulls + `prefix+I`. Confirm the mise-shims fallback on at least one Linux host.
7. **Cleanup after a week of fleet burn-in**: stow re-run to purge any stale `~/.zshrc.d/scripts` symlinks; tag `v1` if not already.

## Open Questions for the Owner

1. **GitHub org/name** — proposals used both `hsadler/twigsmux` and `auro/twigsmux`; pick one before writing the `@plugin` line.
2. **History preservation** — `git filter-repo` to carry history for the five moved files, or plain copy with a pointer commit in dotfiles? (Affects step 1 only.)
3. **Vendored popup.sh scope** — trim the plugin copy to only the geometry presets twigsmux uses, or keep it byte-identical to the dotfiles copy for easy diffing? Recommended: byte-identical, revisit if they diverge.
4. **`wt config shell init zsh` per-popup-call cost** — a few ms of subshell per invocation. Fine as designed; decide only if it ever registers as latency.
5. **Deletion timing** — delete dotfiles script copies in the same PR (step 4) or only after fleet rollout (step 7)? Recommended: same PR, since dotfiles and plugin install travel together per host; but if hosts pull dotfiles automatically before anyone runs `prefix+I`, defer deletion to step 7.

## One vs Two Packages: Honest Verdict

One package is correct, and not merely because the owner prefers it. The strongest two-package argument — a mise-pinned CLI available outside tmux — is empty in fact: wtct hard-requires `$TMUX` (wtct.zsh:37) and wtrt's entire value over bare `wt remove` is tmux session cleanup, so "usable in non-tmux contexts" describes software that doesn't exist. Meanwhile the switcher and the worktree tools share an implicit protocol (the `proj-branch-N` session-name convention appears in both wtct.zsh:54 and twigsmux.sh:75) that changes in lockstep — splitting repos manufactures a version-skew surface across it. The real benefits of the split (pinned versions, clean CLI/UX boundary, mechanical future extraction) are all purchasable inside one package: pin with `@plugin '...#v1'`, keep run-fn.zsh's call path argv-shaped, and if a genuine non-tmux consumer ever appears, `shell/functions/` + `run-fn.zsh` lifts into a mise package without a rewrite. Two packages today would buy a release pipeline and a compatibility matrix for a private five-file toolset with exactly one consumer.