import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("retirement_run", Path(__file__).with_name("run.py"))
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class RetirementHelperTests(unittest.TestCase):
    def test_runtime_observations_do_not_replace_executable_pin_roster(self):
        receipt = {}
        for name in ("native", "template", "dm", "dd"):
            helper.record_pin(receipt, name, Path("E:/pinned") / name, name + "-sha")
        expected = {name: dict(value) for name, value in receipt["pinned_inputs"].items()}
        receipt["native"] = {"markers": ["DQ_RETIRE finished"], "runtimes": []}
        receipt["byond"] = {"markers": ["DQ_RETIRE finished"], "runtimes": []}
        self.assertEqual(receipt["pinned_inputs"], expected)
        self.assertEqual(set(receipt["pinned_inputs"]), {"native", "template", "dm", "dd"})

    def test_error_mode_restored_after_failed_child(self):
        calls = []
        def mode(value):
            calls.append(value)
            return 8
        with self.assertRaisesRegex(RuntimeError, "owned child"):
            with helper.hidden_error_mode(mode):
                raise RuntimeError("owned child")
        self.assertEqual(calls, [3, 8])

    def test_markers_and_standalone_runtime_counts_are_compared(self):
        with tempfile.TemporaryDirectory(dir="E:/dq-cache") as directory:
            log = Path(directory) / "probe.log"
            log.write_text("DQ_RETIRE begin outer_bounds\nruntime error: list index out of bounds\nruntime error: list index out of bounds\nDQ_RETIRE finished\n")
            result = helper.observations(log)
            self.assertEqual(result["runtimes"][0]["count"], 2)
            self.assertEqual(result["markers"], ["DQ_RETIRE begin outer_bounds", "DQ_RETIRE finished"])
            log.write_text("DQ_RETIRE begin outer_bounds\n")
            with self.assertRaisesRegex(ValueError, "did not complete"):
                helper.observations(log)


if __name__ == "__main__":
    unittest.main()
