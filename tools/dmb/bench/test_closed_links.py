"""Native closed-link proof checks using only disposable tiny E: fixtures."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("closed_links", Path(__file__).with_name("closed_links.py"))
closed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(closed)


@unittest.skipUnless(os.name == "nt" and Path("E:/").exists(), "native Windows E: checks")
class NativeClosedLinks(unittest.TestCase):
    def setUp(self):
        base = Path("E:/dq-cache/dmb-protocol-checks")
        base.mkdir(parents=True, exist_ok=True)
        self.home = Path(tempfile.mkdtemp(prefix="closed-links-", dir=base))
        self.roots = [self.home / "measured", self.home / "fresh"]
        for root in self.roots:
            root.mkdir()
            (root / closed.MARKER).write_text(json.dumps({"schema": 1,
                "owner": str(self.home.resolve()), "path": str(root.resolve())}), encoding="utf-8")

    def tearDown(self):
        # These fixtures are exclusively ours, including every synthetic link.
        # Never apply fixture cleanup to real artifacts or shared output stores.
        for directory, _, files in os.walk(self.home, followlinks=False):
            for name in files:
                item = Path(directory) / name
                if not item.is_symlink():
                    item.chmod(item.stat().st_mode | stat.S_IWRITE)
        shutil.rmtree(self.home)

    def pair(self, outside=False):
        first = self.roots[0] / "tiny.rsc"
        second = (self.home if outside else self.roots[1]) / "linked.rsc"
        first.write_bytes(b"synthetic closed-link fixture")
        os.link(first, second)
        first.chmod(first.stat().st_mode & ~stat.S_IWRITE)
        self.assertReadonly(first)
        self.assertReadonly(second)
        return first, second

    def assertReadonly(self, path):
        self.assertTrue(path.stat().st_file_attributes & closed.READONLY)

    def test_internal_closed_inode_is_prepared_without_deleting(self):
        first, second = self.pair()
        report = closed.prepare_owned_readonly(self.roots, ())
        self.assertEqual(report["status"], "prepared", report)
        self.assertEqual(len(report["prepared"]), 1)
        self.assertFalse(report["blocked"])
        for path in (first, second):
            self.assertTrue(path.exists())
            self.assertFalse(path.stat().st_file_attributes & closed.READONLY)
            self.assertEqual(path.read_bytes(), b"synthetic closed-link fixture")
        self.assertEqual(first.stat().st_ino, second.stat().st_ino)

    def test_external_pinned_link_is_preserved_readonly(self):
        first, second = self.pair(outside=True)
        report = closed.prepare_owned_readonly(self.roots, (second,))
        self.assertEqual(report["status"], "partially_prepared")
        self.assertFalse(report["prepared"])
        self.assertEqual(len(report["blocked"]), 1)
        self.assertReadonly(first)
        self.assertReadonly(second)

    def test_invalid_later_marker_prevents_any_attribute_mutation(self):
        first, second = self.pair()
        (self.roots[1] / closed.MARKER).write_text("{}", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "marker mismatch"):
            closed.prepare_owned_readonly(self.roots, ())
        self.assertReadonly(first)
        self.assertReadonly(second)

    def test_reparse_descendant_prevents_any_attribute_mutation(self):
        first, second = self.pair()
        target = self.home / "junction-target"
        target.mkdir()
        junction = self.roots[1] / "junction"
        # NTFS junction creation needs no symlink privilege or elevation.
        result = subprocess.run(["cmd", "/c", "mklink", "/J", str(junction), str(target)],
                                capture_output=True, text=True, timeout=10)
        if result.returncode:
            self.fail("Could not create unelevated synthetic junction: " + result.stderr)
        try:
            with self.assertRaisesRegex(ValueError, "reparse"):
                closed.prepare_owned_readonly(self.roots, ())
            self.assertReadonly(first)
            self.assertReadonly(second)
        finally:
            # Remove the junction itself, never recurse into its target.
            junction.rmdir()


if __name__ == "__main__":
    unittest.main()
