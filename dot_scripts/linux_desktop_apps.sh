#!/bin/bash

# NOTE: Assumes apt repos/PPAs and i386 multiarch are preconfigured.
# Add repo/ppa setup in dot_scripts/linux_setup.sh or follow distro docs.

sudo apt-get update -y
sudo apt-get install -y \
  discord \
  google-chrome-stable \
  obs-studio \
  plexmediaserver \
  steamcmd:i386 \
  sunshine \
  vesktop

if command -v snap >/dev/null; then
  sudo snap install firefox
  sudo snap install vlc
  sudo snap install moonlight
fi

if command -v flatpak >/dev/null; then
  sudo flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo
  sudo flatpak install -y --system flathub org.deskflow.deskflow
fi
