#!/bin/bash

if [[ "$OSTYPE" == "darwin"* ]]; then
  brew install xcode-build-server
  brew install nowplaying-cli
  brew install rename
fi

brew install mise
brew install swiftlint
brew install swiftformat
brew install swift-format
brew install xcbeautify

brew install jq
brew install libyaml
brew install sqlite
brew install bash
brew install bc
brew install coreutils
if [[ "$OSTYPE" == "darwin"* ]]; then
  brew install flock
else
  brew install util-linux
fi
brew install gawk
brew install gnu-sed
brew install ffmpeg
brew install yt-dlp
brew install whisper-cpp
brew install whisperkit-cli
brew install git
brew install worktrunk
brew install gh
brew install glab
brew install steipete/tap/remindctl
brew install steipete/tap/goplaces
brew install dedene/tap/raindrop-cli

brew install zsh
brew install starship
brew install wget
brew install rsync
brew install tmux
brew install tpm
brew install bat
brew install eza
brew install fzf
brew install zoxide
brew install stow
brew install ripgrep
brew install fd
brew install tree
brew install git-delta
brew install neovim
brew install tree-sitter-cli

brew install btop
brew install duf
brew install gdu
brew install rclone
brew install termscp
brew install lazydocker
brew install lazygit
