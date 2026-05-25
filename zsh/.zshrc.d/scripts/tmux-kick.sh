#!/usr/bin/env bash
#
# tmux-kick.sh — interactively detach tmux clients from a centered popup.
#
# Built for the "take over from my phone" case: lists every attached client
# with its resolution as the primary identifier, clearly flags control-mode
# clients (editor/IDE integrations you usually do NOT want to kick) and the
# client you invoked from, then lets you pick what to detach.
#
# Bound in ~/.tmux.conf as prefix+F6, which passes --client-tty '#{client_tty}'
# so the invoking client is identified exactly (no same-session ambiguity).
# Run bare from a shell it falls back to `tmux display-message`.
#
# Defaults are safe:
#   - control-mode clients are NOT offered as targets (use --include-control)
#   - your own client is NOT offered as a target (use --include-self)
#   - detaches (MSG_DETACH); pass --kill to SIGHUP the client process instead
#
# Usage:
#   tmux-kick.sh [--client-tty TTY] [--include-control] [--include-self]
#                [--kill] [-t CLIENT_NAME]
#
set -euo pipefail

include_control=0
include_self=0
kill_client=0
target=""
me_tty=""

while [ $# -gt 0 ]; do
	case "$1" in
		--client-tty)      shift; me_tty="${1:-}" ;;
		--include-control) include_control=1 ;;
		--include-self)    include_self=1 ;;
		--kill)            kill_client=1 ;;
		-t)                shift; target="${1:-}" ;;
		-h|--help)
			sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//'
			exit 0 ;;
		*) echo "unknown arg: $1" >&2; exit 2 ;;
	esac
	shift
done

if ! tmux info >/dev/null 2>&1; then
	echo "no tmux server running" >&2
	exit 1
fi

detach() {
	local name="$1"
	if [ "$kill_client" = 1 ]; then
		tmux detach-client -P -t "$name"   # -P => MSG_DETACHKILL (SIGHUP parent)
	else
		tmux detach-client -t "$name"
	fi
}

# Who am I? Prefer the tty handed in by the keybinding (exact). Fall back to
# display-message when run bare from a shell.
if [ -z "$me_tty" ]; then
	me_tty="$(tmux display-message -p '#{client_tty}' 2>/dev/null || true)"
fi
now="$(date +%s)"

# Non-interactive path.
if [ -n "$target" ]; then
	detach "$target" && echo "detached: $target"
	exit 0
fi

# Pull all attached clients, tab-separated, sorted by most recently active.
# Control-mode clients report empty height AND empty tty; default every
# potentially-empty field so columns never collapse (tab is IFS-whitespace).
mapfile -t rows < <(
	tmux list-clients -F \
'#{client_name}	#{?client_width,#{client_width},?}	#{?client_height,#{client_height},?}	#{client_control_mode}	#{session_name}	#{client_activity}	#{?client_tty,#{client_tty},-}'
)

# Build a parallel array of selectable target names and a printed table.
targets=()
printf '\n  %-3s %-11s %-8s %-16s %-7s %s\n' "#" "RESOLUTION" "KIND" "CLIENT" "IDLE" "SESSION"
printf '  %s\n' "------------------------------------------------------------------------"
idx=0
for row in "${rows[@]}"; do
	IFS=$'\t' read -r name w h control session activity tty <<<"$row"

	res="${w}x${h}"
	kind="term"; [ "$control" = 1 ] && kind="CONTROL"

	idle=$(( now - activity ))
	if   [ "$idle" -lt 60 ];   then idlestr="${idle}s"
	elif [ "$idle" -lt 3600 ]; then idlestr="$(( idle / 60 ))m"
	else                            idlestr="$(( idle / 3600 ))h"; fi

	is_me=0
	[ -n "$me_tty" ] && [ "$tty" != "-" ] && [ "$tty" = "$me_tty" ] && is_me=1
	tag=""; [ "$is_me" = 1 ] && tag=" <- YOU"

	# Decide if this client is a selectable target.
	selectable=1
	[ "$control" = 1 ] && [ "$include_control" = 0 ] && selectable=0
	[ "$is_me" = 1 ]   && [ "$include_self" = 0 ]    && selectable=0

	if [ "$selectable" = 1 ]; then
		idx=$(( idx + 1 ))
		targets+=("$name")
		num="$idx"
	else
		num="-"   # shown for context but not pickable
	fi

	printf '  %-3s %-11s %-8s %-16s %-7s %s%s\n' \
		"$num" "$res" "$kind" "$name" "$idlestr" "$session" "$tag"
done
echo

if [ "${#targets[@]}" -eq 0 ]; then
	echo "Nothing kickable (control-mode and your own client are protected)."
	echo "Use --include-control and/or --include-self to override."
	# In a popup, pause so the message is readable before it closes.
	[ -t 0 ] && { read -rp "press enter to close " _ || true; }
	exit 0
fi

# Pick a target: fzf if available, else a numbered prompt.
choice=""
if command -v fzf >/dev/null 2>&1; then
	choice="$(printf '%s\n' "${targets[@]}" \
		| fzf --prompt='detach which client? ' --height=40% --reverse || true)"
else
	read -rp "Detach which # (blank to cancel)? " n
	[ -z "$n" ] && { echo "cancelled"; exit 0; }
	if ! [[ "$n" =~ ^[0-9]+$ ]] || [ "$n" -lt 1 ] || [ "$n" -gt "${#targets[@]}" ]; then
		echo "invalid selection" >&2; exit 2
	fi
	choice="${targets[$(( n - 1 ))]}"
fi

[ -z "$choice" ] && { echo "cancelled"; exit 0; }

verb="detach"; [ "$kill_client" = 1 ] && verb="KILL"
read -rp "$verb client '$choice'? [y/N] " ok
case "$ok" in
	y|Y) detach "$choice" && echo "${verb}ed: $choice" ;;
	*)   echo "cancelled" ;;
esac
