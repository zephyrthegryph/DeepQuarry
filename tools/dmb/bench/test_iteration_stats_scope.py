"""Compiler profiles must not impersonate unchanged request work."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent))
spec = importlib.util.spec_from_file_location("iteration_stats_subject", Path(__file__).with_name("native-iteration.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class StatsScopeTests(unittest.TestCase):
    def test_unchanged_retains_old_evidence_without_claiming_old_work(self):
        for hit in (True, False):
            with self.subTest(session_hit=hit), tempfile.TemporaryDirectory(dir="E:/dq-cache/dmb-native-v2/integration-gates") as temporary:
                root = Path(temporary)
                (root / ".dmbc").mkdir()
                logs = root / "logs"
                logs.mkdir()
                stats = root / ".dmbc/probe.stats.json"
                stats.write_text(json.dumps({"seconds": 100, "memo": {"recomputed": 48681}}))
                stats.with_name("probe.last-run.json").write_text(json.dumps({"seconds": 1, "session_hit": hit}))
                with patch.object(runner, "run_child", return_value={"exit": 0, "wall_s": 1}):
                    result = runner.compile_one(Path("compiler.exe"), root, Path("probe.dme"), 2, [], root / "outputs", logs, "fresh", runner.time.monotonic() + 30, False, None, None, root / "cache")
                self.assertEqual(result["last_run"]["session_hit"], hit)
                if hit:
                    self.assertNotIn("compiler_stats", result)
                    self.assertNotIn("compiler_stats_evidence", result)
                    self.assertEqual(Path(result["previous_compiler_stats_evidence"]["path"]).read_bytes(), stats.read_bytes())
                    self.assertEqual(result["compiler_stats_scope"], "previous_compilation_excluded_from_unchanged_request")
                else:
                    self.assertEqual(result["compiler_stats"]["memo"]["recomputed"], 48681)
                    self.assertEqual(result["compiler_stats_scope"], "completed_compilation")


if __name__ == "__main__":
    unittest.main()
