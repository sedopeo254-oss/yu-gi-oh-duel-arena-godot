"""The runner must reject abnormal exits even after Godot prints a PASS marker."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


@unittest.skipUnless(shutil.which("bash") and shutil.which("timeout"), "requires Bash and timeout")
class RunnerExitTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.fake = Path(self.temp.name) / "godot"
        self.fake.write_text("""#!/usr/bin/env bash
case " $* " in
  *" --import "*) exit "${IMPORT_EXIT:-0}" ;;
  *" --check-only "*) printf '%s\\n' "${CHECK_TEXT:-}"; exit "${CHECK_EXIT:-0}" ;;
esac
printf '%s\\n' "${RUN_TEXT:-RESULT: PASS}"
if [ "${RUN_SLEEP:-0}" != 0 ]; then sleep "$RUN_SLEEP"; fi
exit "${RUN_EXIT:-0}"
""")
        self.fake.chmod(0o755)

    def run_runner(self, entry="FakeSuite", **settings):
        env = os.environ.copy()
        env.update(GODOT_BIN=str(self.fake), TMPDIR=self.temp.name)
        env.update({key: str(value) for key, value in settings.items()})
        return subprocess.run(
            ["bash", str(Path(__file__).with_name("run_tests.sh")), entry],
            env=env, capture_output=True, text=True, timeout=15,
        )

    def test_clean_pass(self):
        self.assertEqual(self.run_runner().returncode, 0)

    def test_crash_after_pass_fails(self):
        result = self.run_runner(RUN_EXIT=134)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Godot exit 134", result.stdout)

    def test_nonzero_after_pass_fails(self):
        self.assertEqual(self.run_runner(RUN_EXIT=1).returncode, 1)

    def test_failed_assertions_with_zero_exit_fail(self):
        self.assertEqual(self.run_runner(RUN_TEXT="RESULT: FAIL").returncode, 1)

    def test_missing_marker_fails(self):
        self.assertEqual(self.run_runner(RUN_TEXT="no tests ran").returncode, 1)

    def test_parse_nonzero_fails(self):
        self.assertEqual(self.run_runner(CHECK_EXIT=139).returncode, 1)

    def test_parse_error_with_zero_exit_fails(self):
        self.assertEqual(self.run_runner(CHECK_TEXT="Parse Error: broken").returncode, 1)

    def test_import_nonzero_fails(self):
        self.assertEqual(self.run_runner("--import", IMPORT_EXIT=134).returncode, 1)

    def test_import_zero_passes(self):
        self.assertEqual(self.run_runner("--import").returncode, 0)

    def test_timeout_after_pass_fails(self):
        result = self.run_runner(RUN_SLEEP=3, TIMEOUT_SECONDS=1)
        self.assertEqual(result.returncode, 1)
        self.assertIn("timeout", result.stdout)


if __name__ == "__main__":
    unittest.main()
