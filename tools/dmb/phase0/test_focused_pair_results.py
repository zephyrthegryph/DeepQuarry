import unittest
from focused_pair_results import memory_bytes, compare, passing_acceptance


class FocusedPairPolicy(unittest.TestCase):
    def test_memory_explicit_bounds(self):
        self.assertEqual(memory_bytes(4096), 4294967296)
        self.assertEqual(memory_bytes(6144), 6442450944)
        for value in (0, 4095, 6145, True):
            with self.assertRaises(ValueError):
                memory_bytes(value)

    def test_compare_preserves_runtime_error_evidence_and_ignores_duration(self):
        row = dict(status=0, name='probe', runtimes=0, runtime_errors=[], runtime_errors_truncated=False)
        left = {'record': {'clean': True, 'tests': {'probe': dict(row, duration_ds=1)}}}
        right = {'record': {'clean': True, 'tests': {'probe': dict(row, duration_ds=99)}}}
        self.assertTrue(compare(left, right)['matches'])
        right['record']['tests']['probe']['runtime_errors'] = [{'description': 'caught runtime'}]
        self.assertFalse(compare(left, right)['matches'])
        right['record']['tests']['probe']['runtime_errors_truncated'] = True
        with self.assertRaises(ValueError):
            compare(left, right)

    def test_matching_failures_preserve_parity_without_acceptance(self):
        row = dict(status=1, name='probe', message='expected failure', runtimes=1,
                   runtime_errors=[{'description': 'caught runtime'}], runtime_errors_truncated=False)
        left = {'record': {'clean': True, 'tests': {'probe': dict(row)}}}
        right = {'record': {'clean': True, 'tests': {'probe': dict(row)}}}
        result = compare(left, right)
        self.assertTrue(result['parity'])
        self.assertFalse(result['all_tests_passed'])
        self.assertEqual(result['observedRecords']['native']['record']['tests']['probe']['runtime_errors'], row['runtime_errors'])
        left['record']['clean'] = right['record']['clean'] = False
        result = compare(left, right)
        self.assertTrue(result['parity'])
        self.assertFalse(result['all_tests_passed'])
        self.assertFalse(result['nativeClean'])

    def test_matching_skips_are_not_all_tests_passed(self):
        row = dict(status=2, name='probe', runtimes=0, runtime_errors=[], runtime_errors_truncated=False)
        left = {'record': {'clean': True, 'tests': {'probe': dict(row)}}}
        right = {'record': {'clean': True, 'tests': {'probe': dict(row)}}}
        result = compare(left, right)
        self.assertTrue(result['parity'])
        self.assertFalse(result['all_tests_passed'])

    def test_nonzero_child_exit_cannot_count_as_passing_acceptance(self):
        executions = {'byond': {'exit_code': 2, 'timeout': False, 'reaped': True},
                      'native': {'exit_code': 2, 'timeout': False, 'reaped': True}}
        comparison = {'parity': True, 'all_tests_passed': True}
        self.assertFalse(passing_acceptance(comparison, executions))
        self.assertEqual(executions['native']['exit_code'], 2)
        executions['byond']['exit_code'] = executions['native']['exit_code'] = 0
        self.assertTrue(passing_acceptance(comparison, executions))
        executions['native']['reaped'] = False
        self.assertFalse(passing_acceptance(comparison, executions))


if __name__ == '__main__':
    unittest.main()
