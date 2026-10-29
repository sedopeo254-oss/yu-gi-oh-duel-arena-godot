#!/usr/bin/env python3
"""Native integration checks. Requires an explicitly built ocg_probe binary."""
import json
import os
from pathlib import Path
import select
import subprocess
import time
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


class SessionWorker:
    def __init__(self, seed=42):
        self.process = subprocess.Popen([str(BINARY), "--session", "--seed", str(seed)],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        self.buffer = b""

    def read(self, timeout=3):
        deadline = time.monotonic() + timeout
        while b"\n" not in self.buffer:
            ready, _, _ = select.select([self.process.stdout], [], [], max(0, deadline - time.monotonic()))
            if not ready:
                raise AssertionError("native worker response timeout")
            block = os.read(self.process.stdout.fileno(), 4096)
            if not block:
                raise AssertionError("native worker closed before response")
            self.buffer += block
        line, self.buffer = self.buffer.split(b"\n", 1)
        return json.loads(line)

    def send(self, line):
        self.process.stdin.write((line + "\n").encode())

    def answer(self, prompt, kind):
        index = next(i for i, offer in enumerate(prompt["offers"]) if offer["kind"] == kind)
        self.send(f"ANSWER {prompt['player']} {prompt['prompt_id']} {index}")
        return self.read()

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait(timeout=3)
        for pipe in (self.process.stdin, self.process.stdout, self.process.stderr):
            pipe.close()


class NativeSessionTests(unittest.TestCase):
    def worker(self, seed=42):
        worker = SessionWorker(seed)
        self.addCleanup(worker.close)
        self.assertEqual(worker.read()["type"], "ready")
        return worker, worker.read()

    def test_player_stale_and_choice_authority(self):
        worker, prompt = self.worker()
        worker.send("ANSWER 1 1 0")
        self.assertEqual(worker.read()["type"], "rejected")
        worker.send("ANSWER 0 1 999")
        self.assertEqual(worker.read()["type"], "rejected")
        zone = worker.answer(prompt, "normal_summon")
        self.assertEqual(zone["offers"][0]["kind"], "choose_zone")
        worker.send("ANSWER 0 1 0")
        self.assertEqual(worker.read()["type"], "rejected")
        after = worker.answer(zone, "choose_zone")
        self.assertEqual(after["view"]["players"][0]["monster_count"], 1)
        self.assertEqual(after["view"]["players"][0]["hand_count"], 4)
        self.assertNotIn("normal_summon", [choice["kind"] for choice in after["offers"]])
        second = worker.answer(after, "end_turn")
        self.assertEqual((second["player"], second["prompt_id"]), (1, 1))
        worker.send("STOP")
        self.assertEqual(worker.read()["type"], "stopped")
        self.assertEqual(worker.process.wait(timeout=3), 0)

    def test_full_session_to_native_deck_out(self):
        worker, prompt = self.worker(4294967295)
        ids = [0, 0]
        discards = 0
        for count in range(150):
            if prompt["type"] == "over":
                other = worker.read()
                self.assertEqual({prompt["player"], other["player"]}, {0, 1})
                self.assertEqual(prompt["winner"], other["winner"])
                self.assertEqual(prompt["reason_code"], 2)
                self.assertEqual(prompt["view"], other["view"])
                self.assertEqual(count, 139)
                self.assertEqual(discards, 68)
                self.assertEqual(worker.process.wait(timeout=3), 0)
                return
            player = prompt["player"]
            self.assertEqual(prompt["prompt_id"], ids[player] + 1)
            ids[player] += 1
            self.assertEqual(set(prompt["view"]), {"turn_player", "turn_number", "phase", "players"})
            for state in prompt["view"]["players"]:
                self.assertEqual(set(state), {"deck_count", "hand_count", "monster_count", "graveyard_count"})
                self.assertEqual(sum(state.values()), 40)
            kind = "end_turn" if prompt["mode"] == "ACTION" else "discard"
            discards += kind == "discard"
            prompt = worker.answer(prompt, kind)
        self.fail("native session did not reach deck-out")

    def test_parent_eof_closes_duel(self):
        worker, _ = self.worker()
        worker.process.stdin.close()
        self.assertEqual(worker.read()["type"], "stopped")
        self.assertEqual(worker.process.wait(timeout=3), 0)

    def test_malformed_and_oversized_input_fail_closed(self):
        for request in ("ANSWER 0 1 -1", "ANSWER 0 1 0 extra", "ANSWER 9 1 0", "X" * 300):
            with self.subTest(request=request[:30]):
                worker, _ = self.worker()
                worker.send(request)
                self.assertEqual(worker.read()["status"], "error")
                self.assertEqual(worker.process.wait(timeout=3), 1)

    def test_player_wait_is_not_an_engine_timeout(self):
        worker, prompt = self.worker()
        time.sleep(10.2)  # Longer than the native processing watchdog.
        self.assertIsNone(worker.process.poll())
        self.assertEqual(worker.answer(prompt, "end_turn")["player"], 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
