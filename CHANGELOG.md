# Changelog

All notable changes to this project are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Pre-flight check: connection, Wi-Fi signal, Mac → router hop, internet latency, UDP loss
  (IPv4 and IPv6), IPv6, speed with latency under load, line busy, Mac state, background apps,
  checklist. One verdict: Ready, Ready with a warning, Not ready, or Couldn't finish.
- Game Mode: AirDrop/Handoff radio off and kept off, Low Power Mode off, Time Machine paused,
  no sleep, noisy apps quit. One administrator prompt; everything restored on "off" or quit.
- Live watch in the menu bar while Game Mode is on, labelling each hiccup as the Mac's Wi-Fi,
  the internet, or the Mac.
- History of checks and sessions (90 days), CSV export, Delete All Data.
- English and Italian.
- `--check` (JSON results), `--screenshots <dir>` and `--icon <dir>` command-line modes.
