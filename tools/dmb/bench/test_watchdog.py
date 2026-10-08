import subprocess
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import watchdog


class WatchdogTests(unittest.TestCase):
    def process(self):
        process = Mock(pid=123, returncode=None)
        process.poll.return_value = None
        process.wait.return_value = -1
        return process

    def test_taskkill_timeout_still_kills_owned_handle_and_reaps(self):
        process = self.process()
        with patch.object(watchdog.os, "name", "nt"), \
                patch.object(watchdog.subprocess, "CREATE_NO_WINDOW", 0, create=True), \
                patch.object(watchdog.subprocess, "run", side_effect=subprocess.TimeoutExpired("taskkill", 10)):
            receipt = watchdog.terminate_owned(process)
        process.kill.assert_called_once_with()
        process.wait.assert_called_once_with(timeout=5)
        self.assertTrue(receipt["reaped"])
        self.assertIsNotNone(receipt["tree_error"])

    def test_unreapable_owned_process_retains_bounded_error_receipt(self):
        process = self.process()
        process.wait.side_effect = subprocess.TimeoutExpired("owned", 10)
        with patch.object(watchdog.os, "name", "nt"), \
                patch.object(watchdog.subprocess, "CREATE_NO_WINDOW", 0, create=True), \
                patch.object(watchdog.subprocess, "run", side_effect=OSError("tree failure")):
            receipt = watchdog.terminate_owned(process)
        process.kill.assert_called_once_with()
        self.assertFalse(receipt["reaped"])
        self.assertIsNotNone(receipt["wait_error"])
        self.assertIsNone(receipt["returncode"])

    def test_dynamic_benchmark_import_uses_sibling_watchdog_on_timeout(self):
        # The external harness imports by file path, without adding bench to
        # sys.path. A forbidden ordinary import catches accidental reliance on it.
        spec = importlib.util.spec_from_file_location(
            "dynamic_benchmark_for_test", Path(__file__).with_name("dmb-bench.py"))
        benchmark = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(benchmark)
        process = self.process()
        process.wait.side_effect = [subprocess.TimeoutExpired("owned", 1), -1]
        with tempfile.TemporaryDirectory() as directory:
            prefix = Path(directory) / "measurement"
            with patch.dict("sys.modules", {"watchdog": None}), \
                    patch.object(benchmark.os, "name", "nt"), \
                    patch.object(benchmark.subprocess, "CREATE_NO_WINDOW", 0, create=True), \
                    patch.object(benchmark.subprocess, "Popen", return_value=process), \
                    patch.object(benchmark.subprocess, "run", side_effect=subprocess.TimeoutExpired("taskkill", 10)):
                _, _, timed_out = benchmark.run(["owned"], directory, prefix, 1, {})
            receipt = json.loads(prefix.with_suffix(".watchdog.json").read_text())
        process.kill.assert_called_once_with()
        self.assertTrue(timed_out)
        self.assertTrue(receipt["reaped"])
        self.assertIsNotNone(receipt["tree_error"])
