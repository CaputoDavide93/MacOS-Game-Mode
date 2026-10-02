/// The Game Mode guard, run once per session as root after the administrator prompt.
/// It lives inside the app binary, not as a file in the bundle, so nothing on disk can be
/// swapped between the user's approval and the run. See D8 in docs/decisions.md.
public enum GuardScript {
    public static let source = #"""
#!/bin/bash
# Game Ready — Game Mode guard. Started once per session as root, after the user approves
# the administrator prompt. While the flag file exists it keeps the AirDrop/Handoff radio
# (awdl0) down; when the flag goes it restores exactly what it changed, then exits.
#
#   bash -c "$SOURCE" game-mode-guard <flag-file>
#
# The flag must be gamemode.on inside a user's own Application Support/Game Ready folder,
# a regular file (not a symlink) owned by that user. It is re-checked on every loop, so a
# flag swapped for a link or another file after start stops the guard.
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin

FLAG="${1:-}"
STATE_DIR=/var/run/game-ready
PIDFILE="$STATE_DIR/guard.pid"
LOCK="$STATE_DIR/lock"
MAX_SECONDS=$((12 * 3600))   # safety net: never run longer than a long gaming day

[[ $EUID -eq 0 ]] || { echo "must run as root" >&2; exit 1; }
[[ "$FLAG" =~ ^/Users/([A-Za-z0-9._-]+)/Library/Application\ Support/Game\ Ready/gamemode\.on$ ]] \
  || { echo "refusing flag path" >&2; exit 2; }
owner="${BASH_REMATCH[1]}"

flag_ok() {
  [[ -f "$FLAG" && ! -L "$FLAG" ]] && [[ "$(stat -f %Su "$FLAG" 2>/dev/null)" == "$owner" ]]
}
flag_ok || { echo "flag missing, a link, or not owned by $owner" >&2; exit 3; }

mkdir -p "$STATE_DIR" && chmod 755 "$STATE_DIR"
# One guard at a time: mkdir is atomic, so two starts can't both capture settings.
if ! mkdir "$LOCK" 2>/dev/null; then
  if [[ -f "$PIDFILE" && ! -L "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "already running"; exit 0
  fi
  rm -rf "$LOCK"                      # stale lock from a guard that died
  mkdir "$LOCK" 2>/dev/null || { echo "could not take the lock" >&2; exit 5; }
fi

# Remember exactly what we change, so "off" puts back what was there and nothing else.
if ifconfig awdl0 2>/dev/null | head -1 | grep -q '<UP'; then awdl_was_up=1; else awdl_was_up=0; fi
lp_battery=$(pmset -g custom | awk '/^Battery Power:/{s=1} /^AC Power:/{s=0} s&&$1=="lowpowermode"{print $2; exit}')
lp_ac=$(pmset -g custom | awk '/^AC Power:/{s=1} /^Battery Power:/{s=0} s&&$1=="lowpowermode"{print $2; exit}')
tm_was=$(defaults read /Library/Preferences/com.apple.TimeMachine AutoBackup 2>/dev/null || echo 0)

[[ "$lp_battery" == "1" ]] && pmset -b lowpowermode 0
[[ "$lp_ac" == "1" ]] && pmset -c lowpowermode 0
if [[ "$tm_was" == "1" ]]; then tmutil stopbackup 2>/dev/null; tmutil disable 2>/dev/null; fi
ifconfig awdl0 down 2>/dev/null

restore() {
  [[ "$awdl_was_up" == "1" ]] && ifconfig awdl0 up 2>/dev/null
  [[ "$lp_battery" == "1" ]] && pmset -b lowpowermode 1
  [[ "$lp_ac" == "1" ]] && pmset -c lowpowermode 1
  [[ "$tm_was" == "1" ]] && tmutil enable 2>/dev/null
  rm -f "$PIDFILE"
  rmdir "$LOCK" 2>/dev/null
}

# Detach: the administrator prompt returns at once, the loop carries on.
(
  trap restore EXIT
  trap 'exit 0' TERM INT HUP
  started=$SECONDS
  while flag_ok; do
    (( SECONDS - started < MAX_SECONDS )) || break
    ifconfig awdl0 down 2>/dev/null
    sleep 5
  done
) </dev/null >/dev/null 2>&1 &
echo $! > "$PIDFILE"   # bash 3.2 (macOS) cannot report a subshell pid from inside, so record it here
disown
echo "started"
"""#
}
