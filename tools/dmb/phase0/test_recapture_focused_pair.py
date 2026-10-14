"""Caller define conversion policy; no compiler/runtime launch."""
import unittest
from recapture_focused_pair import runtime_extra_defines

class ReplayDefines(unittest.TestCase):
    def test_exact_prefix_is_removed_without_deduplicating_effective_defines(self):
        prefix = ['CBT', 'CIBUILDING', 'CITESTING', 'DEBUG']
        self.assertEqual(runtime_extra_defines(prefix + ['UNIT_TESTS']), ['UNIT_TESTS'])
        self.assertEqual(runtime_extra_defines(prefix + ['DEBUG']), ['DEBUG'])
        self.assertEqual(runtime_extra_defines(prefix), [])
        for invalid in (['UNIT_TESTS'], list(reversed(prefix)), ['CBT', 'CIBUILDING', 'DEBUG', 'CITESTING']):
            with self.assertRaises(ValueError): runtime_extra_defines(invalid)

if __name__ == '__main__': unittest.main()
