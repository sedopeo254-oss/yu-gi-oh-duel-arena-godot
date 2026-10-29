"""Offline import and explicit script allowlist boundary tests."""
import copy
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from import_ocg_cards import ROOT, REVIEWED, normalize, load_pool, reviewed_script, read_bounded


class NativePoolImportTests(unittest.TestCase):
    def setUp(self):
        self.source = json.loads((ROOT / "Data/cards/cards.json").read_text())

    def card(self, code):
        return next(c for c in self.source["cards"] if int(c["passcode"]) == code)

    def test_official_normal_tuner_alias_and_archetype_metadata(self):
        records = {c["code"]: c for c in normalize(self.source)["cards"]}
        self.assertEqual(set(records), set(REVIEWED))
        self.assertTrue(records[21615956]["tuner"])
        self.assertEqual(records[21615956]["setcode"], 0x2c)
        self.assertEqual(records[90582719]["setcode"], 0x1019)
        self.assertEqual(records[37265642]["setcode"], 0x0d)
        self.assertEqual(records[7459013]["setcode"], 6)
        self.assertEqual(records[7459013]["passcode"], "07459013")
        self.assertTrue(all(c["alias"] == 0 for c in records.values()))
        self.assertEqual(load_pool(ROOT)[0], normalize(self.source)["cards"])

    def test_input_read_is_bounded_and_rejects_nonfiles(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "large.json"
            path.write_bytes(b"x" * 20)
            with self.assertRaisesRegex(ValueError, "exceeds"): read_bounded(path, 10)
            with self.assertRaisesRegex(ValueError, "regular file"): read_bounded(Path(directory), 100)
            self.assertEqual(read_bounded(path, 20), b"x" * 20)

    def test_unreviewed_effect_and_high_level_cards_are_not_admitted(self):
        records = normalize(self.source)["cards"]
        self.assertTrue(all(c["level"] <= 4 for c in records))
        self.assertNotIn(89631139, [c["code"] for c in records])
        self.assertNotIn(83764719, [c["code"] for c in records])

    def test_metadata_and_type_tampering_fails_closed(self):
        for key, bad in [("atk", 3000), ("def", 100.0), ("level", True), ("is_tuner", 1),
                         ("is_effect", True), ("official_name", "Injected name"), ("monster_subtypes", ["Effect"])]:
            source = copy.deepcopy(self.source)
            selected = next(c for c in source["cards"] if int(c["passcode"]) == 43096270)
            selected[key] = bad
            with self.subTest(key=key), self.assertRaises(ValueError): normalize(source)

    def test_duplicate_missing_bad_passcodes_and_wrong_shapes_rejected(self):
        for source in [[], {}, {"cards": [None]}, {"cards": [{"passcode": "../../script.lua"}]},
                       {"cards": [self.card(43096270)]},
                       {"cards": self.source["cards"] + [self.card(43096270)]}]:
            with self.subTest(source_type=type(source)), self.assertRaises(ValueError): normalize(source)


class ScriptManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for path in ["Data/reference_cards/scripts.json", "Tools/ocg/lua/c4335645.lua"]:
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / path, target)
        self.path = self.root / "Data/reference_cards/scripts.json"
        self.manifest = json.loads(self.path.read_text())

    def test_exact_owned_script_is_allowed(self):
        self.assertEqual(reviewed_script(self.root), (ROOT / "Tools/ocg/lua/c4335645.lua").read_text())

    def test_unreviewed_code_path_and_extra_keys_rejected(self):
        for key, value in [("code", 83764718), ("path", "../../arbitrary.lua"), ("path", "/tmp/arbitrary.lua"), ("url", "https://example.invalid/effect.lua")]:
            data = copy.deepcopy(self.manifest)
            data["scripts"][0][key] = value
            self.path.write_text(json.dumps(data))
            with self.subTest(key=key), self.assertRaises(ValueError): reviewed_script(self.root)

    def test_edited_or_duplicate_script_requires_new_review(self):
        (self.root / "Tools/ocg/lua/c4335645.lua").write_text("error('not the reviewed script')")
        with self.assertRaisesRegex(ValueError, "hash mismatch"): reviewed_script(self.root)
        self.manifest["scripts"] *= 2
        self.path.write_text(json.dumps(self.manifest))
        with self.assertRaises(ValueError): reviewed_script(self.root)

    def test_symlink_cannot_import_script_outside_project(self):
        script = self.root / "Tools/ocg/lua/c4335645.lua"
        script.unlink()
        script.symlink_to(ROOT / "Tools/ocg/lua/c4335645.lua")
        with self.assertRaisesRegex(ValueError, "escapes project"): reviewed_script(self.root)
