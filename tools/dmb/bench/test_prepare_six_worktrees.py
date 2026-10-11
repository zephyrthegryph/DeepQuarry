"""Pure preparation checks; no compiler, Git child or source isolation."""
import importlib.util
from pathlib import Path
import unittest
from session_acceptance import session_edit_coverage

spec = importlib.util.spec_from_file_location('prepare_six', Path(__file__).with_name('prepare-six-worktrees.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PreparationTests(unittest.TestCase):
    def test_foreign_different_revisions_decline_before_input_reads(self):
        roots = [f'E:/projects/dq-wt/explicit-{index}' for index in range(6)]
        registrations = [{'worktree': root, 'HEAD': str(index) * 40} for index, root in enumerate(roots)]
        with self.assertRaisesRegex(ValueError, 'one explicit source revision'):
            module.prepare(roots, registrations, None)

    def test_duplicate_roots_decline(self):
        with self.assertRaisesRegex(ValueError, 'six distinct'):
            module.prepare(['E:/projects/dq-wt/example'] * 6, [], None)

    def test_unregistered_roots_decline(self):
        roots = [f'E:/projects/dq-wt/explicit-{index}' for index in range(6)]
        with self.assertRaisesRegex(ValueError, 'registered live worktree'):
            module.prepare(roots, [], None)

    def test_preparation_uses_the_runner_policy_for_isolation(self):
        self.assertIs(module.session_edit_coverage, session_edit_coverage)
        edits = [{"kind": "body", "sessions": [0]},
                 {"kind": "structural", "structural_kind": "newproc", "sessions": [1]}]
        admitted = module.session_edit_coverage(edits, 6)
        self.assertEqual(admitted["classification"], "six-session-isolation-probe")
        self.assertEqual(admitted["per_session"][2:], [[], [], [], []])

    def test_incomplete_nonisolated_plan_cannot_claim_full_acceptance(self):
        with self.assertRaises(ValueError):
            module.session_edit_coverage([{"kind": "body", "sessions": list(range(6))}], 6)
        edits = [{"kind": "body"}] + [{"kind": "structural", "structural_kind": kind}
                                      for kind in ("newvar", "newproc", "default")]
        self.assertEqual(module.session_edit_coverage(edits, 6)["classification"],
                         "six-worktree-byte-acceptance")


if __name__ == '__main__':
    unittest.main()
