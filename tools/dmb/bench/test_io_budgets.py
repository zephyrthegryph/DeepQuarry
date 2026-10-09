"""Explicit byte budgets and partial waiting observations are distinct."""
import importlib.util
from pathlib import Path
import unittest
spec = importlib.util.spec_from_file_location("io_budget_bench", Path(__file__).with_name("dmb-bench.py"))
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
class IoBudgets(unittest.TestCase):
    def rows(self, read=326_324_811, written=569_631_392):
        return [dict(status="verified", read_bytes=read, write_bytes=written,
                     stages=[dict(name="input", io_blocked_s=None, io_call_elapsed_s=None)]) for _ in range(3)]
    def test_numeric_budget_passes_with_unknown_blocked_time(self):
        rows=self.rows()
        self.assertEqual(h.io_gate("cold", rows), ("passed", []))
        self.assertEqual(h.io_observations(rows)["blocked_io_observation"], "unknown")
        self.assertEqual(h.io_observations(rows)["blocked_io_budget"], "not_specified_in_design")
    def test_bytes_over_budget_fail_despite_complete_wait_observations(self):
        rows=self.rows(read=400_000_001)
        for row in rows:
            row["io_coverage"]="complete"
            row["stages"][0]["io_blocked_s"]=0.01
        self.assertEqual(h.io_gate("cold", rows)[0], "failed")
        self.assertEqual(h.io_observations(rows)["blocked_io_observation"], "complete")
    def test_partial_annotated_upper_never_claims_full_coverage(self):
        rows=self.rows()
        rows[0]["annotated_io_wait"]={"coverage":"partial_annotated_calls_only", "non_cpu_wait_upper_s":0.25}
        self.assertEqual(h.io_observations(rows)["blocked_io_observation"], "partial")
        self.assertEqual(h.io_gate("cold", rows)[0], "passed")
    def test_missing_bytes_and_missing_runs_remain_unevaluable(self):
        rows=self.rows(read=None)
        self.assertEqual(h.io_gate("cold", rows)[0], "not_evaluable")
        self.assertEqual(h.io_gate("cold", rows[:2])[0], "incomplete")
    def test_profile_measurement_preserves_additive_wait_diagnostic(self):
        spec = importlib.util.spec_from_file_location("io_budget_protocol", Path(__file__).with_name("protocol.py"))
        protocol = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(protocol)
        diagnostic = {"coverage": "partial_annotated_calls_only", "non_cpu_wait_upper_s": 0.25}
        report = {"schema": 2, "annotated_io_wait": diagnostic, "wall_s": 1.0}
        row = protocol.profile_measurement(report, 1.5)
        self.assertEqual(row["annotated_io_wait"], diagnostic)
        self.assertEqual(h.io_observations([row])["blocked_io_observation"], "partial")
    def test_unknown_scenario_does_not_receive_a_fabricated_budget(self):
        self.assertEqual(h.io_gate("cached_population", self.rows())[0], "diagnostic_only")
if __name__ == "__main__": unittest.main()
