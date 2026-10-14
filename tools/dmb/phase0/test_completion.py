"""Authored focused completion-policy fixtures; not executed by this change."""
import unittest
from finalize_baseline import completion_proven

class Completion(unittest.TestCase):
    def receipt(self):
        return dict(status='complete-results', suite_complete=True,
                    shutdown_complete=True, selection_coverage_exact=True,
                    results_present=True, exit_code=0, stop_reason=None,
                    clean_marker=False)
    def test_failed_tests_without_clean_marker_still_complete(self):
        self.assertTrue(completion_proven(self.receipt()))
    def test_clean_marker_grace_is_not_normal_exit_proof(self):
        receipt=self.receipt();receipt.update(clean_marker=True,stop_reason='clean-marker-shutdown-grace')
        self.assertFalse(completion_proven(receipt))
    def test_missing_any_required_proof_declines(self):
        for field in ('suite_complete','shutdown_complete','selection_coverage_exact','results_present'):
            receipt=self.receipt();receipt[field]=False
            self.assertFalse(completion_proven(receipt),field)
    def test_timeout_declines_and_complete_abnormal_exit_is_retained(self):
        receipt=self.receipt();receipt['stop_reason']='timeout'
        self.assertFalse(completion_proven(receipt))
        receipt=self.receipt();receipt.update(exit_code=-1073741819,status='complete-results-abnormal-exit')
        self.assertTrue(completion_proven(receipt))
    def test_unknown_terminal_exit_is_incomplete(self):
        receipt=self.receipt();receipt['exit_code']=None
        self.assertFalse(completion_proven(receipt))

if __name__=='__main__': unittest.main()
