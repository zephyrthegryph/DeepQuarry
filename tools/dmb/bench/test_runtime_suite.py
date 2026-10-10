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

    def test_historical_normal_and_focused_commands(self):
        args = self.args('--tier', 'normal', '--batch-size', '32')
        self.assertIn('--normal-batches=32', runner.command(args, runner.validate(args)))
        args = self.args('--focus', '/datum/unit_test/a', '--focus', '/datum/unit_test/b')
        self.assertIn('--focus=/datum/unit_test/a,/datum/unit_test/b', runner.command(args, runner.validate(args)))

    def test_missing_native_pins_conflicting_modes_and_cleanup_fail_closed(self):
        args = self.args('--tier', 'all', '--batch-size', '32'); args.backend = 'native'
        with self.assertRaises(ValueError): runner.validate(args)
        with self.assertRaises(ValueError): runner.validate(self.args('--tier', 'all', '--batch-size', '32', '--focus', '/datum/unit_test/a'))
        self.assertEqual(runner.finalize_code(0, {'reaped': False}), 70)
        self.assertEqual(runner.finalize_code(124, {'reaped': False}), 124)
        self.assertEqual(runner.finalize_code(0, {'reaped': True}), 0)

    def test_actual_fallback_never_counts_as_native(self):
        args = self.args('--tier', 'all', '--batch-size', '32')
        with self.assertRaises(ValueError): runner.admitted_compile({'compilation': {
            'actualBackend': 'byond', 'requestedBackend': 'native', 'fallback': 'internal_error_70',
            'compiler': {'sha256': args.byond_sha256}}}, args)


if __name__ == '__main__': unittest.main()
