import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class SampledCommandOutcome(unittest.TestCase):
    def test_child_failure_and_diagnostics_survive_successful_capture(self):
        with tempfile.TemporaryDirectory() as directory:
            receipt = Path(directory) / "timing.json"
            result = subprocess.run([
                sys.executable, str(Path(__file__).with_name("timed_command.py")),
                str(receipt), sys.executable, "-c",
                "import sys; print('compiler diagnostic',file=sys.stderr); sys.exit(7)",
            ], capture_output=True, timeout=10)
            data = json.loads(receipt.read_text())
            self.assertEqual(result.returncode, 7)
            self.assertEqual(data["exit_code"], 7)
            self.assertEqual(data["status"], "completed")
            self.assertGreater(data["seconds"], 0)
            self.assertLessEqual(data["started_unix"], data["ended_unix"])
            self.assertEqual(Path(data["stderr"]).read_text().strip(), "compiler diagnostic")
            self.assertEqual(result.stderr, b"")


if __name__ == "__main__":
    unittest.main()
