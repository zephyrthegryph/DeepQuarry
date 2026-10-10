"""Focused checks for symmetric per-test runtime count comparison."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "compare_dm_tests", Path(__file__).with_name("compare-dm-tests.py"))
comparison = importlib.util.module_from_spec(spec)
spec.loader.exec_module(comparison)


class TestRuntimeParity(unittest.TestCase):
    def test_same_status_does_not_hide_fewer_runtime_errors(self):
        baseline = {"/datum/unit_test/power": {"status": 1, "runtimes": 2}}
        candidate = {"/datum/unit_test/power": {"status": 1, "runtimes": 0}}
        report = comparison.compare_results(baseline, candidate)
        self.assertEqual(report["status_changes"], [])
        self.assertEqual(report["runtime_count_changes"], [
            {"name": "/datum/unit_test/power", "native": 2, "translated": 0}])
        reverse = comparison.compare_results(candidate, baseline)
        self.assertEqual(reverse["runtime_count_changes"][0]["translated"], 2)

    def test_equal_counts_have_no_runtime_difference(self):
        results = {"/datum/unit_test/example": {"status": 0, "runtimes": 0}}
        self.assertEqual(comparison.compare_results(results, results)["runtime_count_changes"], [])

    def test_malformed_runtime_counts_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "results.json"
            for invalid in (-1, True, "1", None):
                path.write_text(json.dumps({"test": {"status": 0, "runtimes": invalid}}))
                with self.assertRaises(ValueError):
                    comparison.read_results(path)


if __name__ == "__main__":
    unittest.main()
