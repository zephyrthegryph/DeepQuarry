import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("correctness_reports", Path(__file__).with_name("correctness_reports.py"))
reports = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reports)


class CorrectnessReportsTests(unittest.TestCase):
    def parse(self, text, parser, encoding="utf-8"):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "capture.log"
            path.write_text(text, encoding=encoding)
            return parser(path)

    def test_runtime_source_mapping_and_clock_do_not_hide_procedure_identity(self):
        native = self.parse("01:02:03 code/modules/power/power_bridge.dm:154 list index out of bounds\nproc name: process power (/datum/controller/subsystem/machines/proc/process_power)\n", reports.runtime_errors)
        actual = self.parse("09:08:07 : list index out of bounds\nproc name: process power (/datum/controller/subsystem/machines/proc/process_power)\n", reports.runtime_errors, "utf-16")
        self.assertFalse(reports.compare_records(native, actual)["actual_only"])
        changed = self.parse("09:08:07 : list index out of bounds\nproc name: another (/proc/another)\n", reports.runtime_errors)
        self.assertTrue(reports.compare_records(native, changed)["actual_only"])

    def test_counts_and_locations_remain_visible(self):
        text = "Runtime in C:\\repo\\code\\power.dm,154: bounds\nRuntime in code/power.dm,155: bounds\n"
        record = next(iter(self.parse(text, reports.runtime_errors).values()))
        self.assertEqual(record["count"], 2)
        self.assertEqual(record["lines"], [154, 155])
        self.assertEqual(record["sources"], ["code/power.dm"])

    def test_compiler_error_codes_and_messages_are_not_stripped(self):
        record = next(iter(self.parse("code\\probe.dm:9:error (undefined_var): missing: undefined var\ncode\\probe.dm:10:warning (unused_var): ignored\n", reports.compiler_errors).values()))
        self.assertEqual(record["code"], "undefined_var")
        self.assertEqual(record["message"], "missing: undefined var")
        self.assertEqual(record["lines"], [9])
        mapped = next(iter(self.parse("dm-compile: probe.dm:7:error: undefined procedure\n", reports.compiler_errors).values()))
        self.assertEqual(mapped["source"], "probe.dm")
        self.assertEqual(mapped["lines"], [7])
        self.assertEqual(mapped["message"], "undefined procedure")

    def test_unlocated_runtime_remains_ambiguous_and_cannot_pass_attribution_gate(self):
        expected = self.parse("01:02:03 code/power.dm:154 bounds\n", reports.runtime_errors)
        actual = self.parse("09:08:07 : bounds\n09:08:08 : different\n", reports.runtime_errors)
        result = reports.compare_runtime(expected, actual)
        self.assertFalse(result["attribution_complete"])
        self.assertEqual(len(result["unattributed_actual"]), 2)
        self.assertFalse(result["actual_only"])
        self.assertEqual(result["new_messages"], ["different"])
        self.assertEqual(result["expected_count"], 1)
        self.assertEqual(result["actual_count"], 2)

    def test_unknown_baseline_location_cannot_establish_new_procedure(self):
        expected = self.parse("01:02:03 : bounds\n", reports.runtime_errors)
        actual = self.parse("09:08:07 code/power.dm:154 bounds\n", reports.runtime_errors)
        result = reports.compare_runtime(expected, actual)
        self.assertFalse(result["actual_only"])
        self.assertEqual(len(result["ambiguous_actual"]), 1)

    def test_new_failure_and_missing_test_are_separate_from_shared_failures(self):
        expected = {"a": {"status": 0}, "b": {"status": 1}, "c": {"status": 2}}
        actual = {"a": {"status": 1}, "b": {"status": 1}}
        result = reports.compare_tests(expected, actual)
        self.assertEqual(result["missing"], ["c"])
        self.assertEqual(result["shared_failures"], ["b"])
        self.assertEqual([item["test"] for item in result["new_failures"]], ["a"])


if __name__ == "__main__":
    unittest.main()
