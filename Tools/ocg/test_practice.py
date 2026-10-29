#!/usr/bin/env python3
"""Real native practice decks, private hand projections and supported battle choices."""
import hashlib
import subprocess
import unittest
from test_probe import SessionWorker, BINARY, ROOT


class PracticeWorker(SessionWorker):
    def __init__(self, profile="mixed", seed=42):
        self.process = subprocess.Popen([str(BINARY), "--practice-session", "--seed", str(seed), "--deck", profile],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        self.buffer = b""


class NativePracticeTests(unittest.TestCase):
    def worker(self, profile="mixed", seed=42):
        worker = PracticeWorker(profile, seed)
        self.addCleanup(worker.close)
        ready = worker.read()
        self.assertEqual(ready["type"], "ready")
        self.assertEqual(ready["deck_profile"], profile)
        self.assertEqual(ready["pool_sha256"], hashlib.sha256((ROOT / "Data/reference_cards/native_pool.json").read_bytes()).hexdigest())
        return worker, worker.read()

    def assert_private(self, prompt):
        viewer = prompt["player"]
        self.assertEqual(prompt["view"]["players"][1 - viewer]["hand"], [])
        self.assertEqual(len(prompt["view"]["players"][viewer]["hand"]), prompt["view"]["players"][viewer]["hand_count"])

    def test_set_flip_and_position_change_preserve_hidden_identities(self):
        worker, prompt = self.worker()
        self.assert_private(prompt)
        code = prompt["view"]["players"][0]["hand"][0]["code"]
        prompt = worker.answer(worker.answer(prompt, "set_monster"), "choose_zone")
        card = prompt["view"]["players"][0]["monsters"][0]
        self.assertEqual((card["code"], card["position"], card["known"]), (code, 8, True))
        self.assertNotIn("normal_summon", [c["kind"] for c in prompt["offers"]])
        prompt = worker.answer(prompt, "end_turn")
        self.assert_private(prompt)
        self.assertEqual(prompt["view"]["players"][0]["monsters"][0], {"slot": 0, "position": 8, "known": False})
        prompt = worker.answer(worker.answer(prompt, "end_turn"), "reposition")
        self.assertEqual(prompt["view"]["players"][0]["monsters"][0]["position"], 1)
        self.assertNotIn("reposition", [c["kind"] for c in prompt["offers"]])
        prompt = worker.answer(prompt, "end_turn")
        prompt = worker.answer(prompt, "end_turn")
        while prompt["player"] == 1: prompt = worker.answer(prompt, "discard")
        prompt = worker.answer(prompt, "reposition")
        self.assertEqual(prompt["view"]["players"][0]["monsters"][0]["position"], 4)
        self.assert_private(prompt)

    def test_attack_into_face_down_monster_resolves_actual_defense_battle(self):
        worker, prompt = self.worker()
        slot = min(prompt["view"]["players"][0]["hand"], key=lambda c: c["defense"])["slot"]
        index = next(i for i, choice in enumerate(prompt["offers"]) if choice["kind"] == "set_monster" and choice["label"].endswith(f"slot {slot + 1}"))
        worker.send(f"ANSWER {prompt['player']} {prompt['prompt_id']} {index}")
        prompt = worker.answer(worker.read(), "choose_zone")
        prompt = worker.answer(prompt, "end_turn")
        slot = max(prompt["view"]["players"][1]["hand"], key=lambda c: c["attack"])["slot"]
        index = next(i for i, choice in enumerate(prompt["offers"]) if choice["kind"] == "normal_summon" and choice["label"].endswith(f"slot {slot + 1}"))
        worker.send(f"ANSWER {prompt['player']} {prompt['prompt_id']} {index}")
        prompt = worker.answer(worker.read(), "choose_zone")
        prompt = worker.answer(worker.answer(prompt, "battle_phase"), "attack")
        self.assertEqual(prompt["view"]["players"][0]["monsters"][0], {"slot": 0, "position": 8, "known": False})
        prompt = worker.answer(prompt, "select_monster")
        self.assertEqual(prompt["view"]["players"][0]["graveyard_count"], 1)
        self.assertEqual(prompt["view"]["players"][0]["monster_count"], 0)
        self.assertEqual([p["life_points"] for p in prompt["view"]["players"]], [8000, 8000])

    def test_selected_real_decks_finish_actual_lp_duels(self):
        for profile in ["mixed", "dragons"]:
            for seed in [0, 42, 4294967295]:
                with self.subTest(profile=profile, seed=seed):
                    worker, prompt = self.worker(profile, seed)
                    for count in range(400):
                        self.assert_private(prompt)
                        kinds = [c["kind"] for c in prompt["offers"]]
                        priority = ["normal_summon", "choose_zone", "battle_phase", "attack", "select_monster", "discard", "end_turn", "main_two"] if prompt["player"] == 0 else ["discard", "end_turn", "main_two"]
                        selected = next(kind for kind in priority if kind in kinds)
                        prompt = worker.answer(prompt, selected)
                        if prompt["type"] == "over": break
                    self.assertEqual(prompt["type"], "over")
                    second = worker.read()
                    self.assertEqual((prompt["winner"], prompt["reason_code"]), (0, 1))
                    self.assertEqual(second["winner"], 0)
                    for report in [prompt, second]:
                        self.assert_private(report)
                        self.assertEqual(report["view"]["players"][1]["life_points"], 0)
                    self.assertEqual(worker.process.wait(timeout=3), 0)

    def test_host_deck_shuffle_is_seeded_repeatable_and_varied(self):
        hands = []
        for seed in [42, 42, 43, 44]:
            worker, prompt = self.worker("mixed", seed)
            hands.append([c["code"] for c in prompt["view"]["players"][0]["hand"]])
        self.assertEqual(hands[0], hands[1])
        self.assertNotEqual(hands[0], hands[2])
        self.assertNotEqual(hands[2], hands[3])

    def test_unknown_profile_is_not_a_path_or_script_import(self):
        for profile in ["", "../cards.cdb", "/tmp/effect.lua", "unreviewed", "mixed;echo fail"]:
            worker = PracticeWorker(profile)
            self.addCleanup(worker.close)
            self.assertEqual(worker.read()["status"], "error")
            self.assertEqual(worker.process.wait(timeout=3), 1)


if __name__ == "__main__": unittest.main(verbosity=2)
