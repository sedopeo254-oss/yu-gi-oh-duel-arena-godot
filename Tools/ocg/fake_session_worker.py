#!/usr/bin/env python3
"""Test-only broken child; never selected by OcgReferenceSession.start_fixture."""
import copy
import json
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
revision = json.loads((ROOT / "ThirdParty/ocg/lock.json").read_text())["core"]["revision"]
mode = sys.argv[1]
common = {"schema_version": 1, "core_revision": revision, "fixture_only": True}
view = {"turn_player": 1, "turn_number": 72, "phase": 1, "players": [
    {"deck_count": 0, "hand_count": 6, "monster_count": 0, "graveyard_count": 34},
    {"deck_count": 0, "hand_count": 6, "monster_count": 0, "graveyard_count": 34},
]}


def emit(**message):
    print(json.dumps(dict(common, **message)), flush=True)


emit(type="ready", player=-1, capabilities=["normal_summon", "choose_zone", "end_turn", "shuffle_hand", "discard", "deck_out"])
if mode in ("hidden_top", "hidden_offer", "invalid_mode"):
    prompt = {"type": "prompt", "player": 0, "prompt_id": 1, "mode": "ACTION",
              "offers": [{"kind": "end_turn", "label": "End turn"}], "view": view}
    if mode == "hidden_top":
        prompt["opponent_hand_ids"] = [123456]
    if mode == "hidden_offer":
        prompt["offers"][0]["card_code"] = 123456
    if mode == "invalid_mode":
        prompt["mode"] = "UNSUPPORTED"
    emit(**prompt)
else:
    emit(type="over", player=0, winner=0, reason_code=2, view=view)
    if mode == "prompt_after_over":
        emit(type="prompt", player=0, prompt_id=1, mode="ACTION",
             offers=[{"kind": "end_turn", "label": "End turn"}], view=view)
    if mode != "one_over":
        other_view = copy.deepcopy(view)
        if mode == "mismatched_view":
            other_view["players"][0]["hand_count"] = 5
        emit(type="over", player=0 if mode == "duplicate_over" else 1,
             winner=1 if mode == "mismatched_winner" else 0, reason_code=2, view=other_view)
if mode in ("hang_after_over", "prompt_after_over"):
    time.sleep(30)
raise SystemExit(7 if mode == "crash_after_over" else 0)
