#!/usr/bin/env bash
set -euo pipefail

script_name="$(basename "$0")"
readonly CONTAINER_MARKER_NAME=".git-worktree-container"
resolved_remote_ref=""

usage() {
  cat <<EOF
Usage:
  $script_name <project-path> <branch>

Examples:
  $script_name dropserve master
  $script_name code/dropserve master
  $script_name ~/code/dropserve master

Behavior:
  - Resolves <project-path> from the current directory or as an absolute path.
  - Requires <project-path> to point at a plain git checkout (not an existing linked worktree).
  - Switches the checkout to <branch> first, resolving it from a local branch or a live remote branch.
  - Reshapes the repo so:
      /parent/project        -> /parent/project/<branch>
    while keeping /parent/project as the new worktree container directory.
EOF
}

die() {
  echo "$script_name: $*" >&2
  exit 1
}

local_branch_exists() {
  local repo="$1"
  local branch_name="$2"
  git -C "$repo" show-ref --verify --quiet "refs/heads/$branch_name"
}

remote_exists() {
  local repo="$1"
  local remote_name="$2"
  [[ -n "$remote_name" ]] || return 1
  git -C "$repo" remote get-url "$remote_name" >/dev/null 2>&1
}

ensure_remote_fetch_refspec() {
  local repo="$1"
  local remote_name="$2"
  local branch_name="$3"
  local fetch_refspec="+refs/heads/$branch_name:refs/remotes/$remote_name/$branch_name"
  local configured_refspec=""

  while IFS= read -r configured_refspec; do
    [[ "$configured_refspec" == "$fetch_refspec" ]] && return 10
  done < <(git -C "$repo" config --get-all "remote.$remote_name.fetch" 2>/dev/null || true)

  git -C "$repo" config --add "remote.$remote_name.fetch" "$fetch_refspec"
  return 0
}

append_remote_if_present() {
  local repo="$1"
  local remote_name="$2"
  [[ -n "$remote_name" ]] || return 0
  remote_exists "$repo" "$remote_name" || return 0

  local existing=""
  for existing in "${candidate_remotes[@]}"; do
    [[ "$existing" == "$remote_name" ]] && return 0
  done

  candidate_remotes+=("$remote_name")
}

resolve_remote_branch() {
  local repo="$1"
  local current_branch_name="$2"
  local branch_name="$3"
  local status=0

  resolved_remote_ref=""
  resolve_remote_branch_if_unique "$repo" "$current_branch_name" "$branch_name" || status=$?
  return "$status"
}

resolve_remote_branch_if_unique() {
  local repo="$1"
  local current_branch_name="$2"
  local branch_name="$3"
  local preferred_remote=""
  local remote_name=""
  local -a candidate_remotes=()
  local -a matches=()

  resolved_remote_ref=""
  preferred_remote="$(git -C "$repo" config --get "branch.$current_branch_name.remote" 2>/dev/null || true)"
  append_remote_if_present "$repo" "$preferred_remote"
  append_remote_if_present "$repo" origin

  while IFS= read -r remote_name; do
    [[ -n "$remote_name" ]] || continue
    append_remote_if_present "$repo" "$remote_name"
  done < <(git -C "$repo" remote)

  for remote_name in "${candidate_remotes[@]}"; do
    git -C "$repo" ls-remote --exit-code --heads "$remote_name" "refs/heads/$branch_name" >/dev/null 2>&1 || continue
    matches+=("$remote_name")
  done

  if (( ${#matches[@]} == 1 )); then
    track_fetched_remote_tracking_ref "$repo" "${matches[0]}" "$branch_name"
    git -C "$repo" fetch --no-tags "${matches[0]}" "refs/heads/$branch_name:refs/remotes/${matches[0]}/$branch_name"
    resolved_remote_ref="${matches[0]}/$branch_name"
    return 0
  fi

  if (( ${#matches[@]} > 1 )); then
    return 2
  fi

  return 1
}

slugify_branch() {
  local value="$1"
  value="${value//\//^}"
  printf '%s\n' "$value"
}

abs_dir() {
  (
    cd "$1" 2>/dev/null
    pwd -P
  )
}

cleanup_needed=0
root=""
temp_path=""
container_path=""
final_path=""
original_branch=""
branch_changed=0
target_branch_created=0
added_fetch_remote=""
added_fetch_branch=""
tracked_fetch_remote=""
tracked_fetch_branch=""
fetched_remote_tracking_ref_remote=""
fetched_remote_tracking_ref_branch=""
branch_tracking_config_recorded=0
branch_tracking_config_changed=0
original_branch_tracking_remote=""
original_branch_tracking_remote_present=0
original_branch_tracking_merge=""
original_branch_tracking_merge_present=0

track_fetch_refspec_addition() {
  added_fetch_remote="$1"
  added_fetch_branch="$2"
}

track_fetched_remote_tracking_ref() {
  local repo="$1"
  local remote_name="$2"
  local branch_name="$3"

  git -C "$repo" show-ref --verify --quiet "refs/remotes/$remote_name/$branch_name" && return 0

  fetched_remote_tracking_ref_remote="$remote_name"
  fetched_remote_tracking_ref_branch="$branch_name"
}

record_branch_tracking_config() {
  local repo="$1"
  local branch_name="$2"

  if ((branch_tracking_config_recorded)); then
    return 0
  fi

  original_branch_tracking_remote="$(git -C "$repo" config --get "branch.$branch_name.remote" 2>/dev/null || true)"
  if git -C "$repo" config --get "branch.$branch_name.remote" >/dev/null 2>&1; then
    original_branch_tracking_remote_present=1
  fi

  original_branch_tracking_merge="$(git -C "$repo" config --get "branch.$branch_name.merge" 2>/dev/null || true)"
  if git -C "$repo" config --get "branch.$branch_name.merge" >/dev/null 2>&1; then
    original_branch_tracking_merge_present=1
  fi

  branch_tracking_config_recorded=1
}

set_branch_tracking_config() {
  local repo="$1"
  local branch_name="$2"
  local remote_name="$3"
  local branch_merge_name="$4"

  record_branch_tracking_config "$repo" "$branch_name"
  git -C "$repo" config "branch.$branch_name.remote" "$remote_name"
  git -C "$repo" config "branch.$branch_name.merge" "refs/heads/$branch_merge_name"
  branch_tracking_config_changed=1
}

rollback() {
  local exit_code=$?
  if ((cleanup_needed == 0)); then
    exit "$exit_code"
  fi

  set +e

  if [[ -n "$container_path" ]]; then
    rm -f "$container_path/$CONTAINER_MARKER_NAME" >/dev/null 2>&1 || true
  fi

  if [[ -n "$final_path" && -d "$final_path" && -n "$temp_path" && ! -e "$temp_path" ]]; then
    mv -- "$final_path" "$temp_path" >/dev/null 2>&1 || true
  fi

  if [[ -n "$container_path" && -d "$container_path" && -z "$(find "$container_path" -mindepth 1 -maxdepth 1 2>/dev/null)" ]]; then
    rmdir "$container_path" >/dev/null 2>&1 || true
  fi

  if [[ -n "$temp_path" && -d "$temp_path" ]]; then
    if [[ -n "$root" && ! -e "$root" ]]; then
      mv -- "$temp_path" "$root" >/dev/null 2>&1 || true
    fi
  fi

  local rollback_repo=""
  local candidate=""
  for candidate in "$root" "$temp_path" "$final_path"; do
    [[ -n "$candidate" ]] || continue
    if git -C "$candidate" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      rollback_repo="$candidate"
      break
    fi
  done

  if ((branch_changed)) && [[ -n "$original_branch" && -n "$rollback_repo" ]]; then
    git -C "$rollback_repo" switch "$original_branch" >/dev/null 2>&1 || true

    if ((target_branch_created)); then
      local rollback_head=""
      rollback_head="$(git -C "$rollback_repo" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
      if [[ "$rollback_head" != "$branch" ]]; then
        git -C "$rollback_repo" branch -D "$branch" >/dev/null 2>&1 || true
      fi
    fi
  fi

  if ((branch_tracking_config_changed)) && [[ -n "$rollback_repo" ]]; then
    git -C "$rollback_repo" config --unset-all "branch.$branch.remote" >/dev/null 2>&1 || true
    git -C "$rollback_repo" config --unset-all "branch.$branch.merge" >/dev/null 2>&1 || true

    if ((original_branch_tracking_remote_present)); then
      git -C "$rollback_repo" config "branch.$branch.remote" "$original_branch_tracking_remote" >/dev/null 2>&1 || true
    fi

    if ((original_branch_tracking_merge_present)); then
      git -C "$rollback_repo" config "branch.$branch.merge" "$original_branch_tracking_merge" >/dev/null 2>&1 || true
    fi
  fi

  if [[ -n "$added_fetch_remote" && -n "$added_fetch_branch" && -n "$rollback_repo" ]]; then
    local fetch_refspec="+refs/heads/$added_fetch_branch:refs/remotes/$added_fetch_remote/$added_fetch_branch"
    git -C "$rollback_repo" config --unset-all "remote.$added_fetch_remote.fetch" "$fetch_refspec" >/dev/null 2>&1 || true
  fi

  if [[ -n "$fetched_remote_tracking_ref_remote" && -n "$fetched_remote_tracking_ref_branch" && -n "$rollback_repo" ]]; then
    git -C "$rollback_repo" update-ref -d \
      "refs/remotes/$fetched_remote_tracking_ref_remote/$fetched_remote_tracking_ref_branch" >/dev/null 2>&1 || true
  fi

  exit "$exit_code"
}

trap rollback EXIT

if [[ "${1-}" == "-h" || "${1-}" == "--help" ]]; then
  usage
  exit 0
fi

[[ $# -eq 2 ]] || {
  usage >&2
  exit 2
}

project_input="$1"
branch="$2"

if ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then
  die "invalid branch name: $branch"
fi

if ! root="$(git -C "$project_input" rev-parse --show-toplevel 2>/dev/null)"; then
  die "not inside a git repository: $project_input"
fi
root="$(abs_dir "$root")"

parent_of_root="$(dirname "$root")"
if [[ -f "$parent_of_root/$CONTAINER_MARKER_NAME" ]]; then
  die "repo is already inside worktree container: $parent_of_root"
fi

git_common_dir="$(git -C "$root" rev-parse --git-common-dir 2>/dev/null || true)"
if [[ "$git_common_dir" != ".git" ]]; then
  die "expected a plain checkout at $root; linked worktrees are not supported"
fi

worktree_count="$(git -C "$root" worktree list --porcelain 2>/dev/null | awk '$1 == "worktree" { count++ } END { print count + 0 }')"
if ((worktree_count > 1)); then
  die "repo already has linked worktrees; refusing to move the main checkout"
fi

current_branch="$(git -C "$root" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ -z "$current_branch" ]]; then
  die "detached HEAD is not supported; check out a branch first"
fi
original_branch="$current_branch"

if [[ "$current_branch" != "$branch" ]]; then
  if local_branch_exists "$root" "$branch"; then
    git -C "$root" switch "$branch"
    branch_changed=1
  else
    remote_status=0
    resolve_remote_branch "$root" "$current_branch" "$branch" || remote_status=$?
    if (( remote_status == 0 )); then
      remote_name="${resolved_remote_ref%%/*}"
      remote_branch_name="${resolved_remote_ref#*/}"
      git -C "$root" switch -c "$branch" "refs/remotes/$resolved_remote_ref"
      git -C "$root" config "branch.$branch.remote" "$remote_name"
      git -C "$root" config "branch.$branch.merge" "refs/heads/$remote_branch_name"
      branch_changed=1
      target_branch_created=1
    elif (( remote_status == 2 )); then
      die "branch $branch exists on multiple remotes; create the local branch manually first"
    else
      die "branch $branch not found locally or on any remote"
    fi
  fi
fi

tracked_fetch_remote="$(git -C "$root" config --get "branch.$branch.remote" 2>/dev/null || true)"
tracked_fetch_branch="$(git -C "$root" config --get "branch.$branch.merge" 2>/dev/null || true)"
if [[ -n "$tracked_fetch_remote" && "$tracked_fetch_remote" != "." && "$tracked_fetch_branch" == refs/heads/* ]] \
  && remote_exists "$root" "$tracked_fetch_remote"; then
  tracked_fetch_branch="${tracked_fetch_branch#refs/heads/}"
else
  tracked_fetch_remote=""
  tracked_fetch_branch=""

  remote_status=0
  resolve_remote_branch_if_unique "$root" "$branch" "$branch" || remote_status=$?
  if (( remote_status == 0 )); then
    tracked_fetch_remote="${resolved_remote_ref%%/*}"
    tracked_fetch_branch="${resolved_remote_ref#*/}"
    set_branch_tracking_config "$root" "$branch" "$tracked_fetch_remote" "$tracked_fetch_branch"
  fi
fi

branch_slug="$(slugify_branch "$branch")"
parent_path="$(dirname "$root")"
project_name="$(basename "$root")"
container_path="$parent_path/$project_name"
final_path="$container_path/$branch_slug"
temp_path="$parent_path/.${project_name}.gsw-tmp.$$"

[[ ! -e "$temp_path" ]] || die "temporary path already exists: $temp_path"

cleanup_needed=1

mv -- "$root" "$temp_path"
mkdir -- "$container_path"
[[ ! -e "$final_path" ]] || die "destination already exists: $final_path"
mv -- "$temp_path" "$final_path"
: >"$container_path/$CONTAINER_MARKER_NAME"

if [[ -n "$tracked_fetch_remote" && -n "$tracked_fetch_branch" ]]; then
  if ensure_remote_fetch_refspec "$final_path" "$tracked_fetch_remote" "$tracked_fetch_branch"; then
    track_fetch_refspec_addition "$tracked_fetch_remote" "$tracked_fetch_branch"
  else
    rc=$?
    [[ "$rc" == "10" ]] || exit "$rc"
  fi
fi

cleanup_needed=0

cat <<EOF
Project worktree layout created:
  container: $container_path
  primary:   $final_path

Next:
  cd "$final_path"
  gwt <feature-branch>
EOF
