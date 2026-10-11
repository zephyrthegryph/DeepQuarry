"""Source policy only; never invokes Rust or runtime children."""
import unittest
from unittest.mock import patch
from build_captured_verdigris import validate_roster, begin_phase, finish_phase, validate_resume, profile_environment


class SourceRoster(unittest.TestCase):
    def test_profiles_sanitize_inherited_compiler_overrides_and_are_not_interchangeable(self):
        inherited = {'RUSTFLAGS': '-C opt-level=3', 'CARGO_ENCODED_RUSTFLAGS': 'foreign',
                     'CARGO_BUILD_RUSTFLAGS': 'foreign', 'CARGO_PROFILE_DEV_DEBUG': '2', 'OTHER': 'keep'}
        release, cleared = profile_environment('captured-release', inherited)
        diagnostic, _ = profile_environment('diagnostic-unoptimized', inherited)
        self.assertEqual(set(cleared), set(inherited) - {'OTHER'})
        self.assertEqual(diagnostic['CARGO_PROFILE_RELEASE_OPT_LEVEL'], '0')
        self.assertEqual(diagnostic['CARGO_PROFILE_RELEASE_DEBUG'], '0')
        self.assertEqual(diagnostic['CARGO_PROFILE_RELEASE_LTO'], 'false')
        self.assertEqual(diagnostic['CARGO_PROFILE_RELEASE_PANIC'], 'unwind')
        self.assertEqual(diagnostic['CARGO_PROFILE_RELEASE_CODEGEN_UNITS'], '16')
        self.assertEqual(diagnostic['CARGO_ENCODED_RUSTFLAGS'], '')
        previous = {'schema': 'captured-verdigris-build-v1', 'error': 'timeout',
                    'owned_job_cleanup': {'reaped': True}, 'profile': 'captured-release',
                    'profileEnvironment': release}
        with self.assertRaises(ValueError):
            validate_resume(previous, {'profile': 'diagnostic-unoptimized', 'profileEnvironment': diagnostic})

    def test_resume_requires_failed_reaped_exact_authority(self):
        expected = {'targetDirectory': 'E:/owned/target', 'inputsBefore': {'verdigris/Cargo.lock': 'exact'},
                    'dependencyEnvironment': {'CARGO_HOME': 'E:/cargo'}, 'cargo': {'sha256': 'pin'}}
        previous = {**expected, 'schema': 'captured-verdigris-build-v1',
                    'owned_job_cleanup': {'reaped': True}, 'exit': None, 'timeout': True}
        validate_resume(previous, expected)
        for changed in ({'owned_job_cleanup': {'reaped': False}}, {'timeout': False, 'exit': 0},
                        {'targetDirectory': 'E:/foreign/target'}, {'inputsBefore': {}},
                        {'dependencyEnvironment': {'CARGO_HOME': 'E:/other'}}, {'cargo': {'sha256': 'other'}}):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                validate_resume({**previous, **changed}, expected)

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
