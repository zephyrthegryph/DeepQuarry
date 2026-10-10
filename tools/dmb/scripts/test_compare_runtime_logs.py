"""Focused checks for symmetric captured runtime comparison."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "compare_runtime_logs", Path(__file__).with_name("compare-runtime-logs.py"))
comparison = importlib.util.module_from_spec(spec)
spec.loader.exec_module(comparison)


class TestRuntimeLogs(unittest.TestCase):
    def test_missing_errors_and_count_changes_are_explicit(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            baseline, candidate = root / "baseline.log", root / "candidate.log"
            baseline.write_text("Runtime in code/power.dm,154: list index out of bounds\n" * 2)
            candidate.write_text("Runtime in code/power.dm,999: list index out of bounds\n")
            left, right = map(comparison.runtime_errors, (baseline, candidate))
            report = comparison.compare_errors(left, right)
            self.assertEqual(len(report["count_changes"]), 1)
            self.assertEqual(report["count_changes"][0]["native"]["count"], 2)
            self.assertEqual(len(comparison.compare_errors(left, {})["native_only"]), 1)
            self.assertEqual(len(comparison.compare_errors({}, left)["translated_only"]), 1)


if __name__ == "__main__":
    unittest.main()
