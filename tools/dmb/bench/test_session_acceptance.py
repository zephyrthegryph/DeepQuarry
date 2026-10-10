import unittest
from session_acceptance import required_edit_coverage, bounded_policy

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
        for total, workers, mib in [(0, 1, 4096), (9, 2, 4096), (2, 8, 4096), (2, 2, 0), (2, 2, 32769)]:
            with self.assertRaises(ValueError): bounded_policy(total, workers, mib)
        with self.assertRaises(ValueError): bounded_policy(2, 2, 4096, 5_000_000_000)
    def test_explicit_allowance_does_not_change_worker_budget(self):
        self.assertEqual(bounded_policy(2, 2, 8192, 6_000_000_000), 8192 * 1024 * 1024)
