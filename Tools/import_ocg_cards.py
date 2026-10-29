#!/usr/bin/env python3
"""Offline, allowlisted numeric-card import; never downloads data or executes Lua.

The six approved Normal Monsters come from the project's existing card pool.
This is deliberately not a generic .cdb importer or approval of arbitrary scripts.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Official card facts and pinned-core encodings reviewed before admission.
# code: name, CID, level, attribute, race, ATK, DEF, tuner, archetype setcode
REVIEWED = {
    43096270: ("Alexandrite Dragon", 9863, 4, "LIGHT", "Dragon", 2000, 100, False, 0),
    21615956: ("Flamvell Guard", 7535, 1, "FIRE", "Dragon", 100, 2000, True, 0x2c),
    90582719: ("Gladiator Beast Andal", 7365, 4, "EARTH", "Beast-Warrior", 1900, 1500, False, 0x1019),
    11091375: ("Luster Dragon", 5644, 4, "WIND", "Dragon", 1900, 1600, False, 0),
    37265642: ("Sabersaurus", 6796, 4, "EARTH", "Dinosaur", 1900, 500, False, 0x0d),
    7459013: ("Zure, Knight of Dark World", 6497, 4, "DARK", "Fiend", 1800, 1500, False, 6),
}


def read_bounded(path: Path, limit: int) -> bytes:
    if not path.is_file(): raise ValueError("import input must be a regular file")
    with path.open("rb") as source:
        raw = source.read(limit + 1)
    if len(raw) > limit: raise ValueError(f"input exceeds {limit} bytes")
    return raw


def normalize(document: object) -> dict:
    if not isinstance(document, dict) or not isinstance(document.get("cards"), list):
        raise ValueError("expected a card document with a cards array")
    admitted = {}
    for card in document["cards"]:
        if not isinstance(card, dict):
            raise ValueError("every source card must be an object")
        passcode = card.get("passcode")
        if not isinstance(passcode, str) or not passcode.isascii() or not passcode.isdigit() or not 1 <= len(passcode) <= 8:
            raise ValueError("source passcodes must be decimal strings of at most eight digits")
        code = int(passcode)
        if code not in REVIEWED: continue  # Never silently admit an unreviewed card.
        if code in admitted: raise ValueError("duplicate approved source card")
        name, cid, level, attribute, race, attack, defense, tuner, setcode = REVIEWED[code]
        facts = (card.get("official_name"), card.get("category"), card.get("level"), card.get("attribute"),
                 card.get("race"), card.get("atk"), card.get("def"), card.get("is_normal"),
                 card.get("is_effect"), card.get("is_tuner"), card.get("is_flip"))
        if facts != (name, "Monster", level, attribute, race, attack, defense, True, False, tuner, False):
            raise ValueError(f"source differs from reviewed metadata for {code}")
        if any(type(card.get(key)) is not int for key in ("level", "atk", "def")):
            raise ValueError("integer stats cannot be coerced from booleans/floats")
        if any(type(card.get(key)) is not bool for key in ("is_normal", "is_effect", "is_tuner", "is_flip")):
            raise ValueError("monster flags must be booleans")
        if card.get("monster_subtypes") != (["Normal", "Tuner"] if tuner else ["Normal"]):
            raise ValueError("unsupported monster subtype")
        admitted[code] = {"code": code, "passcode": f"{code:08d}", "name": name, "konami_cid": cid,
            "source_url": f"https://www.db.yugioh-card.com/yugiohdb/card_search.action?cid={cid}&ope=2&request_locale=en",
            "level": level, "attribute": attribute, "race": race, "attack": attack, "defense": defense,
            "tuner": tuner, "alias": 0, "setcode": setcode}
    if set(admitted) != set(REVIEWED): raise ValueError("all six reviewed Normal Monsters are required")
    return {"schema_version": 1, "scope": "six reviewed low-level Normal Monsters; practice copy limits relaxed; no arbitrary card scripts",
            "cards": [admitted[code] for code in sorted(admitted)]}


def load_pool(root: Path) -> tuple[list[dict], str]:
    path = root / "Data/reference_cards/native_pool.json"
    raw = read_bounded(path, 32768)
    expected = normalize(json.loads(read_bounded(root / "Data/cards/cards.json", 2 * 1024 * 1024)))
    if json.loads(raw) != expected: raise ValueError("native pool differs from freshly validated existing card metadata; regenerate it")
    return expected["cards"], hashlib.sha256(raw).hexdigest()


def reviewed_script(root: Path) -> str:
    manifest = json.loads(read_bounded(root / "Data/reference_cards/scripts.json", 8192))
    expected_path = "Tools/ocg/lua/c4335645.lua"
    if not isinstance(manifest, dict) or set(manifest) != {"schema_version", "scripts"} or type(manifest["schema_version"]) is not int or manifest["schema_version"] != 1:
        raise ValueError("unsupported script manifest")
    entries = manifest["scripts"]
    if not isinstance(entries, list) or len(entries) != 1:
        raise ValueError("only the explicitly reviewed Newdoria script is admitted")
    entry = entries[0]
    if not isinstance(entry, dict) or set(entry) != {"code", "path", "sha256"} or type(entry["code"]) is not int or entry["code"] != 4335645 or entry["path"] != expected_path:
        raise ValueError("unreviewed script code/path; arbitrary Lua import is forbidden")
    path = root / expected_path
    if not path.resolve().is_relative_to(root.resolve()): raise ValueError("script escapes project root")
    raw = read_bounded(path, 16384)
    if hashlib.sha256(raw).hexdigest() != entry["sha256"]:
        raise ValueError("reviewed Lua hash mismatch; review source before updating the manifest")
    return raw.decode("utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "Data/cards/cards.json")
    parser.add_argument("--output", type=Path, help="write a validated pool; omitted means validate/preview only")
    args = parser.parse_args()
    raw = read_bounded(args.source, 2 * 1024 * 1024)
    result = normalize(json.loads(raw))
    encoded = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        args.output.write_text(encoded)
        print(f"Validated 6 reviewed cards; wrote {args.output}. No scripts executed.")
    else:
        print(encoded, end="")


if __name__ == "__main__":
    try: main()
    except (ValueError, OSError, RecursionError) as error: raise SystemExit(f"OCG IMPORT REFUSED: {error}")
