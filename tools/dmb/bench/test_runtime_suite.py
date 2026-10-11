"""Pure contracts only: never launches build, compiler or runtime."""
import importlib.util
from pathlib import Path
import unittest
from unittest import mock
import tempfile
import stat
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location('runtime_suite', Path(__file__).with_name('runtime-suite.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)


class Contracts(unittest.TestCase):
    def test_strict_environment_removes_manifest_and_abi_bypasses_without_mutating_caller(self):
        bypasses = ['DQ_PREBUILT_VERDIGRIS', 'DQ_SKIP_VERDIGRIS_ABI_CHECK', 'DQ_WIP_TREE',
                    'DQ_ALLOW_UNREACHABLE_DM', 'DQ_NATIVE_COMPILER', 'DQ_NATIVE_ENGINE_TEMPLATE']
        inherited = {name: '1' for name in bypasses}
        inherited['PATH'] = 'caller-path'
        env = runner.strict_environment(inherited)
        self.assertEqual(env, {'PATH': 'caller-path'})
        self.assertTrue(all(name in inherited for name in bypasses))
        self.assertEqual(runner.strict_environment({}), {})

    def test_owned_paths_resolve_dotdot_and_reject_reparse_ancestors(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory) / 'cache'; cache.mkdir()
            self.assertEqual(runner.owned_cache_path(cache / 'run' / '..' / 'new', cache), cache / 'new')
            with self.assertRaises(ValueError): runner.owned_cache_path(cache / '..' / 'foreign', cache)
            with self.assertRaises(ValueError): runner.owned_cache_path(Path('relative'), cache)
            original = Path.lstat
            def lstat(value):
                if value == cache: return SimpleNamespace(st_mode=stat.S_IFDIR, st_file_attributes=0x400)
                return original(value)
            with mock.patch.object(Path, 'lstat', lstat):
                with self.assertRaisesRegex(ValueError, 'reparse'): runner.owned_cache_path(cache / 'new', cache)
    def args(self, *extra):
        return runner.parser().parse_args(['--checkout', 'E:/work', '--output', 'E:/dq-cache/new', '--backend', 'byond',
            '--bash-exe', 'C:/bash.exe', '--bash-sha256', 'a' * 64, '--byond-exe', 'D:/dm.exe', '--byond-sha256', 'b' * 64,
            '--dd-exe', 'D:/dreamdaemon.exe', '--dd-sha256', 'c' * 64, '--security', 'trusted', *extra])

    def test_all_tier_resume_uses_same_suite_core(self):
        args = self.args('--tier', 'all', '--batch-size', '32', '--resume', 'E:/checkpoint.json', '--resume-sha256', 'd' * 64)
        command = runner.command(args, runner.validate(args))
        self.assertIn('--suite-batches=32', command)
        self.assertIn('--tier=all', command)
        self.assertIn('--suite-resume=' + str(args.resume), command)
        self.assertFalse(any(value.startswith('--normal-resume=') for value in command))

    def test_shorter_owned_cohort_preserves_suite_selection(self):
        args = self.args('--tier', 'all', '--batch-size', '32', '--seconds', '300')
        self.assertTrue(runner.validate(args))
        self.assertEqual(args.seconds, 300)
        self.assertNotIn('--seconds', runner.command(args, True))
        for seconds in ('0', '1801'):
            with self.assertRaisesRegex(ValueError, 'cohort seconds'):
                runner.validate(self.args('--tier', 'all', '--batch-size', '32', '--seconds', seconds))

    def test_historical_normal_and_focused_commands(self):
        args = self.args('--tier', 'normal', '--batch-size', '32')
        self.assertIn('--normal-batches=32', runner.command(args, runner.validate(args)))
        args = self.args('--focus', '/datum/unit_test/a', '--focus', '/datum/unit_test/b')
        focused = runner.command(args, runner.validate(args))
        self.assertEqual(focused[1:], ['tools/dq_focused_test.sh',
                                      '/datum/unit_test/a', '/datum/unit_test/b'])
        self.assertNotIn('dm-test', focused)

    def test_missing_native_pins_conflicting_modes_and_cleanup_fail_closed(self):
        args = self.args('--tier', 'all', '--batch-size', '32'); args.backend = 'native'
        with self.assertRaises(ValueError): runner.validate(args)
        with self.assertRaises(ValueError): runner.validate(self.args('--tier', 'all', '--batch-size', '32', '--focus', '/datum/unit_test/a'))
        self.assertEqual(runner.finalize_code(0, {'reaped': False}), 70)
        self.assertEqual(runner.finalize_code(124, {'reaped': False}), 124)
        self.assertEqual(runner.finalize_code(0, {'reaped': True}), 0)

    def test_captured_focused_output_is_explicit_bounded_and_excludes_suite_modes(self):
        flags = ['--focus', '/datum/unit_test/a', '--seconds', '300',
                 '--focused-compiled-output', 'E:/dq-cache/capture.json',
                 '--focused-compiled-output-sha256', 'd' * 64]
        args = self.args(*flags)
        self.assertFalse(runner.validate(args))
        command = runner.command(args, False)
        self.assertIn('--focused-compiled-output=' + str(args.focused_compiled_output), command)
        self.assertIn('--focused-compiled-output-sha256=' + 'd' * 64, command)
        for change in [{'focused_compiled_output_sha256': None}, {'seconds': 301},
                       {'tier': 'normal'}, {'batch_size': 1}, {'resume': Path('E:/resume.json')},
                       {'plan_sha256': 'a' * 64}]:
            invalid = self.args(*flags)
            for key, value in change.items(): setattr(invalid, key, value)
            with self.assertRaises(ValueError): runner.validate(invalid)
        with self.assertRaises(ValueError):
            runner.validate(self.args('--focus', '/datum/unit_test/a', '--seconds', '300',
                '--focused-compiled-output-sha256', 'd' * 64))

    def test_captured_suite_issues_new_inventory_without_old_prefix_or_plan(self):
        flags = ['--tier', 'all', '--batch-size', '32', '--suite-compiled-output',
                 'E:/dq-cache/capture.json', '--suite-compiled-output-sha256', 'd' * 64]
        args = self.args(*flags)
        self.assertTrue(runner.validate(args))
        self.assertEqual(args.seconds, 300)
        self.assertIn('--suite-compiled-output=' + str(args.suite_compiled_output), runner.command(args, True))
        for change in [{'suite_compiled_output_sha256': None}, {'focus': ['/datum/unit_test/a']},
                       {'resume': Path('E:/old.json')}, {'plan_sha256': 'a' * 64}]:
            invalid = self.args(*flags)
            for key, value in change.items(): setattr(invalid, key, value)
            with self.assertRaises(ValueError): runner.validate(invalid)
        normal = self.args('--tier', 'normal', '--batch-size', '32')
        runner.validate(normal)
        self.assertEqual(normal.seconds, 1800)

    def test_captured_descriptor_pin_detects_modified_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            capture = Path(directory) / 'capture.json'
            capture.write_text('{"pair":"original"}', encoding='utf8')
            digest = runner.hash_file(capture)
            self.assertEqual(runner.pin(capture, digest)['sha256'], digest)
            capture.write_text('{"pair":"changed"}', encoding='utf8')
            with self.assertRaisesRegex(ValueError, 'bytes differ'):
                runner.pin(capture, digest)

    def test_actual_fallback_never_counts_as_native(self):
        args = self.args('--tier', 'all', '--batch-size', '32')
        with self.assertRaises(ValueError): runner.admitted_compile({'compilation': {
            'actualBackend': 'byond', 'requestedBackend': 'native', 'fallback': 'internal_error_70',
            'compiler': {'sha256': args.byond_sha256}}}, args)


if __name__ == '__main__': unittest.main()
