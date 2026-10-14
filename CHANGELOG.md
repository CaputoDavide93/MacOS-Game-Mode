# Changelog

All notable changes to this project are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Game Mode also turns off the AirPlay Receiver, and stops new automatic macOS and App Store
  update downloads from starting during the session (a multi-GB download fills the line; one
  already under way finishes). Both are saved first and put back on "off"; the update
  settings ride on the same single password prompt.

### Changed
- `tools/gen_icon.sh` is now `tools/gen-icon.sh`, the house name for shell scripts.

### Fixed
- Found in a Codex review of the whole app:
  - If the Mac restarted (or the guard was killed) during Game Mode, Low Power Mode and Time
    Machine stayed changed for good. The guard now saves the originals in
    `/var/db/game-ready/originals` before changing anything; turning off from the "left on"
    banner puts them back (a second password prompt), and the file stays until they are.
  - Two Game Mode starts at once could both take the guard's lock. The lock now records its
    owner, a dead guard's lock is reclaimed by one start only, and a pid since reused by
    another program no longer counts as a running guard.
  - "Off" reported done before the guard had finished restoring, and a quick "on" could meet the
    old guard on its way out. "Off" now waits up to 15 s for the guard to exit, and "on" waits
    for an old guard to finish first.
  - When the guard stopped after 12 hours, or another window turned Game Mode off, the app kept
    saying "on" and skipped restoring AirDrop, Handoff, Universal Control and Better xCloud.
    Every end of a session now runs the full "off".
  - A failed password prompt or guard start was never shown; cancelling the prompt stays quiet.
  - A sharing setting that didn't change, or didn't come back, was reported as fine. Both now
    show a message, and what didn't come back is retried on the next check.
  - An internet target that never answered could hide behind an amber reading ("needs
    attention" instead of "couldn't measure").
  - The speed test could pass with no latency-under-load reading for one direction.
  - The first check said "nothing else seems to be using the line" with nothing to compare with.
  - Measuring CPU could crash the app once the kernel's tick counters wrapped (weeks of uptime).
  - The live dot could stay green while the server stopped answering; a new session showed the
    last session's readings; the live watch kept pinging the old router after a network change;
    GeForce NOW and Luna sessions were watched against Xbox's server.
  - After Game Mode turned on or off, the screen still showed the Mac and apps as they were before.
  - Apps were listed as closed even when they refused to quit.
  - Delete All Data looked done even when the file couldn't be deleted.
  - A history line cut short by a crash swallowed the next record.
  - A failed Better xCloud read kept showing the previous browser's settings.
- While a check ran, Basic still showed a greyed-out "Check now" (or "Fix & Play"); the button
  now stays hidden until the check finishes. Advanced's button reads "Checking…".
- "Turn on Game Mode" read as if it switched the Wi-Fi off. It now says the Wi-Fi stays on and
  only AirDrop, Handoff and Universal Control go off. Basic's window is a little taller so it fits.

## [0.3.0] - 2026-10-02

### Added
- Basic and Advanced views. Basic: one status and **Fix & Play**, which applies every fix and opens the game. Advanced: sidebar, readiness score, monospaced readouts, grouped results.

### Changed
- Native macOS surfaces and text everywhere; one brand colour (ready green).

### Fixed
- Game Mode turned itself back off straight after the password prompt, with "the undo plan
  can't be read", whenever there was no undo plan yet (the usual case). Compiler warnings now
  fail the build; one had flagged this.
- Screenshots no longer read or write the real preferences, history or undo plan.
- Quitting during a check could leave Game Mode on; quit now waits for a switch in progress and
  then turns Game Mode off.
- A second Fix & Play during the password prompt could open the game before Game Mode was on.
- An undo plan that can't be read is now reported instead of silently skipped.
- Basic said "Ready to play" for some warnings with no advice; it now points to Advanced.

## [0.2.0] - 2026-10-02

### Added
- Spanish, French, German, Portuguese (Brazil), Japanese, Chinese (Simplified), Korean and Hindi. Machine-assisted, marked for native review.

## [0.1.1] - 2026-10-02

### Fixed
- The app reported its version as 1.0; it now shows the release version. The release build fails if the two ever differ.

## [0.1.0] - 2026-10-02

### Added
- Pre-flight check: connection, Wi-Fi signal, Mac → router hop, internet latency, UDP loss
  (IPv4 and IPv6), IPv6, speed with latency under load, line busy, Mac state, background apps,
  checklist. One verdict: Ready, Ready with a warning, Not ready, or Couldn't finish.
- Game Mode: AirDrop/Handoff radio off and kept off, Low Power Mode off, Time Machine paused,
  no sleep, noisy apps quit. One administrator prompt; everything restored on "off" or quit.
- Live watch in the menu bar while Game Mode is on, labelling each hiccup as the Mac's Wi-Fi,
  the internet, or the Mac.
- History of checks and sessions (90 days), CSV export, Delete All Data.
- Game Mode also sets AirDrop to No One and turns off Handoff and Universal Control, and restores every setting from a saved plan, even after a crash.
- Play opens Xbox Cloud Gaming, GeForce NOW (its Mac app when installed) or Amazon Luna.
- Better xCloud: read its settings to tick the checklist; opt-in tuning during Game Mode, undone on "off".
- English and Italian.
- A game server that never answers, or a Wi-Fi link with no rate, counts as "couldn't measure", never a pass.
- `--check` (JSON results) and `--screenshots <dir>` command-line modes.
- App icon drawn as SVG (`App/Design/AppIcon.svg`), rendered by `tools/gen_icon.sh`.

[Unreleased]: https://github.com/CaputoDavide93/MacOS-Game-Mode/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/CaputoDavide93/MacOS-Game-Mode/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/CaputoDavide93/MacOS-Game-Mode/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/CaputoDavide93/MacOS-Game-Mode/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/CaputoDavide93/MacOS-Game-Mode/releases/tag/v0.1.0
