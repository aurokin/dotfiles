#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(
  cd "$(dirname "${(%):-%x}")/.." 2>/dev/null
  pwd -P
)"

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/wtct-tests.XXXXXX")"
TEST_ROOT="$(
  cd "$TEST_ROOT" 2>/dev/null
  pwd -P
)"

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT INT TERM

export HOME="$TEST_ROOT/home"
export TMUX="test-socket,1,1"
export WTCT_CAPTURE="$TEST_ROOT/scaffold-args"

mkdir -p "$HOME/.zshrc.d/scripts" "$TEST_ROOT/worktree"

cat >"$HOME/.zshrc.d/scripts/tmux-workspace.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$WTCT_CAPTURE"
EOF
chmod +x "$HOME/.zshrc.d/scripts/tmux-workspace.sh"

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

tmux() {
  case "$1" in
    display-message)
      local format="${argv[-1]}"
      case "$format" in
        '#S')
          printf '%s\n' "repo"
          ;;
        '#{pane_id}')
          printf '%s\n' "%1"
          ;;
        '#{client_tty}')
          printf '\n'
          ;;
        *)
          return 1
          ;;
      esac
      ;;
    list-windows)
      printf '%s\n' "@4|ai"
      ;;
    select-window|switch-client)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

wt() {
  [[ "$1" == "switch" ]] || fail "unexpected wt subcommand: $1"
  [[ "$2" == "--create" ]] || fail "expected wt --create"
  [[ "$3" == "--base=@" ]] || fail "expected wt --base=@"
  [[ "$4" == "feature/foo" ]] || fail "expected branch feature/foo"

  builtin cd -- "$TEST_ROOT/worktree"
}

source "$ROOT_DIR/zsh/.zshrc.d/scripts/wtct.zsh"

wtct --branch feature/foo --select-window ai

assert_eq "$(sed -n '1p' "$WTCT_CAPTURE")" "scaffold"
assert_eq "$(sed -n '3p' "$WTCT_CAPTURE")" "%1"
assert_eq "$(sed -n '4p' "$WTCT_CAPTURE")" "$TEST_ROOT/worktree"

printf 'passed wtct scaffold cwd test\n'
