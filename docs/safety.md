# Safety: what Game Ready changes, and how it comes back

Everything below is read from the code (`GuardScript.swift`, `SessionChanges.swift`,
`SharingSettings.swift`, `GameModeController.swift`). **None of it has yet been run on a real
Mac end to end**: the restore logic is tested against stub commands and a throwaway defaults
domain, not against the real system. [testing.md](testing.md) lists each row and its status.

Checking (**Check now**) changes nothing. Only Game Mode, and the optional features below, do.

## Changes made as root (one administrator password prompt)

| Setting | How it is changed | How it is restored |
|---|---|---|
| AirDrop/Handoff radio (`awdl0`) | `ifconfig awdl0 down`, re-asserted while Game Mode runs | `ifconfig awdl0 up` if it was up before |
| Low Power Mode | `pmset -b` / `-c lowpowermode 0`, only if it was on | Set back to 1 on the same power source |
| Time Machine automatic backups | `tmutil stopbackup` and `tmutil disable`, only if it was on | `tmutil enable` |
| Automatic macOS update downloads | `defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool false` | Written back, or deleted if it was not set |
| Automatic App Store updates | `defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool false` | Same |

The original values are written to `/var/db/game-ready/originals` (root-owned) **before** the
first change, and deleted only after everything is restored.

## Changes made as you (no password)

| Setting | Restored from |
|---|---|
| Handoff, Universal Control, AirPlay Receiver (user `defaults`) | `~/Library/Application Support/Game Ready/restore-plan.json`, each value read back to confirm. If a value cannot be read or the plan cannot be saved, nothing is changed |
| Mac kept awake (a display-sleep assertion) | Released when Game Mode ends |
| Apps from your Settings list asked to quit | Not restored. Game Ready asks each app to quit with the normal quit request; an app with unsaved work can show its own save prompt. **Do not put an app with unsaved work on the list.** How apps behave under this has not been run on a real Mac |

## Optional, only if you turn them on

- **AirDrop off**: a configuration profile (`io.github.caputodavide93.gameready.airdrop`)
  that **you** approve in System Settings → General → Device Management. Game Ready never
  installs it silently. It is removed on "off" if you chose "while Game Mode is on", or from
  Settings → Remove, after a password prompt.
- **Better xCloud tuning**: reads and writes `localStorage["BetterXcloud"]` in an xbox.com tab
  through the browser's Apple Events support, which you must enable in the browser. Your
  original values are put back on "off".

## What needs the root password

- Turning Game Mode **on**: one prompt.
- Turning it **off**: no prompt, because it only deletes the flag file the root script watches.
- The exception: if the Mac restarted or the script died mid-session, "off" runs the script
  with `--restore` and asks again.
- Removing the AirDrop-off profile from Settings: its own prompt.

The root script is compiled into the app, takes only fixed arguments, refuses symlinks and
files not owned by you, and stops after 12 hours at most. Full list and how to report a
problem: [SECURITY.md](../SECURITY.md).

## If something is left changed

Open Game Ready and choose **Turn off** when it offers. If you cannot, [uninstall.md](uninstall.md)
has the manual commands for each setting.
