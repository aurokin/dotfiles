#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

script_name="$(basename "$0")"

# Temp directories to clean up on exit.
CLEANUP_DIRS=()

cleanup() {
  set +e
  local d
  for d in "${CLEANUP_DIRS[@]}"; do
    [[ -n "$d" ]] || continue
    rm -rf "$d" >/dev/null 2>&1 || true
  done
}

trap cleanup EXIT

usage() {
  cat <<EOF
Usage:
  $script_name status [path] [--no-fetch] [--jobs N]
  $script_name pull [path] [--include-dirty] [--no-ff-only] [--no-fetch] [--jobs N] [--ttl N] [--force-fetch] [--] [git pull args...]

Environment:
  GIT_WORKSPACE_JOBS  Default for --jobs (default: min(CPU, 8))
  GIT_WORKSPACE_CACHE_DIR  Cache dir (default: $XDG_CACHE_HOME/git-workspace or ~/.cache/git-workspace)
  GIT_WORKSPACE_FETCH_TTL_SECONDS  Treat remote as fresh for N seconds after a successful fetch (default: 120)

Scans:
  - <path> (default: .)
  - each immediate subdirectory (depth 1)
  - if a directory is a linked checkout (.git is a file; worktree/submodule),
    also scans its immediate subdirectories (one extra level)

Status report includes:
  - ahead/behind vs upstream (or origin/<branch> fallback)
  - working tree counts: w (unstaged), s (staged), u (untracked), c (conflicts)

Examples:
  $script_name status
  $script_name status ~/code --no-fetch
  $script_name status ~/code --jobs 8
  $script_name pull ~/code
  $script_name pull --include-dirty -- --rebase
  $script_name pull --no-fetch   # fast (assumes you've already fetched, e.g. via status)
  $script_name pull --ttl 0      # disable fetch cache shortcut
EOF
}

die() {
  echo "$script_name: $*" >&2
  exit 1
}

abs_dir() {
  (
    cd "$1" 2>/dev/null
    pwd -P
  )
}

relpath() {
  local base_abs="$1"
  local target_abs="$2"
  if [[ "$target_abs" == "$base_abs" ]]; then
    printf '%s' '.'
  elif [[ "$target_abs" == "$base_abs/"* ]]; then
    printf '%s' "${target_abs#"$base_abs"/}"
  else
    printf '%s' "$target_abs"
  fi
}

has_git_marker() {
  [[ -d "$1/.git" || -f "$1/.git" ]]
}

is_git_repo_root() {
  has_git_marker "$1" || return 1
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

is_linked_checkout() {
  [[ -f "$1/.git" ]] || return 1
  grep -q '^gitdir: ' "$1/.git" 2>/dev/null
}

git_remote_exists() {
  local repo="$1"
  local remote="$2"
  git -C "$repo" remote get-url "$remote" >/dev/null 2>&1
}

# Globals filled by collect_porcelain()
POR_BRANCH_HEAD=""
POR_BRANCH_OID=""
POR_UPSTREAM=""
POR_AB_AHEAD=""
POR_AB_BEHIND=""
POR_STAGED=0
POR_UNSTAGED=0
POR_UNTRACKED=0
POR_CONFLICTS=0

collect_porcelain() {
  local repo="$1"
  local out
  out="$(git -C "$repo" status --porcelain=2 -b 2>/dev/null)" || return 1

  local branch_head=""
  local branch_oid=""
  local upstream=""
  local ab_ahead=""
  local ab_behind=""
  local staged=0
  local unstaged=0
  local untracked=0
  local conflicts=0

  local ab=""
  local xy=""
  local x=""
  local y=""
  local line=""
  while IFS= read -r line; do
    case "$line" in
      "# branch.head "*)
        branch_head="${line#"# branch.head "}"
        ;;
      "# branch.oid "*)
        branch_oid="${line#"# branch.oid "}"
        ;;
      "# branch.upstream "*)
        upstream="${line#"# branch.upstream "}"
        ;;
      "# branch.ab "*)
        # Example: "# branch.ab +2 -10" (ahead, behind)
        ab="${line#"# branch.ab "}"
        ab_ahead="${ab%% *}"
        ab_behind="${ab#* }"
        ab_ahead="${ab_ahead#+}"
        ab_behind="${ab_behind#-}"
        ;;
      "? "*)
        ((++untracked))
        ;;
      "u "*)
        ((++conflicts))
        ;;
      "1 "*|"2 "*)
        xy="${line:2:2}"
        x="${xy:0:1}"
        y="${xy:1:1}"
        [[ "$x" != "." ]] && ((++staged))
        [[ "$y" != "." ]] && ((++unstaged))
        ;;
      *)
        :
        ;;
    esac
  done <<<"$out"

  POR_BRANCH_HEAD="$branch_head"
  POR_BRANCH_OID="$branch_oid"
  POR_UPSTREAM="$upstream"
  POR_AB_AHEAD="$ab_ahead"
  POR_AB_BEHIND="$ab_behind"
  POR_STAGED="$staged"
  POR_UNSTAGED="$unstaged"
  POR_UNTRACKED="$untracked"
  POR_CONFLICTS="$conflicts"
}

compare_ref_for_repo() {
  local repo="$1"
  local branch_head="$2"
  local upstream="$3"

  if [[ -n "$upstream" ]]; then
    printf '%s' "$upstream"
    return 0
  fi

  if [[ -z "$branch_head" || "$branch_head" == "(detached)" ]]; then
    return 1
  fi

  if ! git_remote_exists "$repo" origin; then
    return 1
  fi

  if git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$branch_head" 2>/dev/null; then
    printf '%s' "origin/$branch_head"
    return 0
  fi

  return 1
}

fetch_remote_for_repo() {
  local repo="$1"
  local upstream="$2"

  if [[ -n "$upstream" ]]; then
    printf '%s' "${upstream%%/*}"
    return 0
  fi

  if git_remote_exists "$repo" origin; then
    printf '%s' "origin"
    return 0
  fi

  return 1
}

mktemp_dir() {
  local d
  d="$(mktemp -d 2>/dev/null)" && { printf '%s' "$d"; return 0; }
  d="$(mktemp -d -t git-workspace 2>/dev/null)" && { printf '%s' "$d"; return 0; }
  return 1
}

cache_root() {
  if [[ -n "${GIT_WORKSPACE_CACHE_DIR:-}" ]]; then
    printf '%s' "$GIT_WORKSPACE_CACHE_DIR"
    return 0
  fi
  local root="${XDG_CACHE_HOME:-$HOME/.cache}"
  printf '%s' "$root/git-workspace"
}

cache_key() {
  local s="$1"
  local out=""
  if command -v sha1sum >/dev/null 2>&1; then
    out="$(printf '%s' "$s" | sha1sum 2>/dev/null || true)"
    printf '%s' "${out%% *}"
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    out="$(printf '%s' "$s" | shasum -a 1 2>/dev/null || true)"
    printf '%s' "${out%% *}"
    return 0
  fi
  if command -v md5sum >/dev/null 2>&1; then
    out="$(printf '%s' "$s" | md5sum 2>/dev/null || true)"
    printf '%s' "${out%% *}"
    return 0
  fi

  # Fallback: checksum + length.
  out="$(printf '%s' "$s" | cksum 2>/dev/null || true)"
  local crc="${out%% *}"
  local rest="${out#* }"
  local len="${rest%% *}"
  printf '%s_%s' "$crc" "$len"
}

cache_fetch_file() {
  local repo_abs="$1"
  local dir
  dir="$(cache_root)"
  printf '%s/fetch-%s.ts' "$dir" "$(cache_key "$repo_abs")"
}

cache_write_fetch_time() {
  local repo_abs="$1"
  local dir
  dir="$(cache_root)"
  mkdir -p "$dir" 2>/dev/null || return 1
  date +%s >"$(cache_fetch_file "$repo_abs")" 2>/dev/null || return 1
}

cache_read_fetch_time() {
  local repo_abs="$1"
  local f
  f="$(cache_fetch_file "$repo_abs")"
  [[ -f "$f" ]] || return 1
  local ts
  ts="$(<"$f")"
  [[ "$ts" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$ts"
}

cache_is_fresh() {
  local repo_abs="$1"
  local ttl="$2"
  [[ "$ttl" =~ ^[0-9]+$ ]] || return 1
  ((ttl > 0)) || return 1

  local last
  last="$(cache_read_fetch_time "$repo_abs" 2>/dev/null || true)"
  [[ -n "$last" ]] || return 1

  local now
  now="$(date +%s 2>/dev/null || true)"
  [[ "$now" =~ ^[0-9]+$ ]] || return 1

  local age=$((now - last))
  if ((age < 0)); then
    return 0
  fi
  ((age <= ttl))
}

cpu_count() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
    return 0
  fi
  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.ncpu 2>/dev/null && return 0
  fi
  echo 4
}

default_jobs() {
  local from_env="${GIT_WORKSPACE_JOBS:-}"
  if [[ -n "$from_env" ]]; then
    printf '%s' "$from_env"
    return 0
  fi
  local n
  n="$(cpu_count)"
  # Cap default concurrency so we don't melt the network.
  if [[ "$n" =~ ^[0-9]+$ ]] && ((n > 8)); then
    n=8
  fi
  if [[ ! "$n" =~ ^[0-9]+$ ]] || ((n < 1)); then
    n=4
  fi
  printf '%s' "$n"
}

supports_wait_n() {
  # wait -n exists in bash >= 4.3
  local major="${BASH_VERSINFO[0]:-0}"
  local minor="${BASH_VERSINFO[1]:-0}"
  ((major > 4)) || { ((major == 4)) && ((minor >= 3)); }
}

status_row_tsv() {
  local repo="$1"
  local fetch_enabled="$2"

  if ! collect_porcelain "$repo"; then
    local display_path
    display_path="$(relpath "$BASE_ABS" "$repo")"
    printf '%s\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\n' \
      "$display_path" "" "" "status-error" "" 0 0 0 0
    return 0
  fi

  local fetch_remote=""
  fetch_remote="$(fetch_remote_for_repo "$repo" "$POR_UPSTREAM" 2>/dev/null || true)"
  local fetch_status=""
  if ((fetch_enabled)) && [[ -n "$fetch_remote" ]]; then
    # These defaults avoid slow recursive submodule fetches and tag downloads.
    local err=""
    if ! err="$(git -C "$repo" fetch --prune --quiet --no-tags --recurse-submodules=no "$fetch_remote" 2>&1)"; then
      fetch_status="fetch-error"
    else
      cache_write_fetch_time "$repo" >/dev/null 2>&1 || true
      # Refresh branch.ab after fetch.
      collect_porcelain "$repo" >/dev/null 2>&1 || true
    fi
  fi

  local compare_ref=""
  compare_ref="$(compare_ref_for_repo "$repo" "$POR_BRANCH_HEAD" "$POR_UPSTREAM" 2>/dev/null || true)"

  local sync=""
  local behind_flag=0
  local no_upstream_flag=0
  local fetch_error_flag=0

  if [[ -n "$fetch_status" ]]; then
    sync="$fetch_status"
    fetch_error_flag=1
  elif [[ -z "$compare_ref" ]]; then
    sync="no-upstream"
    no_upstream_flag=1
  else
    local ahead=""
    local behind=""
    local ab=""

    if [[ -n "$POR_UPSTREAM" && "$compare_ref" == "$POR_UPSTREAM" && -n "$POR_AB_AHEAD" && -n "$POR_AB_BEHIND" ]]; then
      ahead="$POR_AB_AHEAD"
      behind="$POR_AB_BEHIND"
    else
      if ab="$(ahead_behind "$repo" "$compare_ref" 2>/dev/null)"; then
        ahead="${ab%%$'\t'*}"
        behind="${ab#*$'\t'}"
      else
        sync="sync-error"
      fi
    fi

    if [[ -z "$sync" ]]; then
      if [[ "$ahead" == "0" && "$behind" == "0" ]]; then
        sync="ok"
      elif [[ "$ahead" == "0" ]]; then
        sync="behind:$behind"
        behind_flag=1
      elif [[ "$behind" == "0" ]]; then
        sync="ahead:$ahead"
      else
        sync="diverged:+$ahead -$behind"
        behind_flag=1
      fi
    fi
  fi

  local branch_display="$POR_BRANCH_HEAD"
  if [[ "$POR_BRANCH_HEAD" == "(detached)" ]]; then
    if [[ -n "$POR_BRANCH_OID" && "$POR_BRANCH_OID" != "(initial)" ]]; then
      branch_display="detached@${POR_BRANCH_OID:0:7}"
    else
      branch_display="detached"
    fi
  fi

  local dirty_total=$((POR_STAGED + POR_UNSTAGED + POR_UNTRACKED + POR_CONFLICTS))
  local dirty="clean"
  local dirty_flag=0
  if ((dirty_total > 0)); then
    dirty="w:${POR_UNSTAGED} s:${POR_STAGED} u:${POR_UNTRACKED}"
    if ((POR_CONFLICTS > 0)); then
      dirty="c:${POR_CONFLICTS} $dirty"
    fi
    dirty_flag=1
  fi

  local display_path
  display_path="$(relpath "$BASE_ABS" "$repo")"

  printf '%s\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\n' \
    "$display_path" "$branch_display" "$compare_ref" "$sync" "$dirty" \
    "$behind_flag" "$dirty_flag" "$no_upstream_flag" "$fetch_error_flag"
}

pull_job() {
  local repo="$1"
  local display_path="$2"
  local include_dirty="$3"
  local ff_only="$4"
  local no_fetch="$5"
  local ttl="$6"
  local force_fetch="$7"
  shift 7
  local -a extra_pull_args=("$@")

  if ! collect_porcelain "$repo"; then
    echo "==> $display_path"
    echo "FAIL: status-error"
    return 2
  fi

  if [[ "$POR_BRANCH_HEAD" == "(detached)" ]]; then
    echo "==> $display_path (detached)"
    echo "SKIP: detached HEAD"
    return 10
  fi

  local dirty_total=$((POR_STAGED + POR_UNSTAGED + POR_UNTRACKED + POR_CONFLICTS))
  if ((include_dirty == 0 && dirty_total > 0)); then
    echo "==> $display_path ($POR_BRANCH_HEAD)"
    echo "SKIP: dirty (w:${POR_UNSTAGED} s:${POR_STAGED} u:${POR_UNTRACKED} c:${POR_CONFLICTS})"
    return 11
  fi

  local compare_ref=""
  compare_ref="$(compare_ref_for_repo "$repo" "$POR_BRANCH_HEAD" "$POR_UPSTREAM" 2>/dev/null || true)"

  # Cache shortcut: if we just fetched (e.g. via `status`), avoid re-fetching.
  # Only used when we can rely on local remote-tracking refs.
  if ((no_fetch == 0 && force_fetch == 0)) && cache_is_fresh "$repo" "$ttl"; then
    if [[ -n "$compare_ref" ]]; then
      local ahead=""
      local behind=""
      local ab=""
      if [[ -n "$POR_UPSTREAM" && "$compare_ref" == "$POR_UPSTREAM" && -n "$POR_AB_AHEAD" && -n "$POR_AB_BEHIND" ]]; then
        ahead="$POR_AB_AHEAD"
        behind="$POR_AB_BEHIND"
      else
        if ab="$(ahead_behind "$repo" "$compare_ref" 2>/dev/null)"; then
          ahead="${ab%%$'\t'*}"
          behind="${ab#*$'\t'}"
        fi
      fi

      if [[ "$behind" == "0" ]]; then
        echo "==> $display_path ($POR_BRANCH_HEAD)"
        echo "SKIP: up-to-date"
        return 13
      fi

      if ((ff_only == 1)) && [[ ${#extra_pull_args[@]} -eq 0 ]]; then
        echo "==> $display_path ($POR_BRANCH_HEAD)"
        git -C "$repo" merge --ff-only "$compare_ref"
        return $?
      fi
    fi
  fi

  if ((no_fetch)); then
    # merge-only fast path (assumes compare_ref already updated by a prior fetch).
    if ((ff_only == 0)); then
      echo "==> $display_path ($POR_BRANCH_HEAD)"
      echo "FAIL: --no-fetch requires --ff-only"
      return 3
    fi
    if [[ ${#extra_pull_args[@]} -gt 0 ]]; then
      echo "==> $display_path ($POR_BRANCH_HEAD)"
      echo "FAIL: --no-fetch does not accept extra git pull args"
      return 3
    fi
    if [[ -z "$compare_ref" ]]; then
      echo "==> $display_path ($POR_BRANCH_HEAD)"
      echo "SKIP: no upstream (run without --no-fetch)"
      return 12
    fi

    local ab=""
    local behind=""
    if [[ -n "$POR_UPSTREAM" && "$compare_ref" == "$POR_UPSTREAM" && -n "$POR_AB_BEHIND" ]]; then
      behind="$POR_AB_BEHIND"
    else
      if ab="$(ahead_behind "$repo" "$compare_ref" 2>/dev/null)"; then
        behind="${ab#*$'\t'}"
      fi
    fi
    if [[ "$behind" == "0" ]]; then
      echo "==> $display_path ($POR_BRANCH_HEAD)"
      echo "SKIP: up-to-date"
      return 13
    fi

    echo "==> $display_path ($POR_BRANCH_HEAD)"
    git -C "$repo" merge --ff-only "$compare_ref"
    return $?
  fi

  local remote=""
  local remote_branch=""
  local upstream="$POR_UPSTREAM"
  if [[ -n "$upstream" ]]; then
    remote="${upstream%%/*}"
    remote_branch="${upstream#*/}"
  elif git_remote_exists "$repo" origin; then
    remote="origin"
    remote_branch="$POR_BRANCH_HEAD"
  else
    echo "==> $display_path ($POR_BRANCH_HEAD)"
    echo "SKIP: no upstream and no origin remote"
    return 12
  fi

  # Optimized default path: fetch quietly, then ff-only merge if needed.
  if ((ff_only == 1)) && [[ ${#extra_pull_args[@]} -eq 0 ]]; then
    local refspec="+refs/heads/$remote_branch:refs/remotes/$remote/$remote_branch"
    if ! git -C "$repo" fetch --prune --quiet --no-tags --recurse-submodules=no "$remote" "$refspec"; then
      echo "==> $display_path ($POR_BRANCH_HEAD)"
      echo "FAIL: fetch"
      return 2
    fi
    cache_write_fetch_time "$repo" >/dev/null 2>&1 || true

    compare_ref="$remote/$remote_branch"
    local ab=""
    local behind=""
    if ab="$(ahead_behind "$repo" "$compare_ref" 2>/dev/null)"; then
      behind="${ab#*$'\t'}"
    fi
    if [[ "$behind" == "0" ]]; then
      echo "==> $display_path ($POR_BRANCH_HEAD)"
      echo "SKIP: up-to-date"
      return 13
    fi

    echo "==> $display_path ($POR_BRANCH_HEAD)"
    git -C "$repo" merge --ff-only "$compare_ref"
    return $?
  fi

  echo "==> $display_path ($POR_BRANCH_HEAD)"
  local -a pull_cmd
  pull_cmd=(git -C "$repo" pull --prune --no-tags --recurse-submodules=no)
  if ((ff_only)); then
    pull_cmd+=(--ff-only)
  fi
  if [[ ${#extra_pull_args[@]} -gt 0 ]]; then
    pull_cmd+=("${extra_pull_args[@]}")
  fi
  pull_cmd+=("$remote" "$remote_branch")

  "${pull_cmd[@]}"
}

ahead_behind() {
  local repo="$1"
  local compare_ref="$2"
  local out
  out="$(git -C "$repo" rev-list --left-right --count "${compare_ref}...HEAD" 2>/dev/null)" || return 1
  local behind=0
  local ahead=0
  IFS=$'\t ' read -r behind ahead <<<"$out"
  printf '%s\t%s' "$ahead" "$behind"
}

discover_repos() {
  local base="$1"
  local base_abs
  base_abs="$(abs_dir "$base")" || return 1

  BASE_ABS="$base_abs"
  REPOS=()
  WT_DIRS=()
  declare -gA _repo_seen=()

  add_repo() {
    local dir="$1"
    local abs
    abs="$(abs_dir "$dir")" || return 0
    if [[ -n "${_repo_seen[$abs]+x}" ]]; then
      return 0
    fi
    _repo_seen["$abs"]=1
    REPOS+=("$abs")
    if is_linked_checkout "$abs"; then
      WT_DIRS+=("$abs")
    fi
  }

  local candidates=()
  candidates+=("$base_abs")

  shopt -s nullglob
  local d
  for d in "$base_abs"/*; do
    [[ -d "$d" ]] || continue
    candidates+=("$d")
  done

  local c
  for c in "${candidates[@]}"; do
    is_git_repo_root "$c" || continue
    add_repo "$c"
  done

  # One extra level for linked checkouts (worktrees/submodules).
  local wt
  for wt in "${WT_DIRS[@]}"; do
    shopt -s nullglob
    for d in "$wt"/*; do
      [[ -d "$d" ]] || continue
      is_git_repo_root "$d" || continue
      add_repo "$d"
    done
  done
}

print_status() {
  local base="."
  local fetch_enabled=1
  local jobs
  jobs="$(default_jobs)"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-fetch)
        fetch_enabled=0
        ;;
      --jobs|-j)
        shift
        [[ $# -gt 0 ]] || die "--jobs requires a number"
        jobs="$1"
        ;;
      --jobs=*)
        jobs="${1#--jobs=}"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        base="$1"
        ;;
    esac
    shift
  done

  [[ "$jobs" =~ ^[0-9]+$ ]] || die "--jobs must be an integer"
  ((jobs >= 1)) || die "--jobs must be >= 1"

  discover_repos "$base" || die "not a directory: $base"
  if [[ ${#REPOS[@]} -eq 0 ]]; then
    echo "No git repos found."
    return 0
  fi

  local tmp
  tmp="$(mktemp_dir)" || die "failed to create temp dir"

  CLEANUP_DIRS+=("$tmp")

  local supports_n=0
  if supports_wait_n; then
    supports_n=1
  fi

  local running=0
  local -a pids=()

  local idx=0
  local repo
  for repo in "${REPOS[@]}"; do
    (
      set +e
      status_row_tsv "$repo" "$fetch_enabled" >"$tmp/$idx.tsv"
      exit 0
    ) &

    if ((supports_n)); then
      ((++running))
      if ((running >= jobs)); then
        wait -n || true
        running=$((running - 1))
      fi
    else
      pids+=("$!")
      if ((${#pids[@]} >= jobs)); then
        wait "${pids[0]}" || true
        pids=("${pids[@]:1}")
      fi
    fi

    ((++idx))
  done

  if ((supports_n)); then
    while ((running > 0)); do
      wait -n || true
      running=$((running - 1))
    done
  else
    local pid
    for pid in "${pids[@]}"; do
      wait "$pid" || true
    done
  fi

  local -a row_path=()
  local -a row_branch=()
  local -a row_remote=()
  local -a row_sync=()
  local -a row_dirty=()

  local path_w=4
  local branch_w=6
  local remote_w=6
  local sync_w=4
  local dirty_w=5

  local behind_repos=0
  local dirty_repos=0
  local no_upstream=0
  local fetch_errors=0

  local line
  for ((idx = 0; idx < ${#REPOS[@]}; idx++)); do
    if [[ ! -f "$tmp/$idx.tsv" ]]; then
      continue
    fi
    line="$(<"$tmp/$idx.tsv")"

    local pth br rem syn dir behind_flag dirty_flag no_upstream_flag fetch_error_flag
    IFS=$'\t' read -r pth br rem syn dir behind_flag dirty_flag no_upstream_flag fetch_error_flag <<<"$line"

    row_path+=("$pth")
    row_branch+=("$br")
    row_remote+=("$rem")
    row_sync+=("$syn")
    row_dirty+=("$dir")

    [[ "${behind_flag:-0}" == "1" ]] && ((++behind_repos))
    [[ "${dirty_flag:-0}" == "1" ]] && ((++dirty_repos))
    [[ "${no_upstream_flag:-0}" == "1" ]] && ((++no_upstream))
    [[ "${fetch_error_flag:-0}" == "1" ]] && ((++fetch_errors))

    (( ${#pth} > path_w )) && path_w=${#pth}
    (( ${#br} > branch_w )) && branch_w=${#br}
    (( ${#rem} > remote_w )) && remote_w=${#rem}
    (( ${#syn} > sync_w )) && sync_w=${#syn}
    (( ${#dir} > dirty_w )) && dirty_w=${#dir}
  done

  printf "%-${path_w}s  %-${branch_w}s  %-${remote_w}s  %-${sync_w}s  %s\n" \
    "path" "branch" "remote" "sync" "dirty"
  printf "%-${path_w}s  %-${branch_w}s  %-${remote_w}s  %-${sync_w}s  %s\n" \
    "----" "------" "------" "----" "-----"

  local i
  for ((i = 0; i < ${#row_path[@]}; i++)); do
    printf "%-${path_w}s  %-${branch_w}s  %-${remote_w}s  %-${sync_w}s  %s\n" \
      "${row_path[$i]}" "${row_branch[$i]}" "${row_remote[$i]}" "${row_sync[$i]}" "${row_dirty[$i]}"
  done

  echo
  echo "repos:${#row_path[@]} behind:$behind_repos dirty:$dirty_repos no-upstream:$no_upstream fetch-errors:$fetch_errors"
}

run_pull() {
  local base="."
  local include_dirty=0
  local ff_only=1
  local no_fetch=0
  local jobs
  jobs="$(default_jobs)"
  local ttl="${GIT_WORKSPACE_FETCH_TTL_SECONDS:-120}"
  local force_fetch=0
  local -a extra_pull_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --include-dirty)
        include_dirty=1
        ;;
      --no-ff-only)
        ff_only=0
        ;;
      --no-fetch)
        no_fetch=1
        ;;
      --ttl)
        shift
        [[ $# -gt 0 ]] || die "--ttl requires a number"
        ttl="$1"
        ;;
      --ttl=*)
        ttl="${1#--ttl=}"
        ;;
      --force-fetch)
        force_fetch=1
        ;;
      --jobs|-j)
        shift
        [[ $# -gt 0 ]] || die "--jobs requires a number"
        jobs="$1"
        ;;
      --jobs=*)
        jobs="${1#--jobs=}"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        extra_pull_args+=("$@")
        break
        ;;
      *)
        base="$1"
        ;;
    esac
    shift
  done

  [[ "$jobs" =~ ^[0-9]+$ ]] || die "--jobs must be an integer"
  ((jobs >= 1)) || die "--jobs must be >= 1"
  [[ "$ttl" =~ ^[0-9]+$ ]] || die "--ttl must be an integer"
  ((ttl >= 0)) || die "--ttl must be >= 0"

  discover_repos "$base" || die "not a directory: $base"
  if [[ ${#REPOS[@]} -eq 0 ]]; then
    echo "No git repos found."
    return 0
  fi

  local tmp
  tmp="$(mktemp_dir)" || die "failed to create temp dir"

  CLEANUP_DIRS+=("$tmp")

  local supports_n=0
  if supports_wait_n; then
    supports_n=1
  fi

  local running=0
  local -a pids=()

  local idx=0
  local repo
  for repo in "${REPOS[@]}"; do
    local display_path
    display_path="$(relpath "$BASE_ABS" "$repo")"

    (
      set +e
      pull_job "$repo" "$display_path" "$include_dirty" "$ff_only" "$no_fetch" "$ttl" "$force_fetch" "${extra_pull_args[@]}"
      echo "$?" >"$tmp/$idx.rc"
      exit 0
    ) >"$tmp/$idx.out" 2>&1 &

    if ((supports_n)); then
      ((++running))
      if ((running >= jobs)); then
        wait -n || true
        running=$((running - 1))
      fi
    else
      pids+=("$!")
      if ((${#pids[@]} >= jobs)); then
        wait "${pids[0]}" || true
        pids=("${pids[@]:1}")
      fi
    fi

    ((++idx))
  done

  if ((supports_n)); then
    while ((running > 0)); do
      wait -n || true
      running=$((running - 1))
    done
  else
    local pid
    for pid in "${pids[@]}"; do
      wait "$pid" || true
    done
  fi

  local pulled=0
  local skipped_dirty=0
  local skipped_detached=0
  local skipped_no_remote=0
  local skipped_up_to_date=0
  local failed=0

  for ((idx = 0; idx < ${#REPOS[@]}; idx++)); do
    if [[ -f "$tmp/$idx.out" ]]; then
      cat "$tmp/$idx.out"
      echo
    fi

    local code=""
    if [[ -f "$tmp/$idx.rc" ]]; then
      code="$(<"$tmp/$idx.rc")"
    else
      code="1"
    fi

    case "$code" in
      0) ((++pulled)) ;;
      13) ((++skipped_up_to_date)) ;;
      10) ((++skipped_detached)) ;;
      11) ((++skipped_dirty)) ;;
      12) ((++skipped_no_remote)) ;;
      *) ((++failed)) ;;
    esac
  done

  echo "pulled:$pulled skipped-up-to-date:$skipped_up_to_date skipped-dirty:$skipped_dirty skipped-detached:$skipped_detached skipped-no-remote:$skipped_no_remote failed:$failed"
}

main() {
  command -v git >/dev/null 2>&1 || die "git is not installed"

  local cmd="status"
  if [[ $# -gt 0 ]]; then
    case "$1" in
      status|report)
        cmd="status"
        shift
        ;;
      pull)
        cmd="pull"
        shift
        ;;
      -h|--help|help)
        usage
        exit 0
        ;;
      *)
        cmd="status"
        ;;
    esac
  fi

  case "$cmd" in
    status) print_status "$@" ;;
    pull) run_pull "$@" ;;
    *) usage; exit 2 ;;
  esac
}

main "$@"
