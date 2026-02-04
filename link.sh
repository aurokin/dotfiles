#!/bin/bash 

# Make Symlinks
stow -R --no-folding zsh
stow -R tmux git alacritty nvim karabiner lazygit idea bat fonts hammerspoon mise

# Clear Font Cache
# fc-cache -f -v

# Build Bat Theme Cache
bat cache --build
