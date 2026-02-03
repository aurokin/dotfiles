#!/usr/bin/env bash

while :; do
  ~/.zsh_scripts/find-opencode-tmux.sh
  printf '\n'
  IFS= read -r -s -n 1 key || exit 0
  if [ "$key" = r ]; then
    clear
    continue
  fi
  exit 0
done
