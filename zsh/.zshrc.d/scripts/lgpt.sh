#!/usr/bin/env bash
set -euo pipefail

run_resume() {
  # Prefer interactive zsh so .zshrc loads aliases/functions (including `gpt`).
  if command -v zsh >/dev/null 2>&1; then
    exec zsh -ic 'builtin cd -- "$1" && shift && gpt resume "$@"' lgpt "$PWD" "$@"
  fi

  # Fallback for environments without zsh.
  if command -v gpt >/dev/null 2>&1; then
    exec gpt resume "$@"
  fi
  if command -v codex >/dev/null 2>&1; then
    exec codex --dangerously-bypass-approvals-and-sandbox resume "$@"
  fi

  echo "lgpt: unable to run gpt/codex (zsh unavailable and commands not found)." >&2
  exit 127
}

extract_session_id_from_meta() {
  sed -nE 's/.*"id":"([0-9a-f-]{36})".*/\1/p'
}

extract_cwd_from_meta() {
  sed -nE 's/.*"cwd":"([^"]+)".*/\1/p'
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

session_file_for_id() {
  local id="$1"
  local codex_home="${CODEX_HOME:-$HOME/.codex}"
  local sessions_dir="$codex_home/sessions"

  [[ -d "$sessions_dir" ]] || return 1
  find "$sessions_dir" -type f -name "*$id*.jsonl" -print -quit 2>/dev/null
}

session_cwd_for_id() {
  local id="$1"
  local file=""
  local meta=""

  file="$(session_file_for_id "$id" || true)"
  [[ -n "$file" ]] || return 1

  meta="$(head -n 1 "$file" 2>/dev/null || true)"
  [[ -n "$meta" ]] || return 1

  printf '%s\n' "$meta" | extract_cwd_from_meta
}

find_session_id_from_history() {
  local current_cwd="$PWD"
  local history_tail_lines="${LGPT_HISTORY_TAIL_LINES:-3000}"
  local history_files=()
  local file=""
  local id=""
  local id_cwd=""

  if [[ -n "${HISTFILE-}" && -f "$HISTFILE" ]]; then
    history_files+=("$HISTFILE")
  fi
  [[ -f "$HOME/.zsh_history" ]] && history_files+=("$HOME/.zsh_history")
  [[ -f "$HOME/.bash_history" ]] && history_files+=("$HOME/.bash_history")

  [[ ${#history_files[@]} -gt 0 ]] || return 1

  while IFS= read -r file; do
    [[ -f "$file" ]] || continue

    while IFS= read -r id; do
      [[ -n "$id" ]] || continue

      # Keep directory affinity: only accept IDs whose session cwd matches current cwd.
      id_cwd="$(session_cwd_for_id "$id" || true)"
      [[ -n "$id_cwd" ]] || continue
      [[ "$id_cwd" == "$current_cwd" ]] || continue

      printf '%s\n' "$id"
      return 0
    done < <(
      reverse_file <(tail -n "$history_tail_lines" "$file" 2>/dev/null) 2>/dev/null \
        | grep -oE '(codex|gpt)[[:space:]]+resume[[:space:]]+[0-9a-f-]{36}' \
        | awk '{print $3}'
    )
  done < <(printf '%s\n' "${history_files[@]}" | awk '!seen[$0]++')

  return 1
}

find_session_id_for_cwd() {
  local codex_home="${CODEX_HOME:-$HOME/.codex}"
  local sessions_dir="$codex_home/sessions"
  local current_cwd="$PWD"
  local file=""
  local meta=""
  local id=""
  local id_cwd=""

  [[ -d "$sessions_dir" ]] || return 1

  while IFS= read -r file; do
    [[ -f "$file" ]] || continue

    meta="$(head -n 1 "$file" 2>/dev/null || true)"
    [[ -n "$meta" ]] || continue

    id="$(printf '%s\n' "$meta" | extract_session_id_from_meta)"
    id_cwd="$(printf '%s\n' "$meta" | extract_cwd_from_meta)"

    [[ -n "$id" ]] || continue
    [[ "$id_cwd" == "$current_cwd" ]] || continue

    printf '%s\n' "$id"
    return 0
  done < <(
    find "$sessions_dir" -type f -name '*.jsonl' -printf '%T@\t%p\n' 2>/dev/null \
      | sort -nr \
      | cut -f2-
  )

  return 1
}

if [[ "${1-}" == "-h" || "${1-}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  lgpt [SESSION_ID] [PROMPT...]

Behavior:
  - With args: runs `gpt resume "$@"`.
  - Without args: reads shell history bottom-up for the latest resume ID that
    matches the current working directory.
  - If history has no cwd-matching ID, uses the newest Codex session for the
    current working directory.
  - Falls back to `gpt resume --last` if no ID can be resolved.
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

run_resume --last
