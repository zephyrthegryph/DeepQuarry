"""Small exact-proof checks; never launch compiler or inspector."""
import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest


def module(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + ".py"))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


reuse = module("structural_reuse")
protocol = module("protocol")


class ReuseChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir="E:/dq-cache/dmb-protocol-checks")
        self.root = Path(self.temporary.name)
        self.identity = reuse.key(inspector_sha256="i", expected_dmb_sha256="b",
            actual_dmb_sha256="n", actual_rsc_sha256="r", snapshot_id="s", configuration_sha256="c")
        self.full = {"schema_version": 1, "snapshot_id": "s", "tool_complete": True,
            "traversal_complete": True, "signature_algorithm": "md5-length-framed-v1"}
        self.report = self.root / "report.json"
        self.report.write_text(json.dumps(self.full), encoding="utf-8")
        self.registry = reuse.Reports()

    def tearDown(self):
        self.temporary.cleanup()

    def test_first_key_must_execute_and_every_changed_input_misses(self):
        self.assertIsNone(self.registry.lookup(self.identity))
        self.registry.remember(self.identity, self.report, "first")
        self.assertEqual(self.registry.lookup(self.identity)[0], self.full)
        for name in self.identity:
            changed = dict(self.identity, **{name: str(self.identity[name]) + "changed"})
            self.assertIsNone(self.registry.lookup(changed), name)
        self.assertIsNone(reuse.Reports().lookup(self.identity))

    def test_changed_report_hash_fails_closed(self):
        self.registry.remember(self.identity, self.report, "first")
        self.report.write_text(json.dumps(dict(self.full, tool_complete=False)), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            self.registry.lookup(self.identity)

    def test_missing_report_fails_closed(self):
        self.registry.remember(self.identity, self.report, "first")
        self.report.unlink()
        with self.assertRaises(OSError):
            self.registry.lookup(self.identity)

    def test_protocol_recomputes_admission_and_current_rsc_for_each_row(self):
        expected = self.root / "expected.dmb"; expected.write_bytes(b"byond")
        actual = self.root / "actual.dmb"; actual.write_bytes(b"native")
        actual.with_suffix(".rsc").write_bytes(b"resource")
        inspector = self.root / "inspector.exe"; inspector.write_bytes(b"tool")
        configuration = {"project": "test"}
        pin = self.root / "pin.json"
        pin.write_text(json.dumps({"snapshot_id": "s", "dmb_sha256": reuse.digest(expected),
            "semantic_configuration": configuration}), encoding="utf-8")
        full = dict(self.full, complete=True, unexplained_discrepancies=0, semantic_coverage="complete",
            categories={name: {"discrepancy_count": 0} for name in protocol.STRUCTURAL_CATEGORIES},
            category_signatures={name: [] for name in protocol.STRUCTURAL_CATEGORIES},
            uncovered={}, uncovered_signatures={})
        calls = []
        def run(command, *unused):
            calls.append(command)
            Path(command[4]).write_text(json.dumps(full), encoding="utf-8")
            return 0, 1.0, False
        harness = SimpleNamespace(sha=reuse.digest, run=run)
        args = SimpleNamespace(byond_dmb=expected, byond_snapshot=pin, inspector=inspector,
            watchdog=600, structural_baseline=None, establish_structural_baseline=True, native_baseline=None)
        scenario = {"_semantic_configuration": configuration}
        first = self.root / "first"; first.mkdir()
        second = self.root / "second"; second.mkdir()
        a = protocol.structural(harness, args, scenario, actual, first, "s", {})
        b = protocol.structural(harness, args, scenario, actual, second, "s", {})
        self.assertEqual(len(calls), 1)
        self.assertEqual(a["no_regression"], "baseline_established")
        self.assertEqual(b["no_regression"], "passed")
        self.assertEqual(a["structural_check"]["mode"], "executed")
        self.assertEqual(b["structural_check"]["mode"], "authenticated_same_inputs")
        self.assertEqual(a["report"], b["report"])
        self.assertEqual(b["native_pair_sha256"][".rsc"], reuse.digest(actual.with_suffix(".rsc")))
        actual.with_suffix(".rsc").write_bytes(b"changedresource")
        third = self.root / "third"; third.mkdir()
        protocol.structural(harness, args, scenario, actual, third, "s", {})
        self.assertEqual(len(calls), 2)


if __name__ == "__main__":
    unittest.main()
