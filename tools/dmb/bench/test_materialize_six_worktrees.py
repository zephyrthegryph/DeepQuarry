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
    @unittest.skipUnless(os.name == "nt", "Windows path authority")
    def test_normalized_containment_rejects_traversal_and_parent_itself(self):
        self.assertEqual(module.normalized_path("E:/dq-cache/../outside"), Path("E:/outside"))
        for value in ("E:/dq-cache", "E:/dq-cache/../outside"):
            with self.assertRaises(ValueError): module.owned_output(value)
        roots = [f"E:/projects/dq-wt/../escape-{index}" for index in range(6)]
        with self.assertRaises(ValueError): module.target_roots(roots)
if __name__ == "__main__": unittest.main()
