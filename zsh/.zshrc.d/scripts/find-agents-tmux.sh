#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux is not installed or not on PATH."
  exit 1
fi

if ! tmux list-sessions >/dev/null 2>&1; then
  echo "No tmux sessions found."
  exit 0
fi

providers_raw="${TMUX_AGENTS_PROVIDERS:-opencode,gemini,codex,claude}"
providers_raw="${providers_raw//,/ }"
providers=()
old_ifs="$IFS"
IFS=' '
read -r -a providers <<< "$providers_raw"
IFS="$old_ifs"

declare -A provider_pattern
declare -A provider_cmd
declare -A provider_sample_regex
provider_pattern[opencode]="opencode"
provider_cmd[opencode]="opencode"
provider_sample_regex[opencode]="esc interrupt"
provider_pattern[gemini]="gemini"
provider_cmd[gemini]="gemini"
provider_sample_regex[gemini]="esc to cancel"
provider_pattern[codex]="codex"
provider_cmd[codex]="codex"
provider_sample_regex[codex]="esc to cancel|esc to interrupt|esc to stop"
provider_pattern[claude]="claude"
provider_cmd[claude]="claude"
provider_sample_regex[claude]="esc to cancel|esc to interrupt|esc to stop|esc interrupt"

join_with_delim() {
  local delim="$1"
  shift
  local out=""
  local item
  for item in "$@"; do
    [[ -z "$item" ]] && continue
    if [[ -z "$out" ]]; then
      out="$item"
    else
      out+="$delim$item"
    fi
  done
  printf '%s' "$out"
}

build_patterns=()
build_allowlist=()
build_sample_regexes=()
for provider in "${providers[@]}"; do
  [[ -z "$provider" ]] && continue
  pattern_item="${provider_pattern[$provider]-$provider}"
  cmd_item="${provider_cmd[$provider]-$provider}"
  sample_item="${provider_sample_regex[$provider]-}"
  [[ -n "$pattern_item" ]] && build_patterns+=("$pattern_item")
  [[ -n "$cmd_item" ]] && build_allowlist+=("$cmd_item")
  [[ -n "$sample_item" ]] && build_sample_regexes+=("$sample_item")
done

pattern_default="$(join_with_delim '|' "${build_patterns[@]}")"
cmd_allowlist_default="$(join_with_delim ',' "${build_allowlist[@]}")"
sample_regex_default="$(join_with_delim '|' "${build_sample_regexes[@]}")"

if [[ -z "$pattern_default" ]]; then
  pattern_default="opencode|gemini|codex|claude"
fi
if [[ -z "$cmd_allowlist_default" ]]; then
  cmd_allowlist_default="opencode,gemini,codex,claude"
fi
if [[ -z "$sample_regex_default" ]]; then
  sample_regex_default="esc interrupt|esc to cancel|esc to interrupt|esc to stop"
fi

pattern="${TMUX_AGENTS_PATTERN:-$pattern_default}"
sample_lines="${TMUX_AGENTS_SAMPLE_LINES:-120}"
sample_regex="${TMUX_AGENTS_SAMPLE_REGEX:-$sample_regex_default}"
cmd_allowlist="${TMUX_AGENTS_CMD_ALLOWLIST:-$cmd_allowlist_default}"
allowlist_items=()
allowlist_ifs="$IFS"
IFS=','
read -r -a allowlist_items <<< "$cmd_allowlist"
IFS="$allowlist_ifs"
script_basename="$(basename "$0")"
script_path="$0"
json_output=0
debug=0
deep=0

usage() {
  cat <<'USAGE'
Usage: find-agents-tmux.sh [--json] [--debug] [--deep]

Environment:
  TMUX_AGENTS_PROVIDERS       Comma or space-separated list (default: "opencode,gemini,codex,claude")
  TMUX_AGENTS_PATTERN         Regex to identify agent panes (default: "opencode|gemini|codex|claude")
  TMUX_AGENTS_SAMPLE_LINES    Lines to sample from pane (default: 120)
  TMUX_AGENTS_SAMPLE_REGEX    Regex to detect "building" state (default: "esc interrupt|esc to cancel|esc to interrupt|esc to stop")
  TMUX_AGENTS_CMD_ALLOWLIST   Command allowlist (default: "opencode,gemini,codex,claude")
Flags:
  --deep  Run slower process scans (child/tty) for better detection
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) json_output=1 ;;
    --debug) debug=1 ;;
    --deep) deep=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
  shift
done
found=0
json_first=1
want_details=0
if ((json_output || debug)); then
  want_details=1
fi

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

json_field() {
  printf '"%s":"%s",' "$1" "$(json_escape "$2")"
}

json_field_raw() {
  printf '"%s":%s,' "$1" "$2"
}

json_array() {
  local out="["
  local first=1
  for item in "$@"; do
    if ((first)); then first=0; else out+=", "; fi
    out+="\"$(json_escape "$item")\""
  done
  out+="]"
  printf '%s' "$out"
}

has_allowed_cmd() {
  local cmd="$1"
  [[ -z "$cmd" ]] && return 1
  local item
  for item in "${allowlist_items[@]}"; do
    [[ -z "$item" ]] && continue
    if [[ "$cmd" == "$item" ]]; then
      return 0
    fi
  done
  return 1
}

line_has_allowed_cmd() {
  local line="$1"
  [[ -z "$line" ]] && return 1
  local cmd_token="${line#* }"
  cmd_token="${cmd_token%% *}"
  local cmd_base="${cmd_token##*/}"
  has_allowed_cmd "$cmd_token" || has_allowed_cmd "$cmd_base"
}

line_matches_pattern() {
  local line="$1"
  [[ -z "$line" ]] && return 1
  [[ "$line" =~ $pattern ]]
}

is_self_line() {
  local line="$1"
  [[ -z "$line" ]] && return 1
  [[ "$line" == *"$script_basename"* || "$line" == *"$script_path"* ]]
}

rg_available=0
if command -v rg >/dev/null 2>&1; then
  rg_available=1
fi

declare -A pid_comm
declare -A pid_cmdline
declare -A ppid_children
declare -A tty_process_map

while IFS=$' \t' read -r pid ppid tty comm cmdline; do
  [[ -z "$pid" ]] && continue

  pid_comm["$pid"]="$comm"
  pid_cmdline["$pid"]="$cmdline"

  proc_line="$pid ${cmdline:-$comm}"

  if ((deep == 1)) && [[ -n "$ppid" ]]; then
    if [[ -n "${ppid_children[$ppid]+x}" ]]; then
      ppid_children["$ppid"]+=$'\n'"$proc_line"
    else
      ppid_children["$ppid"]="$proc_line"
    fi
  fi

  if [[ -n "$tty" ]]; then
    if [[ -n "${tty_process_map[$tty]+x}" ]]; then
      tty_process_map["$tty"]+=$'\n'"$proc_line"
    else
      tty_process_map["$tty"]="$proc_line"
    fi
  fi
done < <(ps -axo pid=,ppid=,tty=,comm=,command= 2>/dev/null || true)

pane_lines="$(tmux list-panes -a -F $'#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_id}\t#{pane_pid}\t#{pane_current_command}\t#{pane_title}\t#{pane_tty}' 2>/dev/null || true)"
if [[ -z "$pane_lines" ]]; then
  echo "No tmux panes found."
  exit 0
fi

while IFS=$'\t' read -r session win_idx pane_idx pane_id pane_pid pane_cmd pane_title pane_tty; do
  pane_matched=0
  pane_sample_matched=0
  if ((want_details)); then
    matches=()
    child_processes=()
    tty_matches=()
  fi

    if has_allowed_cmd "$pane_cmd"; then
      pane_matched=1
      if ((want_details)); then
        matches+=("current_command: $pane_cmd")
      fi
    fi

    proc_name="${pid_comm[$pane_pid]-}"
    proc_cmdline="${pid_cmdline[$pane_pid]-}"
    if has_allowed_cmd "$proc_name"; then
      pane_matched=1
      if ((want_details)); then
        matches+=("pane_process: $proc_name")
      fi
    fi
    if [[ -n "$proc_cmdline" ]] && [[ "$proc_cmdline" =~ $pattern ]]; then
      pane_matched=1
      if ((want_details)); then
        matches+=("pane_cmdline: $proc_cmdline")
      fi
    fi

    if ((deep == 1)); then
      child_blob="${ppid_children[$pane_pid]-}"
      if [[ -n "$child_blob" ]]; then
        while IFS= read -r line; do
          if ! is_self_line "$line" && { line_has_allowed_cmd "$line" || line_matches_pattern "$line"; }; then
            pane_matched=1
            if ((want_details)); then
              child_processes+=("$line")
            fi
          fi
        done <<< "$child_blob"
      fi
    fi

    if ! ((pane_matched == 1 && deep == 0)); then
      tty_short="${pane_tty#/dev/}"
      if [[ -n "$tty_short" ]]; then
        tty_blob="${tty_process_map[$tty_short]-}"
        if [[ -n "$tty_blob" ]]; then
          while IFS= read -r line; do
            if is_self_line "$line"; then
              continue
            fi
            if line_matches_pattern "$line" || { ((deep == 1)) && line_has_allowed_cmd "$line"; }; then
              pane_matched=1
              if ((want_details)); then
                tty_matches+=("$line")
              fi
            fi
          done <<< "$tty_blob"
        fi
      fi
    fi

    if ((want_details)); then
      for line in "${child_processes[@]}"; do
        matches+=("child_process: $line")
      done
      for line in "${tty_matches[@]}"; do
        matches+=("tty_process: $line")
      done
    fi

    if ((pane_matched == 1)) && [[ "$pane_id" == %* ]]; then
      pane_sample="$(tmux capture-pane -p -t "$pane_id" -S "-$sample_lines" 2>/dev/null || true)"
      if [[ -n "$pane_sample" ]]; then
        if ((rg_available)); then
          if echo "$pane_sample" | rg -q -i -m 1 -e "$sample_regex" >/dev/null 2>&1; then
            pane_sample_matched=1
            if ((want_details)); then
              matches+=("pane_sample: matched /$sample_regex/ in last ${sample_lines} lines")
            fi
          fi
        else
          if echo "$pane_sample" | grep -q -i -m 1 -E "$sample_regex" >/dev/null 2>&1; then
            pane_sample_matched=1
            if ((want_details)); then
              matches+=("pane_sample: matched /$sample_regex/ in last ${sample_lines} lines")
            fi
          fi
        fi
      fi
    fi

  if ((pane_matched == 1)); then
    found=1
    building_emoji="🟢"
    building_bool="false"
    if ((pane_sample_matched == 1)); then
      building_label="Building"
      building_emoji="🟡"
      building_bool="true"
    fi

    display_title="$pane_title"
    if [[ "$display_title" == OC\ \|\ * ]]; then
      display_title="${display_title#OC | }"
    fi

    is_claude_pane=0
    if [[ "$pane_cmd" == "claude" || "$proc_name" == "claude" ]]; then
      is_claude_pane=1
    fi
    if ((is_claude_pane == 1)); then
      if [[ "$display_title" == Claude\ Code\ \|\ * ]]; then
        display_title="${display_title#Claude Code | }"
      elif [[ "$display_title" == Claude\ \|\ * ]]; then
        display_title="${display_title#Claude | }"
      fi
      if [[ "$display_title" =~ ^[^[:alnum:]]+[[:space:]]+(.+)$ ]]; then
        display_title="${BASH_REMATCH[1]}"
      fi
    fi

    if ((json_output)); then
      if ((json_first)); then
        json_first=0
        printf '['
      else
        printf ','
      fi
      printf '{'
      json_field "session" "$session"
      json_field_raw "window_index" "$(json_escape "$win_idx")"
      json_field_raw "pane_index" "$(json_escape "$pane_idx")"
      json_field "pane_id" "$pane_id"
      json_field_raw "pane_pid" "$(json_escape "$pane_pid")"
      json_field "pane_tty" "$pane_tty"
      json_field "pane_title" "$pane_title"
      json_field "pane_title_display" "$display_title"
      json_field "pane_current_command" "$pane_cmd"
      json_field "pane_process" "$proc_name"
      json_field "pane_cmdline" "$proc_cmdline"
      json_field "pattern" "$pattern"
      json_field_raw "sample_lines" "$(json_escape "$sample_lines")"
      json_field "sample_regex" "$sample_regex"
      json_field_raw "building" "$building_bool"
      json_field_raw "matches" "$(json_array "${matches[@]}")"
      json_field_raw "child_processes" "$(json_array "${child_processes[@]}")"
      printf '"tty_processes":%s' "$(json_array "${tty_matches[@]}")"
      printf '}'
    else
      printf '%s %s:%s.%s - %s\n' "$building_emoji" "$session" "$win_idx" "$pane_idx" "$display_title"
      if ((debug)); then
        printf '  pid=%s tty=%s title=%q\n' "$pane_pid" "$pane_tty" "$pane_title"
        for m in "${matches[@]}"; do
          printf '  %s\n' "$m"
        done
      fi
    fi
  fi
done <<< "$pane_lines"

if ((json_output)); then
  if ((json_first)); then
    printf '[]'
  else
    printf ']'
  fi
  printf '\n'
elif ((found == 0)); then
  echo "No agent instances found in tmux panes."
fi
