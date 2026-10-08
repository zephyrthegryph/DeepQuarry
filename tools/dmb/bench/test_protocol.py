"""Small protocol checks; no compiler, benchmark or DreamDaemon invocation."""
import importlib.util
import json
import hashlib
import copy
import os
from pathlib import Path
import stat
import tempfile
from types import SimpleNamespace
import unittest

spec = importlib.util.spec_from_file_location("dmb_bench_protocol", Path(__file__).with_name("protocol.py"))
protocol = importlib.util.module_from_spec(spec)
spec.loader.exec_module(protocol)


class RetentionChecks(unittest.TestCase):
    def setUp(self):
        base = Path("E:/dq-cache/dmb-protocol-checks")
        base.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=base)
        self.root = Path(self.temporary.name).resolve()
        self.helper = SimpleNamespace()

    def tearDown(self):
        # Only synthetic files created by these checks. In particular the
        # read-only hardlink test never references a real pinned/global inode.
        for path in self.root.rglob("*"):
            if path.is_file():
                path.chmod(stat.S_IMODE(path.stat().st_mode) | stat.S_IWRITE)
        self.temporary.cleanup()

    def cohort(self, name):
        return protocol.owned_directory(self.root / name, self.root)

    def run_record(self, cohort, name, rank, passing=True):
        run = protocol.owned_directory(cohort / name, cohort)
        row = {"measurement_revision": 6, "oracle": "passed" if passing else "not_passed",
               "structural_invocation_finished": passing,
               "pair_sha256": {".dmb": "fixture-dmb", ".rsc": "fixture-rsc"},
               "structural_diff": {"complete": True, "no_regression": "baseline_established"}}
        protocol.write(run / "receipt.json", row)
        (run / "cold.trace.json").write_text("large trace fixture")
        os.utime(run / "cold.trace.json", ns=(rank, rank))
        (run / "cold.trace.report.json").write_text("{}")
        (run / "cold.folded").write_text("fixture 1")
        for name in ("pair-store", "oracle-store", "artifacts"):
            directory = protocol.owned_directory(run / name, run)
            (directory / "world.dmb").write_text("large binary fixture")
        (run / "artifacts" / "raw.log").write_text("full diagnostics")
        return run

    def test_complete_round_prepares_readonly_cache_and_partial_round_preserves(self):
        cache = self.root / "cache"
        cache.mkdir()
        round_cache = protocol.owned_directory(cache / "round", cache)
        first = round_cache / "archive.rsc"
        second = round_cache / "linked.rsc"
        first.write_bytes(b"tiny cache fixture")
        os.link(first, second)
        if os.name == "nt":
            first.chmod(stat.S_IREAD)
        passing = {"oracle": "passed", "structural_invocation_finished": True}
        self.assertIsNone(protocol.cleanup_completed_round(round_cache, cache, [passing], 2, set()))
        self.assertTrue(first.exists())
        failed = {"oracle": "not_passed", "structural_invocation_finished": True}
        self.assertIsNone(protocol.cleanup_completed_round(round_cache, cache, [failed], 1, set()))
        self.assertTrue(first.exists())
        result = protocol.cleanup_completed_round(round_cache, cache, [passing], 1, set())
        self.assertEqual(result["status"], "removed", result)
        self.assertFalse(round_cache.exists())

    def test_receipt_without_chrome_retries_completed_bulky_cleanup(self):
        cohort = self.cohort("retry")
        run = self.run_record(cohort, "old", 1)
        (run / "cold.trace.json").unlink()
        row = json.loads((run / "receipt.json").read_text())
        row["structural_diff"] = {"evidence_format": "structural-report-reference-v1", "report_sha256": "fixture"}
        row["cleanup"] = [{"status": "preserved", "reason": "earlier outside link"}]
        protocol.write(run / "receipt.json", row)
        report = protocol.trim_complete_evidence(self.helper, cohort, set())
        self.assertFalse(report["cleanup_limitations"])
        self.assertFalse((run / "pair-store").exists())
        final = json.loads((run / "receipt.json").read_text())
        self.assertEqual(final["retention"], "small_evidence_only")
        self.assertEqual(final["structural_diff"], row["structural_diff"])
        self.assertTrue(final["cleanup_history"])

    def test_joint_cleanup_validates_all_markers_before_loading_helper(self):
        cohort = self.cohort("joint")
        run = self.run_record(cohort, "run", 1)
        first = run / "pair-store"
        invalid = run / "oracle-store"
        protocol.write(invalid / protocol.MARKER, {"owner": "foreign"})
        with self.assertRaisesRegex(ValueError, "ownership marker"):
            protocol.prepare_output_cleanup([first, invalid], run, set())
        self.assertTrue((first / "world.dmb").exists())
        self.assertTrue((invalid / "world.dmb").exists())

    def test_three_complete_runs_across_cohorts_and_small_evidence_retained(self):
        first, second = self.cohort("first"), self.cohort("second")
        runs = [self.run_record(first if i < 2 else second, str(i), i + 1) for i in range(5)]
        failed = self.run_record(first, "failed", 0, passing=False)
        report = protocol.trim_complete_evidence(self.helper, second, set())
        self.assertEqual(report["cleanup_limitations"], [])
        self.assertEqual(sum((run / "cold.trace.json").exists() for run in runs), 3)
        for run in runs[:2]:
            self.assertFalse((run / "pair-store").exists())
            self.assertFalse((run / "artifacts").exists())
            self.assertEqual((run / "oracle-evidence" / "raw.log").read_text(), "full diagnostics")
            self.assertTrue((run / "output-hashes.json").is_file())
            self.assertTrue((run / "cold.trace.report.json").is_file())
            self.assertTrue((run / "cold.folded").is_file())
        self.assertTrue((failed / "pair-store").exists())
        self.assertTrue((failed / "cold.trace.json").exists())

    def test_pinned_descendant_blocks_all_mutation(self):
        cohort = self.cohort("cohort")
        runs = [self.run_record(cohort, str(i), i + 1) for i in range(4)]
        pinned = (runs[0] / "pair-store" / "world.dmb").resolve()
        with self.assertRaisesRegex(ValueError, "protected"):
            protocol.trim_complete_evidence(self.helper, cohort, {pinned})
        self.assertTrue((runs[0] / "cold.trace.json").exists())
        self.assertFalse((runs[0] / "oracle-evidence").exists())
        self.assertTrue(pinned.is_file())

    def test_marker_mismatch_is_not_admitted_for_retention(self):
        cohort = self.cohort("cohort")
        runs = [self.run_record(cohort, str(i), i + 1) for i in range(4)]
        protocol.write(runs[0] / protocol.MARKER, {"owner": "someone else"})
        protocol.trim_complete_evidence(self.helper, cohort, set())
        self.assertTrue((runs[0] / "cold.trace.json").exists())
        self.assertTrue((runs[0] / "pair-store").exists())

    @unittest.skipUnless(os.name == "nt", "Windows shared read-only attributes")
    def test_readonly_hardlink_is_preserved_without_attribute_change(self):
        cohort = self.cohort("cohort")
        runs = [self.run_record(cohort, str(i), i + 1) for i in range(4)]
        original = self.root / "synthetic-pin.rsc"
        original.write_text("shared resource fixture")
        link = runs[0] / "pair-store" / "world.rsc"
        os.link(original, link)
        original.chmod(stat.S_IREAD)
        before = original.stat().st_file_attributes
        report = protocol.trim_complete_evidence(self.helper, cohort, {original.resolve()})
        self.assertEqual(original.stat().st_file_attributes, before)
        self.assertTrue(link.exists())
        self.assertEqual(report["cleanup_limitations"][0]["cleanup"][0]["status"], "preserved")
        self.assertEqual(json.loads((runs[0] / "receipt.json").read_text())["retention"], "cleanup_incomplete")

    def test_valid_fresh_oracle_disposes_outputs_despite_incomplete_structural_report(self):
        cohort = self.cohort("cohort")
        run = self.run_record(cohort, "run", 1)
        row = json.loads((run / "receipt.json").read_text())
        row["structural_diff"] = {"complete": False, "error": "unsupported operand"}
        protocol.cleanup_verified_outputs(self.helper, run, row, set())
        for name in ("pair-store", "oracle-store", "artifacts"):
            self.assertFalse((run / name).exists())
        self.assertTrue((run / "receipt.json").exists())
        self.assertTrue((run / "output-hashes.json").exists())
        self.assertEqual((run / "oracle-evidence" / "raw.log").read_text(), "full diagnostics")
        self.assertFalse(json.loads((run / "receipt.json").read_text())["structural_diff"]["complete"])

    def test_failed_fresh_oracle_retains_outputs(self):
        cohort = self.cohort("cohort")
        run = self.run_record(cohort, "run", 1, passing=False)
        row = json.loads((run / "receipt.json").read_text())
        self.assertEqual(protocol.cleanup_verified_outputs(self.helper, run, row, set()), [])
        self.assertTrue((run / "pair-store" / "world.dmb").exists())

    def test_remove_owned_rejects_wrong_marker_before_delete(self):
        cohort = self.cohort("cohort")
        run = self.run_record(cohort, "run", 1)
        store = run / "pair-store"
        protocol.write(store / protocol.MARKER, {"schema": 1, "owner": str(self.root), "path": str(store)})
        with self.assertRaisesRegex(ValueError, "marker"):
            protocol.remove_owned(store, run, set())
        self.assertTrue((store / "world.dmb").is_file())


class CpuItemChecks(unittest.TestCase):
    def test_wall_only_item_does_not_enter_bounded_cpu_validation(self):
        spec = importlib.util.spec_from_file_location("dmb_bench", Path(__file__).with_name("dmb-bench.py"))
        bench = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bench)
        bounds = {"lower": 1.0, "upper": 1.0}
        stage = {"name": "cpu", "cpu_measurement": "stage_thread_cpu", "cpu_bounds_s": bounds,
                 "max_thread_cpu_bounds_s": bounds, "exclusive_cpu_bounds_s": bounds,
                 "wall_s": 1.0, "allocations": 0, "allocated_bytes": 0, "peak_live_bytes": 0, "calls": 1}
        row = {"total_cpu_s": 1.0, "calibration": {"method": "GetThreadTimes"},
               "cpu_bounds_quantum_s": 0.03125, "critical_path_cpu_bounds_s": bounds,
               "covered_thread_cpu_bounds_s": bounds, "cpu_crosscheck_ratio_bounds": bounds,
               "critical_path_stages": ["cpu"], "stages": [stage]}
        self.assertEqual(bench.bounded_cpu_quality(row), [])
        with_item = copy.deepcopy(row)
        with_item["stages"].append({"name": "one item", "cpu_measurement": "wall_allocations_only",
                                    "cpu_bounds_s": None, "max_thread_cpu_bounds_s": None,
                                    "exclusive_cpu_bounds_s": None})
        self.assertEqual(bench.bounded_cpu_quality(with_item), [])
        with_item["stages"][0]["cpu_bounds_s"] = None
        self.assertTrue(any("cpu:cpu_bounds_s" in error for error in bench.bounded_cpu_quality(with_item)))


class SignatureChecks(unittest.TestCase):
    setUp = RetentionChecks.setUp
    tearDown = RetentionChecks.tearDown

    def test_improvement_admitted_but_new_case_rejected(self):
        a, b, new = "0" * 32, "1" * 32, "2" * 32
        configuration = {"project": "fixture.dme"}
        scenario = {"_semantic_configuration": configuration}
        baseline = {"semantic_configuration_sha256": protocol.configuration_gate.digest(configuration), "schema_version": 1, "snapshot_id": "snapshot", "complete": True,
                    "traversal_complete": True, "tool_complete": True, "semantic_coverage": "complete",
                    "uncovered": {}, "uncovered_signatures": {}, "signature_algorithm": "md5-length-framed-v1",
                    "category_signatures": {kind: ([a, b] if kind == "bytecode" else []) for kind in protocol.STRUCTURAL_CATEGORIES},
                    "categories": {kind: {"discrepancy_count": 2 if kind == "bytecode" else 0} for kind in protocol.STRUCTURAL_CATEGORIES}, "unexplained_discrepancies": 2}
        previous = self.root / "previous.json"
        protocol.write(previous, baseline)
        expected, actual = self.root / "byond.dmb", self.root / "native.dmb"
        expected.write_text("byond fixture")
        actual.write_text("native fixture")
        pin = self.root / "pin.json"
        sha = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
        protocol.write(pin, {"snapshot_id": "snapshot", "dmb_sha256": sha(expected), "semantic_configuration": configuration})
        args = SimpleNamespace(byond_dmb=expected, byond_snapshot=pin, inspector=self.root / "inspector",
                               watchdog=600, structural_baseline=previous, establish_structural_baseline=False)
        current = copy.deepcopy(baseline)
        current["categories"]["bytecode"]["discrepancy_count"] = 1
        current["category_signatures"]["bytecode"] = [a]
        def fake_run(command, *_):
            protocol.write(Path(command[-2]), current)
            return 0, 0.0, False
        helper = SimpleNamespace(sha=sha, run=fake_run)
        result = protocol.structural(helper, args, scenario, actual, self.root, "snapshot", {})
        self.assertEqual(result["no_regression"], "passed")
        self.assertEqual(result["parity_acceptance"], "failed")
        current["category_signatures"]["bytecode"] = [new]
        self.assertEqual(protocol.structural(helper, args, scenario, actual, self.root, "snapshot", {})["no_regression"], "failed")
        current["category_signatures"]["bytecode"] = [a]
        current["categories"]["bytecode"]["discrepancy_count"] = 3
        self.assertEqual(protocol.structural(helper, args, scenario, actual, self.root, "snapshot", {})["no_regression"], "failed")
        # Full pair byte identity can independently preserve unknown evidence;
        # the structural tool/traversal contract is still mandatory.
        actual.with_suffix(".rsc").write_text("native resource fixture")
        native_pin = self.root / "native-pin.json"
        protocol.write(native_pin, {"snapshot_id": "snapshot", "semantic_configuration_sha256": protocol.configuration_gate.digest(configuration), "pair_sha256": {
            extension: sha(actual.with_suffix(extension)) for extension in (".dmb", ".rsc")}})
        args.native_baseline = native_pin
        current["uncovered_signatures"] = None
        current["complete"] = False
        self.assertEqual(protocol.structural(helper, args, scenario, actual, self.root, "snapshot", {})["no_regression"], "passed")
        actual.with_suffix(".rsc").write_text("changed resource fixture")
        self.assertEqual(protocol.structural(helper, args, scenario, actual, self.root, "snapshot", {})["no_regression"], "not_evaluable")

    def test_unknown_semantics_allow_measurement_and_exact_burndown(self):
        case, changed = "a" * 32, "b" * 32
        base = {"schema_version": 1, "snapshot_id": "same", "tool_complete": True, "traversal_complete": True,
                "semantic_coverage": "incomplete", "complete": False,
                "signature_algorithm": "md5-length-framed-v1",
                "categories": {kind: {"discrepancy_count": 0} for kind in protocol.STRUCTURAL_CATEGORIES},
                "category_signatures": {kind: [] for kind in protocol.STRUCTURAL_CATEGORIES},
                "uncovered": {"opaque_value": {"occurrence_count": 2}},
                "uncovered_signatures": {"opaque_value": [case]}}
        self.assertTrue(protocol.exact_structural_evidence(base))
        self.assertEqual(protocol.structural_no_regression(base, copy.deepcopy(base)), "passed")
        improvement = copy.deepcopy(base)
        improvement["uncovered"] = {}
        improvement["uncovered_signatures"] = {}
        self.assertEqual(protocol.structural_no_regression(base, improvement), "passed")
        changed_case = copy.deepcopy(base)
        changed_case["uncovered_signatures"]["opaque_value"] = [changed]
        self.assertEqual(protocol.structural_no_regression(base, changed_case), "failed")
        missing = copy.deepcopy(base)
        missing.pop("uncovered_signatures")
        self.assertEqual(protocol.structural_no_regression(base, missing), "not_evaluable")
        broken_tool = copy.deepcopy(base)
        broken_tool["tool_complete"] = False
        self.assertFalse(protocol.exact_structural_evidence(broken_tool))
        dropped = copy.deepcopy(base)
        dropped["categories"].pop("bytecode")
        dropped["category_signatures"].pop("bytecode")
        self.assertFalse(protocol.exact_structural_evidence(dropped))
        dropped["categories"].clear()
        dropped["category_signatures"].clear()
        self.assertFalse(protocol.exact_structural_evidence(dropped))

    def test_invalid_case_signatures_fail_closed(self):
        self.assertFalse(protocol.valid_case_signatures({"proc": [["bad"]]}))
        self.assertFalse(protocol.valid_case_signatures({"proc": ["0" * 32, "0" * 32]}))
        self.assertTrue(protocol.valid_case_signatures({"proc": []}))


class MeasurementCompositionChecks(unittest.TestCase):
    def test_profile_wall_does_not_replace_measured_child_lifetime(self):
        source = {"schema": 1, "wall_s": 2.0, "wall_scope": "profile_elapsed_wall_interval", "total_cpu_s": 3.0}
        merged = protocol.profile_measurement(source, 5.0)
        self.assertEqual(merged["wall_s"], 5.0)
        self.assertEqual(merged["child_wall_s"], 5.0)
        self.assertEqual(merged["profile_wall_s"], 2.0)
        self.assertEqual(merged["wall_scope"], "harness_child_launch_to_reap")
        self.assertEqual(merged["profile_wall_scope"], "profile_elapsed_wall_interval")
        self.assertEqual(merged["total_cpu_s"], 3.0)
        self.assertEqual(source["wall_s"], 2.0)
        self.assertNotIn("schema", merged)


class ReplayClosureChecks(unittest.TestCase):
    setUp = RetentionChecks.setUp
    tearDown = RetentionChecks.tearDown

    def test_live_mode_keeps_physical_validation_and_non_cold_replay_refused(self):
        helper = SimpleNamespace()
        self.assertEqual(protocol.authenticate_replay_closure(helper, self.root, {"name": "cold"}, None, {})["mode"], "full_physical_source_sha256")
        with self.assertRaisesRegex(ValueError, "no-cache cold replay"):
            protocol.authenticate_replay_closure(helper, self.root, {"name": "body-edit"}, self.root, {})
        with self.assertRaisesRegex(ValueError, "no-cache cold replay"):
            protocol.authenticate_replay_closure(helper, self.root, {"name": "cold", "edits": [{}]}, self.root, {})

    def test_journal_identity_and_topology_pinned_before_compile(self):
        journal = self.root / "journal"
        journal.mkdir()
        manifest = self.root / "comparison.dme"
        manifest.write_text("live bytes are not replay input")
        protocol.write(journal / "index.json", {"files": {str(manifest): [{"size": 10}, 1]}})
        (journal / "index.hash").write_text("captured checksum")
        helper = SimpleNamespace(sha=lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest(),
                                 source_path=lambda root, relative: (root / relative).resolve(),
                                 normal_windows_path=lambda path: Path(path).resolve())
        scenario = {"name": "cold", "project": manifest.name}
        with self.assertRaisesRegex(ValueError, "BYOND snapshot"):
            protocol.authenticate_replay_closure(helper, self.root, scenario, journal, {"snapshot_id": "wrong"})
        closure = protocol.authenticate_replay_closure(helper, self.root, scenario, journal,
                                                      {"snapshot_id": helper.sha(journal / "index.json")})
        self.assertEqual(set(closure["pinned"]), {journal / "index.json", journal / "index.hash"})
        scenario["_closure_validation"] = closure
        protocol.check_source_closure(helper, self.root, {}, [scenario])
        (journal / "index.hash").write_text("changed")
        with self.assertRaisesRegex(ValueError, "journal identity"):
            protocol.check_source_closure(helper, self.root, {}, [scenario])


class SemanticConfigurationChecks(unittest.TestCase):
    setUp = RetentionChecks.setUp
    tearDown = RetentionChecks.tearDown

    def test_changed_define_rejected_and_order_last_wins(self):
        gate = protocol.configuration_gate
        engine = self.root / "engine.bin"
        engine.write_text("pinned engine fixture")
        sha = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
        arguments = ["-DFLAG=old", "-D", "FLAG=new=tail", "--engine-template", str(engine), "--bootstrap-catalog"]
        configuration, _ = gate.command_configuration("comparison.dme", arguments, sha)
        self.assertEqual(configuration["defines"]["FLAG"], "new=tail")
        self.assertEqual(configuration["defines"]["DM_BUILD"], "1687")
        receipts = self.root / "commands.json"
        protocol.write(receipts, [{"producer": "byond", "command": ["dm.exe", "-DFLAG=new=tail", "comparison.dme"],
                                  "exit_code": 0, "timeout": False, "compiler_sha256": "compiler", ".dmb_sha256": "dmb"},
                                 {"producer": "native", "command": ["dmbc.exe", "compile", "comparison.dme", *arguments]}])
        version = self.root / "version.json"
        protocol.write(version, {"compiler_sha256": "compiler", "file_version": "5.0.516.1687"})
        pin = {"dmb_sha256": "dmb", "semantic_configuration": configuration,
               "configuration_evidence": [{"path": str(receipts), "sha256": sha(receipts)}],
               "byond_version_evidence": {"path": str(version), "sha256": sha(version)}}
        self.assertEqual(set(gate.authenticate_pin(pin, configuration, sha)), {receipts, version})
        changed, _ = gate.command_configuration("comparison.dme", [*arguments, "-DFLAG=changed"], sha)
        with self.assertRaisesRegex(ValueError, "configuration differs"):
            gate.authenticate_pin(pin, changed, sha)
        version.write_text("tampered metadata")
        with self.assertRaisesRegex(ValueError, "version evidence hash"):
            gate.authenticate_pin(pin, configuration, sha)

    def test_unknown_flags_bad_defines_and_implicit_engine_fail_closed(self):
        gate = protocol.configuration_gate
        sha = lambda _: "fixture"
        with self.assertRaisesRegex(ValueError, "unclassified"):
            gate.command_configuration("comparison.dme", ["--future-semantics"], sha)
        with self.assertRaisesRegex(ValueError, "invalid define"):
            gate.command_configuration("comparison.dme", ["-D9invalid"], sha)
        with self.assertRaisesRegex(ValueError, "explicit engine"):
            gate.command_configuration("comparison.dme", ["-DOK"], sha)


if __name__ == "__main__":
    unittest.main()
