#!/bin/bash 

# Make Symlinks
stow -R zsh tmux git alacritty nvim karabiner lazygit idea bat fonts hammerspoon

# Clear Font Cache
# fc-cache -f -v

# Build Bat Theme Cache
bat cache --build
