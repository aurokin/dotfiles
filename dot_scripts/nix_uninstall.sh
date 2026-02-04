#!/bin/bash

os="$(uname -s)"

if [[ "$os" == "Darwin" ]]; then
  if [[ -f "/etc/zshrc.backup-before-nix" ]]; then
    sudo mv /etc/zshrc.backup-before-nix /etc/zshrc
  fi
  if [[ -f "/etc/bashrc.backup-before-nix" ]]; then
    sudo mv /etc/bashrc.backup-before-nix /etc/bashrc
  fi
  if [[ -f "/etc/bash.bashrc.backup-before-nix" ]]; then
    sudo mv /etc/bash.bashrc.backup-before-nix /etc/bash.bashrc
  fi

  sudo launchctl unload /Library/LaunchDaemons/org.nixos.nix-daemon.plist
  sudo rm -f /Library/LaunchDaemons/org.nixos.nix-daemon.plist
  sudo launchctl unload /Library/LaunchDaemons/org.nixos.darwin-store.plist
  sudo rm -f /Library/LaunchDaemons/org.nixos.darwin-store.plist

  sudo dscl . -delete /Groups/nixbld
  for u in $(sudo dscl . -list /Users | grep _nixbld); do
    sudo dscl . -delete /Users/$u
  done

  sudo rm -rf /etc/nix /var/root/.nix-profile /var/root/.nix-defexpr /var/root/.nix-channels ~/.nix-profile ~/.nix-defexpr ~/.nix-channels

  echo "Manual steps (per Nix docs):"
  echo "- Remove nix lines from /etc/zshrc, /etc/bashrc, /etc/bash.bashrc if you edited them."
  echo "- Remove nix entry from /etc/fstab using sudo vifs (APFS Nix Store volume)."
  echo "- Remove nix from /etc/synthetic.conf (or delete the file if only nix)."
  echo "- Delete the Nix Store volume with: sudo diskutil apfs deleteVolume /nix"
  echo "- If deleteVolume fails, run 'diskutil list' to find the Nix Store volume and delete it by disk identifier."
else
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl stop nix-daemon.service
    sudo systemctl disable nix-daemon.socket nix-daemon.service
    sudo systemctl daemon-reload
  fi

  sudo rm -rf /etc/nix /etc/profile.d/nix.sh /etc/tmpfiles.d/nix-daemon.conf /nix ~root/.nix-channels ~root/.nix-defexpr ~root/.nix-profile ~root/.cache/nix

  for i in $(seq 1 32); do
    sudo userdel nixbld$i
  done
  sudo groupdel nixbld

  echo "Manual steps (per Nix docs):"
  echo "- Remove nix sourcing lines from /etc/bash.bashrc, /etc/bashrc, /etc/profile, /etc/zsh/zshrc, /etc/zshrc."
fi
