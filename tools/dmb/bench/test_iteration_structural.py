"""Synthetic structural admission checks; never invokes a compiler or inspector."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from iteration_structural import Comparison, authenticate_source_snapshot, source_matches


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def report(snapshot):
    names = ("type_set", "type_headers", "variable_defaults", "procedure_table",
             "procedure_flags", "globals", "strings_by_use", "bytecode", "other")
    return {"schema_version": 1, "snapshot_id": snapshot, "traversal_complete": True,
            "tool_complete": True, "complete": True, "semantic_coverage": "complete",
            "total_discrepancies": 0, "unexplained_discrepancies": 0,
            "signature_algorithm": "md5-length-framed-v1",
            "categories": {name: {"discrepancy_count": 0} for name in names},
            "category_signatures": {name: [] for name in names},
            "uncovered": {}, "uncovered_signatures": {}}


class ComparisonTests(unittest.TestCase):
    def setUp(self):
        scratch = Path("E:/dq-cache/dmb-protocol-checks")
        scratch.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="iteration-structural-", dir=scratch)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.inspector = self.file("inspector", b"synthetic-tool")
        self.expected = self.file("expected.dmb", b"captured-BYOND")
        self.native = self.file("actual.dmb", b"native-current")
        self.file("actual.rsc", b"native-resource")
        self.configuration = {"synthetic_configuration": "exact"}
        self.pin = self.root / "pin.json"
        self.pin.write_text(json.dumps({"dmb_sha256": sha(self.expected),
                           "snapshot_id": "captured", "semantic_configuration": self.configuration}))
        # Configuration evidence is independently covered by its own tests.
        # This suite mocks only that authority, never inspector completion.
        with patch("iteration_structural.semantic_configuration.authenticate_pin"):
            self.comparison = Comparison(self.inspector, self.expected, self.pin,
                                         self.configuration, sha, Path)
        self.invocations = 0
        self.transform = lambda value: value

    def file(self, name, data):
        path = self.root / name
        path.write_bytes(data)
        return path

    def launch(self, executable, arguments, logs, deadline):
        self.assertEqual(executable, self.inspector)
        self.assertEqual(arguments[0], "structural-diff")
        self.invocations += 1
        Path(arguments[3]).write_text(json.dumps(self.transform(report(arguments[4]))))
        return {"exit": 0, "wall_s": 0}

    def compare(self, name, same_source=True, context=None):
        return self.comparison.compare(self.native, self.root / name,
            context or {"current_source": "bytes"}, same_source, self.launch, 1)

    def test_same_input_gate_and_edited_scope_are_separate_from_byte_parity(self):
        baseline = self.compare("initial")
        self.assertEqual(baseline["baseline_admission"], "passed")
        self.assertEqual(baseline["BYOND_byte_parity"], "not_asserted")
        edited = self.compare("edited", False, {"current_source": "changed"})
        self.assertEqual(edited["baseline_admission"], "not_evaluable_cross_revision")
        self.assertEqual(edited["comparison_scope"], "cross_revision_original_BYOND_diagnostic_only")
        self.assertEqual(edited["runtime_parity"], "not_run")

    def test_reuse_authenticates_raw_report_and_reclassifies_each_request(self):
        first = self.compare("first")
        second = self.compare("second")
        self.assertEqual(self.invocations, 1)
        self.assertEqual(second["structural_check"]["mode"], "authenticated_raw_report_reuse")
        self.assertEqual(first["report"], second["report"])
        # Same raw evidence must not carry a previous admission into edited scope.
        edited = self.compare("third", False)
        self.assertEqual(edited["baseline_admission"], "not_evaluable_cross_revision")
        Path(first["report"]).write_text("{}")
        with self.assertRaisesRegex(ValueError, "report hash mismatch"):
            self.compare("tampered")

    def test_changed_output_and_tool_require_independent_evidence(self):
        self.compare("first")
        self.native.write_bytes(b"different-native")
        self.compare("different")
        self.assertEqual(self.invocations, 2)
        self.inspector.write_bytes(b"different-tool")
        with self.assertRaisesRegex(ValueError, "pin/tool changed"):
            self.compare("changed-tool")

    def test_baseline_dmb_pin_and_pin_file_are_authenticated(self):
        self.pin.write_text("{}")
        with self.assertRaisesRegex(ValueError, "pin/tool changed"):
            self.compare("changed-pin")
        with self.assertRaisesRegex(ValueError, "DMB differs"):
            Comparison(self.inspector, self.expected, self.pin, self.configuration, sha, Path)

    def test_missing_coverage_and_existing_differences_leave_gate_open(self):
        def missing(value):
            del value["semantic_coverage"]
            return value
        self.transform = missing
        self.assertEqual(self.compare("missing")["baseline_admission"], "open")
        def differences(value):
            value["total_discrepancies"] = value["unexplained_discrepancies"] = 1
            value["categories"]["bytecode"]["discrepancy_count"] = 1
            value["category_signatures"]["bytecode"] = ["a" * 32]
            return value
        self.transform = differences
        result = self.compare("differences", context={"source": "different-context"})
        self.assertEqual(result["baseline_admission"], "open")
        self.assertEqual(result["total_discrepancies"], 1)

    def test_malformed_category_or_incomplete_tool_cannot_admit(self):
        def malformed(value):
            value["categories"]["bytecode"]["discrepancy_count"] = -1
            return value
        self.transform = malformed
        self.assertEqual(self.compare("malformed")["baseline_admission"], "open")
        def incomplete(value):
            value["tool_complete"] = False
            return value
        self.transform = incomplete
        self.assertEqual(self.compare("incomplete", context={"different": True})["baseline_admission"], "open")

    def test_source_closure_authentication_and_extra_input_rejection(self):
        project = self.root / "project"
        project.mkdir()
        (project / "project.dme").write_bytes(b"/proc/probe()\n\treturn 1\n")
        files = {"project.dme": sha(project / "project.dme")}
        snapshot = {"files": files}
        closure = self.root / "closure.json"
        closure.write_text(json.dumps([{"tree": "source", "path": "project.dme", "sha256": files["project.dme"].upper()}]))
        pin = {"source_closure_manifest_sha256": sha(closure)}
        self.assertEqual(authenticate_source_snapshot(snapshot, closure, pin, sha), sha(closure))
        self.assertTrue(source_matches(project, snapshot, sha))
        (project / "extra.dm").write_bytes(b"/datum/extra\n")
        self.assertFalse(source_matches(project, snapshot, sha))
        with self.assertRaisesRegex(ValueError, "snapshot differs"):
            authenticate_source_snapshot({"files": {}}, closure, pin, sha)
        closure.write_text("[]")
        with self.assertRaisesRegex(ValueError, "closure does not match"):
            authenticate_source_snapshot(snapshot, closure, pin, sha)


if __name__ == "__main__":
    unittest.main()
