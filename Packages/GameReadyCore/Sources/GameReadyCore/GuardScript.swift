/// The Game Mode guard, run once per session as root after the administrator prompt.
/// It lives inside the app binary, not as a file in the bundle, so nothing on disk can be
/// swapped between the user's approval and the run. See D8 in docs/decisions.md.
public enum GuardScript {
    public static let source = #"""
#!/bin/bash
# Game Ready — Game Mode guard. Started once per session as root, after the user approves
# the administrator prompt. While the flag file exists it keeps the AirDrop/Handoff radio
# (awdl0) down; when the flag goes it restores every setting it changed, then exits.
#
#   bash -c "$SOURCE" game-mode-guard <flag-file>
#
# The flag must be gamemode.on inside a user's own Application Support/Game Ready folder,
# owned by that user. Nothing else is accepted.
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin

FLAG="${1:-}"
STATE_DIR=/var/run/game-ready
PIDFILE="$STATE_DIR/guard.pid"
STATE="$STATE_DIR/state"

[[ $EUID -eq 0 ]] || { echo "must run as root" >&2; exit 1; }
[[ "$FLAG" =~ ^/Users/[A-Za-z0-9._-]+/Library/Application\ Support/Game\ Ready/gamemode\.on$ ]] \
  || { echo "refusing flag path" >&2; exit 2; }
[[ -f "$FLAG" && ! -L "$FLAG" ]] || { echo "flag missing" >&2; exit 3; }
owner_home="/Users/$(stat -f %Su "$FLAG")"
[[ "$FLAG" == "$owner_home/"* ]] || { echo "flag not owned by its home's user" >&2; exit 4; }

mkdir -p "$STATE_DIR" && chmod 755 "$STATE_DIR"
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "already running"; exit 0
fi

# Remember what we change, so "off" puts back exactly what was there.
lowpower_was=$(pmset -g | awk '/lowpowermode/{print $2; exit}')
tm_was=$(defaults read /Library/Preferences/com.apple.TimeMachine AutoBackup 2>/dev/null || echo 0)
printf 'lowpower=%s\ntm=%s\n' "${lowpower_was:-0}" "$tm_was" > "$STATE"

[[ "${lowpower_was:-0}" == "1" ]] && pmset -a lowpowermode 0
if [[ "$tm_was" == "1" ]]; then tmutil stopbackup 2>/dev/null; tmutil disable 2>/dev/null; fi
ifconfig awdl0 down 2>/dev/null

restore() {
  ifconfig awdl0 up 2>/dev/null
  [[ "${lowpower_was:-0}" == "1" ]] && pmset -a lowpowermode 1
  [[ "$tm_was" == "1" ]] && tmutil enable 2>/dev/null
  rm -f "$PIDFILE" "$STATE"
}

# Detach: the administrator prompt returns at once, the loop carries on.
(
  trap restore EXIT
  trap 'exit 0' TERM INT HUP
  while [[ -f "$FLAG" ]]; do
    ifconfig awdl0 down 2>/dev/null
    sleep 5
  done
) </dev/null >/dev/null 2>&1 &
echo $! > "$PIDFILE"   # bash 3.2 (macOS) cannot report a subshell pid from inside, so record it here
disown
echo "started"
"""#
}
