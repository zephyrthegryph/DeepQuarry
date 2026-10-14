"""Synthetic provenance checks only; no compiler or benchmark subprocesses."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest

spec = importlib.util.spec_from_file_location("edited_snapshot", Path(__file__).with_name("edited_snapshot.py"))
edited = importlib.util.module_from_spec(spec)
spec.loader.exec_module(edited)


class EditedSnapshotChecks(unittest.TestCase):
    def test_exact_derivative_and_parent_baseline_rejection(self):
        base = Path("E:/dq-cache/dmb-protocol-checks")
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as temp:
            root = Path(temp)
            sha = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
            write = lambda path, value: path.write_text(json.dumps(value), encoding="utf-8")
            parent, journal = root / "parent", root / "derivative"
            before, after = b"proc a1\n", b"proc a2\n"
            for directory, value, content in ((parent, 1, before), (journal, 2, after)):
                (directory / "payloads").mkdir(parents=True)
                (directory / "payloads" / format(value, "032x")).write_bytes(content)
                write(directory / "index.json", {"files": {"source.dm": [{"size": len(content), "file_id": None}, value]}, "negative": {}, "folders": {}})
                (directory / "index.hash").write_bytes(b"synthetic checksum fixture")
            overlay = {"canonical_path": "source.dm", "old_xxh3_128": "1", "new_xxh3_128": "2", "byte_length": len(before),
                       "before": "a1", "after": "a2", "old_payload_sha256": sha(parent / "payloads" / format(1, "032x")),
                       "new_payload_sha256": sha(journal / "payloads" / format(2, "032x"))}
            write(root / "overlay.json", overlay)
            variant = {"schema": 1, "physical_source_changed": False, "snapshot": str(journal), "original_snapshot": str(parent),
                       "index_sha256": sha(journal / "index.json"), "index_hash_sha256": sha(journal / "index.hash"),
                       "original_index_sha256": sha(parent / "index.json"), "original_index_hash_sha256": sha(parent / "index.hash"),
                       "overlay_sha256": sha(root / "overlay.json")}
            write(root / "variant.json", variant)
            scenario = {"variant_receipt": str(root / "variant.json"), "variant_receipt_sha256": sha(root / "variant.json"), "input_journal": str(journal)}
            pin = {"snapshot_id": variant["index_sha256"], "source_variant_sha256": scenario["variant_receipt_sha256"]}
            result = edited.authenticate(SimpleNamespace(sha=sha), scenario, parent, pin)
            self.assertEqual(result["snapshot_id"], variant["index_sha256"])
            self.assertEqual(before, (parent / "payloads" / format(1, "032x")).read_bytes())
            with self.assertRaisesRegex(ValueError, "BYOND"):
                edited.authenticate(SimpleNamespace(sha=sha), scenario, parent, {**pin, "snapshot_id": variant["original_index_sha256"]})
            with self.assertRaisesRegex(ValueError, "no live edits"):
                edited.authenticate(SimpleNamespace(sha=sha), {**scenario, "edits": [{"path": "source.dm"}]}, parent, pin)
            (journal / "payloads" / format(2, "032x")).write_bytes(before)
            with self.assertRaisesRegex(ValueError, "payload hash"):
                edited.authenticate(SimpleNamespace(sha=sha), scenario, parent, pin)
