"""Pure preparation checks; no compiler, Git child or source isolation."""
import importlib.util
from pathlib import Path
import unittest

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


if __name__ == '__main__':
    unittest.main()
