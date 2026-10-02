# 🔒 Security Policy

## Reporting a vulnerability

Please report vulnerabilities privately via
[GitHub Security Advisories](https://github.com/CaputoDavide93/MacOS-Game-Mode/security/advisories/new)
rather than opening a public issue. You should get a response within a week.

## Data handling

- **No accounts, analytics, crash reporting or update checks.** The only network traffic is
  test traffic to the hosts in `Packages/GameReadyCore/Sources/GameReadyCore/Endpoints.swift`
  (Cloudflare and Hetzner speed tests, Cloudflare DNS `1.1.1.1`, the Xbox Cloud Gaming front door).
  A test fails on any other host in the sources.
- **What stays on the Mac:** check results and game-session summaries, as JSON lines in
  `~/Library/Application Support/Game Ready/history.jsonl`, pruned after 90 days. They hold
  grades, finding codes and numbers (latency, speed, signal), never the network name, an
  address or anything typed. **Delete All Data** in History removes the file.
- **Settings** (browser, apps to quit, checklist ticks) live in the app's UserDefaults.

## The privileged part

Game Mode runs one script as root, after macOS asks for an administrator password.

- The script's text is compiled into the app binary (`GuardScript.swift`); nothing is read
  from a file that could be swapped before it runs.
- Its only argument is the app's own flag file. The script accepts nothing but
  `/Users/<user>/Library/Application Support/Game Ready/gamemode.on`, refuses symlinks and
  files not owned by that user, re-checks both every 5 seconds while it runs, stops after
  12 hours at most, and refuses to start a second copy.
- It changes three things (the AirDrop/Handoff radio `awdl0`, Low Power Mode per power
  source, Time Machine automatic backups), records their previous values first, and restores
  only what it changed when the flag disappears or the script stops.
- Turning Game Mode off is deleting the flag file; no further root access happens.

## Supported versions

Only the latest commit on `main` is supported.
