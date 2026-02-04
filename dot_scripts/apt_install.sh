#!/bin/bash

sudo apt-get update -y

# NOTE: Assumes third-party repos are preconfigured (Docker, Caddy, etc.).
sudo apt-get install -y \
  build-essential \
  clang \
  caddy \
  curl \
  docker-buildx-plugin \
  docker-ce \
  docker-ce-cli \
  docker-compose \
  docker-compose-plugin \
  flatpak \
  htop \
  liblua5.4-dev \
  playerctl \
  redis \
  rsync \
  xclip \
  xdotool \
  zsh
