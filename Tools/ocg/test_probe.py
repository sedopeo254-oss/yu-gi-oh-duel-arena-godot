#!/usr/bin/env python3
"""Native integration checks. Requires an explicitly built ocg_probe binary."""
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / "Tools/ocg/bin/ocg_probe"


class NativeProbeTests(unittest.TestCase):
    def invoke(self, *args):
        result = subprocess.run([str(BINARY), *args], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.stderr, "")
        return result.returncode, json.loads(result.stdout)

    def test_real_core_scenario_and_repeatability(self):
        code, report = self.invoke("--seed", "42")
        self.assertEqual(code, 0)
        self.assertEqual(report["status"], "ok")
        self.assertEqual(report["core_revision"], json.loads((ROOT / "ThirdParty/ocg/lock.json").read_text())["core"]["revision"])
        self.assertTrue(report["fixture_only"])
        self.assertEqual(report["opening_hand_counts"], [5, 5])
        self.assertEqual(report["after_summon_hand_counts"], [4, 5])
        self.assertEqual(report["after_summon_field_counts"], [1, 0])
        self.assertEqual(report["after_summon_options"], 0)
        self.assertEqual(report["second_turn_hand_counts"], [4, 6])
        self.assertEqual(report["second_turn_deck_counts"], [35, 34])
        self.assertTrue(report["invalid_response_rejected"])
        self.assertEqual(self.invoke("--seed", "42"), (0, report))
        self.assertNotEqual(self.invoke("--seed", "43")[1]["transcript_fnv1a64"], report["transcript_fnv1a64"])

    def test_invalid_invocations(self):
        for args in ((), ("--bad", "42"), ("--seed", "-1"), ("--seed", "4294967296"),
                     ("--seed", ""), ("--seed", "1; echo fail"), ("--seed", "1.0"),
                     ("--seed", "9" * 100), ("--seed", "1", "extra")):
            with self.subTest(args=args):
                code, report = self.invoke(*args)
                self.assertNotEqual(code, 0)
                self.assertEqual(report["status"], "error")
                self.assertIn("error", report)

    def test_seed_boundaries_and_lifecycle_repetition(self):
        # Independent processes catch accidental dependence on residual global state.
        for seed in (0, 1, 2147483648, 4294967295, *range(10)):
            with self.subTest(seed=seed):
                code, report = self.invoke("--seed", str(seed))
                self.assertEqual(code, 0)
                self.assertEqual(report["seed"], seed)
                self.assertEqual(report["turns"], 2)
                self.assertEqual(report["summons"], 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
