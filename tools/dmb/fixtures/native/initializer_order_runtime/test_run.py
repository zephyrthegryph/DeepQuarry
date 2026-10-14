import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("startup_order_run", Path(__file__).with_name("run.py"))
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

class StartupOrderTests(unittest.TestCase):
    def test_authentic_source_and_sequence_are_admitted(self):
        helper.validate_fixture_sources()
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "probe.log"
            file.write_text("\n".join(helper.EXPECTED), encoding="utf-8")
            self.assertEqual(helper.observations(file)["markers"], helper.EXPECTED)

    def test_equal_but_wrong_backend_sequence_cannot_pass(self):
        wrong = list(helper.EXPECTED)
        wrong[0], wrong[1] = wrong[1], wrong[0]
        with tempfile.TemporaryDirectory() as directory:
            for backend in ("native", "byond"):
                file = Path(directory) / (backend + ".log")
                file.write_text("\n".join(wrong), encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "independent pinned BYOND"):
                    helper.observations(file)

if __name__ == "__main__":
    unittest.main()
