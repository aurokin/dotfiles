#!/usr/bin/env bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "$script_dir/tmux-pane-utils.sh"

if [[ ! -t 0 ]]; then
  "$script_dir/find-agents-tmux.sh"
  exit 0
fi

cup0=$'\033[H'
el=$'\033[2K'
ed=$'\033[J'
civis=''
cnorm=''

if command -v tput >/dev/null 2>&1; then
  cup0="$(tput cup 0 0 2>/dev/null || true)"
  el="$(tput el 2>/dev/null || true)"
  ed="$(tput ed 2>/dev/null || true)"
  civis="$(tput civis 2>/dev/null || true)"
  cnorm="$(tput cnorm 2>/dev/null || true)"
fi
if [[ -z "$cup0" ]]; then
  cup0=$'\033[H'
fi
if [[ -z "$el" ]]; then
  el=$'\033[2K'
fi
if [[ -z "$ed" ]]; then
  ed=$'\033[J'
fi

prompt='auto refresh every 2s; 1-9 switch panes; Ctrl-B for tmux prefix; any other key closes'
prev_hash=''
prev_lines=0
resize=1
rendered_output=''
render_lines=()
key_targets=()
client_tty=''

if command -v tmux >/dev/null 2>&1 && [[ -n "${TMUX:-}" ]]; then
  client_tty="$(tmux display-message -p '#{client_tty}' 2>/dev/null || true)"
fi

cleanup() {
  if [[ -n "$cnorm" ]]; then
    printf '%s' "$cnorm"
  fi
  stty sane >/dev/null 2>&1 || true
}

trap 'cleanup' EXIT INT TERM HUP
trap 'resize=1' WINCH

if [[ -n "$civis" ]]; then
  printf '%s' "$civis"
fi

activate_tmux_prefix() {
  command -v tmux >/dev/null 2>&1 || return 0
  [[ -n "${TMUX:-}" ]] || return 0
  tmux switch-client -T prefix >/dev/null 2>&1 || true
}

refresh_popup_state() {
  local output=""
  local line=""
  local pane_id=""
  local building_bool=""
  local session=""
  local win_idx=""
  local pane_idx=""
  local display_title=""
  local line_no=0
  local number=0
  local emoji=""
  local rendered_line=""

  output="$("$script_dir/find-agents-tmux.sh" --popup-tsv 2>&1)"
  render_lines=()
  key_targets=()

  if [[ -z "$output" ]]; then
    render_lines=("No agent instances found in tmux panes.")
  else
    while IFS= read -r line; do
      if [[ "$line" == *$'\t'* ]]; then
        IFS=$'\t' read -r pane_id building_bool session win_idx pane_idx display_title <<< "$line"
        emoji='🟢'
        if [[ "$building_bool" == "true" ]]; then
          emoji='🟡'
        fi

        ((line_no++))
        if (( line_no <= 9 )); then
          number=$line_no
          key_targets[$number]="$pane_id"
          rendered_line="#${number} ${emoji} ${session}:${win_idx}.${pane_idx} - ${display_title}"
        else
          rendered_line="   ${emoji} ${session}:${win_idx}.${pane_idx} - ${display_title}"
        fi
        render_lines+=("$rendered_line")
      else
        render_lines+=("$line")
      fi
    done <<< "$output"
  fi

  rendered_output=''
  if ((${#render_lines[@]} > 0)); then
    rendered_output="$(printf '%s\n' "${render_lines[@]}")"
  fi
}

while :; do
  refresh_popup_state
  hash_source="${rendered_output}"$'\n'"${prompt}"
  if command -v cksum >/dev/null 2>&1; then
    hash="$(printf '%s' "$hash_source" | cksum)"
  else
    hash="$hash_source"
  fi

  if [[ "$hash" != "$prev_hash" || $resize -eq 1 ]]; then
    frame="$cup0"
    lines=0
    if [[ -n "$rendered_output" ]]; then
      while IFS= read -r line; do
        frame+="${el}"$'\r'"${line}"$'\n'
        ((lines++))
      done <<< "$rendered_output"
    fi
    frame+="${el}"$'\r\n'
    frame+="${el}"$'\r'"${prompt}"$'\n'
    current_lines=$((lines + 2))
    if (( prev_lines > current_lines )); then
      for ((i=current_lines; i<prev_lines; i++)); do
        frame+="${el}"$'\r\n'
      done
    fi
    if (( resize == 1 )); then
      frame+="$ed"
    fi
    printf '%s' "$frame"
    prev_hash="$hash"
    prev_lines=$current_lines
    resize=0
  fi

  if IFS= read -r -s -n 1 -t 2 key; then
    if [[ "$key" == [1-9] ]]; then
      pane_id="${key_targets[$key]-}"
      if [[ -n "$pane_id" ]]; then
        if tmux_pane_exists "$pane_id"; then
          tmux_focus_pane "$client_tty" "$pane_id"
        else
          tmux_msg "$client_tty" "Agent pane ${key} is no longer available."
        fi
      fi
    elif [[ "$key" == $'\002' ]]; then
      activate_tmux_prefix
    fi
    exit 0
  else
    if [[ ! -t 0 ]]; then
      exit 0
    fi
  fi
done
