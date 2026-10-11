"""Pure policy checks; no worktrees, copies, Git subprocesses or compilers."""
import importlib.util
from pathlib import Path
import unittest
import os
spec = importlib.util.spec_from_file_location("materialize_six", Path(__file__).with_name("materialize-six-worktrees.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
class PolicyTests(unittest.TestCase):
    def test_seed_never_overwrites_existing_content(self):
        self.assertEqual(module.seed_action(True, True, True), "verified")
        self.assertEqual(module.seed_action(False, True, True), "verified")
        self.assertEqual(module.seed_action(False, False, False), "seed")
        for tracked in (True, False):
            with self.assertRaises(ValueError): module.seed_action(tracked, True, False)
        with self.assertRaises(ValueError): module.seed_action(True, False, False)
    def test_relative_paths_cannot_escape_or_seed_producer_outputs(self):
        self.assertEqual(module.relative_path("icons/gen/item.dmi"), Path("icons/gen/item.dmi"))
        for value in ("../code.dm", "/code.dm", "E:/code.dm", "a\\b", "a//b", ".git/config", "a/target/file", "probe.dmb", "a/../b"):
            with self.assertRaises(ValueError): module.relative_path(value)
    def test_explicit_untracked_seed_mode_never_uses_historical_tracked_rows(self):
        rows = [{"path": "tools/compiler.rs", "sha256": "old"},
                {"path": "icons/gen/item.dmi", "sha256": "asset"}]
        tracked = {"tools/compiler.rs": ("100644", "blob", "current")}
        self.assertEqual(module.selected_seed_rows(rows, tracked, False), rows)
        selected = module.selected_seed_rows(rows, tracked, True)
        self.assertEqual(selected, [rows[1]])
        self.assertIs(selected[0], rows[1])
        self.assertEqual(rows[0]["sha256"], "old")

    def test_disk_floor_and_projected_root_bytes(self):
        module.admit_disk_space(module.FREE_FLOOR + 7_000_000_000, 7_000_000_000)
        for free, projected in ((14_959_337_472, 0), (module.FREE_FLOOR, 1),
                                (module.FREE_FLOOR + 7_000_000_000 - 1, 7_000_000_000)):
            with self.assertRaises(ValueError): module.admit_disk_space(free, projected)

    @unittest.skipUnless(os.name == "nt", "Windows path authority")
    def test_normalized_containment_rejects_traversal_and_parent_itself(self):
        self.assertEqual(module.normalized_path("E:/dq-cache/../outside"), Path("E:/outside"))
        for value in ("E:/dq-cache", "E:/dq-cache/../outside"):
            with self.assertRaises(ValueError): module.owned_output(value)
        roots = [f"E:/projects/dq-wt/../escape-{index}" for index in range(6)]
        with self.assertRaises(ValueError): module.target_roots(roots)
if __name__ == "__main__": unittest.main()
