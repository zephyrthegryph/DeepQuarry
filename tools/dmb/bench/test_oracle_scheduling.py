"""Fresh oracle requests are independent of resident daemon lifetime."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
spec = importlib.util.spec_from_file_location('oracle_subject', Path(__file__).with_name('native-iteration.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
class OracleSchedulingTests(unittest.TestCase):
    def test_fresh_runs_without_daemon_and_keeps_cache_disabled(self):
        endpoint = Mock()
        with tempfile.TemporaryDirectory() as directory, patch.object(runner, 'run_child', return_value={'exit':0,'wall_s':1}) as child:
            root = Path(directory)
            result = runner.compile_one(Path('compiler.exe'), root, Path('world.dme'), 2, [], root/'artifacts', root/'logs', 'fresh', 30, False, endpoint, None, root/'cache')
            endpoint.probe.assert_not_called()
            args = child.call_args.args[1]
            self.assertIn('--no-daemon', args)
            self.assertIn('--no-cache', args)
            self.assertEqual(result['exit'], 0)
    def test_retained_cannot_run_without_owned_daemon(self):
        with patch.object(runner, 'run_child') as child:
            with self.assertRaisesRegex(RuntimeError, 'owned daemon missing'):
                runner.compile_one(Path('compiler.exe'), Path('.'), Path('world.dme'), 2, [], Path('output'), Path('logs'), 'retained', 30, True, Mock(), None, Path('cache'))
            child.assert_not_called()
