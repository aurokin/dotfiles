#!/usr/bin/env bash

if [[ ! -t 0 ]]; then
  ~/.zshrc.d/scripts/find-agents-tmux.sh
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

prompt='auto refresh every 2s; any key to close'
prev_hash=''
prev_lines=0
resize=1

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

while :; do
  output="$(~/.zshrc.d/scripts/find-agents-tmux.sh 2>&1)"
  hash_source="${output}"$'\n'"${prompt}"
  if command -v cksum >/dev/null 2>&1; then
    hash="$(printf '%s' "$hash_source" | cksum)"
  else
    hash="$hash_source"
  fi

  if [[ "$hash" != "$prev_hash" || $resize -eq 1 ]]; then
    frame="$cup0"
    lines=0
    if [[ -n "$output" ]]; then
      while IFS= read -r line; do
        frame+="${el}"$'\r'"${line}"$'\n'
        ((lines++))
      done <<< "$output"
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
    if [[ "$key" == $'\002' ]]; then
      activate_tmux_prefix
    fi
    exit 0
  else
    if [[ ! -t 0 ]]; then
      exit 0
    fi
  fi
done
