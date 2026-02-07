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
declare -A provider_sample_parts

register_provider() {
  local name="$1"
  local pattern="$2"
  local cmd="$3"
  local sample_parts="$4"
  provider_pattern["$name"]="$pattern"
  provider_cmd["$name"]="$cmd"
  provider_sample_parts["$name"]="$sample_parts"
}

register_provider opencode "opencode" "opencode" ""
register_provider gemini "gemini" "gemini" "esc to cancel"
register_provider codex "codex" "codex" "esc to cancel|esc to interrupt|esc to stop"
register_provider claude "claude" "claude" "esc to cancel|esc to interrupt|esc to stop"

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

strip_leading_glyphs() {
  local s="$1"
  if [[ "$s" =~ ^[^[:alnum:]]+[[:space:]]+(.+)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "$s"
  fi
}

strip_known_prefixes() {
  local s="$1"
  case "$s" in
    'OC | '*) s="${s#OC | }" ;;
    'Claude Code | '*) s="${s#Claude Code | }" ;;
    'Claude | '*) s="${s#Claude | }" ;;
  esac
  printf '%s' "$s"
}

normalize_title_for_provider() {
  local provider="$1"
  local title="$2"
  local activity_title="${3:-}"

  title="$(strip_known_prefixes "$title")"

  if [[ "$provider" == "claude" ]]; then
    title="$(strip_leading_glyphs "$title")"
  fi

  if [[ "$provider" == "codex" && -n "$activity_title" ]]; then
    title="$activity_title"
  fi

  printf '%s' "$title"
}

extract_codex_activity_title() {
  local sample="$1"
  local line=""
  local title=""
  local trimmed=""
  local candidate=""
  local re='^(.+)[[:space:]]*\([^)]*esc[[:space:]]+to[[:space:]]+(interrupt|cancel|stop)[^)]*\)[[:space:]]*$'
  local lines=()
  local i=0

  # Read into an array so we can scan bottom-up (the most recent status line wins).
  while IFS= read -r line; do
    lines+=("$line")
  done <<< "$sample"

  for ((i=${#lines[@]}-1; i>=0; i--)); do
    line="${lines[$i]}"
    [[ -z "$line" ]] && continue

    trimmed="$line"
    trimmed="$(trim_ws "$trimmed")"

    trimmed="$(strip_leading_glyphs "$trimmed")"
    trimmed="$(trim_ws "$trimmed")"

    # Codex often prints: "<activity title> (<time> • esc to interrupt)"
    if [[ "$trimmed" =~ $re ]]; then
      candidate="${BASH_REMATCH[1]}"
      candidate="$(trim_ws "$candidate")"
      if [[ -n "$candidate" ]]; then
        title="$candidate"
        break
      fi
    fi
  done

  printf '%s' "$title"
}


build_patterns=()
build_allowlist=()
build_sample_regexes=()
declare -A seen_providers
declare -A seen_patterns
declare -A seen_allowlist
declare -A seen_sample_parts

trim_ws() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

for provider in "${providers[@]}"; do
  [[ -z "$provider" ]] && continue
  if [[ -n "${seen_providers[$provider]+x}" ]]; then
    continue
  fi
  seen_providers["$provider"]=1

  pattern_item="${provider_pattern[$provider]-$provider}"
  cmd_item="${provider_cmd[$provider]-$provider}"
  sample_item="${provider_sample_parts[$provider]-}"

  if [[ -n "$pattern_item" ]] && [[ -z "${seen_patterns[$pattern_item]+x}" ]]; then
    build_patterns+=("$pattern_item")
    seen_patterns["$pattern_item"]=1
  fi
  if [[ -n "$cmd_item" ]] && [[ -z "${seen_allowlist[$cmd_item]+x}" ]]; then
    build_allowlist+=("$cmd_item")
    seen_allowlist["$cmd_item"]=1
  fi

  if [[ -n "$sample_item" ]]; then
    sample_item="$(trim_ws "$sample_item")"
    sample_item_ifs="$IFS"
    IFS='|'
    read -r -a sample_parts <<< "$sample_item"
    IFS="$sample_item_ifs"
    for sample_part in "${sample_parts[@]}"; do
      sample_part="$(trim_ws "$sample_part")"
      [[ -z "$sample_part" ]] && continue
      if [[ -z "${seen_sample_parts[$sample_part]+x}" ]]; then
        build_sample_regexes+=("$sample_part")
        seen_sample_parts["$sample_part"]=1
      fi
    done
  fi
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
  sample_regex_default="esc to cancel|esc to interrupt|esc to stop"
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
  TMUX_AGENTS_SAMPLE_REGEX    Regex to detect "building" state (default: "esc to cancel|esc to interrupt|esc to stop")
  TMUX_AGENTS_OPENCODE_SAMPLE_LINES Lines to sample for opencode footer detection (default: 12)
  TMUX_AGENTS_OPENCODE_FOOTER_BUILD_REGEX Regex to detect opencode "building" from footer (default: "^[[:space:]]*[^[:alnum:][:space:]]{2,}[[:space:]]+esc interrupt")
  TMUX_AGENTS_CLAUDE_SAMPLE_LINES Lines to sample for claude build detection (default: 40)
  TMUX_AGENTS_CLAUDE_TITLE_BUILD_REGEX Regex to detect claude "building" from pane title (default: "^[[:space:]]*[braille-spinner][[:space:]]+")
  TMUX_AGENTS_CLAUDE_BUILD_REGEX  Regex to detect claude "building" (default: "^[[:space:]]*esc to interrupt[[:space:]]*$")
  TMUX_AGENTS_GEMINI_BUILD_REGEX  Regex to detect gemini "building" (default: "\(esc to cancel, [0-9]+[smhd]\)")
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

add_match() {
  ((want_details)) || return 0
  matches+=("$1")
}

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
    # Treat "<item>-<suffix>" as equivalent (e.g. "codex-aarch64-a", "claude-code").
    if [[ "$cmd" == "$item" || "$cmd" == "$item"-* ]]; then
      return 0
    fi
  done
  return 1
}

provider_from_cmd() {
  local cmd="$1"
  [[ -z "$cmd" ]] && return 1
  local cmd_base="${cmd##*/}"
  local item
  for item in "${allowlist_items[@]}"; do
    [[ -z "$item" ]] && continue
    if [[ "$cmd_base" == "$item" || "$cmd_base" == "$item"-* ]]; then
      printf '%s' "$item"
      return 0
    fi
  done
  return 1
}

provider_from_text() {
  local text="$1"
  [[ -z "$text" ]] && return 1

  local provider
  local pat
  for provider in "${providers[@]}"; do
    [[ -z "$provider" ]] && continue
    pat="${provider_pattern[$provider]-$provider}"
    [[ -z "$pat" ]] && continue
    if [[ "$text" =~ $pat ]]; then
      printf '%s' "$provider"
      return 0
    fi
  done

  return 1
}

provider_from_pane_title() {
  local title="$1"
  [[ -z "$title" ]] && return 1
  case "$title" in
    'OC | '*)
      [[ -n "${seen_providers[opencode]+x}" ]] || return 1
      printf '%s' opencode
      return 0
      ;;
    'Claude Code | '*|'Claude | '*)
      [[ -n "${seen_providers[claude]+x}" ]] || return 1
      printf '%s' claude
      return 0
      ;;
  esac
  return 1
}

provider_from_ps_line() {
  local line="$1"
  [[ -z "$line" ]] && return 1
  local rest="${line#* }"
  local cmd_token="${rest%% *}"
  provider_from_cmd "$cmd_token" || provider_from_text "$rest"
}

line_has_allowed_cmd() {
  local line="$1"
  [[ -z "$line" ]] && return 1
  provider_from_ps_line "$line" >/dev/null 2>&1
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

sample_matches_regex() {
  local sample="$1"
  local regex="$2"
  [[ -z "$sample" || -z "$regex" ]] && return 1
  if ((rg_available)); then
    rg -q -i -m 1 -e "$regex" <<<"$sample" >/dev/null 2>&1
  else
    grep -q -i -m 1 -E "$regex" <<<"$sample" >/dev/null 2>&1
  fi
}

opencode_footer_build_regex_default='^[[:space:]]*[^[:alnum:][:space:]]{2,}[[:space:]]+esc interrupt'
# Claude Code updates the terminal title while it is running (often a braille spinner prefix).
# When it is waiting for user input, the title usually switches to a non-spinner marker (e.g. "✳").
claude_title_build_regex_default='^[[:space:]]*[⠁⠂⠄⡀⢀⠠⠐⠈⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏⣾⣽⣻⢿⡿⣟⣯⣷][[:space:]]+'
claude_build_regex_default='^[[:space:]]*esc to interrupt[[:space:]]*$'
gemini_build_regex_default='\(esc to cancel, [0-9]+[smhd]\)'

capture_pane_sample() {
  local pane_id="$1"
  local lines="$2"
  [[ -z "$pane_id" || -z "$lines" ]] && return 1
  tmux capture-pane -p -t "$pane_id" -S "-$lines" 2>/dev/null || true
}

opencode_is_building_from_sample() {
  local sample="$1"
  local footer_out_var="${2:-}"
  local regex_out_var="${3:-}"

  [[ -z "$sample" ]] && return 1

  local footer=""
  local build_regex="${TMUX_AGENTS_OPENCODE_FOOTER_BUILD_REGEX:-$opencode_footer_build_regex_default}"
  footer="$(extract_last_line_containing "$sample" "esc interrupt" 2>/dev/null || true)"

  [[ -n "$footer_out_var" ]] && printf -v "$footer_out_var" '%s' "$footer"
  [[ -n "$regex_out_var" ]] && printf -v "$regex_out_var" '%s' "$build_regex"

  [[ -z "$footer" ]] && return 1
  sample_matches_regex "$footer" "$build_regex"
}

claude_is_building_from_title_and_sample() {
  local pane_title="${1:-}"
  local sample="${2:-}"
  local source_out_var="${3:-}"
  local regex_out_var="${4:-}"

  local source=""
  local regex_used=""

  local title_regex="${TMUX_AGENTS_CLAUDE_TITLE_BUILD_REGEX:-$claude_title_build_regex_default}"
  if [[ -n "$pane_title" ]]; then
    local title_check
    title_check="$(strip_known_prefixes "$pane_title")"
    title_check="$(trim_ws "$title_check")"
    if [[ -n "$title_check" ]] && sample_matches_regex "$title_check" "$title_regex"; then
      source="pane_title"
      regex_used="$title_regex"
      [[ -n "$source_out_var" ]] && printf -v "$source_out_var" '%s' "$source"
      [[ -n "$regex_out_var" ]] && printf -v "$regex_out_var" '%s' "$regex_used"
      return 0
    fi
  fi

  if [[ -n "$sample" ]]; then
    local build_regex="${TMUX_AGENTS_CLAUDE_BUILD_REGEX:-$claude_build_regex_default}"
    if sample_matches_regex "$sample" "$build_regex"; then
      source="pane_sample"
      regex_used="$build_regex"
      [[ -n "$source_out_var" ]] && printf -v "$source_out_var" '%s' "$source"
      [[ -n "$regex_out_var" ]] && printf -v "$regex_out_var" '%s' "$regex_used"
      return 0
    fi
  fi

  [[ -n "$source_out_var" ]] && printf -v "$source_out_var" '%s' ""
  [[ -n "$regex_out_var" ]] && printf -v "$regex_out_var" '%s' ""
  return 1
}

gemini_is_building_from_title_and_sample() {
  local pane_title="$1"
  local sample="${2:-}"
  local regex_out_var="${3:-}"

  local build_regex="${TMUX_AGENTS_GEMINI_BUILD_REGEX:-$gemini_build_regex_default}"
  [[ -n "$regex_out_var" ]] && printf -v "$regex_out_var" '%s' "$build_regex"

  # Fast path: gemini sets pane title to "Ready" vs "Working".
  if [[ "$pane_title" == *"Working"* ]]; then
    return 0
  fi
  if [[ "$pane_title" == *"Ready"* ]]; then
    return 1
  fi

  [[ -z "$sample" ]] && return 1
  sample_matches_regex "$sample" "$build_regex"
}

extract_last_line_containing() {
  local sample="$1"
  local needle="$2"
  [[ -z "$sample" || -z "$needle" ]] && return 1

  local line=""
  local lines=()
  local i=0

  while IFS= read -r line; do
    lines+=("$line")
  done <<< "$sample"

  for ((i=${#lines[@]}-1; i>=0; i--)); do
    line="${lines[$i]}"
    [[ -z "$line" ]] && continue
    if [[ "$line" == *"$needle"* ]]; then
      printf '%s' "$(trim_ws "$line")"
      return 0
    fi
  done

  return 1
}

declare -A pid_comm
declare -A pid_cmdline
declare -A ppid_children
declare -A tty_process_map
ps_data_loaded=0

ensure_ps_data() {
  local panes_blob="${1:-}"
  ((ps_data_loaded)) && return 0
  ps_data_loaded=1

  [[ -z "$panes_blob" ]] && return 0

  local -A wanted_pids=()
  local -A wanted_ttys=()

  local session=""
  local win_idx=""
  local pane_idx=""
  local pane_id=""
  local pane_pid=""
  local pane_cmd=""
  local pane_title=""
  local pane_tty=""
  local tty_short=""

  while IFS=$'\t' read -r session win_idx pane_idx pane_id pane_pid pane_cmd pane_title pane_tty; do
    [[ -n "$pane_pid" ]] && wanted_pids["$pane_pid"]=1
    tty_short="${pane_tty#/dev/}"
    [[ -n "$tty_short" ]] && wanted_ttys["$tty_short"]=1
  done <<< "$panes_blob"

  local pid=""
  local ppid=""
  local tty=""
  local comm=""
  local cmdline=""
  local proc_line=""
  while IFS=$' \t' read -r pid ppid tty comm cmdline; do
    [[ -z "$pid" ]] && continue

    proc_line="$pid ${cmdline:-$comm}"

    if [[ -n "${wanted_pids[$pid]+x}" ]]; then
      pid_comm["$pid"]="$comm"
      pid_cmdline["$pid"]="$cmdline"
    fi

    if [[ -n "$tty" && -n "${wanted_ttys[$tty]+x}" ]]; then
      if [[ -n "${tty_process_map[$tty]+x}" ]]; then
        tty_process_map["$tty"]+=$'\n'"$proc_line"
      else
        tty_process_map["$tty"]="$proc_line"
      fi
    fi

    if ((deep == 1)) && [[ -n "$ppid" && -n "${wanted_pids[$ppid]+x}" ]]; then
      if [[ -n "${ppid_children[$ppid]+x}" ]]; then
        ppid_children["$ppid"]+=$'\n'"$proc_line"
      else
        ppid_children["$ppid"]="$proc_line"
      fi
    fi
  done < <(ps -axo pid=,ppid=,tty=,comm=,command= 2>/dev/null || true)
}

pane_lines="$(tmux list-panes -a -F $'#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_id}\t#{pane_pid}\t#{pane_current_command}\t#{pane_title}\t#{pane_tty}' 2>/dev/null || true)"
if [[ -z "$pane_lines" ]]; then
  echo "No tmux panes found."
  exit 0
fi

if ((want_details || deep)); then
  ensure_ps_data "$pane_lines"
fi

while IFS=$'\t' read -r session win_idx pane_idx pane_id pane_pid pane_cmd pane_title pane_tty; do
  pane_matched=0
  pane_building=0
  pane_activity_title=""
  pane_provider=""
  proc_name=""
  proc_cmdline=""
  if ((want_details)); then
    matches=()
    child_processes=()
    tty_matches=()
  fi

  if has_allowed_cmd "$pane_cmd"; then
    pane_matched=1
    pane_provider="$(provider_from_cmd "$pane_cmd" || true)"
    add_match "current_command: $pane_cmd"
  fi

  if ((pane_matched == 0)); then
    pane_provider="$(provider_from_pane_title "$pane_title" 2>/dev/null || true)"
    if [[ -n "$pane_provider" ]]; then
      pane_matched=1
      add_match "pane_title: $pane_title"
    fi
  fi

  if ((pane_matched == 0)); then
    ensure_ps_data "$pane_lines"
  fi
  if ((ps_data_loaded == 1)); then
    proc_name="${pid_comm[$pane_pid]-}"
    proc_cmdline="${pid_cmdline[$pane_pid]-}"
  fi

  if [[ -z "$pane_provider" ]]; then
    pane_provider="$(provider_from_cmd "$proc_name" || true)"
  fi

  if has_allowed_cmd "$proc_name"; then
    pane_matched=1
    add_match "pane_process: $proc_name"
  fi
  if [[ -n "$proc_cmdline" ]] && [[ "$proc_cmdline" =~ $pattern ]]; then
    pane_matched=1
    if [[ -z "$pane_provider" ]]; then
      pane_provider="$(provider_from_text "$proc_cmdline" || true)"
    fi
    add_match "pane_cmdline: $proc_cmdline"
  fi

  if ((deep == 1)); then
    child_blob="${ppid_children[$pane_pid]-}"
    if [[ -n "$child_blob" ]]; then
      while IFS= read -r line; do
        if ! is_self_line "$line" && { line_has_allowed_cmd "$line" || line_matches_pattern "$line"; }; then
          pane_matched=1
          if [[ -z "$pane_provider" ]]; then
            pane_provider="$(provider_from_ps_line "$line" 2>/dev/null || true)"
          fi
          ((want_details)) && child_processes+=("$line")
        fi
      done <<< "$child_blob"
    fi
  fi

  if ! ((pane_matched == 1 && deep == 0 && want_details == 0)); then
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
            if [[ -z "$pane_provider" ]]; then
              pane_provider="$(provider_from_ps_line "$line" 2>/dev/null || true)"
            fi
            ((want_details)) && tty_matches+=("$line")
          fi
        done <<< "$tty_blob"
      fi
    fi
  fi

  if ((want_details)); then
    for line in "${child_processes[@]}"; do
      add_match "child_process: $line"
    done
    for line in "${tty_matches[@]}"; do
      add_match "tty_process: $line"
    done
  fi

  if ((pane_matched == 1)) && [[ "$pane_id" == %* ]]; then
    pane_sample=""
    case "$pane_provider" in
      codex)
        pane_sample="$(capture_pane_sample "$pane_id" "$sample_lines")"
        if [[ -n "$pane_sample" ]]; then
          pane_activity_title="$(extract_codex_activity_title "$pane_sample")"
          if [[ -n "$pane_activity_title" ]]; then
            pane_building=1
            add_match "activity_title: $pane_activity_title"
          fi
        fi
        ;;
      claude)
        claude_source=""
        claude_regex=""
        if claude_is_building_from_title_and_sample "$pane_title" "" claude_source claude_regex; then
          pane_building=1
        else
          claude_sample_lines="${TMUX_AGENTS_CLAUDE_SAMPLE_LINES:-40}"
          pane_sample="$(capture_pane_sample "$pane_id" "$claude_sample_lines")"
          if [[ -n "$pane_sample" ]] && claude_is_building_from_title_and_sample "$pane_title" "$pane_sample" claude_source claude_regex; then
            pane_building=1
          fi
        fi
        if [[ -n "$claude_regex" ]]; then
          add_match "claude_build_source: $claude_source"
          add_match "claude_build_regex: $claude_regex"
        fi
        ;;
      gemini)
        if [[ "$pane_title" == *"Working"* ]]; then
          pane_building=1
        elif [[ "$pane_title" == *"Ready"* ]]; then
          :
        else
          gemini_regex=""
          pane_sample="$(capture_pane_sample "$pane_id" "$sample_lines")"
          if [[ -n "$pane_sample" ]] && gemini_is_building_from_title_and_sample "$pane_title" "$pane_sample" gemini_regex; then
            pane_building=1
          fi
          if ((pane_building == 1)) && [[ -n "$gemini_regex" ]]; then
            add_match "gemini_build_regex: $gemini_regex"
          fi
        fi
        ;;
      opencode)
        opencode_footer=""
        opencode_regex=""
        opencode_sample_lines="${TMUX_AGENTS_OPENCODE_SAMPLE_LINES:-12}"
        pane_sample="$(capture_pane_sample "$pane_id" "$opencode_sample_lines")"
        if [[ -n "$pane_sample" ]] && opencode_is_building_from_sample "$pane_sample" opencode_footer opencode_regex; then
          pane_building=1
        fi
        if [[ -n "$opencode_footer" ]]; then
          add_match "opencode_footer: $opencode_footer"
          add_match "opencode_footer_build_regex: $opencode_regex"
        fi
        ;;
      *)
        pane_sample="$(capture_pane_sample "$pane_id" "$sample_lines")"
        if [[ -n "$pane_sample" ]] && sample_matches_regex "$pane_sample" "$sample_regex"; then
          pane_building=1
          add_match "pane_sample: matched /$sample_regex/ in last ${sample_lines} lines"
        fi
        ;;
    esac
  fi

  if ((pane_matched == 1)); then
    found=1
    building_emoji="🟢"
    building_bool="false"
    if ((pane_building == 1)); then
      building_emoji="🟡"
      building_bool="true"
    fi

    display_title="$pane_title"
    display_title="$(normalize_title_for_provider "$pane_provider" "$display_title" "$pane_activity_title")"

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
      json_field "provider" "$pane_provider"
      json_field "activity_title" "$pane_activity_title"
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
