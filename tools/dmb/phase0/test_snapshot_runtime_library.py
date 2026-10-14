"""Pure source authority controls; no compiler, Cargo or runtime."""
import unittest
from snapshot_runtime_library import matching_abi


class Abi(unittest.TestCase):
    def test_same_current_declarations(self):
        self.assertEqual(matching_abi('#define VERDIGRIS_ABI "abcd"\n',
                                     'pub const ABI: &str = "abcd";'), "abcd")

    def test_foreign_and_absent_declarations_decline(self):
        for dm, rust in [('#define VERDIGRIS_ABI "034eab3a3bbb7263"\n',
                          'pub const ABI: &str = "bc10d05a700cfdd7";'),
                         ('', 'pub const ABI: &str = "abcd";'),
                         ('#define VERDIGRIS_ABI "abcd"\n' * 2,
                          'pub const ABI: &str = "abcd";')]:
            with self.subTest(dm=dm), self.assertRaises(ValueError):
                matching_abi(dm, rust)


if __name__ == "__main__":
    unittest.main()
