"""Offline provenance/recovery tests; no native build or Internet required."""
from pathlib import Path
import subprocess
import json
import shutil
import hashlib
import tempfile
import unittest

from build_ocg_probe import extract_pinned_source, prepare_core, generate_card_fixture, ROOT


class CoreBootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.source.mkdir()
        self.git(self.source, "init", "-q")
        (self.source / "probe.cpp").write_text("pinned source\n")
        (self.source / ".gitignore").write_text("ignored.cpp\n")
        self.git(self.source, "add", ".")
        self.git(self.source, "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "fixture")
        self.revision = self.git(self.source, "rev-parse", "HEAD").strip()
        self.metadata = {"repository": str(self.source), "revision": self.revision}

    @staticmethod
    def git(directory, *args):
        return subprocess.check_output(["git", *args], cwd=directory, text=True, stderr=subprocess.DEVNULL)

    def test_missing_source_requires_explicit_fetch(self):
        destination = self.root / "missing"
        with self.assertRaisesRegex(RuntimeError, "--fetch"):
            prepare_core(destination, self.metadata, False)
        self.assertFalse(destination.exists())

    def test_incomplete_initialization_requires_explicit_fetch(self):
        destination = self.root / "incomplete"
        destination.mkdir()
        self.git(destination, "init", "-q")
        with self.assertRaisesRegex(RuntimeError, "incomplete"):
            prepare_core(destination, self.metadata, False)

    def test_interrupted_fetch_resumes_safely(self):
        destination = self.root / "incomplete"
        destination.mkdir()
        self.git(destination, "init", "-q")
        self.assertEqual(prepare_core(destination, self.metadata, True), self.revision)
        self.assertEqual((destination / "probe.cpp").read_text(), "pinned source\n")

    def test_populated_nonrepository_is_not_overwritten(self):
        destination = self.root / "not-a-repo"
        destination.mkdir()
        important = destination / "keep.txt"
        important.write_text("user work")
        with self.assertRaisesRegex(RuntimeError, "not an empty"):
            prepare_core(destination, self.metadata, True)
        self.assertEqual(important.read_text(), "user work")

    def test_wrong_revision_is_not_overwritten(self):
        wrong = dict(self.metadata, revision="0" * 40)
        with self.assertRaisesRegex(RuntimeError, "exactly match"):
            prepare_core(self.source, wrong, True)
        self.assertEqual(self.git(self.source, "rev-parse", "HEAD").strip(), self.revision)

    def test_dirty_source_is_rejected_without_destroying_edits(self):
        modified = self.source / "probe.cpp"
        modified.write_text("user edits")
        with self.assertRaisesRegex(RuntimeError, "clean"):
            prepare_core(self.source, self.metadata, True)
        self.assertEqual(modified.read_text(), "user edits")

    def test_compilation_source_excludes_hidden_edits_and_ignored_files(self):
        self.git(self.source, "update-index", "--assume-unchanged", "probe.cpp")
        (self.source / "probe.cpp").write_text("hidden modification")
        (self.source / "ignored.cpp").write_text("untracked compiler input")
        self.assertEqual(prepare_core(self.source, self.metadata, False), self.revision)
        destination = self.root / "compile-source"
        extract_pinned_source(self.source, self.revision, destination)
        self.assertEqual((destination / "probe.cpp").read_text(), "pinned source\n")
        self.assertFalse((destination / "ignored.cpp").exists())


class ReferenceCardDataTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for relative in ("Data/reference_cards/newdoria_battle.json", "Tools/ocg/lua/c4335645.lua", "Tools/ocg/lua/test_newdoria.lua"):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
        self.path = self.root / "Data/reference_cards/newdoria_battle.json"
        self.data = json.loads(self.path.read_text())
        self.output = self.root / "reference_cards.h"

    def generate(self, value):
        self.path.write_text(json.dumps(value))
        generate_card_fixture(self.root, self.output)

    def test_official_numeric_mapping_and_leading_zero_passcode(self):
        self.generate(self.data)
        result = self.output.read_text()
        self.assertIn("4335645u, TYPE_MONSTER | TYPE_EFFECT, 4, ATTRIBUTE_DARK, RACE_FIEND, 1200, 800", result)
        self.assertIn("32541773u, TYPE_MONSTER | TYPE_NORMAL", result)
        self.assertIn(hashlib.sha256((self.root / "Tools/ocg/lua/c4335645.lua").read_bytes()).hexdigest(), result)

    def test_rejects_malformed_schema_and_card_record(self):
        for value in ([], None, {}, {"schema_version": True, "cards": []}, {"schema_version": 1, "cards": [None, 5]}):
            with self.subTest(value=value), self.assertRaises(ValueError): self.generate(value)

    def test_rejects_missing_duplicate_and_unreviewed_card_ids(self):
        for ids in ([4335645], [4335645, 4335645], [4335645, 99999999]):
            data = dict(self.data, cards=[dict(self.data["cards"][1], code=code) for code in ids])
            with self.subTest(ids=ids), self.assertRaises(ValueError): self.generate(data)

    def test_rejects_unprinted_or_mismatched_passcodes(self):
        for passcode in (4335645, "4335645", "04335646", "+4335645", " 4335645", "０４３３５６４５", None):
            self.data["cards"][1]["passcode"] = passcode
            with self.subTest(passcode=passcode), self.assertRaises(ValueError): self.generate(self.data)

    def test_rejects_unreviewed_stats_and_numeric_type_coercion(self):
        for key, value in (("attack", 1500), ("defense", 800.0), ("level", 4.0), ("race", "Warrior"), ("attribute", "EARTH")):
            data = json.loads(self.path.read_text())
            data["cards"][1][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): self.generate(data)
            self.path.write_text(json.dumps(self.data))


if __name__ == "__main__":
    unittest.main()
