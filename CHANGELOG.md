# Changelog

All notable changes to this project are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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

[Unreleased]: https://github.com/CaputoDavide93/MacOS-Game-Mode/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/CaputoDavide93/MacOS-Game-Mode/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/CaputoDavide93/MacOS-Game-Mode/releases/tag/v0.1.0
