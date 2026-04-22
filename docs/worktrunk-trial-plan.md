# Worktrunk Trial Plan

## Goal

Evaluate whether `worktrunk` should become the long-term engine behind worktree creation in this repo, while keeping the current `gwt`/`gws`/`gwp` workflow working during the trial.

This is not a rip-and-replace plan. It is a staged comparison and migration plan.

## Recommendation

- Keep the current custom `gwt` for now.
- Keep `gws` and `gwp`.
- Trial `worktrunk` in parallel.
- If the trial goes well, replace most of the custom `gwt` implementation with a thin wrapper around `wt switch` instead of continuing to grow shell logic.

## Why Evaluate Worktrunk

The current custom workflow is powerful but expensive to maintain.

Current scope:

- [`zsh/.zshrc.d/scripts/git-new-worktree.sh`](/Users/auro/.dotfiles/zsh/.zshrc.d/scripts/git-new-worktree.sh)
- [`zsh/.zshrc.d/scripts/git-worktree-paths.sh`](/Users/auro/.dotfiles/zsh/.zshrc.d/scripts/git-worktree-paths.sh)
- [`zsh/.zshrc.d/scripts/git-workspace.sh`](/Users/auro/.dotfiles/zsh/.zshrc.d/scripts/git-workspace.sh)
- [`tests/git-worktree-integration.sh`](/Users/auro/.dotfiles/tests/git-worktree-integration.sh)

What `worktrunk` already provides out of the box:

- configurable worktree path templates
- remote-only branch switching
- existing worktree switching
- shell integration for `cd`
- hooks
- list/remove/merge/relocate/prune workflows

Useful references:

- https://worktrunk.dev/
- https://worktrunk.dev/config/
- https://worktrunk.dev/switch/
- https://worktrunk.dev/list/
- https://worktrunk.dev/step/
- https://github.com/max-sixty/worktrunk

## Current `gwt` vs `worktrunk`

### What maps cleanly

- Centralized path:
  - current: `~/worktrees/<project>/<branch-slug>`
  - `worktrunk`: `worktree-path = "~/worktrees/{{ repo }}/{{ branch | sanitize }}"`

- Existing local branch:
  - current: `gwt <branch>`
  - `worktrunk`: `wt switch <branch>`

- Remote-only branch:
  - current: `gwt <branch>`
  - `worktrunk`: `wt switch <branch>`

### What does not match exactly

- New branch creation:
  - current: `gwt <branch>` auto-creates from the current branch when the branch does not exist
  - `worktrunk`: `wt switch --create --base=@ <branch>`

- Duplicate branch behavior:
  - current: hard-error if the branch is already checked out elsewhere
  - `worktrunk`: switches to the existing worktree

- Branch slug format:
  - current: `feature/login -> feature^login`
  - `worktrunk`: `feature/login -> feature-login`

- Workspace scanning:
  - current: `gws` / `gwp` scan arbitrary parent directories, with special handling for `~/worktrees`
  - `worktrunk`: repo-scoped `wt list`, not a replacement for `gws` / `gwp`

## Decision

Do not replace `gwt` with raw `wt switch` directly.

If we adopt `worktrunk`, the right shape is:

- keep `gws` / `gwp`
- keep current `gwt` during the trial
- later replace `gwt` with a small wrapper over `wt switch`

## Trial Configuration

Recommended user config:

```toml
# ~/.config/worktrunk/config.toml
worktree-path = "~/worktrees/{{ repo }}/{{ branch | sanitize }}"
```

Recommended setup:

1. Install `worktrunk`.
2. Install shell integration with `wt config shell install`.
3. Leave current aliases unchanged.
4. Add a temporary personal alias for direct testing, for example `wts='wt switch --no-cd'` or just use `wt` directly.

## Trial Workflow

Use `worktrunk` on a small number of repos first.

### Equivalent trial commands

- Existing local branch:
  - `gwt feature/foo`
  - `wt switch feature/foo`

- Remote-only branch:
  - `gwt release`
  - `wt switch release`

- New branch from current branch:
  - `gwt feature/foo`
  - `wt switch --create --base=@ feature/foo`

### Things to evaluate explicitly

- whether `feature-login` is acceptable in place of `feature^login`
- whether "switch to existing worktree" feels better than the current hard-error rule
- whether shell integration feels reliable enough to trust daily
- whether `wt list` adds enough value even though it does not replace `gws`
- whether hooks / relocate / prune reduce enough custom maintenance to justify the workflow shift

## Phase Plan

### Phase 1: Parallel trial

- Keep current scripts unchanged.
- Install and configure `worktrunk`.
- Use it on 1-2 repos for one week.
- Do not change `gwt`, `gws`, or `gwp` yet.

### Phase 2: Wrapper prototype

If the trial is positive, prototype a new `gwt` wrapper with this behavior:

- if branch exists locally: `wt switch <branch>`
- else if branch exists on exactly one remote: `wt switch <branch>`
- else: `wt switch --create --base=@ <branch>`

Important:

- this wrapper should be small
- do not port all current path and recovery logic into the wrapper
- let `worktrunk` own path creation and switching behavior

### Phase 3: Narrow the custom surface

Once the wrapper is stable:

- retire most of the custom logic in [`git-new-worktree.sh`](/Users/auro/.dotfiles/zsh/.zshrc.d/scripts/git-new-worktree.sh)
- remove worktree-path creation logic that `worktrunk` already handles
- keep only user-facing policy that still matters and is small enough to justify

### Phase 4: Re-evaluate `gws` / `gwp`

Keep `gws` / `gwp` unless there is a separate reason to replace them.

Right now `worktrunk` does not cover:

- scanning arbitrary parent directories
- your special `~/worktrees` direct-vs-nested view
- multi-repo pull behavior across a workspace root

## Exit Criteria

Move from trial to wrapper only if all of these are true:

- `worktrunk` feels stable in daily use
- the path format differences are acceptable
- the duplicate-branch behavior is acceptable or easy to wrap
- the new-branch-from-current flow is easy to express with a tiny wrapper
- it clearly reduces maintenance burden versus the current custom script

Stay on the current custom `gwt` if any of these remain unacceptable:

- branch path format must stay `^`-based
- hard-error semantics are required instead of switching
- `wt switch --create --base=@` feels too different from `gwt <branch>`
- `worktrunk` shell integration is unreliable in practice

## Immediate Next Step

Implement only the trial setup first:

1. install `worktrunk`
2. add the user config
3. test it on a small number of repos
4. keep debugging the current custom tool in parallel

This keeps the current workflow safe while giving a path out of long-term shell maintenance.
