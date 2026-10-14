import unittest
from iteration_history import EditHistory


class HistoryTests(unittest.TestCase):
    def test_later_revision_contains_all_prior_edits_and_sessions_are_independent(self):
        history = EditHistory(6)
        first = {"path": "a.dm", "before_sha256": "one", "after_sha256": "two"}
        history.append(0, first)
        baseline = history.snapshot(0)
        first["after_sha256"] = "caller mutation"
        history.append(0, {"path": "b.dm", "after_sha256": "three"})
        self.assertEqual([edit["path"] for edit in history.snapshot(0)], ["a.dm", "b.dm"])
        self.assertEqual(baseline, [{"path": "a.dm", "before_sha256": "one", "after_sha256": "two"}])
        self.assertEqual(history.snapshot(5), [])
        baseline.clear()
        self.assertEqual(len(history.snapshot(0)), 2)

    def test_empty_session_roster_is_rejected(self):
        with self.assertRaises(ValueError):
            EditHistory(0)
