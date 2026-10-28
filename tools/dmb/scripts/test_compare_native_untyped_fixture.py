import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

from compare_native_untyped_fixture import compare, observe, rows


def finding(**changes):
    value = {"rule": "call", "file": "code/probe.dm", "line": 12,
             "message": "/datum/probe/var/saved is assigned a call's result",
             "identity": "/datum/probe::saved"}
    value.update(changes)
    return value


def parsed(*values):
    return rows("\n".join(json.dumps(value) for value in values), "fixture")


class UntypedOracleTests(unittest.TestCase):
    def test_exact_fields_not_only_expected_coordinate_rows(self):
        reference = parsed(finding())
        for key, value in (("rule", "typed"), ("file", "code/other.dm"),
                           ("line", 13), ("message", "different reason"),
                           ("identity", "/datum/other::saved")):
            with self.subTest(key=key):
                self.assertFalse(compare(reference, parsed(finding(**{key: value})))["matched"])

    def test_duplicate_findings_have_significant_multiplicity(self):
        report = compare(parsed(finding(), finding()), parsed(finding()))
        self.assertFalse(report["matched"])
        self.assertEqual(report["differences"][0]["reference_count"], 2)
        self.assertEqual(report["differences"][0]["native_count"], 1)

    def test_legacy_row_order_is_preserved_and_count_report_order_is_stable(self):
        a, b = finding(), finding(file="code/second.dm", line=3)
        report = compare(parsed(a, b), parsed(b, a))
        self.assertFalse(report["matched"])
        self.assertEqual(report["differences"], [])
        self.assertEqual(report["order_difference_count"], 2)
        self.assertEqual(report["first_order_differences"][0]["position"], 1)
        self.assertEqual(compare(parsed(b, a), parsed(a))["differences"],
                         compare(parsed(a, b), parsed(a))["differences"])

    def test_rejects_empty_reference_without_explicit_clean_fixture(self):
        with self.assertRaisesRegex(ValueError, "empty reference"):
            compare([], [])
        report = compare([], [], allow_empty_reference=True)
        self.assertTrue(report["matched"])
        self.assertFalse(report["full_analysis_parity"])

    def test_malformed_or_foreign_output_cannot_be_silent_success(self):
        invalid = ["compiler log line", "[]", '{"rule":"call"}',
                   json.dumps(finding(line=True)), json.dumps(finding(line=0)),
                   json.dumps(finding(rule="unported")),
                   json.dumps(dict(finding(), ignored="extra")),
                   json.dumps(finding()).replace('"line": 12', '"line": 12, "line": 13')]
        for text in invalid:
            with self.subTest(text=text), self.assertRaisesRegex(ValueError, "native:1:"):
                rows(text, "native")

    def test_executable_observation_uses_argument_array_and_propagates_failure(self):
        with patch.object(Path, "is_dir", return_value=True), \
             patch("compare_native_untyped_fixture.digest", return_value="stable"), \
             patch("compare_native_untyped_fixture.subprocess.run") as run:
            run.return_value = subprocess.CompletedProcess([], 2, "", "explicit error")
            with self.assertRaisesRegex(ValueError, "reference exited 2"):
                observe(Path("oracle with spaces.exe"), None, Path("fixture with spaces"), 7,
                        "reference")
            command = run.call_args.args[0]
            self.assertEqual(len(command), 2)
            self.assertTrue(command[0].endswith("oracle with spaces.exe"))
            self.assertTrue(command[1].endswith("fixture with spaces"))
            self.assertNotIn("shell", run.call_args.kwargs)
            self.assertEqual(run.call_args.kwargs["timeout"], 7)

    def test_replaced_producer_binary_cannot_certify_observations(self):
        with patch.object(Path, "is_dir", return_value=True), \
             patch("compare_native_untyped_fixture.digest", side_effect=["before", "after"]), \
             patch("compare_native_untyped_fixture.subprocess.run") as run:
            run.return_value = subprocess.CompletedProcess([], 0, json.dumps(finding()), "")
            with self.assertRaisesRegex(ValueError, "executable changed"):
                observe(Path("producer.exe"), None, Path("fixture"), 7, "native")


if __name__ == "__main__":
    unittest.main()
