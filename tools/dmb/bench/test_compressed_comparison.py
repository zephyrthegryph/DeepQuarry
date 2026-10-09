"""Authenticated complete profiler overlays; no compiler execution."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location("compressed", Path(__file__).with_name("prepare-compressed-comparison.py"))
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)


class OverlayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp_root = Path("E:/dq-cache/dmb-protocol-checks")
        cls.temp_root.mkdir(parents=True, exist_ok=True)

    def test_complete_subtree_replaces_obsolete_modules_and_keeps_nonprofile_sources(self):
        with tempfile.TemporaryDirectory(dir=self.temp_root) as directory:
            root = Path(directory)
            overlay = root / "overlay"
            current = {
                h.PROFILE + "Cargo.toml": b"current manifest",
                h.PROFILE + "src/lib.rs": b"mod nested; mod thread_label;",
                h.PROFILE + "src/thread_label.rs": b"thread helper",
                h.PROFILE + "src/nested/mod.rs": b"nested module",
                h.LOCK: b"current lock",
            }
            for name, data in current.items():
                path = overlay / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            original = {
                h.PROFILE + "src/lib.rs": b"old lib",
                h.PROFILE + "src/obsolete.rs": b"obsolete",
                h.LOCK: b"old lock",
                "tools/dmb/crates/dm-exec/src/lib.rs": b"unaltered executor",
            }
            archive = root / "parent.zip"
            with zipfile.ZipFile(archive, "w") as zipped:
                for name, data in original.items():
                    zipped.writestr(name, data)
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps([
                {"path": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
                for name, data in original.items()]), encoding="utf-8")
            record = root / "build.json"
            record.write_text(json.dumps({"source_archive": str(archive),
                "source_archive_sha256": h.sha(archive), "manifest": str(manifest),
                "manifest_sha256": h.sha(manifest)}), encoding="utf-8")
            with patch.object(h, "e_path", lambda path: Path(path).resolve()):
                result = h.prepare(record, record, overlay, root / "output", 30)
            for snapshot in result["snapshots"]:
                with zipfile.ZipFile(snapshot["source_archive"]) as zipped:
                    expected = {**current, "tools/dmb/crates/dm-exec/src/lib.rs": b"unaltered executor"}
                    self.assertEqual(set(zipped.namelist()), set(expected))
                    self.assertEqual({name: zipped.read(name) for name in zipped.namelist()}, expected)
                self.assertEqual(snapshot["build_status"], "not_built")
            self.assertEqual(result["required_environment"], {"DMB_TRACE_COMPRESSION": "gzip"})

    def test_nested_module_is_required_in_snapshot_and_roster_changes_detected(self):
        with tempfile.TemporaryDirectory(dir=self.temp_root) as directory:
            root = Path(directory)
            for name in (h.PROFILE + "Cargo.toml", h.PROFILE + "src/lib.rs", h.LOCK):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"source")
            before = h.snapshot_overlay(root)
            nested = root / h.PROFILE / "src/new.rs"
            nested.write_bytes(b"new module")
            self.assertNotEqual(before, h.snapshot_overlay(root))
            self.assertTrue(h.replaced_by_overlay(h.PROFILE + "src/obsolete.rs"))
            self.assertFalse(h.replaced_by_overlay("tools/dmb/crates/dm-exec/src/lib.rs"))


class ParentLockTests(unittest.TestCase):
    manifest = b'[package]\nname="dm-profile"\nversion="0.1.0"\n[dependencies]\nflate2="1"\n'
    lock = b'''version=4
[[package]]
name="dm-profile"
version="0.1.0"
dependencies=["flate2"]
[[package]]
name="flate2"
version="1.1.0"
source="registry+https://example.test/index"
checksum="abc"
dependencies=["crc32fast"]
[[package]]
name="crc32fast"
version="1.0.0"
source="registry+https://example.test/index"
checksum="def"
'''

    def test_unrelated_parent_lock_edges_are_retained_with_identical_profiler_closure(self):
        unrelated = b'\n[[package]]\nname="dm-syntax"\nversion="0.1.0"\ndependencies=["memchr"]\n[[package]]\nname="memchr"\nversion="2.8.3"\n'
        digest = h.compatible_parent_lock(self.lock, self.lock + unrelated, self.manifest)
        self.assertEqual(digest, h.compatible_parent_lock(self.lock, self.lock, self.manifest))
        self.assertEqual(len(digest), 64)

    def test_checksum_version_and_missing_dependency_changes_fail_closed(self):
        for changed in (self.lock.replace(b'checksum="def"', b'checksum="other"'),
                        self.lock.replace(b'version="1.0.0"', b'version="2.0.0"'),
                        self.lock.replace(b'dependencies=["crc32fast"]', b'dependencies=[]')):
            with self.assertRaises(ValueError):
                h.compatible_parent_lock(changed, self.lock, self.manifest)

    def test_manifest_and_ambiguous_lock_dependency_are_rejected(self):
        with self.assertRaises(ValueError):
            h.profiler_closure(self.lock, self.manifest.replace(b'flate2="1"', b'other="1"'))
        duplicate = b'\n[[package]]\nname="flate2"\nversion="2.0.0"\n'
        with self.assertRaises(ValueError):
            h.profiler_closure(self.lock + duplicate, self.manifest)


if __name__ == "__main__":
    unittest.main()
