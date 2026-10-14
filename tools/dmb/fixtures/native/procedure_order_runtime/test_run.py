import importlib.util
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("procedure_order_test_runner", HERE / "run.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

class ProcedureOrderContract(unittest.TestCase):
    def test_authenticated_fixture_accepts_independent_sequence(self):
        runner.validate_fixture_sources()
        with tempfile.TemporaryDirectory(dir="E:/dq-cache/dmb-native-v2/fixture-tmp") as directory:
            log = Path(directory) / "probe.log"
            log.write_text("\n".join(runner.EXPECTED), encoding="utf-8")
            self.assertEqual(runner.observations(log)["markers"], runner.EXPECTED)

    def test_equal_wrong_order_is_rejected_for_each_backend(self):
        wrong = runner.EXPECTED.copy()
        wrong[0], wrong[1] = wrong[1], wrong[0]
        with tempfile.TemporaryDirectory(dir="E:/dq-cache/dmb-native-v2/fixture-tmp") as directory:
            for backend in ("native", "byond"):
                log = Path(directory) / (backend + ".log")
                log.write_text("\n".join(wrong), encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "differs from pinned BYOND"):
                    runner.observations(log)

if __name__ == "__main__":
    unittest.main()
