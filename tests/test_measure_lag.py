"""Tests for scripts/measure_lag.py: statistics, parsing, verdicts, report, dry run. No network."""
import csv
import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIX = ROOT / "tests" / "fixtures"
spec = importlib.util.spec_from_file_location("measure_lag", ROOT / "scripts" / "measure_lag.py")
ml = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ml)


def runs_with(metric_values, received=60, sent=62):
    return [{"p95": v, "received": received, "sent": sent} for v in metric_values]


class Statistics(unittest.TestCase):
    def test_percentile_matches_linear_interpolation(self):
        xs = [1, 2, 3, 4, 5]
        self.assertEqual(ml.percentile(xs, 50), 3)
        self.assertEqual(ml.percentile(xs, 0), 1)
        self.assertEqual(ml.percentile(xs, 100), 5)
        self.assertAlmostEqual(ml.percentile(xs, 95), 4.8)
        self.assertAlmostEqual(ml.percentile([10, 20], 25), 12.5)
        self.assertEqual(ml.percentile([7], 99), 7)

    def test_percentile_ignores_input_order_and_rejects_empty(self):
        self.assertEqual(ml.percentile([5, 1, 3], 50), 3)
        with self.assertRaises(ValueError):
            ml.percentile([], 50)

    def test_jitter_is_mean_consecutive_difference(self):
        self.assertAlmostEqual(ml.jitter_ms([1, 3, 2, 6]), (2 + 1 + 4) / 3)
        self.assertEqual(ml.jitter_ms([5]), 0.0)

    def test_summarise_counts_loss_from_sent(self):
        s = ml.summarise([2.0, 4.0, 6.0, 8.0], sent=5)
        self.assertEqual(s["received"], 4)
        self.assertEqual(s["loss_pct"], 20.0)
        self.assertEqual(s["max"], 8.0)
        self.assertEqual(s["p50"], 5.0)

    def test_summarise_with_no_replies_is_all_loss_not_zero_latency(self):
        s = ml.summarise([], sent=10)
        self.assertEqual(s["loss_pct"], 100.0)
        self.assertIsNone(s["p95"])

    def test_midranks_average_ties(self):
        self.assertEqual(ml.midranks([1, 2, 2, 3]), [1.0, 2.5, 2.5, 4.0])

    def test_fully_separated_five_v_five_reaches_the_exact_floor(self):
        p = ml.permutation_p([1, 2, 3, 4, 5], [6, 7, 8, 9, 10])
        self.assertAlmostEqual(p, 2 / 252)

    def test_identical_groups_give_p_one(self):
        self.assertEqual(ml.permutation_p([1, 2, 3, 4, 5], [1, 2, 3, 4, 5]), 1.0)

    def test_large_samples_use_seeded_monte_carlo(self):
        a = [float(i) for i in range(20)]
        b = [float(i) + 100 for i in range(20)]
        self.assertEqual(ml.permutation_p(a, b, seed=3), ml.permutation_p(a, b, seed=3))
        self.assertLess(ml.permutation_p(a, b), 0.001)


class Verdicts(unittest.TestCase):
    def test_clear_gap_is_reported(self):
        c = ml.compare(runs_with([3, 3.1, 3.2, 3.3, 3.4]), runs_with([60, 70, 80, 90, 100]))
        self.assertEqual(c["verdict"], "higher_when_active")

    def test_noise_is_reported_as_no_clear_difference(self):
        c = ml.compare(runs_with([3.0, 3.4, 3.1, 3.6, 3.2]), runs_with([3.3, 3.1, 3.5, 3.0, 3.4]))
        self.assertEqual(c["verdict"], "no_clear_difference")

    def test_separated_but_tiny_gap_is_not_a_difference(self):
        c = ml.compare(runs_with([3.00, 3.01, 3.02, 3.03, 3.04]), runs_with([3.10, 3.11, 3.12, 3.13, 3.14]))
        self.assertEqual(c["verdict"], "no_clear_difference")
        self.assertIn("too small", c["why"])

    def test_opposite_direction_is_flagged_not_hidden(self):
        c = ml.compare(runs_with([60, 70, 80, 90, 100]), runs_with([3, 3.1, 3.2, 3.3, 3.4]))
        self.assertEqual(c["verdict"], "lower_when_active")

    def test_too_few_runs_is_inconclusive(self):
        c = ml.compare(runs_with([3, 3, 3, 3]), runs_with([90, 90, 90, 90]))
        self.assertEqual(c["verdict"], "inconclusive")

    def test_runs_with_mostly_lost_replies_do_not_count(self):
        bad = runs_with([3, 3, 3], received=10, sent=62)
        c = ml.compare(runs_with([3, 3, 3, 3, 3]) + bad, runs_with([90] * 5))
        self.assertEqual(len(c["quiet_values"]), 5)


class Parsing(unittest.TestCase):
    def test_macos_ping_output(self):
        rtts, sent = ml.parse_ping((FIX / "ping-macos.txt").read_text(), requested=99)
        self.assertEqual(sent, 5)
        self.assertEqual(rtts, [2.512, 3.1, 40.25, 2.9])   # duplicate reply ignored, timeout skipped

    def test_garbage_gives_nothing_and_falls_back_to_requested(self):
        self.assertEqual(ml.parse_ping("ping: cannot resolve", requested=7), ([], 7))

    def test_targets_cannot_smuggle_options_or_commands(self):
        for ok in ("1.1.1.1", "192.168.1.1", "router.local", "2606:4700::1111"):
            self.assertTrue(ml.valid_target(ok), ok)
        for bad in ("-f", "--help", "1.1.1.1; rm -rf ~", "a b", "", "$(id)"):
            self.assertFalse(ml.valid_target(bad), bad)

    def test_order_alternates_with_required_counts(self):
        for seed in range(20):
            order = ml.condition_order(5, seed)
            self.assertEqual(len(order), 10)
            self.assertEqual(order.count(ml.QUIET), 5)
            self.assertTrue(all(a != b for a, b in zip(order, order[1:])))
        self.assertEqual(ml.condition_order(5, 4), ml.condition_order(5, 4))


class Awdl(unittest.TestCase):
    def test_state_is_one_of_the_known_words(self):
        self.assertIn(ml.awdl_state(), {"up", "down", "absent", "unknown"})


class DryRun(unittest.TestCase):
    def run_fixture(self, name):
        out = tempfile.mkdtemp()
        rc = ml.main(["--dry-run", "--fixture", str(FIX / name), "--out", out])
        self.assertEqual(rc, 0)
        return Path(out)

    def test_effect_fixture_writes_files_and_reports_the_effect(self):
        out = self.run_fixture("fixture-effect.json")
        report = (out / "report.md").read_text()
        self.assertIn("DRY RUN: fixture data, not a measurement", report)
        self.assertIn("### Mac to router\n\n**HIGHER WHEN ACTIVE", report)
        self.assertIn("### Mac to internet\n\n**NO CLEAR DIFFERENCE", report)
        self.assertNotIn("Null result", report)  # the router showed an effect
        rows = list(csv.DictReader(open(out / "summary.csv")))
        self.assertEqual(len(rows), 20)
        self.assertEqual({r["source"] for r in rows}, {"fixture"})
        self.assertTrue((out / "samples.csv").read_text().startswith("run,condition,target,seq,rtt_ms"))

    def test_null_fixture_says_so_plainly(self):
        out = self.run_fixture("fixture-null.json")
        report = (out / "report.md").read_text()
        self.assertEqual(report.count("NO CLEAR DIFFERENCE"), 2)
        self.assertNotIn("HIGHER WHEN ACTIVE", report)
        self.assertIn("**Null result.**", report)
        self.assertIn("does not prove the radio never matters", report)

    def test_report_lists_every_run_and_no_addresses(self):
        report = (self.run_fixture("fixture-null.json") / "report.md").read_text()
        self.assertEqual(report.count("| router |"), 10)
        self.assertEqual(report.count("| internet |"), 10)
        self.assertNotRegex(report, r"\d+\.\d+\.\d+\.\d+")

    def test_dry_run_without_fixture_is_refused(self):
        with self.assertRaises(SystemExit):
            ml.main(["--dry-run", "--out", tempfile.mkdtemp()])

    def test_live_run_refuses_too_few_runs_before_touching_the_network(self):
        with self.assertRaises(SystemExit):
            ml.main(["--internet", "1.1.1.1", "--runs", "3", "--out", tempfile.mkdtemp()])


if __name__ == "__main__":
    unittest.main()
