import unittest
from session_acceptance import required_edit_coverage, bounded_policy, edit_sessions, session_edit_coverage, daemon_reserve

class CoverageTests(unittest.TestCase):
    def test_each_required_edit_is_explicit(self):
        edits = [{"kind": "body"}] + [
            {"kind": "structural", "structural_kind": kind}
            for kind in ("newvar", "newproc", "default")]
        self.assertEqual(required_edit_coverage(edits)["required"], ["body", "default", "newproc", "newvar"])
        for index in range(len(edits)):
            with self.assertRaises(ValueError):
                required_edit_coverage(edits[:index] + edits[index + 1:])
    def test_generic_structural_label_cannot_claim_all_cases(self):
        with self.assertRaises(ValueError):
            required_edit_coverage([{"kind": "body"}, {"kind": "structural"}])


class BoundsTests(unittest.TestCase):
    def test_default_worker_and_memory_caps(self):
        self.assertEqual(bounded_policy(2, 2, 4096, 4_000_000_000), 4096 * 1024 * 1024)
        for total, workers, mib in [(0, 1, 4096), (3, 1, 4096), (8, 2, 4096), (9, 2, 4096), (2, 8, 4096), (2, 2, 0), (2, 2, 32769)]:
            with self.assertRaises(ValueError): bounded_policy(total, workers, mib)
        with self.assertRaises(ValueError): bounded_policy(2, 2, 4096, 5_000_000_000)
    def test_explicit_allowance_does_not_change_worker_budget(self):
        self.assertEqual(bounded_policy(2, 2, 8192, 6_000_000_000), 8192 * 1024 * 1024)


class AssignmentTests(unittest.TestCase):
    def test_asymmetric_probe_preserves_four_unchanged_roots(self):
        edits = [{"kind": "body", "sessions": [0]},
                 {"kind": "structural", "structural_kind": "newproc", "sessions": [1]}]
        coverage = session_edit_coverage(edits, 6)
        self.assertEqual(coverage["classification"], "six-session-isolation-probe")
        self.assertEqual(coverage["per_session"], [["body"], ["newproc"], [], [], [], []])
        self.assertEqual(edit_sessions({"kind": "body"}, 6), tuple(range(6)))

    def test_six_label_cannot_admit_a_different_session_count(self):
        edits = [{"kind": "body"}] + [
            {"kind": "structural", "structural_kind": kind}
            for kind in ("newvar", "newproc", "default")]
        for count in (1, 5, 7, True, 6.0):
            with self.assertRaises(ValueError):
                session_edit_coverage(edits, count)

    def test_full_coverage_requires_every_root(self):
        edits = [{"kind": "body", "sessions": list(range(6))}] + [
            {"kind": "structural", "structural_kind": kind, "sessions": list(range(6))}
            for kind in ("newvar", "newproc", "default")]
        self.assertEqual(session_edit_coverage(edits, 6)["classification"], "six-worktree-byte-acceptance")

    def test_invalid_assignments_and_false_isolation_decline(self):
        for targets in ([], [0, 0], [-1], [6], [True], "0"):
            with self.assertRaises(ValueError): edit_sessions({"sessions": targets}, 6)
        with self.assertRaises(ValueError):
            session_edit_coverage([{"kind": "body", "sessions": [0]},
                {"kind": "structural", "structural_kind": "newvar", "sessions": [0]}], 6)


class ReserveTests(unittest.TestCase):
    def test_reserve_uses_smaller_aggregate_gate(self):
        self.assertEqual(daemon_reserve(4096 * 1024 ** 2, 4_000_000_000), 2_000_000_000)
        self.assertEqual(daemon_reserve(1024 * 1024 ** 2, 2_000_000_000), 512 * 1024 ** 2)
        self.assertEqual(daemon_reserve(512 * 1024 ** 2, 512 * 1024 ** 2), 256 * 1024 ** 2)
        with self.assertRaises(ValueError): daemon_reserve(512 * 1024 ** 2, 1)
