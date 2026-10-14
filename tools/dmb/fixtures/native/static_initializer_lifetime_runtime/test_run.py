import importlib.util
from pathlib import Path
import tempfile
import unittest
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("lifetime_contract", HERE / "run.py")
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)
class LifetimeTests(unittest.TestCase):
    def read(self, markers):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "probe.log"
            file.write_text("\n".join(markers), encoding="utf-8")
            return contract.observations(file)
    def test_independent_contract(self):
        self.assertEqual(self.read(contract.EXPECTED)["runtimes"], [])
        for index, wrong in [(0, 2), (2, 14), (3, 7), (4, 1), (6, 11)]:
            markers = list(contract.EXPECTED)
            markers[index] = f"DQ_LIFETIME {contract.LABELS[index]} {wrong}"
            with self.assertRaises(ValueError):
                self.read(markers)
    def test_exact_retained_edits(self):
        spec = importlib.util.spec_from_file_location("lifetime_retained", HERE / "run_retained.py")
        retained = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(retained)
        source = (HERE / "probe.dm").read_text(encoding="utf-8")
        steps = retained.contract.read_steps(HERE / "scenarios.json", retained.LABELS, "DQ_LIFETIME")
        for step in steps:
            source = retained.contract.apply_step(source, step)
            self.assertEqual(step["expected"][0], 1)
            self.assertEqual(step["expected"][4], 2)
        self.assertIn("return 13", source)
        self.assertIn("var/unrelated_default = 31", source)
if __name__ == "__main__":
    unittest.main()
