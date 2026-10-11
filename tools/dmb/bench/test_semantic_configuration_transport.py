"""Transport path admission preserves semantic configuration and actual commands."""
import unittest
from pathlib import Path
import semantic_configuration as policy


class CompileResultTransport(unittest.TestCase):
    def test_result_path_is_transport_only_but_requires_one_value(self):
        base = ['--engine-template', 'E:/dq-cache/template.dmb', '--bootstrap-catalog']
        plain, _ = policy.command_configuration('comparison.dme', base, lambda path: 'a' * 64)
        actual, _ = policy.command_configuration('comparison.dme', base + ['--compile-result-file', 'E:/dq-cache/result.json'], lambda path: 'a' * 64)
        self.assertEqual(plain, actual)
        for extra in (['--compile-result-file'], ['--compile-result-file', 'first', '--compile-result-file', 'second']):
            with self.assertRaises(ValueError):
                policy.command_configuration('comparison.dme', base + extra, lambda path: 'a' * 64)


if __name__ == '__main__':
    unittest.main()
