"""Fake ownership ordering only; never launches Cargo or a Windows Job."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest

sys.path.insert(0, str(Path(__file__).parent))
spec = importlib.util.spec_from_file_location('frozen_build', Path(__file__).with_name('frozen-build.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class OwnedBuildTests(unittest.TestCase):
    def fixture(self, timeout=False, reaped=True, resume_error=False):
        events = []
        class Child:
            calls = 0
            def wait(self, timeout):
                events.append(('wait', timeout)); self.calls += 1
                if self.calls == 1 and timeout_case:
                    raise subprocess.TimeoutExpired('fake cargo', timeout)
                return 0
        timeout_case = timeout
        class Job:
            def __init__(self, limit): events.append(('limit', limit))
            def add(self, child): events.append('assign')
            def resume(self, child):
                events.append('resume')
                if resume_error: raise RuntimeError('fake resume rejection')
            def close(self):
                events.append('close')
                return {'reaped': reaped, 'memory': {'peak_job_commit_bytes': 123,
                    'scope': 'Windows owned-job commit accounting; not private-byte or working-set peak'}}
        def popen(*args, **kwargs):
            events.append(('spawn', kwargs['creationflags']))
            return Child()
        result = module.execute_owned_build(['fake'], Path('E:/owned'), {}, None,
            300, 4_000_000_000, Job, popen)
        return events, result

    def test_suspended_assignment_precedes_execution_and_success_reaps(self):
        events, (code, cleanup, failure) = self.fixture()
        self.assertEqual(events[:4], [('limit', 4_000_000_000), ('spawn', 0x08000004), 'assign', 'resume'])
        self.assertEqual(events[-2:], ['close', ('wait', 5)])
        self.assertEqual(code, 0); self.assertTrue(cleanup['reaped']); self.assertIsNone(failure)
        self.assertEqual(cleanup['memory']['peak_job_commit_bytes'], 123)

    def test_timeout_and_failed_resume_always_close_job(self):
        events, (code, cleanup, failure) = self.fixture(timeout=True)
        self.assertEqual(code, 124); self.assertIn('close', events); self.assertTrue(cleanup['reaped'])
        self.assertIn('watchdog', failure)
        events, (code, cleanup, failure) = self.fixture(resume_error=True)
        self.assertEqual(code, 70); self.assertIn('close', events); self.assertIn('resume rejection', failure)

    def test_no_successful_binary_pin_when_reap_fails(self):
        _, (code, cleanup, failure) = self.fixture(reaped=False)
        self.assertEqual(code, 70); self.assertFalse(cleanup['reaped']); self.assertIn('not reaped', failure)

if __name__ == '__main__':
    unittest.main()
