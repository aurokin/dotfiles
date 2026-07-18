#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
launcher="$repo_root/zsh/.zshrc.d/scripts/super-claude"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

fake_bin="$tmp_root/bin"
mkdir -p "$fake_bin"
# The single-quoted lines intentionally defer expansion to the generated fake.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "CLAUDE_CONFIG_DIR=%s\n" "${CLAUDE_CONFIG_DIR-<unset>}"' \
  'printf "CLAUDE_CODE_SUBAGENT_MODEL=%s\n" "${CLAUDE_CODE_SUBAGENT_MODEL-<unset>}"' \
  'printf "ARGS="' \
  'for arg in "$@"; do printf "<%s>" "$arg"; done' \
  'printf "\n"' > "$fake_bin/claude"
chmod +x "$fake_bin/claude"

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
  local profile="$1" model="$2"
  mkdir -p "$profile"
  printf '{"model":"%s","availableModels":["%s"]}\n' "$model" "$model" > "$profile/settings.json"
}

run_launcher() {
  local profile="$1"
  shift
  env -u CLAUDE_CODE_SUBAGENT_MODEL \
    PATH="$fake_bin:/usr/bin:/bin" \
    SUPER_CLAUDE_API_KEY="test-token" \
    SUPER_CLAUDE_CONFIG_DIR="$profile" \
    "$launcher" "$@"
}

run_test() {
  local name="$1"
  shift
  "$@"
  pass_count=$((pass_count + 1))
  printf 'PASS: %s\n' "$name"
}

test_first_run_bootstrap() {
  local profile="$tmp_root/bootstrap"
  local output
  output="$(run_launcher "$profile" prompt)"
  assert_contains "$output" 'CLAUDE_CODE_SUBAGENT_MODEL=claude-anthropic-fable-5' 'bootstrap subagent model'
  assert_contains "$output" 'ARGS=<prompt><--model><claude-anthropic-fable-5><--permission-mode><default>' 'bootstrap arguments'
  [[ -f "$profile/settings.json" ]] || fail 'bootstrap settings.json was not created'
  local mode
  if [[ "$(uname -s)" == 'Darwin' ]]; then
    mode="$(stat -f '%Lp' "$profile/settings.json")"
  else
    mode="$(stat -c '%a' "$profile/settings.json")"
  fi
  [[ "$mode" == 600 ]] || fail 'bootstrap settings.json mode is not 600'
}

test_saved_model() {
  local profile="$tmp_root/saved"
  write_settings "$profile" 'claude-codex-gpt-5.6-sol'
  local output
  output="$(run_launcher "$profile" prompt)"
  assert_contains "$output" 'CLAUDE_CODE_SUBAGENT_MODEL=claude-codex-gpt-5.6-sol' 'saved subagent model'
  assert_contains "$output" 'ARGS=<prompt><--model><claude-codex-gpt-5.6-sol><--permission-mode><default>' 'saved arguments'
  assert_not_contains "$output" 'claude-anthropic-fable-5' 'saved model must not reset to Fable'
}

test_explicit_model_pair() {
  local profile="$tmp_root/explicit-pair"
  write_settings "$profile" 'claude-codex-gpt-5.6-sol'
  local output
  output="$(run_launcher "$profile" --model claude-xai-grok-4.5 prompt)"
  assert_contains "$output" 'CLAUDE_CODE_SUBAGENT_MODEL=claude-xai-grok-4.5' 'explicit pair subagent model'
  assert_contains "$output" 'ARGS=<--model><claude-xai-grok-4.5><prompt><--permission-mode><default>' 'explicit pair arguments'
}

test_explicit_model_equals() {
  local profile="$tmp_root/explicit-equals"
  write_settings "$profile" 'claude-codex-gpt-5.6-sol'
  local output
  output="$(run_launcher "$profile" --model=claude-kimi-k3 prompt)"
  assert_contains "$output" 'CLAUDE_CODE_SUBAGENT_MODEL=claude-kimi-k3' 'explicit equals subagent model'
  assert_contains "$output" 'ARGS=<--model=claude-kimi-k3><prompt><--permission-mode><default>' 'explicit equals arguments'
}

test_dedicated_subagent_override() {
  local profile="$tmp_root/subagent-override"
  write_settings "$profile" 'claude-codex-gpt-5.6-sol'
  local output
  output="$(SUPER_CLAUDE_SUBAGENT_MODEL=claude-anthropic-opus-4.8 run_launcher "$profile" prompt)"
  assert_contains "$output" 'CLAUDE_CODE_SUBAGENT_MODEL=claude-anthropic-opus-4.8' 'dedicated subagent override'
  assert_contains "$output" 'ARGS=<prompt><--model><claude-codex-gpt-5.6-sol><--permission-mode><default>' 'dedicated override preserves main model'
}

test_official_subagent_override() {
  local profile="$tmp_root/official-subagent-override"
  write_settings "$profile" 'claude-codex-gpt-5.6-sol'
  local output
  output="$(
    PATH="$fake_bin:/usr/bin:/bin" \
      SUPER_CLAUDE_API_KEY='test-token' \
      SUPER_CLAUDE_CONFIG_DIR="$profile" \
      CLAUDE_CODE_SUBAGENT_MODEL='claude-xai-grok-4.5' \
      "$launcher" prompt
  )"
  assert_contains "$output" 'CLAUDE_CODE_SUBAGENT_MODEL=claude-xai-grok-4.5' 'official subagent override'
  assert_contains "$output" 'ARGS=<prompt><--model><claude-codex-gpt-5.6-sol><--permission-mode><default>' 'official override preserves main model'
}

test_resume_does_not_force_saved_model() {
  local profile="$tmp_root/resume"
  write_settings "$profile" 'claude-codex-gpt-5.6-sol'
  local output
  output="$(run_launcher "$profile" --resume 00000000-0000-0000-0000-000000000000)"
  assert_contains "$output" 'CLAUDE_CODE_SUBAGENT_MODEL=<unset>' 'resume subagent model'
  assert_contains "$output" 'ARGS=<--resume><00000000-0000-0000-0000-000000000000><--permission-mode><default>' 'resume arguments'
  assert_not_contains "$output" '<--model>' 'resume must not force saved model'
}

test_resume_with_explicit_model() {
  local profile="$tmp_root/resume-explicit"
  write_settings "$profile" 'claude-codex-gpt-5.6-sol'
  local output
  output="$(run_launcher "$profile" --resume 00000000-0000-0000-0000-000000000000 --model claude-codex-gpt-5.6-terra)"
  assert_contains "$output" 'CLAUDE_CODE_SUBAGENT_MODEL=claude-codex-gpt-5.6-terra' 'resume explicit subagent model'
  assert_contains "$output" 'ARGS=<--resume><00000000-0000-0000-0000-000000000000><--model><claude-codex-gpt-5.6-terra><--permission-mode><default>' 'resume explicit arguments'
}

test_management_command_has_no_model_override() {
  local profile="$tmp_root/version"
  write_settings "$profile" 'claude-codex-gpt-5.6-sol'
  local output
  output="$(run_launcher "$profile" --dangerously-skip-permissions --version)"
  assert_contains "$output" 'CLAUDE_CODE_SUBAGENT_MODEL=<unset>' 'management subagent model'
  assert_contains "$output" 'ARGS=<--dangerously-skip-permissions><--version>' 'management arguments'
  assert_not_contains "$output" '<--model>' 'management command must not force a model'
}

test_print_prompt_named_like_command_still_gets_model() {
  local profile="$tmp_root/print-command-name"
  write_settings "$profile" 'claude-codex-gpt-5.6-sol'
  local output
  output="$(run_launcher "$profile" -p doctor)"
  assert_contains "$output" 'CLAUDE_CODE_SUBAGENT_MODEL=claude-codex-gpt-5.6-sol' 'print prompt subagent model'
  assert_contains "$output" 'ARGS=<-p><doctor><--model><claude-codex-gpt-5.6-sol><--permission-mode><default>' 'print prompt arguments'
}

run_test 'first-run bootstrap' test_first_run_bootstrap
run_test 'saved model' test_saved_model
run_test 'explicit --model pair' test_explicit_model_pair
run_test 'explicit --model=value' test_explicit_model_equals
run_test 'dedicated subagent override' test_dedicated_subagent_override
run_test 'official subagent override' test_official_subagent_override
run_test 'resume without stale override' test_resume_does_not_force_saved_model
run_test 'resume with explicit model' test_resume_with_explicit_model
run_test 'management command' test_management_command_has_no_model_override
run_test 'print prompt named like command' test_print_prompt_named_like_command_still_gets_model

printf 'All %d Super Claude launcher tests passed.\n' "$pass_count"
