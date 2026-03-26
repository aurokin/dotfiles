#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  git-new-worktree.sh <branch> [start-point] [path]
  git-new-worktree.sh <branch> [--from <start-point>] [--path <path>]

Examples:
  git-new-worktree.sh feature/login
  git-new-worktree.sh feature/login main
  git-new-worktree.sh feature/login --path ../feature-login
  git-new-worktree.sh feature/login --path ../feature^login
  git-new-worktree.sh feature/login --from main --path ../feature^login
  git-new-worktree.sh feature/login main ../feature-login

Behavior:
  - Creates a new worktree for <branch>.
  - Defaults start-point to the currently checked out branch, otherwise HEAD.
  - Defaults path to ../<branch>, with "/" replaced by "^" to avoid nesting.
  - Supports optional --from/-f and --path/-p flags while keeping the default flow positional and flag-free.
  - If you want to set only the path, use --path; the second positional argument is always the start-point.
  - The branch name must be the first argument.
EOF
}

slugify_branch() {
  local value="$1"

  value="${value//\//^}"

  printf '%s\n' "$value"
}

branch_worktree_path() {
  local target="$1"

  git worktree list --porcelain 2>/dev/null | awk -v target="refs/heads/$target" '
    $1 == "worktree" { path = substr($0, 10) }
    $1 == "branch" && $2 == target { print path; exit }
  '
}

if [[ "${1-}" == "-h" || "${1-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -n "${1-}" && "${1-}" == -* ]]; then
  echo "git-new-worktree.sh: branch must be the first argument" >&2
  usage >&2
  exit 2
fi

branch="${1-}"
start_point=""
path_arg=""
start_point_explicit=false
path_arg_explicit=false

if [[ -n "$branch" ]]; then
  shift
fi

set_start_point() {
  local value="$1"

  if [[ -n "$start_point" ]]; then
    echo "git-new-worktree.sh: start-point specified more than once" >&2
    exit 2
  fi

  start_point="$value"
  start_point_explicit=true
}

set_path_arg() {
  local value="$1"

  if [[ -n "$path_arg" ]]; then
    echo "git-new-worktree.sh: path specified more than once" >&2
    exit 2
  fi

  path_arg="$value"
  path_arg_explicit=true
}

add_positional_arg() {
  local value="$1"

  if [[ -z "$start_point" ]]; then
    set_start_point "$value"
    return 0
  fi

  if [[ -z "$path_arg" ]]; then
    set_path_arg "$value"
    return 0
  fi

  echo "git-new-worktree.sh: too many arguments" >&2
  usage >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from|-f)
      [[ $# -ge 2 ]] || {
        echo "git-new-worktree.sh: missing value for $1" >&2
        exit 2
      }
      set_start_point "$2"
      shift 2
      ;;
    --path|-p)
      [[ $# -ge 2 ]] || {
        echo "git-new-worktree.sh: missing value for $1" >&2
        exit 2
      }
      set_path_arg "$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        add_positional_arg "$1"
        shift
      done
      ;;
    -*)
      echo "git-new-worktree.sh: unknown option: $1" >&2
      exit 2
      ;;
    *)
      add_positional_arg "$1"
      shift
      ;;
  esac
done

if [[ -z "$branch" ]]; then
  usage >&2
  exit 1
fi

if ! root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "git-new-worktree.sh: not inside a git repository" >&2
  exit 1
fi

if ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then
  echo "git-new-worktree.sh: invalid branch name: $branch" >&2
  exit 2
fi

branch_slug="$(slugify_branch "$branch")"

if [[ -z "$path_arg" ]]; then
  path_arg="$root/../$branch_slug"
fi

if [[ -z "$start_point" ]]; then
  if current_branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)"; then
    start_point="$current_branch"
  else
    start_point="HEAD"
  fi
fi

if git show-ref --verify --quiet "refs/heads/$branch"; then
  if [[ "$start_point_explicit" == true ]]; then
    echo "git-new-worktree.sh: --from/start-point cannot be used when branch '$branch' already exists" >&2
    exit 2
  fi
  existing_path="$(branch_worktree_path "$branch" || true)"
  if [[ -n "$existing_path" ]]; then
    echo "git-new-worktree.sh: branch '$branch' is already checked out at $existing_path" >&2
    echo "Use a different branch name, choose a different worktree branch, or run git worktree add --force manually if you want duplicate checkouts." >&2
    exit 1
  fi
  exec git worktree add -- "$path_arg" "$branch"
fi

exec git worktree add -b "$branch" -- "$path_arg" "$start_point"
