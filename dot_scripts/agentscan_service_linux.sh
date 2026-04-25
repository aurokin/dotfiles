#!/bin/bash
# Install agentscan daemon as a systemd --user service on Linux.
# Enables on every login and supervises the daemon with restart-on-failure
# so it can recover whenever a tmux server reappears.

set -e

if [[ "$OSTYPE" != "linux-gnu"* ]]; then
  echo "agentscan_service_linux.sh: not running on Linux ($OSTYPE)" >&2
  exit 1
fi

shim="$HOME/.local/share/mise/shims/agentscan"

if [[ ! -x "$shim" ]]; then
  echo "agentscan shim not found at $shim" >&2
  echo "Run 'mise install' first." >&2
  exit 1
fi

unit_dir="$HOME/.config/systemd/user"
unit="${unit_dir}/agentscan.service"
mkdir -p "$unit_dir"

cat > "$unit" <<UNIT
[Unit]
Description=agentscan tmux agent daemon
StartLimitIntervalSec=600
StartLimitBurst=20

[Service]
Type=simple
Environment=PATH=${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=${shim} daemon run
Restart=on-failure
RestartSec=30

[Install]
WantedBy=default.target
UNIT

systemctl --user daemon-reload
systemctl --user enable --now agentscan.service

echo "Installed systemd user unit: agentscan.service"
echo "Logs: journalctl --user -u agentscan.service"
