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

pattern="${OPENCODE_PATTERN:-opencode}"
sample_lines="${OPENCODE_SAMPLE_LINES:-120}"
sample_regex="${OPENCODE_SAMPLE_REGEX:-esc interrupt}"
json_output=0
debug=0
deep=0

usage() {
  cat <<'USAGE'
Usage: find-opencode-tmux.sh [--json] [--debug] [--deep]

Environment:
  OPENCODE_PATTERN       Pattern to identify opencode panes (default: "opencode")
  OPENCODE_SAMPLE_LINES  Lines to sample from pane (default: 120)
  OPENCODE_SAMPLE_REGEX  Regex to detect "building" state (default: "esc interrupt")
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

rg_available=0
if command -v rg >/dev/null 2>&1; then
  rg_available=1
fi

declare -A pid_comm
declare -A pid_cmdline
declare -A ppid_children
declare -A tty_processes

while read -r pid ppid tty comm cmdline; do
  [[ -z "$pid" ]] && continue

  pid_comm["$pid"]="$comm"
  pid_cmdline["$pid"]="$cmdline"

  proc_line="$pid ${cmdline:-$comm}"

  if [[ -n "$ppid" ]]; then
    if [[ -n "${ppid_children[$ppid]+x}" ]]; then
      ppid_children["$ppid"]+=$'\n'"$proc_line"
    else
      ppid_children["$ppid"]="$proc_line"
    fi
  fi

  if [[ -n "$tty" ]]; then
    if [[ -n "${tty_processes[$tty]+x}" ]]; then
      tty_processes["$tty"]+=$'\n'"$proc_line"
    else
      tty_processes["$tty"]="$proc_line"
    fi
  fi
done < <(ps -axo pid=,ppid=,tty=,comm=,command= 2>/dev/null || true)

while IFS=$'\t' read -r session win_idx pane_idx pane_id pane_pid pane_cmd pane_title pane_tty; do
  matches=()
  child_processes=()
  tty_processes=()
  pane_sample_matched=0

    if [[ "$pane_cmd" == *"$pattern"* ]]; then
      matches+=("current_command: $pane_cmd")
    fi

    proc_name="${pid_comm[$pane_pid]-}"
    proc_cmdline="${pid_cmdline[$pane_pid]-}"
    if [[ "$proc_name" == *"$pattern"* ]]; then
      matches+=("pane_process: $proc_name")
    fi
    if [[ -n "$proc_cmdline" ]] && [[ "$proc_cmdline" == *"$pattern"* ]]; then
      matches+=("pane_cmdline: $proc_cmdline")
    fi

    if [[ "$pane_title" == *"$pattern"* ]]; then
      matches+=("pane_title: $pane_title")
    fi

    if ((deep == 1)); then
      child_blob="${ppid_children[$pane_pid]-}"
      if [[ -n "$child_blob" ]]; then
        while IFS= read -r line; do
          [[ -n "$line" && "$line" == *"$pattern"* ]] && child_processes+=("$line")
        done <<< "$child_blob"
      fi

      tty_short="${pane_tty#/dev/}"
      if [[ -n "$tty_short" ]]; then
        tty_blob="${tty_processes[$tty_short]-}"
        if [[ -n "$tty_blob" ]]; then
          while IFS= read -r line; do
            [[ -n "$line" && "$line" == *"$pattern"* ]] && tty_processes+=("$line")
          done <<< "$tty_blob"
        fi
      fi

      for line in "${child_processes[@]}"; do
        matches+=("child_process: $line")
      done
      for line in "${tty_processes[@]}"; do
        matches+=("tty_process: $line")
      done
    fi

    if ((${#matches[@]} > 0)) && [[ "$pane_id" == %* ]]; then
      pane_sample="$(tmux capture-pane -p -t "$pane_id" -S "-$sample_lines" 2>/dev/null || true)"
      if [[ -n "$pane_sample" ]]; then
        if ((rg_available)); then
          if echo "$pane_sample" | rg -i -n -m 1 -e "$sample_regex" >/dev/null 2>&1; then
            pane_sample_matched=1
            matches+=("pane_sample: matched /$sample_regex/ in last ${sample_lines} lines")
          fi
        else
          if echo "$pane_sample" | grep -i -m 1 -E "$sample_regex" >/dev/null 2>&1; then
            pane_sample_matched=1
            matches+=("pane_sample: matched /$sample_regex/ in last ${sample_lines} lines")
          fi
        fi
      fi
    fi

  if ((${#matches[@]} > 0)); then
    found=1
    building_label="Idle"
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
      printf '"tty_processes":%s' "$(json_array "${tty_processes[@]}")"
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
done < <(tmux list-panes -a -F $'#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_id}\t#{pane_pid}\t#{pane_current_command}\t#{pane_title}\t#{pane_tty}')

if ((json_output)); then
  if ((json_first)); then
    printf '[]'
  else
    printf ']'
  fi
  printf '\n'
elif ((found == 0)); then
  echo "No opencode instances found in tmux panes."
fi
