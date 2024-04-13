#!/bin/bash

nix-env -iA nixpkgs.glibcLocales
nix-env -iA nixpkgs.gccgo13
nix-env -iA nixpkgs.nodejs_20
nix-env -iA nixpkgs.python3
nix-env -iA nixpkgs.ruby
nix-env -iA nixpkgs.zulu17
nix-env -iA nixpkgs.lua
nix-env -iA nixpkgs.sass

nix-env -iA nixpkgs.zsh
nix-env -iA nixpkgs.pure-prompt

nix-env -iA nixpkgs.wget
nix-env -iA nixpkgs.tmux
nix-env -iA nixpkgs.httpie
nix-env -iA nixpkgs.bat
nix-env -iA nixpkgs.eza
nix-env -iA nixpkgs.fzf
nix-env -iA nixpkgs.zoxide
nix-env -iA nixpkgs.stow
nix-env -iA nixpkgs.ripgrep
nix-env -iA nixpkgs.tree
nix-env -iA nixpkgs.delta
nix-env -iA nixpkgs.neovim

nix-env -iA nixpkgs.btop
nix-env -iA nixpkgs.duf
nix-env -iA nixpkgs.gdu
nix-env -iA nixpkgs.rclone
nix-env -iA nixpkgs.termscp
nix-env -iA nixpkgs.lazydocker

nix-env -iA nixpkgs.yarn
nix-env -iA nixpkgs.typescript
nix-env -iA nixpkgs.rubyPackages_3_3.xcodeproj
nix-env -iA nixpkgs.xcbeautify
nix-env -iA nixpkgs.prettierd
nix-env -iA nixpkgs.watchman
nix-env -iA nixpkgs.ranger

