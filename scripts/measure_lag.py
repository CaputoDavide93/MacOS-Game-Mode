#!/usr/bin/env python3
"""Measure whether AWDL (AirDrop/Handoff radio) activity changes latency on this Mac.

Alternating protocol: quiet, active, quiet, active ... (at least 5 runs of each).
Each run pings your router and one public host side by side, then the tool writes
samples.csv, summary.csv and report.md. The report states a null result as plainly
as a positive one. See docs/evidence.md.

The tool never changes a system setting: you put the Mac in each condition yourself.
The only network traffic is ICMP to the two targets you name (or your detected router).

  scripts/measure_lag.py --internet 1.1.1.1                       # live, prompts per run
  scripts/measure_lag.py --dry-run --fixture tests/fixtures/…json  # no network, fixture data
"""
from __future__ import annotations

import argparse
import csv
import itertools
import json
import math
import platform
import random
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

QUIET, ACTIVE = "quiet", "active"
MIN_RUNS_PER_CONDITION = 5
PRIMARY_METRIC = "p95"          # declared before any data is seen
MIN_PRACTICAL_MS = 1.0          # a gap smaller than this is not worth calling a difference
ALPHA = 0.05
MIN_DELIVERED_FRACTION = 0.5    # a run with less than half its replies is unusable
MAX_EXACT_COMBINATIONS = 200_000
MONTE_CARLO_DRAWS = 50_000
MIN_PING_INTERVAL = 0.2         # macOS ping refuses a shorter interval without root

TARGET_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.:\-]*$")
REPLY_RE = re.compile(r"icmp_seq=(\d+).*?time[=<]([\d.]+)\s*ms")
SENT_RE = re.compile(r"(\d+) packets transmitted")


# ---------------------------------------------------------------- statistics

def percentile(values: list[float], p: float) -> float:
    """Linear-interpolation percentile (same definition as numpy's default)."""
    if not values:
        raise ValueError("percentile of no values")
    xs = sorted(values)
    if len(xs) == 1:
        return xs[0]
    rank = (p / 100.0) * (len(xs) - 1)
    lo = math.floor(rank)
    hi = math.ceil(rank)
    return xs[lo] + (xs[hi] - xs[lo]) * (rank - lo)


def jitter_ms(rtts_in_order: list[float]) -> float:
    """Mean absolute difference between consecutive replies (RFC 3550 style)."""
    if len(rtts_in_order) < 2:
        return 0.0
    diffs = [abs(b - a) for a, b in zip(rtts_in_order, rtts_in_order[1:])]
    return sum(diffs) / len(diffs)


def summarise(rtts_in_order: list[float], sent: int) -> dict:
    """One run, one target. `rtts_in_order` holds replies only; `sent` is what was sent."""
    got = len(rtts_in_order)
    row = {"sent": sent, "received": got,
           "loss_pct": round(100.0 * (sent - got) / sent, 2) if sent else 100.0}
    if got == 0:
        row.update({k: None for k in ("min", "p50", "p95", "p99", "max", "mean", "stddev", "jitter")})
        return row
    row.update({
        "min": min(rtts_in_order),
        "p50": percentile(rtts_in_order, 50),
        "p95": percentile(rtts_in_order, 95),
        "p99": percentile(rtts_in_order, 99),
        "max": max(rtts_in_order),
        "mean": statistics.fmean(rtts_in_order),
        "stddev": statistics.pstdev(rtts_in_order),
        "jitter": jitter_ms(rtts_in_order),
    })
    return row


def midranks(values: list[float]) -> list[float]:
    order = sorted(range(len(values)), key=lambda i: values[i])
    ranks = [0.0] * len(values)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and values[order[j + 1]] == values[order[i]]:
            j += 1
        for k in range(i, j + 1):
            ranks[order[k]] = (i + j) / 2.0 + 1.0
        i = j + 1
    return ranks


def permutation_p(a: list[float], b: list[float], seed: int = 1) -> float:
    """Two-sided exact permutation test on the rank sum (Mann-Whitney). Monte Carlo if huge."""
    if not a or not b:
        return 1.0
    pooled = a + b
    n_a, n = len(a), len(pooled)
    ranks = midranks(pooled)
    expected = n_a * (n + 1) / 2.0
    observed = abs(sum(ranks[:n_a]) - expected)
    eps = 1e-9
    total = math.comb(n, n_a)
    if total <= MAX_EXACT_COMBINATIONS:
        hits = sum(1 for idx in itertools.combinations(range(n), n_a)
                   if abs(sum(ranks[i] for i in idx) - expected) >= observed - eps)
        return hits / total
    rng = random.Random(seed)
    hits = 0
    for _ in range(MONTE_CARLO_DRAWS):
        rng.shuffle(ranks)
        if abs(sum(ranks[:n_a]) - expected) >= observed - eps:
            hits += 1
    return (hits + 1) / (MONTE_CARLO_DRAWS + 1)


def compare(quiet_runs: list[dict], active_runs: list[dict], metric: str = PRIMARY_METRIC) -> dict:
    """Compare one metric across runs of the two conditions. Returns a verdict dict."""
    usable = lambda runs: [r[metric] for r in runs
                           if r[metric] is not None and r["received"] >= MIN_DELIVERED_FRACTION * r["sent"]]
    q, a = usable(quiet_runs), usable(active_runs)
    out = {"metric": metric, "quiet_values": q, "active_values": a,
           "quiet_median": statistics.median(q) if q else None,
           "active_median": statistics.median(a) if a else None,
           "difference": None, "p_value": None}
    if len(q) < MIN_RUNS_PER_CONDITION or len(a) < MIN_RUNS_PER_CONDITION:
        out["verdict"] = "inconclusive"
        out["why"] = (f"needs at least {MIN_RUNS_PER_CONDITION} usable runs per condition; "
                      f"got {len(q)} quiet and {len(a)} active")
        return out
    diff = out["active_median"] - out["quiet_median"]
    p = permutation_p(q, a)
    out["difference"], out["p_value"] = diff, p
    if p < ALPHA and abs(diff) >= MIN_PRACTICAL_MS:
        out["verdict"] = "higher_when_active" if diff > 0 else "lower_when_active"
        out["why"] = "the gap is larger than run-to-run noise would usually produce"
    else:
        out["verdict"] = "no_clear_difference"
        if p >= ALPHA:
            out["why"] = "the gap is within what run-to-run noise produces"
        else:
            out["why"] = f"the gap is under {MIN_PRACTICAL_MS:g} ms, too small to matter"
    return out


# ------------------------------------------------------------------- parsing

def parse_ping(output: str, requested: int) -> tuple[list[float], int]:
    """Replies in sequence order, and how many probes were sent. Tolerates junk lines."""
    seen: dict[int, float] = {}
    for line in output.splitlines():
        m = REPLY_RE.search(line)
        if m:
            seen.setdefault(int(m.group(1)), float(m.group(2)))
    m = SENT_RE.search(output)
    sent = int(m.group(1)) if m else requested
    return [seen[k] for k in sorted(seen)], sent


def valid_target(t: str) -> bool:
    return bool(TARGET_RE.match(t)) and len(t) <= 253


# --------------------------------------------------------------------- phases

def condition_order(runs_per_condition: int, seed: int) -> list[str]:
    """Strictly alternating, with a seeded coin flip for which condition goes first."""
    first = random.Random(seed).choice([QUIET, ACTIVE])
    second = ACTIVE if first == QUIET else QUIET
    return [c for _ in range(runs_per_condition) for c in (first, second)]


def detect_router() -> str | None:
    try:
        out = subprocess.run(["route", "-n", "get", "default"], capture_output=True,
                             text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    m = re.search(r"gateway:\s*(\S+)", out)
    return m.group(1) if m else None


def awdl_state() -> str:
    """Read-only: is the AWDL interface up? Recorded so the report can show the condition took hold."""
    try:
        out = subprocess.run(["ifconfig", "awdl0"], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return "unknown"
    if out.returncode != 0:
        return "absent"
    first = out.stdout.splitlines()[0] if out.stdout else ""
    return "up" if "<UP" in first else "down"


def live_run(router: str, internet: str, duration: int, interval: float) -> dict[str, tuple[list[float], int]]:
    count = max(1, int(duration / interval))
    procs = {name: subprocess.Popen(["ping", "-n", "-c", str(count), "-i", str(interval), target],
                                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
             for name, target in (("router", router), ("internet", internet))}
    result = {}
    for name, p in procs.items():
        try:
            out, _ = p.communicate(timeout=duration + 30)
        except subprocess.TimeoutExpired:
            p.kill()
            out, _ = p.communicate()
        result[name] = parse_ping(out or "", count)
    return result


def load_fixture(path: Path) -> list[dict]:
    data = json.loads(path.read_text())
    runs = data["runs"]
    for r in runs:
        if r["condition"] not in (QUIET, ACTIVE):
            raise ValueError(f"bad condition {r['condition']!r}")
        for t in ("router", "internet"):
            if t not in r:
                raise ValueError(f"run {r.get('run')} has no {t}")
    return runs


# -------------------------------------------------------------------- output

SUMMARY_FIELDS = ["run", "condition", "awdl0", "target", "sent", "received", "loss_pct",
                  "min", "p50", "p95", "p99", "max", "mean", "stddev", "jitter", "source"]
SAMPLE_FIELDS = ["run", "condition", "target", "seq", "rtt_ms"]


def fmt(v, nd=2):
    return "n/a" if v is None else f"{v:.{nd}f}"


def write_csvs(out: Path, runs: list[dict], source: str) -> list[dict]:
    """runs: [{run, condition, router:{rtts,sent}, internet:{rtts,sent}}]. Returns summary rows."""
    rows = []
    with open(out / "samples.csv", "w", newline="") as fs:
        w = csv.DictWriter(fs, SAMPLE_FIELDS)
        w.writeheader()
        for r in runs:
            for t in ("router", "internet"):
                for i, v in enumerate(r[t]["rtts"]):
                    w.writerow({"run": r["run"], "condition": r["condition"], "target": t,
                                "seq": i, "rtt_ms": v})
                s = summarise(r[t]["rtts"], r[t]["sent"])
                rows.append({"run": r["run"], "condition": r["condition"], "target": t,
                             "awdl0": r.get("awdl0", "unknown"), "source": source, **s})
    with open(out / "summary.csv", "w", newline="") as f:
        w = csv.DictWriter(f, SUMMARY_FIELDS)
        w.writeheader()
        for row in rows:
            w.writerow({k: ("" if row.get(k) is None else
                            (round(row[k], 3) if isinstance(row[k], float) else row[k]))
                        for k in SUMMARY_FIELDS})
    return rows


VERDICT_TEXT = {
    "higher_when_active": "HIGHER WHEN ACTIVE. In these runs, {metric} was higher with the AirDrop/Handoff radio active.",
    "lower_when_active": "LOWER WHEN ACTIVE. Unexpected: {metric} was lower with the radio active. Treat as noise or a setup problem until it repeats.",
    "no_clear_difference": "NO CLEAR DIFFERENCE. These runs do not show the radio changing {metric}.",
    "inconclusive": "INCONCLUSIVE. Not enough usable runs to say anything.",
}
TARGET_LABEL = {"router": "Mac to router", "internet": "Mac to internet"}


def build_report(rows: list[dict], meta: dict) -> str:
    L = []
    L.append("# Game Ready lag measurement report\n")
    if meta["source"] == "fixture":
        L.append("> **DRY RUN: fixture data, not a measurement.** Nothing here describes any real network.\n")
    L.append("## Setup\n")
    for k in ("macOS", "Mac", "Link", "Notes", "Duration per run", "Ping interval", "Runs per condition",
              "Order", "Seed"):
        if meta.get(k) not in (None, ""):
            L.append(f"- {k}: {meta[k]}")
    L.append("- Targets: your router and one public host (addresses are not recorded).")
    L.append("- Conditions: **quiet** = AirDrop receiving off, Handoff off, no Apple device nearby probing;"
             " **active** = AirDrop open, a second Apple device repeatedly opening the AirDrop sheet. "
             "See docs/evidence.md for the exact steps.\n")
    L.append("## Result\n")
    L.append(f"The primary comparison was fixed before looking at any data: per-run **{PRIMARY_METRIC}** "
             f"round-trip time, median across runs, quiet vs active, exact rank-sum permutation test "
             f"(a difference counts only if p < {ALPHA} **and** it is at least {MIN_PRACTICAL_MS:g} ms).\n")
    verdicts = {}
    for t in ("router", "internet"):
        qr = [r for r in rows if r["target"] == t and r["condition"] == QUIET]
        ar = [r for r in rows if r["target"] == t and r["condition"] == ACTIVE]
        c = compare(qr, ar)
        verdicts[t] = c
        L.append(f"### {TARGET_LABEL[t]}\n")
        L.append(f"**{VERDICT_TEXT[c['verdict']].format(metric=PRIMARY_METRIC + ' latency')}**\n")
        if c["difference"] is not None:
            L.append(f"- Quiet median of per-run {PRIMARY_METRIC}: {fmt(c['quiet_median'])} ms "
                     f"(runs: {', '.join(fmt(v) for v in c['quiet_values'])})")
            L.append(f"- Active median of per-run {PRIMARY_METRIC}: {fmt(c['active_median'])} ms "
                     f"(runs: {', '.join(fmt(v) for v in c['active_values'])})")
            L.append(f"- Difference (active minus quiet): {c['difference']:+.2f} ms, p = {c['p_value']:.3f}")
        L.append(f"- Why: {c['why']}.\n")
    L.append("## All runs\n")
    L.append("`awdl0` is the AWDL interface state read before and after each run (read-only). If it was "
             "\"up\" in quiet runs, the quiet condition may not have taken hold (other things can keep it up); say so when you share.\n")
    L.append("| Run | Condition | awdl0 | Target | Sent | Loss % | Min | p50 | p95 | p99 | Max | Jitter |")
    L.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in sorted(rows, key=lambda r: (r["run"], r["target"])):
        L.append(f"| {r['run']} | {r['condition']} | {r['awdl0']} | {r['target']} | {r['sent']} | {fmt(r['loss_pct'], 1)} | "
                 f"{fmt(r['min'])} | {fmt(r['p50'])} | {fmt(r['p95'])} | {fmt(r['p99'])} | "
                 f"{fmt(r['max'])} | {fmt(r['jitter'])} |")
    L.append("\nAll values are milliseconds except loss. Every run is listed, none dropped. Jitter is the mean "
             "gap between consecutive replies.\n")
    L.append("## What this does and does not show\n")
    L.append("- It compares two conditions on **this Mac, in this spot, on this day**. It is not a general claim.")
    L.append("- \"No clear difference\" means these runs could not see one. It does not prove the radio never matters.")
    L.append("- A difference shows the two conditions differ in latency. "
             "It does not by itself show that a game stream feels better.")
    L.append("- Pings measure the Mac's own hop and one internet path, not any game service.")
    any_hit = any(v["verdict"] in ("higher_when_active", "lower_when_active") for v in verdicts.values())
    if not any_hit:
        L.append("- **Null result.** If you share this, share it as it stands: a null result is a result.")
    return "\n".join(L) + "\n"


# ---------------------------------------------------------------------- main

def meta_from_args(args, order: list[str], source: str) -> dict:
    return {"source": source,
            "macOS": platform.mac_ver()[0] or platform.platform() if source != "fixture" else None,
            "Mac": platform.machine() if source != "fixture" else None,
            "Link": args.link, "Notes": args.notes,
            "Duration per run": f"{args.duration} s" if source != "fixture" else None,
            "Ping interval": f"{args.interval} s" if source != "fixture" else None,
            "Runs per condition": len(order) // 2,
            "Order": " ".join("Q" if c == QUIET else "A" for c in order),
            "Seed": args.seed if source != "fixture" else None}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--internet", help="public host to ping (you choose it; nothing is hard-coded)")
    ap.add_argument("--router", help="router address; detected from the default route if omitted")
    ap.add_argument("--runs", type=int, default=MIN_RUNS_PER_CONDITION, help="runs per condition (min 5)")
    ap.add_argument("--duration", type=int, default=300, help="seconds per run (default 300)")
    ap.add_argument("--interval", type=float, default=MIN_PING_INTERVAL, help="seconds between pings (min 0.2)")
    ap.add_argument("--seed", type=int, help="seed for which condition goes first (default: random, recorded)")
    ap.add_argument("--out", default="measure-out", help="output folder (default measure-out/<timestamp>)")
    ap.add_argument("--link", help="free text, e.g. '5 GHz, channel 36, 1200 Mbps' (never the network name)")
    ap.add_argument("--notes", help="free text for the report")
    ap.add_argument("--yes", action="store_true", help="do not wait for Enter between runs")
    ap.add_argument("--dry-run", action="store_true", help="no network: analyse --fixture only")
    ap.add_argument("--fixture", help="JSON of runs, used with --dry-run")
    args = ap.parse_args(argv)

    if args.seed is None:
        args.seed = random.SystemRandom().randrange(1, 10**6)
    out = Path(args.out)
    if args.dry_run:
        if not args.fixture:
            ap.error("--dry-run needs --fixture")
        fixture_runs = load_fixture(Path(args.fixture))
        runs = [{"run": r["run"], "condition": r["condition"], "awdl0": r.get("awdl0", "unknown"),
                 "router": {"rtts": r["router"]["rtts"], "sent": r["router"]["sent"]},
                 "internet": {"rtts": r["internet"]["rtts"], "sent": r["internet"]["sent"]}}
                for r in fixture_runs]
        order = [r["condition"] for r in runs]
        source = "fixture"
    else:
        if platform.system() != "Darwin":
            ap.error("live runs are for macOS; use --dry-run --fixture elsewhere")
        if args.runs < MIN_RUNS_PER_CONDITION:
            ap.error(f"--runs must be at least {MIN_RUNS_PER_CONDITION}: fewer cannot support a conclusion")
        if args.interval < MIN_PING_INTERVAL:
            ap.error(f"--interval must be at least {MIN_PING_INTERVAL}")
        if not args.internet:
            ap.error("--internet HOST is required (a public host you choose to ping)")
        router = args.router or detect_router()
        if not router:
            ap.error("could not detect the router; pass --router")
        for t in (router, args.internet):
            if not valid_target(t):
                ap.error(f"not a valid host or address: {t!r}")
        order = condition_order(args.runs, args.seed)
        out = out / time.strftime("%Y%m%d-%H%M%S")
        print(f"{len(order)} runs of {args.duration} s, order {' '.join(c[0].upper() for c in order)}. "
              f"About {len(order) * args.duration // 60} minutes of pinging. Ctrl-C to stop; nothing is written until the end.")
        runs = []
        for i, cond in enumerate(order, 1):
            how = ("AirDrop receiving OFF, Handoff OFF, no nearby Apple device probing" if cond == QUIET else
                   "AirDrop OPEN, second Apple device repeatedly opening the AirDrop sheet")
            print(f"\nRun {i}/{len(order)}: set the Mac to {cond.upper()}: {how}.")
            if not args.yes:
                input("Press Enter when set, to start pinging... ")
            awdl_before = awdl_state()
            res = live_run(router, args.internet, args.duration, args.interval)
            runs.append({"run": i, "condition": cond, "awdl0": f"{awdl_before}>{awdl_state()}",
                         "router": {"rtts": res["router"][0], "sent": res["router"][1]},
                         "internet": {"rtts": res["internet"][0], "sent": res["internet"][1]}})
        source = "measured"
    out.mkdir(parents=True, exist_ok=True)
    rows = write_csvs(out, runs, source)
    report = build_report(rows, meta_from_args(args, order, source))
    (out / "report.md").write_text(report)
    print(report)
    print(f"Wrote {out}/summary.csv, samples.csv, report.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
