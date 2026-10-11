"""Source policy only; never invokes Rust or runtime children."""
import unittest
from build_captured_verdigris import validate_roster


class SourceRoster(unittest.TestCase):
    def test_filtered_toolchain_lock_roster_is_required(self):
        files = {'verdigris/rust-toolchain.toml': 'a', 'verdigris/Cargo.lock': 'b'}
        validate_roster(files)
        for invalid in ({}, {**files, '.dmbc/cache.bin': 'c'}, {**files, '.dmbc': 'c'}):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                validate_roster(invalid)


if __name__ == '__main__':
    unittest.main()
