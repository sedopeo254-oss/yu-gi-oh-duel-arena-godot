"""Offline provenance/recovery tests; no native build or Internet required."""
from pathlib import Path
import subprocess
import tempfile
import unittest

from build_ocg_probe import extract_pinned_source, prepare_core


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


if __name__ == "__main__":
    unittest.main()
