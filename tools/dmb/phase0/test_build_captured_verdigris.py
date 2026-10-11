"""Source policy only; never invokes Rust or runtime children."""
import unittest
from unittest.mock import patch
from build_captured_verdigris import validate_roster, begin_phase, finish_phase


class SourceRoster(unittest.TestCase):
    def test_phase_deadlines_do_not_consume_next_phase_budget(self):
        phases = []
        with patch('build_captured_verdigris.time.monotonic', side_effect=[10, 290, 295, 500, 505, 700]):
            for name in ('source_admission', 'owned_cargo', 'source_verification'):
                finish_phase(begin_phase(name, phases))
        self.assertEqual([p['deadline_monotonic'] for p in phases], [310, 595, 805])
        self.assertEqual([p['actual_seconds'] for p in phases], [280, 205, 195])
        self.assertEqual(sum(p['maximum_seconds'] for p in phases), 900)

    def test_filtered_toolchain_lock_roster_is_required(self):
        files = {'verdigris/rust-toolchain.toml': 'a', 'verdigris/Cargo.lock': 'b'}
        validate_roster(files)
        for invalid in ({}, {**files, '.dmbc/cache.bin': 'c'}, {**files, '.dmbc': 'c'}):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                validate_roster(invalid)


if __name__ == '__main__':
    unittest.main()
