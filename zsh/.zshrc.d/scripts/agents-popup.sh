#!/usr/bin/env bash

while :; do
  ~/.zshrc.d/scripts/find-opencode-tmux.sh
  printf '\n'
  printf 'r to refresh, any key to close\n'
  IFS= read -r -s -n 1 key || exit 0
  if [ "$key" = r ]; then
    clear
    continue
  fi
  exit 0
done
