#!/usr/bin/env bash
set -euo pipefail

run_resume() {
  # Prefer interactive zsh so .zshrc loads aliases/functions (including `cc`).
  if command -v zsh >/dev/null 2>&1; then
    exec zsh -ic 'builtin cd -- "$1" && shift && cc --resume "$@"' lcc "$PWD" "$@"
  fi

  # Fallback for environments without zsh.
  if command -v claude >/dev/null 2>&1; then
    exec claude --dangerously-skip-permissions --resume "$@"
  fi

  echo "lcc: unable to run claude (zsh unavailable and command not found)." >&2
  exit 127
}

extract_session_id_from_entry() {
  sed -nE 's/.*"sessionId":"([0-9a-f-]{36})".*/\1/p'
}

extract_project_from_entry() {
  sed -nE 's/.*"project":"([^"]+)".*/\1/p'
}

reverse_file() {
  local file="$1"

  if command -v tac >/dev/null 2>&1; then
    tac "$file"
    return 0
  fi

  if tail -r "$file" >/dev/null 2>&1; then
    tail -r "$file"
    return 0
  fi

  awk '{lines[NR]=$0} END {for (i=NR; i>=1; i--) print lines[i]}' "$file"
}

project_dir_for_cwd() {
  local claude_home="${CLAUDE_HOME:-$HOME/.claude}"
  local current_cwd="$PWD"
  local project_key=""

  project_key="$(printf '%s' "$current_cwd" | sed 's/[^[:alnum:]_-]/-/g')"
  printf '%s/projects/%s\n' "$claude_home" "$project_key"
}

find_session_id_from_history() {
  local claude_home="${CLAUDE_HOME:-$HOME/.claude}"
  local history_file="$claude_home/history.jsonl"
  local current_cwd="$PWD"
  local history_tail_lines="${LCC_HISTORY_TAIL_LINES:-5000}"
  local line=""
  local project=""
  local session_id=""

  [[ -f "$history_file" ]] || return 1

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue

    project="$(printf '%s\n' "$line" | extract_project_from_entry)"
    [[ "$project" == "$current_cwd" ]] || continue

    session_id="$(printf '%s\n' "$line" | extract_session_id_from_entry)"
    [[ -n "$session_id" ]] || continue

    printf '%s\n' "$session_id"
    return 0
  done < <(reverse_file <(tail -n "$history_tail_lines" "$history_file" 2>/dev/null) 2>/dev/null)

  return 1
}

find_session_id_for_cwd() {
  local project_dir=""
  local files=()
  local newest_file=""

  project_dir="$(project_dir_for_cwd)"
  [[ -d "$project_dir" ]] || return 1

  shopt -s nullglob
  files=("$project_dir"/*.jsonl)
  shopt -u nullglob

  [[ ${#files[@]} -gt 0 ]] || return 1

  newest_file="$(ls -t "${files[@]}" 2>/dev/null | head -n 1)"
  [[ -n "$newest_file" ]] || return 1

  basename "$newest_file" .jsonl
}

if [[ "${1-}" == "-h" || "${1-}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  lcc [SESSION_ID|SEARCH_TERM] [PROMPT...]

Behavior:
  - With args: runs `cc --resume "$@"`.
  - Without args: reads Claude history bottom-up for the latest session ID that
    matches the current working directory.
  - If history has no cwd-matching session, uses the newest Claude session
    stored for the current working directory.
  - Falls back to `cc --continue` if no session ID can be resolved.
EOF
  exit 0
fi

if [[ $# -gt 0 ]]; then
  run_resume "$@"
fi

session_id=""
session_id="$(find_session_id_from_history || true)"
if [[ -z "$session_id" ]]; then
  session_id="$(find_session_id_for_cwd || true)"
fi

if [[ -n "$session_id" ]]; then
  run_resume "$session_id"
fi

if command -v zsh >/dev/null 2>&1; then
  exec zsh -ic 'builtin cd -- "$1" && cc --continue' lcc "$PWD"
fi

if command -v claude >/dev/null 2>&1; then
  exec claude --dangerously-skip-permissions --continue
fi

echo "lcc: unable to run claude (zsh unavailable and command not found)." >&2
exit 127
