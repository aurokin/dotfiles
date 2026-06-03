#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(
  cd "$(dirname "${0}")/.." 2>/dev/null
  pwd -P
)"

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/wtrt-tests.XXXXXX")"
TEST_ROOT="$(
  cd "$TEST_ROOT" 2>/dev/null
  pwd -P
)"
PASS_COUNT=0
WT_LOG="$TEST_ROOT/wt.log"
TMUX_LOG="$TEST_ROOT/tmux.log"

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT INT TERM

mkdir -p "$TEST_ROOT/repo"

wt() {
  printf 'pwd=%s args=%s\n' "$PWD" "$*" >>"$WT_LOG"
}

tmux() {
  case "$1" in
    list-sessions)
      printf 'current\n'
      printf 'other-streaming\n'
      printf 'diffwarden-streaming\n'
      return 0
      ;;
    display-message)
      printf 'current\n'
      return 0
      ;;
    kill-session)
      if [[ "${WTRT_FAIL_KILL:-0}" == "1" ]]; then
        return 1
      fi
      printf '%s\n' "$*" >>"$TMUX_LOG"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# shellcheck source=/dev/null
source "$ROOT_DIR/zsh/.zshrc.d/scripts/wtrt.zsh"

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

  : >"$WT_LOG"
  : >"$TMUX_LOG"
  "$name"
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok %s\n' "$name"
}

test_wtrt_keeps_existing_call_shape() {
  wtrt streaming
  assert_eq "$(cat "$WT_LOG")" "pwd=$PWD args=remove --force-delete streaming"
}

test_wtrt_runs_remove_from_cwd() {
  wtrt --cwd "$TEST_ROOT/repo" streaming
  assert_eq "$(cat "$WT_LOG")" "pwd=$TEST_ROOT/repo args=remove --force-delete streaming"
}

test_wtrt_rejects_missing_cwd_argument() {
  if wtrt --cwd >/dev/null 2>&1; then
    fail "expected missing --cwd argument to fail"
  fi
}

test_wtrt_accepts_option_terminator() {
  wtrt -- streaming
  assert_eq "$(cat "$WT_LOG")" "pwd=$PWD args=remove --force-delete streaming"
}

test_wtrt_accepts_option_terminator_after_cwd() {
  wtrt --cwd "$TEST_ROOT/repo" -- streaming
  assert_eq "$(cat "$WT_LOG")" "pwd=$TEST_ROOT/repo args=remove --force-delete streaming"
}

test_wtrt_kills_explicit_session_only() {
  wtrt --cwd "$TEST_ROOT/repo" --session diffwarden-streaming streaming
  assert_eq "$(cat "$TMUX_LOG")" "kill-session -t =diffwarden-streaming"
}

test_wtrt_does_not_kill_current_explicit_session() {
  wtrt --session current streaming
  assert_eq "$(cat "$TMUX_LOG")" ""
}

test_wtrt_propagates_explicit_session_kill_failure() {
  if WTRT_FAIL_KILL=1 wtrt --session diffwarden-streaming streaming >/dev/null 2>&1; then
    fail "expected explicit session kill failure to propagate"
  fi
}

run_test test_wtrt_keeps_existing_call_shape
run_test test_wtrt_runs_remove_from_cwd
run_test test_wtrt_rejects_missing_cwd_argument
run_test test_wtrt_accepts_option_terminator
run_test test_wtrt_accepts_option_terminator_after_cwd
run_test test_wtrt_kills_explicit_session_only
run_test test_wtrt_does_not_kill_current_explicit_session
run_test test_wtrt_propagates_explicit_session_kill_failure

printf 'passed %d tests\n' "$PASS_COUNT"
