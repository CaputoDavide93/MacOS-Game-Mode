# Testing

## Automated

| What | Command | Covers |
|---|---|---|
| Core tests | `cd Packages/GameReadyCore && swift test` | Every grading rule, the verdict, ping parsing, the 429 speed-test rule, the live layer split, history (append, prune, corrupt lines, failed writes), CSV, DNS bytes, the guard script (parses with macOS bash 3.2 and refuses to run without root, both executed; its flag re-check, lock and per-setting restore are source-level assertions, not executed, because the script needs root), and the host allowlist |
| Strings | `python3 tools/gen_strings.py --check` | Every finding, check, step, event and checklist item has English and Italian copy; the catalogue is current |
| Diagram | `python3 tools/gen_diagram.py --check` | `docs/assets/architecture-*.svg` match the code that draws them |
| Everything | `scripts/check.sh` | All of the above plus a Release build |

## On a real Mac

Device-only behaviour. ✅ verified · ⚠️ partly · ⬜ not yet run.

| Behaviour | Status | Where / how |
|---|---|---|
| Full check on Ethernet: all probes return, verdict "warning" only for the checklist | ✅ | M-series Mac, macOS 27, wired; `--check` JSON (2 Oct 2026) |
| Speed test: download and upload measured, 429 handled | ⚠️ | Measured on the same run; the 429 fallback is covered by unit tests, not yet seen live |
| Full check on Wi-Fi with AirDrop on: Mac → router flagged | ⬜ | Expected: red hop with spikes; green after Game Mode |
| Game Mode on: one password prompt, AirDrop radio stays down 30 min | ⬜ | Watch `ifconfig awdl0` every 5 s |
| Game Mode off restores AirDrop, Low Power Mode and Time Machine to their previous values (the only place restore is executed) | ⬜ | Compare `pmset -g`, `tmutil` status and `ifconfig awdl0` before/after |
| Quit with Game Mode on → restored before exit | ⬜ | |
| Kill the app with Game Mode on → reopening offers "Turn off" | ⬜ | |
| Live watch labels a router spike as "Mac's Wi-Fi" and a server-only spike as "Internet" | ⬜ | Logic covered by unit tests |
| AirDrop No One / Handoff off / Universal Control off take effect, and come back on "off" | ⬜ | The `defaults` round trip is tested on a throwaway domain; the effect on the real agents is not yet seen |
| Better xCloud: read with an xbox.com tab open; tune on Game Mode on; original values back on "off" | ⬜ | Script generation is compiled (`osacompile`) and executed (JavaScriptCore) in tests; not yet run against the real page |
| Play opens each service (and the GeForce NOW app when installed) | ⬜ | |
| VoiceOver reads every result as "name: grade. sentence" | ⬜ | |
| Light and dark render correctly | ✅ | `--screenshots`, reviewed by eye |
