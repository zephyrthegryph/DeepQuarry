"""Small endpoint-proof admission fixtures; no compiler runs."""
import copy
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
spec = importlib.util.spec_from_file_location("domain_adoption", Path(__file__).with_name("domain_adoption.py"))
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)

class AdoptionTests(unittest.TestCase):
    def fixture(self):
        stage = {"max_thread_cpu_s": 1.0, "cpu_s": 2.0,
                 "max_thread_cpu_bounds_s": {"upper": 1.25}, "cpu_bounds_s": {"upper": 2.5}}
        proof = {"critical_point_s": 2.0, "original_upper_s": 2.5,
                 "all_thread_union_upper_s": 3.0, "upper_s": 2.5, "proof": h.COMPLETE,
                 "total_point_s": 4.0, "original_total_upper_s": 5.0,
                 "total_union_upper_s": 3.0, "total_upper_s": 3.0, "total_proof": h.COMPLETE,
                 "selected_threads": 2, "selected_intervals": 4}
        mapping = {"domain": ["a", "exclusive:b"]}
        row = {"cpu_bounds_method": "paired_thread_cpu_quantization",
               "domain_cpu_selectors": copy.deepcopy(mapping), "domain_cpu_bounds": {"domain": proof},
               "stages": {"a": stage, "exclusive:b": copy.deepcopy(stage)}}
        return row, mapping
    def evaluate(self, row, mapping):
        return h.evaluate(row, mapping, lambda value: value["stages"])
    def test_complete_total_sharpens_without_changing_critical_or_original_points(self):
        row, mapping = self.fixture()
        before = copy.deepcopy(row)
        costs, notes, errors = self.evaluate(row, mapping)
        self.assertEqual(errors, [])
        self.assertEqual(costs["domain"], (2.5, 3.0))
        self.assertEqual(notes["domain"]["original_total_upper_s"], 5.0)
        self.assertEqual(row, before)
    def test_historical_and_incomplete_proofs_keep_original_bounds(self):
        row, mapping = self.fixture()
        row.pop("domain_cpu_bounds"); row.pop("domain_cpu_selectors")
        self.assertEqual(self.evaluate(row, mapping)[0]["domain"], (2.5, 5.0))
        row, mapping = self.fixture()
        proof = row["domain_cpu_bounds"]["domain"]
        proof.update(total_proof="missing_temporal_proof", total_union_upper_s=None, total_upper_s=5.0)
        self.assertEqual(self.evaluate(row, mapping)[0]["domain"], (2.5, 5.0))
        self.assertEqual(self.evaluate(row, mapping)[2], [])
    def test_wrong_map_original_and_malformed_complete_claims_are_rejected(self):
        for field, value in (("original_total_upper_s", 4.0), ("total_point_s", 3.0),
                             ("total_union_upper_s", float("nan")), ("total_union_upper_s", -1),
                             ("total_upper_s", 6.0), ("selected_threads", 0),
                             ("selected_intervals", 1), ("total_upper_s", 2.0)):
            row, mapping = self.fixture();row["domain_cpu_bounds"]["domain"][field] = value
            self.assertTrue(self.evaluate(row, mapping)[2], (field, value))
        for names in (["exclusive:b", "a"], ["a", "b"]):
            row, mapping = self.fixture();row["domain_cpu_selectors"]["domain"] = names
            self.assertTrue(self.evaluate(row, mapping)[2])
    def test_partial_new_schema_rejected_but_old_critical_schema_falls_back(self):
        row, mapping = self.fixture()
        proof = row["domain_cpu_bounds"]["domain"]
        proof.pop("original_total_upper_s")
        self.assertTrue(self.evaluate(row, mapping)[2])
        for key in list(proof):
            if key.startswith("total_") or key.startswith("selected_"):
                proof.pop(key)
        self.assertEqual(self.evaluate(row, mapping)[2], [])
        self.assertEqual(self.evaluate(row, mapping)[0]["domain"], (2.5, 5.0))

    def test_unproved_sharpening_is_rejected(self):
        row, mapping = self.fixture()
        row["domain_cpu_bounds"]["domain"]["total_proof"] = "overlapping_selector_intervals"
        self.assertTrue(self.evaluate(row, mapping)[2])

    def test_gate_median_uses_proved_uppers_and_historical_fallback(self):
        spec = importlib.util.spec_from_file_location("gate_test", Path(__file__).with_name("dmb-bench.py"))
        gate = importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
        rows = []
        for cap in (2.8, 3.0, 5.0):
            row, mapping = self.fixture()
            row.update(status="verified", measurement_revision=6, binary_mode="acceptance", allocation_counting=False,
                       critical_path_stages=["a", "exclusive:b"])
            a = {"name": "a", **row["stages"]["a"]}
            b = {"name": "b", **row["stages"]["exclusive:b"]}
            b.update(max_thread_exclusive_cpu_s=b["max_thread_cpu_s"], exclusive_cpu_s=b["cpu_s"],
                     max_thread_exclusive_cpu_bounds_s=b["max_thread_cpu_bounds_s"],
                     exclusive_cpu_bounds_s=b["cpu_bounds_s"])
            row["stages"] = [a, b]
            proof = row["domain_cpu_bounds"]["domain"]
            proof.update(total_union_upper_s=cap, total_upper_s=cap,
                         all_thread_union_upper_s=cap, upper_s=min(2.5, cap))
            rows.append(row)
        summary = {"critical_path_cpu_budget_upper_s": 2.5, "total_cpu_s": 4.0, "peak_private_bytes": 1}
        with patch.object(gate, "cpu_quality", return_value=[]), patch.object(gate, "medians", return_value=summary), \
             patch.object(gate, "STAGE_BUDGETS", {"domain": (2.6, 3.1)}):
            self.assertEqual(gate.gate("fixture", rows, [], mapping), ("passed", []))
            for row in rows:
                row.pop("domain_cpu_bounds");row.pop("domain_cpu_selectors")
            self.assertEqual(gate.gate("fixture", rows, [], mapping),
                             ("failed", ["domain exceeds cold CPU stage budget"]))

if __name__ == "__main__":
    unittest.main()
