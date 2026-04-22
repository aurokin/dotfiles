# Worktree Migration Plan

## Goal

Move the repo's worktree workflow to a centralized layout under `~/worktrees` and remove the old repo-local container model.

Target layout:

- `~/worktrees/{project-name}/{branch-name}`
- Branch path uses the existing slug rule: `/` becomes `^`

Example:

- `~/code/devlane` -> `~/worktrees/devlane/feature^login`

## Final Command Model

- `gwt` is the primary and only worktree creation command.
- `gwt` becomes strict: `gwt <branch>` only.
- `gsw` is removed completely.
- `gwt` is assumed to be run from inside a checkout of the target repo.

## `gwt` Behavior

### Branch resolution

- If the branch exists locally, use it.
- If the branch does not exist locally:
  - Check remotes only in this case.
  - Preferred remote order:
    - the remote configured for the current branch
    - `origin`
    - all other remotes
  - If exactly one remote has the branch, use it and configure upstream tracking.
  - If more than one remote has the branch, fail and tell the user to create the local branch manually first.
  - If no remote has the branch, create it from the current branch in the current checkout.

### Where it can run

- `gwt` can run from any checkout of the repo, including linked worktrees.
- Detached HEAD is rejected.
- Dirty working trees are allowed.

### Path rules

- Destination is always `~/worktrees/{project-name}/{branch-slug}`.
- `~/worktrees` and `~/worktrees/{project-name}` are created automatically if needed.
- `{project-name}` is derived from repo context, not blindly from the current directory basename.
- Canonical path resolution is required before path checks.

### Project name derivation

- If the current checkout is already under `~/worktrees/{project}/{branch}`, use `{project}`.
- Otherwise, if running from an arbitrary linked worktree outside `~/worktrees`, derive `{project}` from the repo's main checkout basename.
- Otherwise, use the current repo root basename.

### Rejections and collisions

- If the target branch is already checked out in the current checkout, fail.
- If the target branch is already checked out in another worktree, fail.
- If Git thinks the branch is checked out elsewhere but that path no longer exists, fail and suggest `git worktree prune`.
- If the destination path already exists on disk, fail.
- If `~/worktrees/{project}` is itself a git repo, fail instead of creating nested worktrees inside it.
- Detect slug collisions caused by `/ -> ^` and fail clearly.

### Cleanup guidance

- Human-facing paths may use `~/...` for readability.
- Copy-pastable cleanup commands must use absolute paths.
- If an existing conflicting checkout is a registered worktree and still exists:
  - print `git worktree remove /abs/path`
- If Git still has a stale registration for a missing path:
  - print `git worktree prune`
- If the destination path is just an occupied filesystem path and not a registered worktree:
  - print `rm -rf /abs/path`

### Success output

- On success, print only the final path.
- Success path should use `~/worktrees/...` form.

## Shared Helper

Add a shared shell helper for the standardized worktree path logic:

- canonical repo root resolution
- project-name derivation
- branch slugging
- destination path building
- detection of direct repos at `~/worktrees/{project}`

`gwt` and any future tooling should use the same helper instead of re-implementing these rules.

## `gws` / `gwp` Behavior

### General scanning

- Outside `~/worktrees`, scan only one level deep.
- Remove all `.git-worktree-container` behavior.
- Anything related to `.git-worktree-container` is deleted.

### Special handling for `~/worktrees`

When the resolved base path is exactly `$HOME/worktrees`:

- scan direct repos at `~/worktrees/{project}`
- scan nested repos at `~/worktrees/{project}/{branch}`
- do not scan deeper than two levels

### `gws ~/worktrees` output

Print two separate tables:

- `Direct Repos`
- `Nested Worktrees`

Rules:

- omit empty sections
- keep one combined summary line at the end
- section split is presentation only

### `gwp ~/worktrees`

- Use the same ordering as `gws ~/worktrees`
- Process direct repos first, then nested worktrees
- Path-sorted within each category

## Compatibility / Removal

- Remove `gsw` from aliases, docs, tests, and scripts.
- Delete `git-setup-worktree.sh`.
- Stop creating `.git-worktree-container`.
- Stop discovering `.git-worktree-container` layouts.

## Test Plan

Delete the old `gsw`-centric integration coverage and replace it with `gwt`-centric coverage for:

- existing local branch creates `~/worktrees/{project}/{branch}`
- remote-only branch creates a tracked worktree
- missing branch is created from the current branch
- branch already checked out elsewhere prints the correct cleanup guidance
- stale registered worktree path prints `git worktree prune`
- current checkout already on the target branch fails without worktree-removal guidance
- occupied destination path prints the correct cleanup guidance
- slug collision detection
- rejection when `~/worktrees/{project}` is itself a git repo
- `gws ~/worktrees` shows `Direct Repos` and `Nested Worktrees`
- `gwp ~/worktrees` follows the same ordering

## Implementation Order

1. Add the shared helper for centralized worktree path logic.
2. Rewrite `git-new-worktree.sh` around the new strict `gwt <branch>` flow.
3. Remove `gsw` alias and delete `git-setup-worktree.sh`.
4. Update `git-workspace.sh` for one-level general scanning and the special `~/worktrees` two-level view.
5. Rewrite integration tests around the new behavior.
6. Update `README.md` and any usage/help text.
