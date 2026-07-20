#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
menu="$repo_root/zsh/.zshrc.d/scripts/super-claude-menu"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

fake_bin="$tmp_root/bin"
mkdir -p "$fake_bin"

# The single-quoted lines intentionally defer expansion to the generated fake.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'if [[ -n "${FAKE_RUNNER_LOG:-}" ]]; then printf "<%s>" "$@" >> "$FAKE_RUNNER_LOG"; printf "\n" >> "$FAKE_RUNNER_LOG"; fi' \
  'if [[ "${1:-}" == "--version" && -n "${FAKE_BOOTSTRAP_MODEL:-}" ]]; then' \
  '  mkdir -p "$SUPER_CLAUDE_CONFIG_DIR"' \
  '  printf "{\"model\":\"%s\",\"availableModels\":[\"%s\"]}\n" "$FAKE_BOOTSTRAP_MODEL" "$FAKE_BOOTSTRAP_MODEL" > "$SUPER_CLAUDE_CONFIG_DIR/settings.json"' \
  '  exit 0' \
  'fi' \
  'printf "RUNNER_SUBAGENT=%s\n" "${SUPER_CLAUDE_SUBAGENT_MODEL-<unset>}"' \
  'printf "RUNNER_ARGS="' \
  'for arg in "$@"; do printf "<%s>" "$arg"; done' \
  'printf "\n"' > "$fake_bin/super-claude"
chmod 755 "$fake_bin/super-claude"

# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'input="$(cat)"' \
  'if [[ -n "${FZF_CAPTURE:-}" ]]; then printf "%s\n" "$input" > "$FZF_CAPTURE"; fi' \
  'if [[ "${FZF_CANCEL:-0}" == 1 ]]; then exit 130; fi' \
  'while IFS= read -r line; do' \
  '  if [[ "$line" == *"${FZF_SELECT:-}"* ]]; then printf "%s\n" "$line"; exit 0; fi' \
  'done <<< "$input"' \
  'exit 1' > "$fake_bin/fzf"
chmod 755 "$fake_bin/fzf"

pass_count=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local output="$1" expected="$2" label="$3"
  [[ "$output" == *"$expected"* ]] || fail "$label: expected [$expected] in output:\n$output"
}

assert_not_contains() {
  local output="$1" unexpected="$2" label="$3"
  [[ "$output" != *"$unexpected"* ]] || fail "$label: unexpected [$unexpected] in output:\n$output"
}

write_settings() {
  local profile="$1"
  shift
  local saved="$1"
  shift
  mkdir -p "$profile"
  {
    printf '{"model":"%s","availableModels":[' "$saved"
    local first=1 model
    for model in "$@"; do
      if [[ "$first" == 0 ]]; then printf ','; fi
      printf '"%s"' "$model"
      first=0
    done
    printf ']}\n'
  } > "$profile/settings.json"
}

standard_settings() {
  local profile="$1"
  write_settings "$profile" 'claude-codex-gpt-5.6-sol' \
    'claude-anthropic-fable-5' \
    'claude-anthropic-opus-4.8' \
    'claude-anthropic-sonnet-5' \
    'claude-codex-gpt-5.6-sol' \
    'claude-codex-gpt-5.6-terra' \
    'claude-codex-gpt-5.6-luna' \
    'claude-xai-grok-4.5' \
    'claude-kimi-k3' \
    'claude-opencode-glm-5.2'
}

file_mode() {
  if [[ "$(uname -s)" == 'Darwin' ]]; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

run_menu() {
  local profile="$1"
  shift
  PATH="$fake_bin:/usr/bin:/bin" \
    SUPER_CLAUDE_CONFIG_DIR="$profile" \
    SUPER_CLAUDE_RUNNER_PATH="$fake_bin/super-claude" \
    "$menu" "$@"
}

run_test() {
  local name="$1"
  shift
  "$@"
  pass_count=$((pass_count + 1))
  printf 'PASS: %s\n' "$name"
}

test_friendly_selection_and_passthrough() {
  local profile="$tmp_root/friendly" capture="$tmp_root/friendly-fzf"
  standard_settings "$profile"
  local output
  output="$(FZF_SELECT='Kimi / K3' FZF_CAPTURE="$capture" run_menu "$profile" --dangerously-skip-permissions --continue)"
  assert_contains "$output" 'RUNNER_SUBAGENT=claude-kimi-k3' 'selected subagent environment'
  assert_contains "$output" 'RUNNER_ARGS=<--dangerously-skip-permissions><--continue><--model><claude-kimi-k3>' 'selected runner arguments'
  [[ "$(<"$profile/subagent-model")" == 'claude-kimi-k3' ]] || fail 'selected subagent preference was not persisted'
  [[ "$(file_mode "$profile/subagent-model")" == 600 ]] || fail 'selected subagent preference mode is not 600'
  [[ "$(jq -r .model "$profile/settings.json")" == 'claude-codex-gpt-5.6-sol' ]] || fail 'menu rewrote the saved main model'
  local rows
  rows="$(<"$capture")"
  assert_contains "$rows" $'Codex / GPT-5.6 Sol  [saved default]\tclaude-codex-gpt-5.6-sol' 'saved default first row'
  assert_contains "$rows" $'Kimi / K3\tclaude-kimi-k3' 'friendly Kimi row'
}

test_unknown_model_uses_raw_id() {
  local profile="$tmp_root/unknown"
  write_settings "$profile" 'claude-future-model' 'claude-future-model'
  local output
  output="$(FZF_SELECT='claude-future-model' run_menu "$profile")"
  assert_contains "$output" 'RUNNER_SUBAGENT=claude-future-model' 'unknown subagent environment'
  assert_contains "$output" 'RUNNER_ARGS=<--model><claude-future-model>' 'unknown model selection'
  [[ "$(<"$profile/subagent-model")" == 'claude-future-model' ]] || fail 'unknown model preference was not persisted'
}

test_family_shorthand_marks_saved_default() {
  local profile="$tmp_root/family-shorthand" capture="$tmp_root/family-shorthand-fzf"
  write_settings "$profile" 'fable' \
    'claude-anthropic-fable-5' \
    'claude-codex-gpt-5.6-sol'
  local output rows
  output="$(FZF_SELECT='Anthropic / Fable 5' FZF_CAPTURE="$capture" run_menu "$profile")"
  rows="$(<"$capture")"
  assert_contains "$rows" $'Anthropic / Fable 5  [saved default]\tclaude-anthropic-fable-5' 'family shorthand saved row'
  assert_contains "$output" 'RUNNER_SUBAGENT=claude-anthropic-fable-5' 'family shorthand selected child'
  [[ "$(jq -r .model "$profile/settings.json")" == 'fable' ]] || fail 'family shorthand main default was rewritten'
}

test_explicit_model_bypasses_menu() {
  local profile="$tmp_root/explicit" capture="$tmp_root/explicit-fzf"
  standard_settings "$profile"
  printf '%s\n' 'claude-codex-gpt-5.6-sol' > "$profile/subagent-model"
  chmod 600 "$profile/subagent-model"
  local output
  output="$(FZF_CAPTURE="$capture" run_menu "$profile" --model claude-xai-grok-4.5 -p hello)"
  assert_contains "$output" 'RUNNER_SUBAGENT=<unset>' 'explicit bypass environment'
  assert_contains "$output" 'RUNNER_ARGS=<--model><claude-xai-grok-4.5><-p><hello>' 'explicit model passthrough'
  [[ ! -e "$capture" ]] || fail 'explicit model unexpectedly opened fzf'
  [[ "$(<"$profile/subagent-model")" == 'claude-codex-gpt-5.6-sol' ]] || fail 'explicit bypass changed sticky preference'
}

test_cancel_launches_nothing() {
  local profile="$tmp_root/cancel" log="$tmp_root/cancel-runner"
  standard_settings "$profile"
  printf '%s\n' 'claude-codex-gpt-5.6-sol' > "$profile/subagent-model"
  chmod 600 "$profile/subagent-model"
  local status
  set +e
  FZF_CANCEL=1 FAKE_RUNNER_LOG="$log" run_menu "$profile" >/dev/null 2>&1
  status=$?
  set -e
  [[ "$status" == 130 ]] || fail "cancel returned $status instead of 130"
  [[ ! -s "$log" ]] || fail 'cancel invoked the runner'
  [[ "$(<"$profile/subagent-model")" == 'claude-codex-gpt-5.6-sol' ]] || fail 'cancel changed sticky preference'
}

test_numbered_fallback() {
  local profile="$tmp_root/fallback"
  standard_settings "$profile"
  local output
  output="$(
    printf '2\n' | PATH='/usr/bin:/bin' \
      SUPER_CLAUDE_CONFIG_DIR="$profile" \
      SUPER_CLAUDE_RUNNER_PATH="$fake_bin/super-claude" \
      "$menu" --dangerously-skip-permissions 2>/dev/null
  )"
  assert_contains "$output" 'RUNNER_SUBAGENT=claude-anthropic-fable-5' 'numbered fallback subagent environment'
  assert_contains "$output" 'RUNNER_ARGS=<--dangerously-skip-permissions><--model><claude-anthropic-fable-5>' 'numbered fallback selection'
  [[ "$(<"$profile/subagent-model")" == 'claude-anthropic-fable-5' ]] || fail 'numbered fallback preference was not persisted'
}

test_missing_profile_bootstraps_through_runner() {
  local profile="$tmp_root/bootstrap"
  local output
  output="$(FAKE_BOOTSTRAP_MODEL='claude-anthropic-opus-4.8' FZF_SELECT='Anthropic / Opus 4.8' run_menu "$profile")"
  assert_contains "$output" 'RUNNER_SUBAGENT=claude-anthropic-opus-4.8' 'bootstrap subagent environment'
  assert_contains "$output" 'RUNNER_ARGS=<--model><claude-anthropic-opus-4.8>' 'bootstrap selection'
  [[ -f "$profile/settings.json" ]] || fail 'menu did not bootstrap missing profile settings'
  [[ "$(<"$profile/subagent-model")" == 'claude-anthropic-opus-4.8' ]] || fail 'bootstrap preference was not persisted'
}

test_clear_sticky_entry_removes_preference() {
  local profile="$tmp_root/clear-sticky" capture="$tmp_root/clear-sticky-fzf"
  standard_settings "$profile"
  printf '%s\n' 'claude-kimi-k3' > "$profile/subagent-model"
  chmod 600 "$profile/subagent-model"
  local output rows
  output="$(FZF_SELECT='Clear sticky' FZF_CAPTURE="$capture" run_menu "$profile" --continue)"
  rows="$(<"$capture")"
  assert_contains "$rows" $'Clear sticky subagent model  [Kimi / K3]\t[clear-sticky]' 'clear sticky row'
  assert_contains "$output" 'RUNNER_SUBAGENT=<unset>' 'clear left subagent environment unset'
  assert_contains "$output" 'RUNNER_ARGS=<--continue>' 'clear launched without forced model'
  assert_not_contains "$output" '--model' 'clear appended a model argument'
  [[ ! -e "$profile/subagent-model" ]] || fail 'clear did not remove sticky preference'
}

test_no_clear_entry_without_sticky() {
  local profile="$tmp_root/no-clear" capture="$tmp_root/no-clear-fzf"
  standard_settings "$profile"
  FZF_SELECT='Kimi / K3' FZF_CAPTURE="$capture" run_menu "$profile" >/dev/null
  local rows
  rows="$(<"$capture")"
  assert_not_contains "$rows" 'Clear sticky subagent model' 'clear entry offered without sticky file'
}

test_help_is_local_and_does_not_launch() {
  local profile="$tmp_root/help" log="$tmp_root/help-runner"
  standard_settings "$profile"
  local output
  output="$(FAKE_RUNNER_LOG="$log" run_menu "$profile" --help)"
  assert_contains "$output" 'Usage: super-claude-menu' 'local help'
  [[ ! -s "$log" ]] || fail 'help invoked the runner'
}

run_test 'friendly selection and passthrough' test_friendly_selection_and_passthrough
run_test 'unknown model raw ID' test_unknown_model_uses_raw_id
run_test 'family shorthand saved default' test_family_shorthand_marks_saved_default
run_test 'explicit model bypass' test_explicit_model_bypasses_menu
run_test 'cancel launches nothing' test_cancel_launches_nothing
run_test 'numbered fallback' test_numbered_fallback
run_test 'missing profile bootstrap' test_missing_profile_bootstraps_through_runner
run_test 'clear sticky entry' test_clear_sticky_entry_removes_preference
run_test 'no clear entry without sticky' test_no_clear_entry_without_sticky
run_test 'local help' test_help_is_local_and_does_not_launch

printf 'All %d Super Claude menu tests passed.\n' "$pass_count"
