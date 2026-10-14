import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("registration", Path(__file__).with_name("run_registration.py"))
registration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(registration)


class RegistrationContract(unittest.TestCase):
    def test_sources_match_independent_captures(self):
        for case in registration.CAPTURE["cases"]:
            registration.validate_sources(case)

    def test_equal_wrong_sequences_are_rejected(self):
        expected = registration.CAPTURE["cases"]["custom_forward"]["expected"]
        wrong = registration.CAPTURE["cases"]["custom_defined"]["expected"]
        self.assertNotEqual(expected, wrong)
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "probe.log"
            log.write_text("\n".join(expected), encoding="utf-8")
            self.assertEqual(registration.read_observations(log, expected)["markers"], expected)
            log.write_text("\n".join(wrong), encoding="utf-8")
            for _backend in ("native", "byond"):
                with self.assertRaises(ValueError):
                    registration.read_observations(log, expected)


if __name__ == "__main__":
    unittest.main()
