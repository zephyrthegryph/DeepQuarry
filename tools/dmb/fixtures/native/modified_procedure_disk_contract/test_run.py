import importlib.util
from pathlib import Path
import unittest
spec = importlib.util.spec_from_file_location("modified_disk_contract", Path(__file__).with_name("run.py"))
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
class ContractPolicy(unittest.TestCase):
    def test_revisions_keep_target_body_for_replay_then_change_nested_value_and_type(self):
        text = Path(__file__).with_name("probe.dm").read_text()
        steps = r.revisions(text)
        self.assertEqual([row[0] for row in steps], ["cold", "unrelated_body", "shifted_origins", "nested_value", "removed_nested_type"])
        self.assertIn("amount=7", steps[1][1])
        self.assertTrue(steps[2][1].startswith("\n\n"))
        self.assertIn("amount=9", steps[3][1])
        self.assertNotIn("/obj/inner\n", steps[4][1])
        self.assertFalse(steps[4][3])
    def test_exact_procedure_evidence_cannot_be_replaced_by_other_hit_counts(self):
        stats = {"memo": {"disk_hits": 2, "resident_hits": 0}, "session_hit": False,
                 "explanations": [{"path": "/proc/unrelated", "occurrence": 0, "outcome": "DiskHit"}]}
        with self.assertRaises(ValueError): r.disk_evidence(stats)
        stats["explanations"].append({"path": "/proc/modified_value", "occurrence": 0, "outcome": "Recomputed"})
        self.assertEqual(r.disk_evidence(stats)["modified_procedure"]["outcome"], "Recomputed")
        stats["memo"]["resident_hits"] = 1
        with self.assertRaises(ValueError): r.disk_evidence(stats)
if __name__ == "__main__": unittest.main()
