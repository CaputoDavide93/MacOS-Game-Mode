/// The Game Mode guard, run once per session as root after the administrator prompt.
/// It lives inside the app binary, not as a file in the bundle, so nothing on disk can be
/// swapped between the user's approval and the run. See D8, D13 and D14 in docs/decisions.md.
public enum GuardScript {
    /// Exists while a guard holds the session (the app waits for it to go on "off").
    public static let lockPath = "/var/run/game-ready/lock"
    /// The running guard's pid, readable by the app to tell a live guard from a dead one.
    public static let pidPath = "/var/run/game-ready/guard.pid"
    /// The settings as they were before Game Mode. Outside /var/run so a restart keeps it.
    public static let journalPath = "/var/db/game-ready/originals"

    public static let source = #"""
#!/bin/bash
# Game Ready — Game Mode guard. Started once per session as root, after the user approves
# the administrator prompt. While the flag file exists it keeps the AirDrop/Handoff radio
# (awdl0) down, with Low Power Mode off, Time Machine paused and automatic macOS and App Store
# update downloads paused; when the flag goes it restores exactly what it changed, then exits.
#
#   bash -c "$SOURCE" game-mode-guard <flag-file>     start a session
#   bash -c "$SOURCE" game-mode-guard --restore       put back what a dead guard left changed
#   bash -c "$SOURCE" game-mode-guard <flag-file> --airdrop-session
#                                                     also remove the AirDrop profile on "off"
#   bash -c "$SOURCE" game-mode-guard --remove-airdrop   remove the AirDrop profile now
#
# The flag must be gamemode.on inside a user's own Application Support/Game Ready folder,
# a regular file (not a symlink) owned by that user. It is re-checked on every loop, so a
# flag swapped for a link or another file after start stops the guard.
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin

FLAG="${1:-}"
EXTRA="${2:-}"
AD_PROFILE=io.github.caputodavide93.gameready.airdrop   # AirDropProfile.identifier
STATE_DIR=/var/run/game-ready
PIDFILE="$STATE_DIR/guard.pid"
LOCK="$STATE_DIR/lock"
JOURNAL_DIR=/var/db/game-ready   # survives a restart, unlike /var/run
JOURNAL="$JOURNAL_DIR/originals"
MAX_SECONDS=$((12 * 3600))       # safety net: never run longer than a long gaming day

[[ $EUID -eq 0 ]] || { echo "must run as root" >&2; exit 1; }
# Is Game Ready's AirDrop profile installed? "yes", "no", or "unknown" when the list can't be
# read: only a list that was read and lacks the exact identifier counts as gone.
ad_state() {
  local out
  out=$(profiles -P 2>/dev/null) || { echo unknown; return; }
  if printf '%s\n' "$out" | awk -v id="$AD_PROFILE" '/profileIdentifier:/ && $NF == id { f = 1 } END { exit !f }'; then
    echo yes
  else
    echo no
  fi
}
if [[ "$FLAG" == "--remove-airdrop" ]]; then
  [[ $# -eq 1 ]] || { echo "refusing argument" >&2; exit 2; }
  # Only ever this one identifier: Game Ready's own profile.
  profiles remove -identifier "$AD_PROFILE" >/dev/null 2>&1
  [[ "$(ad_state)" == "no" ]] || { echo "the AirDrop profile may still be installed" >&2; exit 8; }
  echo "removed"; exit 0
fi
ad_session=0
ad_arg=0   # this start's own choice; in guard mode it wins over an older journal's
if [[ "$FLAG" == "--restore" ]]; then
  [[ $# -eq 1 ]] || { echo "refusing argument" >&2; exit 2; }
  MODE=restore
else
  [[ $# -le 2 ]] || { echo "refusing argument" >&2; exit 2; }
  case "$EXTRA" in
    "") ;;
    --airdrop-session) ad_session=1; ad_arg=1 ;;
    *) echo "refusing argument" >&2; exit 2 ;;
  esac
  MODE=guard
  [[ "$FLAG" =~ ^/Users/([A-Za-z0-9._-]+)/Library/Application\ Support/Game\ Ready/gamemode\.on$ ]] \
    || { echo "refusing flag path" >&2; exit 2; }
  owner="${BASH_REMATCH[1]}"
fi

flag_ok() {
  [[ -f "$FLAG" && ! -L "$FLAG" ]] && [[ "$(stat -f %Su "$FLAG" 2>/dev/null)" == "$owner" ]]
}
[[ $MODE == restore ]] || flag_ok || { echo "flag missing, a link, or not owned by $owner" >&2; exit 3; }

# A pid names a live guard only if that process is bash: a pid left by a killed guard may
# since belong to something else.
alive() {
  local p
  [[ -f "$1" && ! -L "$1" ]] || return 1
  p=$(cat "$1" 2>/dev/null)
  [[ "$p" =~ ^[0-9]+$ ]] && kill -0 "$p" 2>/dev/null && [[ "$(ps -p "$p" -o comm= 2>/dev/null)" == *bash ]]
}
age_of() { echo $(( $(date +%s) - $(stat -f %m "$1" 2>/dev/null || echo 0) )); }

mkdir -p "$STATE_DIR" && chmod 755 "$STATE_DIR"
TOKEN="$$.$RANDOM.$(date +%s)"
# One guard at a time: mkdir is atomic, so two starts can't both capture settings.
if ! mkdir "$LOCK" 2>/dev/null; then
  if alive "$PIDFILE" || alive "$LOCK/pid"; then echo "already running"; exit 0; fi
  # No owner recorded yet: another start is between taking the lock and writing its pid.
  if [[ ! -f "$LOCK/pid" ]] && (( $(age_of "$LOCK") < 30 )); then echo "another start in progress" >&2; exit 5; fi
  # Reclaim a dead guard's lock under a second lock, and look again inside it, so two starts
  # that both saw it stale can't both reclaim it.
  [[ -d "$LOCK.reclaim" ]] && (( $(age_of "$LOCK.reclaim") >= 30 )) && rmdir "$LOCK.reclaim" 2>/dev/null
  mkdir "$LOCK.reclaim" 2>/dev/null || { echo "another start in progress" >&2; exit 5; }
  if alive "$PIDFILE" || alive "$LOCK/pid"; then rmdir "$LOCK.reclaim"; echo "already running"; exit 0; fi
  if [[ -d "$LOCK" && ! -f "$LOCK/pid" ]] && (( $(age_of "$LOCK") < 30 )); then
    rmdir "$LOCK.reclaim"; echo "another start in progress" >&2; exit 5   # a fresh start took it meanwhile
  fi
  rm -rf "$LOCK"
  mkdir "$LOCK" 2>/dev/null || { rmdir "$LOCK.reclaim"; echo "could not take the lock" >&2; exit 5; }
  echo $$ > "$LOCK/pid"; echo "$TOKEN" > "$LOCK/owner"
  rmdir "$LOCK.reclaim"
fi
echo $$ > "$LOCK/pid"
echo "$TOKEN" > "$LOCK/owner"
# Only the lock's owner lets go of it.
release() {
  [[ "$(cat "$LOCK/owner" 2>/dev/null)" == "$TOKEN" ]] || return 0
  rm -f "$PIDFILE"; rm -rf "$LOCK"
}

SU=/Library/Preferences/com.apple.SoftwareUpdate      # AutomaticDownload: macOS updates
AS=/Library/Preferences/com.apple.commerce            # AutoUpdate: App Store apps
# su_dl/as_up: 1 or 0 as set, empty when the key isn't set (restored by deleting it).
# "0" also stands for "nothing to put back", so a journal from before these keys restores none.
awdl_was_up=0; lp_battery=""; lp_ac=""; tm_was=0; su_dl=0; as_up=0
su_seen=0; as_seen=0   # whether the journal had them (one from an older version may not)
# key=value lines, checked one by one; the file is never executed.
read_journal() {
  local k v
  while IFS='=' read -r k v; do
    [[ "$v" =~ ^[01]?$ ]] || continue
    case "$k" in
      awdl_was_up) awdl_was_up=${v:-0} ;;
      lp_battery)  lp_battery=$v ;;
      lp_ac)       lp_ac=$v ;;
      tm_was)      tm_was=${v:-0} ;;
      ad_session)  [[ "$v" == "1" ]] && ad_session=1 ;;
      su_dl)       su_dl=$v; su_seen=1 ;;
      as_up)       as_up=$v; as_seen=1 ;;
    esac
  done < "$JOURNAL"
}

# The journal goes only once every lasting setting is back; otherwise it stays for a retry.
# (The AirDrop radio isn't one: a restart brings it back by itself.)
restored_all=1
# put_back <domain> <key> <original>: 1 → on again, empty → unset again, 0 → untouched.
put_back() {
  case "$3" in
    1) defaults write "$1" "$2" -bool true || restored_all=0 ;;
    "") defaults delete "$1" "$2" 2>/dev/null
        defaults read "$1" "$2" >/dev/null 2>&1 && restored_all=0 ;;   # still there: retry later
  esac
}
# A key's value as 1/0, empty when it isn't set, and 0 ("leave it alone") when it can't be
# read for any other reason: guessing "not set" would make restore delete a real value.
read_bool() {
  local v
  if v=$(defaults read "$1" "$2" 2>&1); then
    [[ "$v" == "0" ]] && echo 0 || echo 1
  elif [[ "$v" == *"does not exist"* || "$v" == *"Could not find key"* ]]; then   # both wordings occur
    echo ""
  else
    echo 0
  fi
}
restore() {
  [[ "$awdl_was_up" == "1" ]] && ifconfig awdl0 up 2>/dev/null
  if [[ "$lp_battery" == "1" ]]; then pmset -b lowpowermode 1 || restored_all=0; fi
  if [[ "$lp_ac" == "1" ]]; then pmset -c lowpowermode 1 || restored_all=0; fi
  if [[ "$tm_was" == "1" ]]; then tmutil enable 2>/dev/null || restored_all=0; fi
  put_back "$SU" AutomaticDownload "$su_dl"
  put_back "$AS" AutoUpdate "$as_up"
  # "During Game Mode" AirDrop block: the profile goes with the session.
  if [[ "$ad_session" == "1" ]]; then
    profiles remove -identifier "$AD_PROFILE" >/dev/null 2>&1
    [[ "$(ad_state)" == "no" ]] || restored_all=0   # still there, or can't tell: retry later
  fi
  [[ $restored_all == 1 ]] && rm -f "$JOURNAL"
  release
}

# A guard that never got to restore (a restart, a kill) left the true originals behind:
# keep those, not today's values, which are the ones it changed.
if [[ -f "$JOURNAL" && ! -L "$JOURNAL" ]]; then
  read_journal
elif [[ $MODE == restore ]]; then
  release; echo "nothing to restore"; exit 0
else
  # Remember exactly what we change, so "off" puts back what was there and nothing else.
  if ifconfig awdl0 2>/dev/null | head -1 | grep -q '<UP'; then awdl_was_up=1; fi
  lp_battery=$(pmset -g custom | awk '/^Battery Power:/{s=1} /^AC Power:/{s=0} s&&$1=="lowpowermode"{print $2; exit}')
  lp_ac=$(pmset -g custom | awk '/^AC Power:/{s=1} /^Battery Power:/{s=0} s&&$1=="lowpowermode"{print $2; exit}')
  tm_was=$(defaults read /Library/Preferences/com.apple.TimeMachine AutoBackup 2>/dev/null || echo 0)
  [[ "$tm_was" == "1" ]] || tm_was=0
fi

if [[ $MODE == guard ]]; then
  # Whether the AirDrop profile goes with this session is this session's choice (an "Always"
  # user keeps it), not whatever an older session's journal said.
  ad_session=$ad_arg
  # Settings this journal doesn't hold yet are still as the user left them: record them now.
  [[ $su_seen == 1 ]] || su_dl=$(read_bool "$SU" AutomaticDownload)
  [[ $as_seen == 1 ]] || as_up=$(read_bool "$AS" AutoUpdate)
  mkdir -p "$JOURNAL_DIR" && chmod 755 "$JOURNAL_DIR"
  printf 'awdl_was_up=%s\nlp_battery=%s\nlp_ac=%s\ntm_was=%s\nsu_dl=%s\nas_up=%s\nad_session=%s\n' \
    "$awdl_was_up" "$lp_battery" "$lp_ac" "$tm_was" "$su_dl" "$as_up" "$ad_session" > "$JOURNAL.tmp" \
    && mv -f "$JOURNAL.tmp" "$JOURNAL" \
    || { echo "could not save the original settings" >&2; release; exit 6; }
fi

if [[ $MODE == restore ]]; then
  restore
  [[ $restored_all == 1 ]] || { echo "some settings could not be restored" >&2; exit 7; }
  echo "restored"; exit 0
fi

[[ "$lp_battery" == "1" ]] && pmset -b lowpowermode 0
[[ "$lp_ac" == "1" ]] && pmset -c lowpowermode 0
if [[ "$tm_was" == "1" ]]; then tmutil stopbackup 2>/dev/null; tmutil disable 2>/dev/null; fi
# Downloads already under way finish; no new one starts while you play.
[[ "$su_dl" != "0" ]] && defaults write "$SU" AutomaticDownload -bool false
[[ "$as_up" != "0" ]] && defaults write "$AS" AutoUpdate -bool false
ifconfig awdl0 down 2>/dev/null

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
echo $! > "$LOCK/pid"
disown
echo "started"
"""#
}
