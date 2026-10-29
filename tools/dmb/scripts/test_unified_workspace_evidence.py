"""Bounded evidence from the actual-workspace integration coordinator."""
import unittest
from collections import deque
from unified_actual_workspace_raw import Actual, diagnostic_excerpt


class WorkspaceEvidenceTests(unittest.TestCase):
    def test_timeout_preserves_last_stage_and_both_bounded_ends(self):
        text = "first error\n" + "x" * 100000 + "\nnative stage query_prepare.source_abi: started\n"
        row = diagnostic_excerpt(text)
        self.assertTrue(row["truncated"])
        self.assertLessEqual(len(row["text"].encode()), 16384)
        self.assertIn("first error", row["text"])
        self.assertEqual(row["last_progress_line"], "native stage query_prepare.source_abi: started")

    def test_partial_utf8_and_empty_evidence_are_bounded(self):
        self.assertEqual(diagnostic_excerpt(None)["text"], "")
        row = diagnostic_excerpt(bytes([255]) * 20000)
        self.assertTrue(row["truncated"])
        self.assertLessEqual(len(row["text"].encode()), 16384)

    def test_all_pages_share_one_evidence_cap_and_preserve_latest(self):
        capture = Actual.__new__(Actual)
        capture.calls = []
        capture.stderr_evidence_bytes = 0
        capture.stderr_evidence_calls = deque()
        for _ in range(100):
            capture._record_call({"stderr_evidence": diagnostic_excerpt(
                "x" * 100000 + "\nnative stage query_prepare.startup: started\n")})
        self.assertLessEqual(capture.stderr_evidence_bytes, 1024 * 1024)
        self.assertTrue(capture.calls[0]["stderr_evidence_evicted"])
        self.assertEqual(capture.calls[-1]["stderr_evidence"]["last_progress_line"],
                         "native stage query_prepare.startup: started")


if __name__ == "__main__":
    unittest.main()
