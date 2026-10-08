"""Independent CPU audit counters cannot replace acceptance measurements."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "dmb_bench", Path(__file__).resolve().parents[1] / "bench" / "dmb-bench.py")
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)


class CpuQuality(unittest.TestCase):
    def row(self):
        return dict(
            critical_path_cpu_s=1.0, total_cpu_s=1.0, covered_thread_cpu_s=1.0,
            cpu_crosscheck_ratio=1.0, critical_path_stages=["build"],
            calibration=dict(method="QueryThreadCycleTime", cycles_per_cpu_second=3e9,
                             calibration_cpu_s=0.5, calibration_wall_s=0.6),
            stages=[dict(name="build", calls=1, cpu_s=1.0, max_thread_cpu_s=1.0,
                         exclusive_cpu_s=1.0, wall_s=2.0, allocations=1,
                         allocated_bytes=8, peak_live_bytes=8)])

    def test_coarse_agreement_does_not_repair_cycle_disagreement(self):
        row = self.row()
        self.assertEqual(bench.cpu_quality(row), [])
        row.update(covered_thread_cpu_s=1.2, cpu_crosscheck_ratio=1.2,
                   coarse_covered_thread_cpu_s=1.0, coarse_cpu_crosscheck_ratio=1.0)
        row["stages"][0].update(cpu_s=1.2, exclusive_cpu_s=1.2)
        self.assertIn("covered/process CPU differ by more than 5%", bench.cpu_quality(row))

    def test_coarse_clock_cannot_be_relabelled_as_primary(self):
        row = self.row()
        row["calibration"]["method"] = "GetThreadTimes"
        self.assertIn("unknown/missing thread CPU clock calibration", bench.cpu_quality(row))

    def test_long_wall_calibration_without_enough_cpu_is_rejected(self):
        row = self.row()
        row["calibration"].update(calibration_cpu_s=0.015625, calibration_wall_s=2.0)
        self.assertIn("Windows calibration has less than 500 ms thread CPU", bench.cpu_quality(row))

    def test_per_thread_evidence_replaces_only_global_calibration(self):
        row = self.row()
        row["calibration"].update(cycles_per_cpu_second=None, calibration_cpu_s=None,
                                  calibration_wall_s=0.0)
        thread = dict(thread="worker", status="valid_observed_envelope",
                      cycles_per_cpu_second=3e9, observed_cpu_s=1.2,
                      checked_subintervals=2, envelope_relative_quantization_uncertainty=0.03,
                      max_relative_rate_deviation=0.02, max_relative_quantization_uncertainty=0.1)
        row.update(thread_calibrations=[thread], cpu_conversion_complete=True)
        self.assertEqual(bench.cpu_quality(row), [])
        thread["max_relative_rate_deviation"] = 0.3
        self.assertIn("per-thread rate is unstable despite valid status", bench.cpu_quality(row))
        thread["max_relative_rate_deviation"] = 0.02
        thread.update(status="insufficient_stability_windows", checked_subintervals=1)
        row["cpu_conversion_complete"] = False
        self.assertIn("per-thread CPU conversion is incomplete", bench.cpu_quality(row))
        self.assertIn("per-thread calibration lacks two stability windows", bench.cpu_quality(row))

    def test_short_linux_thread_does_not_need_cycle_calibration(self):
        row = self.row()
        row["calibration"].update(method="CLOCK_THREAD_CPUTIME_ID", calibration_wall_s=0.0)
        row.update(thread_calibrations=[dict(thread="worker", status="native_nanoseconds",
                                            observed_cpu_s=0.001)], cpu_conversion_complete=True)
        self.assertEqual(bench.cpu_quality(row), [])


if __name__ == "__main__":
    unittest.main()
