# Evidence: does AirDrop's radio change latency on your Mac?

Game Ready's pitch is that cloud-gaming lag has separate causes, and one of them is the Mac's
own Wi-Fi pausing for AirDrop and Handoff (the AWDL radio). That is a hypothesis. This page
describes a way to test it on your own Mac, what the test can and cannot show, and how to
share a result, including a result that finds nothing.

As of this page, **no results have been collected**. The tool is tested on invented fixture
data only (see [testing.md](testing.md)). Until real runs are published, treat the AWDL claim
as unproven.

## The tool

```bash
scripts/measure_lag.py --internet <a public host you choose>      # live, asks before each run
scripts/measure_lag.py --dry-run --fixture tests/fixtures/fixture-null.json   # no network
```

Python 3 standard library only; macOS `ping` and `route`. It never changes a setting: you put
the Mac in each condition yourself. The only traffic is ICMP to your router (detected from the
default route, or `--router`) and the one public host you pass; nothing is hard-coded, and
neither address is written to the report. It reads `ifconfig awdl0` (read-only) before and
after each run. It does not read the Wi-Fi network name.

Options worth knowing: `--runs` (per condition, minimum 5), `--duration` (seconds per run,
default 300), `--link "5 GHz, channel 36"` and `--notes` (free text for the report), `--seed`
(which condition goes first), `--yes` (do not wait for Enter between runs).

## The protocol

1. **Fix the setup.** One Mac, one spot, 5 GHz or 6 GHz Wi-Fi, same position for every run,
   the household otherwise quiet (no downloads, no video calls). Note the macOS version, band,
   channel and link rate. Do the same test on Ethernet if you can: AWDL should not matter on a
   wire, so it is a useful control.
2. **Two conditions**, set by you before each run:
   - **quiet**: AirDrop set to Receiving Off, Handoff off in System Settings, no nearby Apple
     device actively probing.
   - **active**: AirDrop open to Everyone (10 minutes), a second Apple device nearby, signed
     in to the same Apple ID, repeatedly opening the AirDrop sheet; Handoff on.
3. **Alternate**: quiet, active, quiet, active ... at least 5 of each (10 runs). Which
   condition goes first is a seeded coin flip, recorded in the report. Alternating spreads
   slow changes in the Wi-Fi environment across both conditions.
4. **Each run** pings the router and the public host side by side at 5 pings per second for
   `--duration` seconds (default 300). Run it longer if you can; 600 seconds matches the
   original 10-minute plan.
5. **One question, decided in advance.** The tool compares the per-run **p95** round-trip time,
   quiet against active, with an exact rank-sum permutation test. It calls a difference only if
   p < 0.05 **and** the median gap is at least 1 ms. Everything else (p50, p99, max, jitter,
   loss) is listed for every run but is descriptive, not a second chance to find something.
6. **Report all runs**, not the best ones. The tool does.

Outputs go to `measure-out/<timestamp>/`: `samples.csv` (every reply), `summary.csv` (one row
per run and target) and `report.md`.

## What a result means

| Report says | It means | It does not mean |
|---|---|---|
| Higher when active | On this Mac, here, p95 router (or internet) latency was higher with AWDL activity | That games feel worse, or that this happens on other Macs |
| No clear difference | These runs could not see one at this spot | That AWDL never matters. 5 runs per side only detect large effects |
| Lower when active | Unexpected; treat as noise or a setup problem until it repeats | That AirDrop speeds things up |
| Inconclusive | Fewer than 5 usable runs per condition (a run needs at least half its replies) | Anything |

The test also does not cover: a game stream itself, other Macs or routers, long-term
behaviour, or whether the radio really went quiet. The `awdl0` column helps with the last one,
but AWDL can stay up for other reasons, so it is evidence, not proof.

If you want to look at a game service's own numbers, read its in-stream stats overlay during
a run and quote it as "I read the service's overlay". Those overlays differ per service and
are not part of this tool.

## Sharing a result

Share what you got, including nothing. Copy this template and fill it in; attach
`report.md` and `summary.csv` unedited.

```text
Mac: <model, chip>          macOS: <version>
Link: <Wi-Fi band, channel, link rate>  or  Ethernet <speed>
Router: <make/model, optional>   Position: <same spot for all runs: yes/no>
Runs: <n> per condition, <duration> s each, order <Q A Q A ...>
Router p95: quiet <x> ms, active <y> ms, p = <p>  -> <verdict word from the report>
Internet p95: quiet <x> ms, active <y> ms, p = <p> -> <verdict word from the report>
awdl0 during quiet runs: <down / up / mixed>
What I did not control: <e.g. other devices on the Wi-Fi>
Files: report.md, summary.csv
```

Before posting, check the files: they hold no network name or address, but your `--notes` and
`--link` text goes in as typed.

If the result is null, say "no clear difference at my spot in N runs", not "AirDrop does not
matter". If it is positive, say "on my Mac, in these runs", not "AirDrop causes lag".

## How the tool is tested

`tests/test_measure_lag.py` covers the percentile and jitter maths, the permutation test
(including its exact floor for 5 against 5), the verdict rules (clear gap, noise, a tiny but
consistent gap, the opposite direction, too few runs, runs with lost replies), the macOS ping
parser, host validation, the alternating order, and the report and CSVs generated from two
fixtures: one with an invented router effect and one with none. The fixtures are invented
numbers and every report made from them is stamped "DRY RUN". What the tool measures on a real
Mac has **not been run yet**.
