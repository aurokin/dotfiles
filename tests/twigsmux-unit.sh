#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null
  pwd -P
)"

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/twigsmux-tests.XXXXXX")"
TEST_ROOT="$(
  cd "$TEST_ROOT" 2>/dev/null
  pwd -P
)"
PASS_COUNT=0

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT INT TERM

export HOME="$TEST_ROOT/home"
mkdir -p "$HOME/worktrees/diffwarden/streaming/src" "$HOME/worktrees/diffwarden/feature-foo" "$HOME/worktrees/dotfiles/cleanup" "$HOME/worktrees/dotfiles/streaming" "$HOME/worktrees/dotfiles/ticket-123" "$HOME/worktrees/other/streaming" "$HOME/code/diffwarden/src" "$HOME/code/dotfiles" "$HOME/code/other"
mkdir -p "$HOME/code/recorded-diffwarden"

# shellcheck disable=SC2034
current_session="diffwarden"
# shellcheck disable=SC2034
prefix_current=0

tmux() {
  case "$1" in
    display-message)
      shift
      local target=""
      local format=""

      while [[ $# -gt 0 ]]; do
        case "$1" in
          -p)
            shift
            ;;
          -t)
            target="${2#=}"
            target="${target%:}"
            shift 2
            ;;
          *)
            format="$1"
            shift
            ;;
        esac
      done

        case "$target|$format" in
        'diffwarden-streaming|#{session_id}')
          printf '%s\n' "\$17"
          ;;
        'diffwarden-recorded|#{session_id}')
          printf '%s\n' "\$18"
          ;;
        'diffwarden-recorded-cwd|#{session_id}')
          printf '%s\n' "\$21"
          ;;
        'diffwarden-recorded-drift|#{session_id}')
          printf '%s\n' "\$27"
          ;;
        'diffwarden-recorded-drift|#{pane_current_path}')
          printf '%s\n' "$HOME/worktrees/other/streaming"
          ;;
        'diffwarden-recorded-drift|#{session_path}')
          printf '%s\n' "$HOME/worktrees/other/streaming"
          ;;
        'diffwarden-streaming|#{pane_current_path}')
          printf '%s\n' "$HOME/worktrees/diffwarden/streaming/src"
          ;;
        'diffwarden-streaming|#{session_path}')
          printf '%s\n' "$HOME/code/diffwarden"
          ;;
        'diffwarden-feature-foo|#{session_id}')
          printf '%s\n' "\$26"
          ;;
        'diffwarden-feature-foo|#{pane_current_path}')
          printf '%s\n' "$HOME/worktrees/diffwarden/feature-foo"
          ;;
        'diffwarden-feature-foo|#{session_path}')
          printf '%s\n' "$HOME/worktrees/diffwarden/feature-foo"
          ;;
        'diffwarden-feature/foo|#{session_id}')
          printf '%s\n' "\$29"
          ;;
        'diffwarden-feature/foo|#{pane_current_path}')
          printf '%s\n' "$HOME/worktrees/diffwarden/feature-foo"
          ;;
        'diffwarden-feature/foo|#{session_path}')
          printf '%s\n' "$HOME/worktrees/diffwarden/feature-foo"
          ;;
        'diffwarden-main-path|#{session_id}')
          printf '%s\n' "\$19"
          ;;
        'diffwarden-main-path|#{pane_current_path}')
          printf '%s\n' "$HOME/code/diffwarden"
          ;;
        'diffwarden-main-path|#{session_path}')
          printf '%s\n' "$HOME/code/diffwarden"
          ;;
        'diffwarden-src|#{session_id}')
          printf '%s\n' "\$28"
          ;;
        'diffwarden-src|#{pane_current_path}')
          printf '%s\n' "$HOME/code/diffwarden/src"
          ;;
        'diffwarden-src|#{session_path}')
          printf '%s\n' "$HOME/code/diffwarden/src"
          ;;
        'diffwarden-worktrees-project-root|#{session_id}')
          printf '%s\n' "\$20"
          ;;
        'diffwarden-worktrees-project-root|#{pane_current_path}')
          printf '%s\n' "$HOME/worktrees/diffwarden"
          ;;
        'diffwarden-worktrees-project-root|#{session_path}')
          printf '%s\n' "$HOME/worktrees/diffwarden"
          ;;
        'diffwarden-feature|#{session_id}')
          printf '%s\n' "\$22"
          ;;
        'diffwarden-feature|#{pane_current_path}')
          printf '%s\n' "$HOME/worktrees/dotfiles/cleanup"
          ;;
        'diffwarden-feature|#{session_path}')
          printf '%s\n' "$HOME/worktrees/dotfiles/cleanup"
          ;;
        'diffwarden-streaming-moved|#{session_id}')
          printf '%s\n' "\$23"
          ;;
        'diffwarden-streaming-moved|#{pane_current_path}')
          printf '%s\n' "$HOME/worktrees/other/streaming"
          ;;
        'diffwarden-streaming-moved|#{session_path}')
          printf '%s\n' "$HOME/worktrees/diffwarden/streaming"
          ;;
        'diffwarden-streaming-in-dotfiles|#{session_id}')
          printf '%s\n' "\$24"
          ;;
        'diffwarden-streaming-in-dotfiles|#{pane_current_path}')
          printf '%s\n' "$HOME/worktrees/dotfiles/streaming"
          ;;
        'diffwarden-streaming-in-dotfiles|#{session_path}')
          printf '%s\n' "$HOME/worktrees/dotfiles/streaming"
          ;;
        'diffwarden-ticket-123|#{session_id}')
          printf '%s\n' "\$25"
          ;;
        'diffwarden-ticket-123|#{pane_current_path}')
          printf '%s\n' "$HOME/worktrees/dotfiles/ticket-123"
          ;;
        'diffwarden-ticket-123|#{session_path}')
          printf '%s\n' "$HOME/worktrees/dotfiles/ticket-123"
          ;;
        'diffwarden|#{pane_current_path}'|'diffwarden|#{session_path}')
          printf '%s\n' "$HOME/code/diffwarden"
          ;;
        *)
          return 1
          ;;
      esac
      ;;
    show-option)
      if [[ "$4" == "\$18" && "$5" == '@twigsmux_worktree_branch' ]]; then
        printf 'feature/recorded\n'
        return 0
      fi
      if [[ "$4" == "\$27" && "$5" == '@twigsmux_worktree_branch' ]]; then
        printf 'streaming\n'
        return 0
      fi
      if [[ "$4" == "\$21" && "$5" == '@twigsmux_worktree_cwd' ]]; then
        printf '%s\n' "$HOME/code/recorded-diffwarden"
        return 0
      fi
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

git() {
  local cwd=""

  if [[ "${1-}" == "-C" ]]; then
    cwd="$2"
    shift 2
  fi

  if [[ "${1-}" == "worktree" && "${2-}" == "list" && "${3-}" == "--porcelain" ]]; then
    case "$cwd" in
      "$HOME/worktrees/diffwarden/streaming/src"|\
      "$HOME/worktrees/diffwarden/streaming"|\
      "$HOME/worktrees/diffwarden/feature-foo"|\
      "$HOME/code/diffwarden/src"|\
      "$HOME/code/diffwarden")
      printf 'worktree %s\n' "$HOME/code/diffwarden"
      printf 'HEAD abc123\n'
      printf 'branch refs/heads/main\n'
      printf '\n'
      printf 'worktree %s\n' "$HOME/worktrees/diffwarden/streaming"
      printf 'HEAD def456\n'
      printf 'branch refs/heads/streaming\n'
      printf '\n'
      printf 'worktree %s\n' "$HOME/worktrees/diffwarden/feature-foo"
      printf 'HEAD fed789\n'
      printf 'branch refs/heads/feature/foo\n'
      return 0
      ;;
      "$HOME/worktrees/dotfiles/cleanup")
      printf 'worktree %s\n' "$HOME/code/dotfiles"
      printf 'HEAD abc123\n'
      printf 'branch refs/heads/main\n'
      printf '\n'
      printf 'worktree %s\n' "$HOME/worktrees/dotfiles/cleanup"
      printf 'HEAD def456\n'
      printf 'branch refs/heads/cleanup\n'
      return 0
      ;;
      "$HOME/worktrees/dotfiles/streaming")
      printf 'worktree %s\n' "$HOME/code/dotfiles"
      printf 'HEAD abc123\n'
      printf 'branch refs/heads/main\n'
      printf '\n'
      printf 'worktree %s\n' "$HOME/worktrees/dotfiles/streaming"
      printf 'HEAD def456\n'
      printf 'branch refs/heads/streaming\n'
      return 0
      ;;
      "$HOME/worktrees/dotfiles/ticket-123")
      printf 'worktree %s\n' "$HOME/code/dotfiles"
      printf 'HEAD abc123\n'
      printf 'branch refs/heads/main\n'
      printf '\n'
      printf 'worktree %s\n' "$HOME/worktrees/dotfiles/ticket-123"
      printf 'HEAD def456\n'
      printf 'branch refs/heads/ticket-123\n'
      return 0
      ;;
      "$HOME/worktrees/other/streaming")
      printf 'worktree %s\n' "$HOME/code/other"
      printf 'HEAD abc123\n'
      printf 'branch refs/heads/main\n'
      printf '\n'
      printf 'worktree %s\n' "$HOME/worktrees/other/streaming"
      printf 'HEAD def456\n'
      printf 'branch refs/heads/streaming\n'
      return 0
      ;;
    esac
  fi

  return 1
}

# shellcheck source=/dev/null
TWIGSMUX_SOURCE_ONLY=1 source "$ROOT_DIR/zsh/.zshrc.d/scripts/twigsmux.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
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

run_test() {
  local name="$1"

  "$name"
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok %s\n' "$name"
}

test_selected_session_prefers_recorded_branch() {
  assert_eq "$(worktree_target_for_selected_session diffwarden-recorded)" "feature/recorded"
}

test_selected_session_prefers_recorded_cwd() {
  assert_eq "$(worktree_cwd_for_selected_session diffwarden-recorded-cwd)" "$HOME/code/recorded-diffwarden"
}

test_recorded_branch_without_cwd_rejects_drifted_path_cwd() {
  assert_eq "$(worktree_cwd_for_selected_session diffwarden-recorded-drift || true)" ""
}

test_selected_session_uses_worktree_path() {
  assert_eq "$(worktree_target_for_selected_session diffwarden-streaming)" "streaming"
}

test_selected_session_uses_git_branch_for_slashed_worktree_path() {
  assert_eq "$(worktree_target_for_selected_session diffwarden-feature-foo)" "feature/foo"
}

test_unrecorded_slashed_branch_session_is_not_a_path_conflict() {
  if worktree_session_path_conflicts_with_name "diffwarden-feature/foo"; then
    fail "did not expect slashed branch session to conflict with slugged path"
  fi
}

test_unrecorded_slashed_branch_session_uses_git_branch() {
  assert_eq "$(worktree_target_for_selected_session "diffwarden-feature/foo")" "feature/foo"
}

test_selected_session_infers_cwd_from_worktree_path() {
  assert_eq "$(worktree_cwd_for_selected_session diffwarden-streaming)" "$HOME/code/diffwarden"
}

test_selected_session_strips_project_prefix_from_main_checkout_path() {
  assert_eq "$(worktree_target_for_selected_session diffwarden-main-path)" "main-path"
}

test_selected_session_strips_project_prefix_from_main_checkout_subdir() {
  assert_eq "$(worktree_target_for_selected_session diffwarden-src)" "src"
}

test_selected_session_does_not_strip_from_worktrees_project_root() {
  assert_eq "$(worktree_target_for_selected_session diffwarden-worktrees-project-root)" "diffwarden-worktrees-project-root"
}

test_selected_session_path_conflict_keeps_session_name_without_stable_target() {
  assert_eq "$(worktree_target_for_selected_session diffwarden-feature)" "diffwarden-feature"
}

test_selected_session_path_conflict_has_no_cwd() {
  assert_eq "$(worktree_cwd_for_selected_session diffwarden-feature || true)" ""
}

test_selected_session_path_conflict_is_detected() {
  if ! worktree_session_path_conflicts_with_name diffwarden-feature; then
    fail "expected path/name conflict"
  fi
}

test_selected_session_path_disagreement_keeps_session_name() {
  assert_eq "$(worktree_target_for_selected_session diffwarden-streaming-moved)" "diffwarden-streaming-moved"
}

test_selected_session_path_disagreement_has_no_cwd() {
  assert_eq "$(worktree_cwd_for_selected_session diffwarden-streaming-moved || true)" ""
}

test_selected_session_path_disagreement_is_detected() {
  if ! worktree_session_paths_disagree diffwarden-streaming-moved; then
    fail "expected path disagreement"
  fi
}

test_same_slug_cross_project_path_conflict_is_detected() {
  if ! worktree_session_path_conflicts_with_name diffwarden-streaming-in-dotfiles; then
    fail "expected same-slug cross-project conflict"
  fi
}

test_same_slug_cross_project_path_conflict_has_no_cwd() {
  assert_eq "$(worktree_cwd_for_selected_session diffwarden-streaming-in-dotfiles || true)" ""
}

test_legacy_ticket_cross_project_path_conflict_is_detected() {
  if ! worktree_session_path_conflicts_with_name diffwarden-ticket-123; then
    fail "expected legacy ticket cross-project conflict"
  fi
}

test_legacy_ticket_cross_project_path_conflict_has_no_cwd() {
  assert_eq "$(worktree_cwd_for_selected_session diffwarden-ticket-123 || true)" ""
}

test_query_strips_current_project_prefix() {
  assert_eq "$(worktree_target_for_query diffwarden-streaming)" "streaming"
}

test_legacy_ticket_session_still_strips_project() {
  assert_eq "$(worktree_target_for_selected_session foo-bar-123)" "bar-123"
}

run_test test_selected_session_prefers_recorded_branch
run_test test_selected_session_prefers_recorded_cwd
run_test test_recorded_branch_without_cwd_rejects_drifted_path_cwd
run_test test_selected_session_uses_worktree_path
run_test test_selected_session_uses_git_branch_for_slashed_worktree_path
run_test test_unrecorded_slashed_branch_session_is_not_a_path_conflict
run_test test_unrecorded_slashed_branch_session_uses_git_branch
run_test test_selected_session_infers_cwd_from_worktree_path
run_test test_selected_session_strips_project_prefix_from_main_checkout_path
run_test test_selected_session_strips_project_prefix_from_main_checkout_subdir
run_test test_selected_session_does_not_strip_from_worktrees_project_root
run_test test_selected_session_path_conflict_keeps_session_name_without_stable_target
run_test test_selected_session_path_conflict_has_no_cwd
run_test test_selected_session_path_conflict_is_detected
run_test test_selected_session_path_disagreement_keeps_session_name
run_test test_selected_session_path_disagreement_has_no_cwd
run_test test_selected_session_path_disagreement_is_detected
run_test test_same_slug_cross_project_path_conflict_is_detected
run_test test_same_slug_cross_project_path_conflict_has_no_cwd
run_test test_legacy_ticket_cross_project_path_conflict_is_detected
run_test test_legacy_ticket_cross_project_path_conflict_has_no_cwd
run_test test_query_strips_current_project_prefix
run_test test_legacy_ticket_session_still_strips_project

printf 'passed %d tests\n' "$PASS_COUNT"
