"""Pinned BYOND comparisons for iterations, separate from native byte oracles."""
import hashlib
import json
from pathlib import Path

import semantic_configuration
import structural_evidence
import structural_reuse
from protocol import exact_structural_evidence


class Comparison:
    def __init__(self, inspector, expected, pin_path, configuration, sha, validate_path):
        self.inspector = validate_path(inspector)
        self.expected = validate_path(expected)
        self.pin_path = validate_path(pin_path)
        self.pin = json.loads(self.pin_path.read_text(encoding="utf-8"))
        self.sha = sha
        self.pin_sha = sha(self.pin_path)
        self.inspector_sha = sha(self.inspector)
        self.expected_sha = sha(self.expected)
        if self.expected_sha != self.pin.get("dmb_sha256"):
            raise ValueError("captured BYOND DMB differs from authenticated pin")
        semantic_configuration.authenticate_pin(self.pin, self.pin["semantic_configuration"], sha)
        self.configuration = configuration
        self.configuration_sha = semantic_configuration.digest(configuration)
        self.configuration_matches = configuration == self.pin["semantic_configuration"]
        self.reports = structural_reuse.Reports()

    def compare(self, native, directory, source_context, same_source, launch, deadline):
        if self.sha(self.pin_path) != self.pin_sha or self.sha(self.expected) != self.expected_sha or self.sha(self.inspector) != self.inspector_sha:
            raise ValueError("structural comparison pin/tool changed")
        native_sha = self.sha(native)
        rsc_sha = self.sha(native.with_suffix(".rsc"))
        snapshot = hashlib.sha256(json.dumps(source_context, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        identity = structural_reuse.key(inspector_sha256=self.inspector_sha,
            expected_dmb_sha256=self.expected_sha, actual_dmb_sha256=native_sha,
            actual_rsc_sha256=rsc_sha, snapshot_id=snapshot,
            configuration_sha256=self.configuration_sha)
        reused = self.reports.lookup(identity)
        directory.mkdir(parents=True)
        if reused is None:
            report = directory / "structural-diff.json"
            execution = launch(self.inspector, ["structural-diff", str(self.expected), str(native), str(report), snapshot], directory / "logs", deadline)
            if execution["exit"] != 0:
                raise ValueError("structural inspector failed")
            report_sha = self.sha(report)
            value = json.loads(report.read_text(encoding="utf-8"))
            if self.sha(report) != report_sha:
                raise ValueError("structural report changed while loading")
            execution_mode = "executed"
        else:
            value, descriptor = reused
            report = Path(descriptor["report"])
            report_sha = descriptor["report_sha256"]
            execution = None
            execution_mode = "authenticated_raw_report_reuse"
        if value.get("schema_version") != 1 or value.get("snapshot_id") != snapshot:
            raise ValueError("structural report schema/context mismatch")
        valid = (exact_structural_evidence(value)
                 and type(value.get("total_discrepancies")) is int
                 and type(value.get("unexplained_discrepancies")) is int
                 and 0 <= value["unexplained_discrepancies"] <= value["total_discrepancies"]
                 and sum(entry["discrepancy_count"] for entry in value["categories"].values()) == value["total_discrepancies"])
        if reused is None and valid:
            self.reports.remember(identity, report, directory)
        enriched = dict(value, report=str(report), report_sha256=report_sha,
                        semantic_configuration_sha256=self.configuration_sha)
        result = structural_evidence.compact(enriched)
        source_identical = same_source and self.configuration_matches
        result.update({"comparison_scope": "same_captured_source_and_configuration" if source_identical else "cross_revision_original_BYOND_diagnostic_only",
            "baseline_snapshot_id": self.pin.get("snapshot_id"),
            "configuration_matches_baseline": self.configuration_matches,
            "source_identical_to_baseline": same_source,
            "structural_check": {"mode": execution_mode, "identity": identity},
            "inspector_execution": execution,
            "baseline_admission": "not_evaluable_cross_revision" if not source_identical else
                ("passed" if valid and value.get("complete") is True and value.get("semantic_coverage") == "complete" and not value.get("uncovered") and value.get("total_discrepancies") == 0 and value.get("unexplained_discrepancies") == 0 else "open"),
            "BYOND_byte_parity": "not_asserted",
            "runtime_parity": "not_run"})
        if (self.sha(native) != native_sha or self.sha(native.with_suffix(".rsc")) != rsc_sha
                or self.sha(self.expected) != self.expected_sha or self.sha(self.inspector) != self.inspector_sha):
            raise ValueError("structural inputs changed during comparison")
        # Optional producer diagnostic sidecar is never admission authority.
        summary_path = Path(str(report) + ".summary.json")
        if summary_path.exists():
            summary_sha = self.sha(summary_path)
            if summary_path.stat().st_size > 1024 * 1024:
                raise ValueError("structural summary exceeds diagnostic size limit")
            summary = json.loads(summary_path.read_text(encoding="utf-8"))
            if self.sha(summary_path) != summary_sha:
                raise ValueError("structural summary changed while loading")
            if (summary.get("schema_version") != 1 or summary.get("snapshot_id") != snapshot
                    or any(summary.get(field) != value.get(field) for field in
                           ("total_discrepancies", "unexplained_discrepancies", "complete",
                            "tool_complete", "traversal_complete", "semantic_coverage"))
                    or set(summary.get("categories", {})) != set(value["categories"])
                    or set(summary.get("uncovered", {})) != set(value["uncovered"] )):
                raise ValueError("structural summary differs from authenticated raw report")
            for roster, signatures, count in (("categories", "category_signatures", "discrepancy_count"),
                                              ("uncovered", "uncovered_signatures", "occurrence_count")):
                for kind, entry in summary[roster].items():
                    original = value[roster][kind]
                    if (entry.get(count) != original[count]
                            or entry.get("unique_case_count") != len(value[signatures][kind])
                            or entry.get("examples") != original.get("examples", [])[:5]):
                        raise ValueError("structural summary category differs from raw report")
            shapes = {}
            for procedure in value.get("bytecode_procedures", {}).values():
                kind = procedure["shape_classification"]
                shapes[kind] = shapes.get(kind, 0) + 1
            if summary.get("bytecode_shape_counts") != shapes:
                raise ValueError("structural summary shapes differ from raw report")
            summary.update(comparison_scope=result["comparison_scope"],
                           baseline_admission=result["baseline_admission"],
                           opcode_equivalence="not_asserted_by_difference_counts_or_instruction_shapes",
                           raw_report=str(report), raw_report_sha256=report_sha)
            diagnostic_path = directory / "structural-summary.json"
            diagnostic_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
            result["diagnostic_summary"] = str(diagnostic_path)
        (directory / "structural-admission.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
        return result


def source_matches(project, snapshot, sha):
    """Exact file roster and bytes, without treating path names as authority."""
    files = snapshot["files"]
    actual = {}
    for path in project.rglob("*"):
        if path.is_file():
            actual[path.relative_to(project).as_posix()] = path
    if set(actual) != set(files):
        return False
    return all(sha(actual[name]) == expected for name, expected in files.items())


def authenticate_source_snapshot(snapshot, closure_path, pin, sha):
    before = sha(closure_path)
    if before != pin.get("source_closure_manifest_sha256"):
        raise ValueError("source closure does not match captured BYOND pin")
    entries = json.loads(Path(closure_path).read_text(encoding="utf-8-sig"))
    files = {}
    for entry in entries:
        if entry["tree"] == "source":
            if entry["path"] in files:
                raise ValueError("duplicate captured source closure path")
            files[entry["path"]] = entry["sha256"].lower()
    if sha(closure_path) != before or snapshot.get("files") != files:
        raise ValueError("source snapshot differs from authenticated captured closure")
    return before
