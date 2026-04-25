#!/bin/bash
# Install agentscan daemon as a launchd user agent on macOS.
# Loads on every login and supervises the daemon with restart-on-failure
# so it can recover whenever a tmux server reappears.

set -e

if [[ "$OSTYPE" != "darwin"* ]]; then
  echo "agentscan_service_osx.sh: not running on macOS ($OSTYPE)" >&2
  exit 1
fi

shim="$HOME/.local/share/mise/shims/agentscan"

if [[ ! -x "$shim" ]]; then
  echo "agentscan shim not found at $shim" >&2
  echo "Run 'mise install' first." >&2
  exit 1
fi

label=com.aurokin.agentscan
plist="$HOME/Library/LaunchAgents/${label}.plist"
log_dir="$HOME/Library/Logs"
mkdir -p "$(dirname "$plist")" "$log_dir"

cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTD/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${shim}</string>
        <string>daemon</string>
        <string>run</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ThrottleInterval</key>
    <integer>30</integer>
    <key>StandardOutPath</key>
    <string>${log_dir}/agentscan.log</string>
    <key>StandardErrorPath</key>
    <string>${log_dir}/agentscan.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true
# bootout is async; wait up to 10s for the unload to complete before bootstrap
# so re-runs do not race into a "service already loaded" (errno 37) failure.
for _ in $(seq 1 20); do
  launchctl print "gui/$(id -u)/${label}" >/dev/null 2>&1 || break
  sleep 0.5
done
launchctl bootstrap "gui/$(id -u)" "$plist"

echo "Installed launchd agent: ${label}"

# Log rotation: launchd appends to plain files indefinitely, so install a
# newsyslog drop-in to bound disk growth (~weekly rotation, 4 generations).
echo "Installing log rotation (requires sudo)..."
newsyslog_conf=/etc/newsyslog.d/com.aurokin.agentscan.conf
if sudo tee "$newsyslog_conf" >/dev/null <<NEWSYSLOG
# logfilename                                          [owner:group]    mode count size when  flags
${log_dir}/agentscan.log                                $(id -un):staff  644  4     *    \$W0   Z
${log_dir}/agentscan.err.log                            $(id -un):staff  644  4     *    \$W0   Z
NEWSYSLOG
then
  echo "Installed log rotation: ${newsyslog_conf}"
else
  echo "Warning: log rotation not installed (sudo unavailable)." >&2
  echo "Re-run this script from an interactive shell to add rotation." >&2
fi
echo "Logs: ${log_dir}/agentscan.log, ${log_dir}/agentscan.err.log"
