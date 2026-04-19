#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null
  pwd -P
)"

SETUP_SCRIPT="$ROOT_DIR/zsh/.zshrc.d/scripts/git-setup-worktree.sh"
NEW_WORKTREE_SCRIPT="$ROOT_DIR/zsh/.zshrc.d/scripts/git-new-worktree.sh"
WORKSPACE_SCRIPT="$ROOT_DIR/zsh/.zshrc.d/scripts/git-workspace.sh"

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-worktree-tests.XXXXXX")"
PASS_COUNT=0

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT INT TERM

export HOME="$TEST_ROOT/home"
export XDG_CACHE_HOME="$TEST_ROOT/cache"
export GIT_CONFIG_GLOBAL="$TEST_ROOT/home/.gitconfig"
export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME="Dotfiles Test"
export GIT_AUTHOR_EMAIL="dotfiles-tests@example.com"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

mkdir -p "$HOME" "$XDG_CACHE_HOME"
: >"$GIT_CONFIG_GLOBAL"

abs_dir() {
  (
    cd "$1" 2>/dev/null
    pwd -P
  )
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_under_test_root() {
  local path="$1"
  local abs

  abs="$(abs_dir "$path")" || fail "expected path to exist under test root: $path"
  [[ "$abs" == "$TEST_ROOT"/* ]] || fail "path escaped test root: $abs"
}

assert_path_exists() {
  local path="$1"
  [[ -e "$path" ]] || fail "expected path to exist: $path"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'Expected output to contain: %s\n' "$needle" >&2
    printf 'Actual output:\n%s\n' "$haystack" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"

  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'Expected output to not contain: %s\n' "$needle" >&2
    printf 'Actual output:\n%s\n' "$haystack" >&2
    exit 1
  fi
}

assert_matches() {
  local haystack="$1"
  local pattern="$2"

  if ! grep -Eq "$pattern" <<<"$haystack"; then
    printf 'Expected output to match regex: %s\n' "$pattern" >&2
    printf 'Actual output:\n%s\n' "$haystack" >&2
    exit 1
  fi
}

assert_eq() {
  local actual="$1"
  local expected="$2"

  if [[ "$actual" != "$expected" ]]; then
    printf 'Expected: %s\n' "$expected" >&2
    printf 'Actual: %s\n' "$actual" >&2
    exit 1
  fi
}

assert_local_branch_exists() {
  local repo="$1"
  local branch="$2"

  git -C "$repo" show-ref --verify --quiet "refs/heads/$branch" || fail "expected local branch to exist: $branch"
}

assert_local_branch_missing() {
  local repo="$1"
  local branch="$2"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    fail "expected local branch to be absent: $branch"
  fi
}

assert_remote_fetch_refspec_present() {
  local repo="$1"
  local remote="$2"
  local branch="$3"
  local expected="+refs/heads/$branch:refs/remotes/$remote/$branch"
  local actual=""

  actual="$(git -C "$repo" config --get-all "remote.$remote.fetch" 2>/dev/null || true)"
  grep -Fxq "$expected" <<<"$actual" || fail "expected remote fetch refspec to exist: $expected"
}

assert_remote_fetch_refspec_missing() {
  local repo="$1"
  local remote="$2"
  local branch="$3"
  local unexpected="+refs/heads/$branch:refs/remotes/$remote/$branch"
  local actual=""

  actual="$(git -C "$repo" config --get-all "remote.$remote.fetch" 2>/dev/null || true)"
  if grep -Fxq "$unexpected" <<<"$actual"; then
    fail "expected remote fetch refspec to be absent: $unexpected"
  fi
}

assert_remote_tracking_ref_missing() {
  local repo="$1"
  local remote="$2"
  local branch="$3"

  if git -C "$repo" show-ref --verify --quiet "refs/remotes/$remote/$branch"; then
    fail "expected remote-tracking ref to be absent: refs/remotes/$remote/$branch"
  fi
}

create_repo() {
  local repo="$1"
  local branch="$2"

  mkdir -p "$repo"
  git init -b "$branch" "$repo" >/dev/null
  printf 'seed\n' >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -m "Initial commit" >/dev/null
}

create_remote_only_branch_clone() {
  local workspace="$1"
  local base_branch="$2"
  local remote_branch="$3"
  local remote_branch_slug="${remote_branch//\//^}"
  local origin_repo="$workspace/origin.git"
  local seed_repo="$workspace/seed"
  local clone_repo="$workspace/clone"

  git init --bare "$origin_repo" >/dev/null
  create_repo "$seed_repo" "$base_branch"

  git -C "$seed_repo" remote add origin "$origin_repo"
  git -C "$seed_repo" push -u origin "$base_branch" >/dev/null

  git -C "$seed_repo" switch -c "$remote_branch" >/dev/null
  printf '%s\n' "$remote_branch" >"$seed_repo/$remote_branch_slug.txt"
  git -C "$seed_repo" add "$remote_branch_slug.txt"
  git -C "$seed_repo" commit -m "Add $remote_branch" >/dev/null
  git -C "$seed_repo" push -u origin "$remote_branch" >/dev/null

  git clone --single-branch --branch "$base_branch" "$origin_repo" "$clone_repo" >/dev/null
  printf '%s\n' "$clone_repo"
}

create_ambiguous_remote_only_branch_clone() {
  local workspace="$1"
  local base_branch="$2"
  local remote_branch="$3"
  local origin_repo="$workspace/origin.git"
  local upstream_repo="$workspace/upstream.git"
  local seed_repo="$workspace/seed"
  local clone_repo="$workspace/clone"

  git init --bare "$origin_repo" >/dev/null
  git init --bare "$upstream_repo" >/dev/null
  create_repo "$seed_repo" "$base_branch"

  git -C "$seed_repo" remote add origin "$origin_repo"
  git -C "$seed_repo" remote add upstream "$upstream_repo"
  git -C "$seed_repo" push -u origin "$base_branch" >/dev/null
  git -C "$seed_repo" push -u upstream "$base_branch" >/dev/null

  git -C "$seed_repo" switch -c "$remote_branch" >/dev/null
  printf '%s\n' "$remote_branch" >"$seed_repo/ambiguous-branch.txt"
  git -C "$seed_repo" add ambiguous-branch.txt
  git -C "$seed_repo" commit -m "Add $remote_branch to both remotes" >/dev/null
  git -C "$seed_repo" push -u origin "$remote_branch" >/dev/null
  git -C "$seed_repo" push -u upstream "$remote_branch" >/dev/null

  git clone --single-branch --branch "$base_branch" "$origin_repo" "$clone_repo" >/dev/null
  git -C "$clone_repo" remote add upstream "$upstream_repo"
  printf '%s\n' "$clone_repo"
}

create_second_mv_failure_stub() {
  local stub_dir="$1"
  local real_mv=""

  real_mv="$(command -v mv)"
  mkdir -p "$stub_dir"

  cat >"$stub_dir/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
count_file="\${GIT_TEST_MV_COUNT_FILE:?}"
count=0
if [[ -f "\$count_file" ]]; then
  count="\$(<"\$count_file")"
fi
count=\$((count + 1))
printf '%s' "\$count" >"\$count_file"
if [[ "\$count" == "2" ]]; then
  echo "simulated mv failure" >&2
  exit 1
fi
exec "$real_mv" "\$@"
EOF
  chmod +x "$stub_dir/mv"
}

run_test() {
  local name="$1"

  echo "==> $name"
  "$name"
  PASS_COUNT=$((PASS_COUNT + 1))
}

test_converted_repo_stays_discoverable() {
  local workspace="$TEST_ROOT/workspace-discovery"
  local repo="$workspace/foo"
  local output=""

  create_repo "$repo" main
  assert_under_test_root "$repo"

  bash "$SETUP_SCRIPT" "$repo" main >/dev/null

  assert_path_exists "$workspace/foo/.git-worktree-container"
  assert_path_exists "$workspace/foo/main/.git"
  output="$(bash "$WORKSPACE_SCRIPT" status "$workspace" --no-fetch)"

  assert_contains "$output" "foo/main"
  assert_contains "$output" "repos:1"
}

test_matching_repo_and_branch_names_work() {
  local workspace="$TEST_ROOT/workspace-matching"
  local repo="$workspace/main"

  create_repo "$repo" main
  assert_under_test_root "$repo"

  bash "$SETUP_SCRIPT" "$repo" main >/dev/null

  assert_path_exists "$workspace/main/main/.git"
  assert_under_test_root "$workspace/main/main"
}

test_new_worktree_is_sibling_and_discoverable() {
  local workspace="$TEST_ROOT/workspace-siblings"
  local repo="$workspace/foo"
  local primary="$workspace/foo/main"
  local feature="$workspace/foo/feature^test"
  local output=""

  create_repo "$repo" main
  assert_under_test_root "$repo"

  bash "$SETUP_SCRIPT" "$repo" main >/dev/null

  (
    cd "$primary"
    bash "$NEW_WORKTREE_SCRIPT" feature/test >/dev/null
  )

  assert_path_exists "$feature/.git"
  assert_under_test_root "$feature"

  output="$(bash "$WORKSPACE_SCRIPT" status "$workspace" --no-fetch)"

  assert_contains "$output" "foo/main"
  assert_contains "$output" "foo/feature^test"
  assert_contains "$output" "repos:2"
}

test_remote_only_branch_tracks_correct_history() {
  local workspace="$TEST_ROOT/workspace-remote-only"
  local repo=""
  local converted_repo=""
  local head_oid=""
  local remote_oid=""
  local remote_ref_exists=""
  local upstream=""

  repo="$(create_remote_only_branch_clone "$workspace" main release)"
  assert_under_test_root "$repo"
  remote_ref_exists="$(git -C "$repo" show-ref --verify --quiet refs/remotes/origin/release; printf '%s' "$?")"
  assert_eq "$remote_ref_exists" "1"

  bash "$SETUP_SCRIPT" "$repo" release >/dev/null

  converted_repo="$workspace/clone/release"
  assert_path_exists "$converted_repo/.git"

  head_oid="$(git -C "$converted_repo" rev-parse HEAD)"
  remote_oid="$(git -C "$converted_repo" rev-parse refs/remotes/origin/release)"
  upstream="$(git -C "$converted_repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')"

  assert_eq "$head_oid" "$remote_oid"
  assert_eq "$upstream" "origin/release"
  assert_remote_fetch_refspec_present "$converted_repo" origin release
}

test_remote_only_branch_with_slash_tracks_correct_history() {
  local workspace="$TEST_ROOT/workspace-remote-slash"
  local repo=""
  local converted_repo=""
  local head_oid=""
  local remote_oid=""
  local remote_ref_exists=""
  local upstream=""

  repo="$(create_remote_only_branch_clone "$workspace" main feature/test)"
  assert_under_test_root "$repo"
  remote_ref_exists="$(git -C "$repo" show-ref --verify --quiet refs/remotes/origin/feature/test; printf '%s' "$?")"
  assert_eq "$remote_ref_exists" "1"

  bash "$SETUP_SCRIPT" "$repo" feature/test >/dev/null

  converted_repo="$workspace/clone/feature^test"
  assert_path_exists "$converted_repo/.git"

  head_oid="$(git -C "$converted_repo" rev-parse HEAD)"
  remote_oid="$(git -C "$converted_repo" rev-parse refs/remotes/origin/feature/test)"
  upstream="$(git -C "$converted_repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')"

  assert_eq "$head_oid" "$remote_oid"
  assert_eq "$upstream" "origin/feature/test"
  assert_remote_fetch_refspec_present "$converted_repo" origin feature/test
}

test_existing_local_branch_preserves_remote_fetch_refspec() {
  local workspace="$TEST_ROOT/workspace-existing-local"
  local repo=""
  local converted_repo=""
  local seed_repo="$workspace/seed"
  local before_remote_oid=""
  local after_remote_oid=""
  local head_oid=""
  local upstream=""

  repo="$(create_remote_only_branch_clone "$workspace" main release)"
  assert_under_test_root "$repo"

  git -C "$repo" fetch origin "refs/heads/release:refs/remotes/origin/release" >/dev/null
  git -C "$repo" switch -c release refs/remotes/origin/release >/dev/null
  git -C "$repo" config branch.release.remote origin
  git -C "$repo" config branch.release.merge refs/heads/release
  git -C "$repo" switch main >/dev/null

  assert_local_branch_exists "$repo" release
  assert_remote_fetch_refspec_missing "$repo" origin release

  bash "$SETUP_SCRIPT" "$repo" release >/dev/null

  converted_repo="$workspace/clone/release"
  assert_path_exists "$converted_repo/.git"
  assert_remote_fetch_refspec_present "$converted_repo" origin release

  upstream="$(git -C "$converted_repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')"
  assert_eq "$upstream" "origin/release"

  before_remote_oid="$(git -C "$converted_repo" rev-parse refs/remotes/origin/release)"

  git -C "$seed_repo" switch release >/dev/null
  printf 'advance\n' >>"$seed_repo/release.txt"
  git -C "$seed_repo" add release.txt
  git -C "$seed_repo" commit -m "Advance release" >/dev/null
  git -C "$seed_repo" push origin release >/dev/null

  git -C "$converted_repo" fetch origin >/dev/null
  after_remote_oid="$(git -C "$converted_repo" rev-parse refs/remotes/origin/release)"
  head_oid="$(git -C "$converted_repo" rev-parse HEAD)"

  [[ "$before_remote_oid" != "$after_remote_oid" ]] || fail "expected origin/release to advance after fetch"
  assert_eq "$head_oid" "$before_remote_oid"

  git -C "$converted_repo" pull --ff-only >/dev/null
  head_oid="$(git -C "$converted_repo" rev-parse HEAD)"
  assert_eq "$head_oid" "$after_remote_oid"
}

test_existing_local_branch_without_tracking_discovers_remote_upstream() {
  local workspace="$TEST_ROOT/workspace-existing-local-no-tracking"
  local repo=""
  local converted_repo=""
  local seed_repo="$workspace/seed"
  local before_remote_oid=""
  local after_remote_oid=""
  local head_oid=""
  local upstream=""

  repo="$(create_remote_only_branch_clone "$workspace" main release)"
  assert_under_test_root "$repo"

  git -C "$repo" fetch origin "refs/heads/release:refs/remotes/origin/release" >/dev/null
  git -C "$repo" switch -c release refs/remotes/origin/release >/dev/null
  git -C "$repo" config --unset-all branch.release.remote >/dev/null 2>&1 || true
  git -C "$repo" config --unset-all branch.release.merge >/dev/null 2>&1 || true

  assert_local_branch_exists "$repo" release
  assert_remote_fetch_refspec_missing "$repo" origin release

  bash "$SETUP_SCRIPT" "$repo" release >/dev/null

  converted_repo="$workspace/clone/release"
  assert_path_exists "$converted_repo/.git"
  assert_remote_fetch_refspec_present "$converted_repo" origin release

  upstream="$(git -C "$converted_repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')"
  assert_eq "$upstream" "origin/release"

  before_remote_oid="$(git -C "$converted_repo" rev-parse refs/remotes/origin/release)"

  git -C "$seed_repo" switch release >/dev/null
  printf 'advance\n' >>"$seed_repo/release.txt"
  git -C "$seed_repo" add release.txt
  git -C "$seed_repo" commit -m "Advance release" >/dev/null
  git -C "$seed_repo" push origin release >/dev/null

  git -C "$converted_repo" fetch origin >/dev/null
  after_remote_oid="$(git -C "$converted_repo" rev-parse refs/remotes/origin/release)"
  head_oid="$(git -C "$converted_repo" rev-parse HEAD)"

  [[ "$before_remote_oid" != "$after_remote_oid" ]] || fail "expected origin/release to advance after fetch"
  assert_eq "$head_oid" "$before_remote_oid"

  git -C "$converted_repo" pull --ff-only >/dev/null
  head_oid="$(git -C "$converted_repo" rev-parse HEAD)"
  assert_eq "$head_oid" "$after_remote_oid"
}

test_setup_rejects_already_grouped_primary_checkout() {
  local workspace="$TEST_ROOT/workspace-already-grouped"
  local repo="$workspace/foo"
  local primary="$workspace/foo/main"
  local output=""

  create_repo "$repo" main

  bash "$SETUP_SCRIPT" "$repo" main >/dev/null

  if output="$(bash "$SETUP_SCRIPT" "$primary" main 2>&1)"; then
    fail "expected setup to reject an already-grouped primary checkout"
  fi

  assert_contains "$output" "repo is already inside worktree container"
  assert_path_exists "$workspace/foo/.git-worktree-container"
  assert_path_exists "$primary/.git"
  if [[ -e "$primary/main" ]]; then
    fail "expected setup to avoid creating a nested primary checkout"
  fi
}

test_deleted_remote_branch_is_rejected() {
  local workspace="$TEST_ROOT/workspace-deleted-remote"
  local repo=""
  local origin_repo="$workspace/origin.git"
  local seed_repo="$workspace/seed"
  local output=""

  repo="$(create_remote_only_branch_clone "$workspace" main release)"
  assert_under_test_root "$repo"

  git -C "$seed_repo" switch main >/dev/null
  git -C "$seed_repo" push "$origin_repo" --delete release >/dev/null

  if output="$(bash "$SETUP_SCRIPT" "$repo" release 2>&1)"; then
    fail "expected setup to reject a deleted remote-only branch"
  fi

  assert_contains "$output" "branch release not found locally or on any remote"
  assert_path_exists "$repo/.git"
}

test_ambiguous_remote_only_branch_reports_explicit_error() {
  local workspace="$TEST_ROOT/workspace-ambiguous-remote"
  local repo=""
  local output=""

  repo="$(create_ambiguous_remote_only_branch_clone "$workspace" main release)"
  assert_under_test_root "$repo"

  if output="$(bash "$SETUP_SCRIPT" "$repo" release 2>&1)"; then
    fail "expected setup to reject an ambiguous remote-only branch"
  fi

  assert_contains "$output" "branch release exists on multiple remotes; create the local branch manually first"
  assert_not_contains "$output" "branch release not found locally or on any remote"
  assert_path_exists "$repo/.git"
}

test_setup_rolls_back_when_second_move_fails() {
  local workspace="$TEST_ROOT/workspace-rollback"
  local repo="$workspace/foo"
  local stub_dir="$TEST_ROOT/stubs"
  local mv_count_file="$TEST_ROOT/mv-count"
  local output=""

  create_repo "$repo" main
  create_second_mv_failure_stub "$stub_dir"

  if output="$(PATH="$stub_dir:$PATH" GIT_TEST_MV_COUNT_FILE="$mv_count_file" bash "$SETUP_SCRIPT" "$repo" main 2>&1)"; then
    fail "expected setup to fail when the second mv is forced to fail"
  fi

  assert_contains "$output" "simulated mv failure"
  assert_path_exists "$repo/.git"
  assert_not_contains "$(find "$workspace" -maxdepth 2 -name '.git-worktree-container' -print)" ".git-worktree-container"
  assert_eq "$(git -C "$repo" rev-parse --show-toplevel)" "$(abs_dir "$repo")"
}

test_setup_rolls_back_created_branch_when_second_move_fails() {
  local workspace="$TEST_ROOT/workspace-rollback-created-branch"
  local repo=""
  local stub_dir="$TEST_ROOT/stubs-created-branch"
  local mv_count_file="$TEST_ROOT/mv-count-created-branch"
  local output=""

  repo="$(create_remote_only_branch_clone "$workspace" main release)"
  create_second_mv_failure_stub "$stub_dir"

  if output="$(PATH="$stub_dir:$PATH" GIT_TEST_MV_COUNT_FILE="$mv_count_file" bash "$SETUP_SCRIPT" "$repo" release 2>&1)"; then
    fail "expected setup to fail when the second mv is forced to fail"
  fi

  assert_contains "$output" "simulated mv failure"
  assert_path_exists "$repo/.git"
  assert_eq "$(git -C "$repo" symbolic-ref --quiet --short HEAD)" "main"
  assert_local_branch_missing "$repo" "release"
  assert_remote_fetch_refspec_missing "$repo" origin release
  assert_remote_tracking_ref_missing "$repo" origin release
  assert_not_contains "$(find "$workspace" -maxdepth 2 -name '.git-worktree-container' -print)" ".git-worktree-container"
}

test_setup_rolls_back_to_original_branch_without_deleting_existing_branch() {
  local workspace="$TEST_ROOT/workspace-rollback-existing-branch"
  local repo="$workspace/foo"
  local stub_dir="$TEST_ROOT/stubs-existing-branch"
  local mv_count_file="$TEST_ROOT/mv-count-existing-branch"
  local output=""

  create_repo "$repo" main
  git -C "$repo" switch -c release >/dev/null
  git -C "$repo" switch main >/dev/null
  create_second_mv_failure_stub "$stub_dir"

  if output="$(PATH="$stub_dir:$PATH" GIT_TEST_MV_COUNT_FILE="$mv_count_file" bash "$SETUP_SCRIPT" "$repo" release 2>&1)"; then
    fail "expected setup to fail when the second mv is forced to fail"
  fi

  assert_contains "$output" "simulated mv failure"
  assert_path_exists "$repo/.git"
  assert_eq "$(git -C "$repo" symbolic-ref --quiet --short HEAD)" "main"
  assert_local_branch_exists "$repo" "release"
  assert_not_contains "$(find "$workspace" -maxdepth 2 -name '.git-worktree-container' -print)" ".git-worktree-container"
}

test_plain_repo_nested_repo_is_not_discovered() {
  local workspace="$TEST_ROOT/workspace-nested"
  local repo="$workspace/app"
  local nested_repo="$repo/vendor"
  local output=""

  create_repo "$repo" main
  create_repo "$nested_repo" main

  output="$(bash "$WORKSPACE_SCRIPT" status "$workspace" --no-fetch)"

  assert_contains "$output" "app"
  assert_contains "$output" "repos:1"
  assert_not_contains "$output" "vendor"
}

test_grouped_nested_repo_is_not_discovered() {
  local workspace="$TEST_ROOT/workspace-grouped"
  local nested_repo="$workspace/cache/repo"
  local output=""

  create_repo "$nested_repo" main

  output="$(bash "$WORKSPACE_SCRIPT" status "$workspace" --no-fetch)"

  assert_contains "$output" "No git repos found."
  assert_not_contains "$output" "cache/repo"
}

test_status_preserves_empty_remote_column() {
  local workspace="$TEST_ROOT/workspace-no-upstream"
  local repo="$workspace/app"
  local output=""

  create_repo "$repo" main

  output="$(bash "$WORKSPACE_SCRIPT" status "$workspace" --no-fetch)"

  assert_matches "$output" '^app[[:space:]]+main[[:space:]]+no-upstream[[:space:]]+clean$'
  assert_contains "$output" "repos:1 behind:0 dirty:0 no-upstream:1 fetch-errors:0"
}

run_test test_converted_repo_stays_discoverable
run_test test_matching_repo_and_branch_names_work
run_test test_new_worktree_is_sibling_and_discoverable
run_test test_remote_only_branch_tracks_correct_history
run_test test_remote_only_branch_with_slash_tracks_correct_history
run_test test_existing_local_branch_preserves_remote_fetch_refspec
run_test test_existing_local_branch_without_tracking_discovers_remote_upstream
run_test test_setup_rejects_already_grouped_primary_checkout
run_test test_deleted_remote_branch_is_rejected
run_test test_ambiguous_remote_only_branch_reports_explicit_error
run_test test_setup_rolls_back_when_second_move_fails
run_test test_setup_rolls_back_created_branch_when_second_move_fails
run_test test_setup_rolls_back_to_original_branch_without_deleting_existing_branch
run_test test_plain_repo_nested_repo_is_not_discovered
run_test test_grouped_nested_repo_is_not_discovered
run_test test_status_preserves_empty_remote_column

printf 'PASS: %d tests\n' "$PASS_COUNT"
