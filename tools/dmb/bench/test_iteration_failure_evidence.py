"""Synthetic interruption evidence; never launches a compiler or daemon."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).parent))
spec = importlib.util.spec_from_file_location("iteration_failure_subject", Path(__file__).with_name("native-iteration.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

class FailureEvidenceTests(unittest.TestCase):
    def test_memory_interruption_preserves_child_and_log_identity(self):
        child = Mock(pid=123, returncode=75)
        memory = Mock()
        memory.check.side_effect = [None, RuntimeError("owned memory exceeded")]
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "request"
            with patch.object(runner, "_owned_memory", memory), patch.object(runner.subprocess, "Popen", return_value=child), patch.object(runner, "terminate_owned", return_value={"reaped": True}), patch.object(runner.subprocess, "CREATE_NO_WINDOW", 0, create=True):
                with self.assertRaisesRegex(RuntimeError, "owned memory exceeded"):
                    runner.run_child(Path("compiler.exe"), ["compile", "project.dme"], directory, runner.time.monotonic() + 30)
            evidence = json.loads((directory / "child.json").read_text())
            self.assertEqual(evidence["status"], "interrupted")
            self.assertEqual(evidence["pid"], 123)
            self.assertEqual(evidence["arguments"], ["compile", "project.dme"])
            self.assertEqual(evidence["exit"], 75)
            self.assertFalse(evidence["timing_admitted"])
            self.assertFalse(evidence["admitted_output"])
            self.assertGreaterEqual(evidence["wall_s"], 0)
            self.assertTrue(Path(evidence["stderr"]).exists())
            memory.unregister.assert_called_once_with(child)
