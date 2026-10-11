"""Small policy tests; never launches a compiler."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("include_return_probe", Path(__file__).with_name("run.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

class DiagnosticEvidenceTests(unittest.TestCase):
    def test_dm_and_dme_windows_paths_preserve_order_and_coordinates(self):
        text = "E:\\owned\\child.dm:7:error: expected expression\nE:\\owned\\probe.dme:3:warning: ignored\nnoise\n"
        rows = probe.diagnostics(text)
        self.assertEqual([(r["line"], r["severity"]) for r in rows], [(7, "error"), (3, "warning")])
        self.assertEqual(rows[0]["file"], "E:\\owned\\child.dm")
        self.assertEqual(rows[1]["file"], "E:\\owned\\probe.dme")

    def test_normalization_returns_independent_rows_and_keeps_raw_evidence(self):
        rows = probe.diagnostics("E:\\owned\\child.dm:7:error: expected expression")
        normalized = probe.relative_diagnostics(rows, "E:/owned")
        self.assertEqual(normalized[0]["file"], "child.dm")
        self.assertEqual(rows[0]["file"], "E:\\owned\\child.dm")
        normalized[0]["message"] = "changed"
        self.assertEqual(rows[0]["message"], "expected expression")
        self.assertEqual(probe.relative_diagnostics(rows, "E:/other")[0]["file"], "E:/owned/child.dm")

if __name__ == "__main__":
    unittest.main()
