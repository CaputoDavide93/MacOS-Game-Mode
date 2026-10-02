# Decisions

Numbered, dated, and never rewritten: a changed mind is a new entry that supersedes an old one.

## D1 — SwiftUI, not Flutter (2026-10-02)
The house default for apps is Flutter. This app is Mac-only and lives on system APIs:
CoreWLAN (Wi-Fi link), IOKit (power, controllers), `SCDynamicStore` (primary interface),
`NSRunningApplication`, `IOPMAssertion`, a menu-bar extra, and later a privileged helper
(`SMAppService`). Flutter would be a thin shell over native code for all of it.

## D2 — Logic in a pure Swift package (2026-10-02)
`Packages/GameReadyCore` holds models, thresholds, grading, the verdict, speed-test
validation, the live-watch classifier and history. No AppKit, SwiftUI, sockets or
processes. Probes in the app produce plain values; the package turns them into results.
This keeps every rule unit-testable with `swift test`, without the app.

## D3 — Results are codes, words live in the UI (2026-10-02)
`Finding` is an enum; only the app maps it to localised text. Logs and history store codes
and numbers, never user content.

## D4 — "Couldn't measure" is never green (2026-10-02)
`Grade.unknown` counts as amber in the verdict. If an essential check (connection, Wi-Fi
hop, internet, UDP) can't be measured, the verdict is **incomplete**, not "ready".

## D5 — The layer split (2026-10-02)
Two pings run side by side: to the router (the Mac's own Wi-Fi hop) and to the game
service. Router bad → the Mac's Wi-Fi. Router fine and server bad → the internet. Server
bad with no router reading → no blame. This is the test that separates AirDrop's radio
(AWDL) pausing the Wi-Fi from a busy household line.

## D6 — A speed test counts only if the bytes arrived (2026-10-02)
Rate-limited speed endpoints answer HTTP 429 with a 1-byte body in a few milliseconds,
which reads as an instant, perfect test. A transfer is valid only with a 2xx status and
≥ 90% of the expected bytes (or ≥ 1 MB when we cut it short on time). No valid transfer →
fall back to the next provider; none at all → "couldn't measure". At most one speed test
every 2 minutes: it fills the whole household line.

## D7 — Latency under load is measured to the internet, not the router (2026-10-02)
Bufferbloat sits in the gateway's queue to the provider, so the loaded ping must cross it.
The spec draft said "router side"; that would miss exactly the problem it's meant to find.
Loaded latency pings `1.1.1.1` during the download and upload phases; the rise is
loaded median − idle median.

## D8 — Game Mode without a password on "off" (2026-10-02)
The privileged part (AirDrop radio down, Low Power Mode, Time Machine) runs as a small root
script started once per session with an administrator prompt. It keeps the AirDrop radio
down every 5 s while a **flag file in the user's own Application Support folder** exists,
and restores every setting it changed when the flag goes. Turning Game Mode off is
deleting that file: no second prompt. The script validates the flag path, keeps its own
state file, and refuses a second copy of itself. When a Developer ID is available, this
moves to an `SMAppService` daemon with fixed operations (spec §3.2); the script stays as
the fallback.

## D9 — History is JSON lines, not SQLite (2026-10-02)
A few hundred records over 90 days. Append-only JSON lines need no schema migrations,
survive a crash mid-write (a bad last line is skipped), and are easy to inspect. SQLite
would add a C API surface for no benefit at this size.

## D10 — No sandbox (2026-10-02)
The app runs `/sbin/ping`, reads `tmutil` status, quits other apps on request and starts a
root script with the user's approval. None of that is allowed in the App Sandbox, so the
app is distributed outside the App Store, hardened-runtime signed when a Developer ID exists.

## D11 — Ping via `/sbin/ping`, UDP via Network.framework (2026-10-02)
ICMP needs raw sockets or the system ping binary; `/sbin/ping` is setuid, stable, and its
output format is parsed by `PingLine` (tested). UDP loss is measured with DNS queries over
`NWConnection`, which is what a game stream rides on.

## D12 — Fallback speed server: Hetzner over HTTPS (2026-10-02)
The first fallback tried (a UK-only mirror) didn't answer over HTTPS, and plain HTTP would
need an App Transport Security exception. Hetzner's public mirror serves a 1 GB file over
HTTPS and is reachable worldwide, so it is the download fallback when Cloudflare rate-limits.
Upload has no fallback: if Cloudflare refuses, upload is "couldn't measure" (never a pass).
