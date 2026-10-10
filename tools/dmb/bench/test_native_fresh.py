import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("native_fresh", Path(__file__).with_name("native-fresh.py"))
fresh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fresh)


class FreshAdmission(unittest.TestCase):
    def test_semantic_order_and_no_routing_passthrough(self):
        scenario = {"arguments": ["-DA=1", "--no-daemon", "-DA=2", "--engine-template", "old", "--bootstrap-catalog"]}
        self.assertEqual(fresh.semantic_arguments(scenario, "pinned"), ["-DA=1", "-DA=2", "--bootstrap-catalog", "--engine-template", "pinned"])
        with self.assertRaises(ValueError):
            fresh.semantic_arguments({"arguments": ["--output-store", "unowned"]}, "pinned")

    def test_post_compile_source_recheck_allows_only_preserved_exact_telemetry(self):
        with tempfile.TemporaryDirectory(prefix="native-fresh-source-", dir="E:/dq-cache") as temp:
            root = Path(temp)
            project = root / "project"
            project.mkdir()
            source = project / "probe.dme"
            source.write_bytes(b"source")
            sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
            snapshot = {"files": {"probe.dme": sha(source)}}
            fresh.confirm_source(project, snapshot, sha)
            telemetry = project / ".dmbc"
            telemetry.mkdir()
            (telemetry / "probe.stats.json").write_text("{}")
            fresh.preserve_telemetry(source, root / "telemetry", lambda p: None, sha)
            fresh.confirm_source(project, snapshot, sha)
            source.write_bytes(b"mutated")
            with self.assertRaisesRegex(ValueError, "after compilation"):
                fresh.confirm_source(project, snapshot, sha)
            source.write_bytes(b"source")
            (project / "unexpected.dm").write_text("new input")
            with self.assertRaises(ValueError):
                fresh.confirm_source(project, snapshot, sha)

    def test_generated_empty_lock_exception_is_exact_and_never_removed(self):
        with tempfile.TemporaryDirectory(prefix="native-fresh-lock-", dir="E:/dq-cache") as temp:
            root = Path(temp)
            source = root / "probe.dme"
            source.write_bytes(b"source")
            sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
            snapshot = {"files": {"probe.dme": sha(source)}}
            lock = fresh.require_absent_lock(root, Path("probe.dme"), snapshot)
            lock.parent.mkdir()
            lock.write_bytes(b"")
            proof = fresh.confirm_source(root, snapshot, sha, lock)
            self.assertEqual(proof["bytes"], 0)
            self.assertTrue(lock.exists())
            with self.assertRaisesRegex(ValueError, "before run"):
                fresh.require_absent_lock(root, Path("probe.dme"), snapshot)
            lock.write_bytes(b"tampered")
            with self.assertRaisesRegex(ValueError, "empty"):
                fresh.confirm_source(root, snapshot, sha, lock)
            lock.write_bytes(b"")
            (lock.parent / "other.lock").write_bytes(b"")
            with self.assertRaisesRegex(ValueError, "captured closure"):
                fresh.confirm_source(root, snapshot, sha, lock)
            with self.assertRaisesRegex(ValueError, "captured source"):
                fresh.require_absent_lock(root, Path("probe.dme"), {"files": {**snapshot["files"], ".dmbc/build.lock": sha(lock)}})

    def test_pair_admission_requires_actual_matching_artifacts_and_generation(self):
        with tempfile.TemporaryDirectory(prefix="native-fresh-fixture-", dir="E:/dq-cache") as temp:
            root = Path(temp)
            slots = root / "slots"
            slot = slots / "one"
            slot.mkdir(parents=True)
            project = root / "artifacts" / "probe.dme"
            project.parent.mkdir()
            result = {"schema_version": 1, "kind": "native_pair", "output_project": str(project),
                      "store": str(root / "store"), "pair_id": "1" * 32,
                      "dmb_hash": "2" * 32, "rsc_hash": "3" * 32, "dmb_bytes": 3, "rsc_bytes": 4}
            acquired = {**result, "kind": "acquired_pair", "slot": str(slot),
                        "dmb": str(slot / "deepquarry.dmb"), "rsc": str(slot / "deepquarry.rsc")}
            (slot / "slot-complete").write_text(result["pair_id"])
            for ext, data in (("dmb", b"dmb"), ("rsc", b"data")):
                Path(acquired[ext]).write_bytes(data)
                project.with_suffix("." + ext).write_bytes(data)
            def regular(path):
                if not path.is_file() or path.is_symlink(): raise ValueError("not regular")
            sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
            outputs = fresh.admit_pair(result, acquired, project, root / "store", slots, regular, sha)
            self.assertEqual(outputs["rsc"]["bytes"], 4)
            project.with_suffix(".rsc").write_bytes(b"evil")
            with self.assertRaisesRegex(ValueError, "copy differs"):
                fresh.admit_pair(result, acquired, project, root / "store", slots, regular, sha)
            with self.assertRaisesRegex(ValueError, "generation"):
                fresh.admit_pair(result, {**acquired, "pair_id": "4" * 32}, project, root / "store", slots, regular, sha)


if __name__ == "__main__":
    unittest.main()
