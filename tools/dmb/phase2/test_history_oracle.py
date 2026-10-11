"""Pure policy/owned-child fixtures; never invoke Git or a compiler."""
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile
from history_oracle import synchronize, roster_matches
from history_owned import archive_relative, run_owned, succeeded


class HistoryPolicy(unittest.TestCase):
    def test_archive_paths_reject_escapes_and_windows_drive_forms(self):
        for value in ("../foreign", "/foreign", "C:relative", "C:/absolute", "a\\b"):
            with self.assertRaises(ValueError): archive_relative(value)
        self.assertEqual(archive_relative("code/probe.dm").as_posix(), "code/probe.dm")

    def test_owned_timeout_reaps_job_and_preserves_failed_result(self):
        events = []
        class Child:
            stderr = io.BytesIO()
            def communicate(self, timeout): raise subprocess.TimeoutExpired("fixture", timeout)
            def wait(self, timeout): events.append("wait")
        class Job:
            def __init__(self, limit): events.append(("limit", limit))
            def add(self, child): events.append("assign")
            def resume(self, child): events.append("resume")
            def close(self): events.append("close"); return {"reaped": True}
        result = run_owned(["fixture"], Path("."), {}, io.BytesIO(), 1, 4000,
                           job_factory=Job, popen=lambda *a, **kw: Child())
        self.assertFalse(succeeded(result))
        self.assertEqual(result["failure"], "owned child watchdog")
        self.assertEqual(events, [("limit", 4000), "assign", "resume", "close", "wait"])

    def test_single_owned_source_replaces_tracked_roster_preserving_seed(self):
        # Windows cache-only workspace, no worktree or external mutation.
        cache = Path("E:/dq-cache")
        cache.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="history-policy-", dir=cache) as owned:
            root = Path(owned)
            tree = root / "source"; tree.mkdir()
            seed = tree / "icons/gen/seed.dmi"; seed.parent.mkdir(parents=True)
            seed.write_bytes(b"fixed seed")
            archive = root / "snapshot.zip"
            with zipfile.ZipFile(archive, "w") as z:
                z.writestr("code/old.dm", b"old")
                z.writestr("deepquarry.dme", b"manifest")
            first = synchronize(archive, tree, {}, 100)
            self.assertTrue(roster_matches(tree, first))
            with zipfile.ZipFile(archive, "w") as z:
                z.writestr("code/new.dm", b"new")
                z.writestr("deepquarry.dme", b"new manifest")
            second = synchronize(archive, tree, first, 100)
            self.assertFalse((tree / "code/old.dm").exists())
            self.assertEqual(seed.read_bytes(), b"fixed seed")
            self.assertTrue(roster_matches(tree, second))
            (tree / "code/new.dm").write_bytes(b"tampered")
            self.assertFalse(roster_matches(tree, second))


if __name__ == "__main__": unittest.main()
