import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("damage_contract", Path(__file__).with_name("run.py"))
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)


class ContractTests(unittest.TestCase):
    def read(self, lines):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "probe.log"
            file.write_text("\n".join(lines), encoding="utf-8")
            return contract.observations(file)

    def expected(self):
        return [f"DQ_DAMAGE {label} {band} {band} {band} 1"
                for label, band in contract.EXPECTED] + ["DQ_DAMAGE finished"]

    def test_explicit_contract_admits_all_ten_cases(self):
        result = self.read(self.expected())
        self.assertEqual(result["runtimes"], [])
        self.assertEqual(len(result["markers"]), 11)

    def test_equal_but_wrong_backend_result_is_rejected(self):
        lines = self.expected()
        lines[2] = "DQ_DAMAGE moderate 3 3 2 0"
        with self.assertRaises(ValueError):
            self.read(lines)

    def test_runtime_or_missing_case_is_rejected(self):
        with self.assertRaises(ValueError):
            self.read(self.expected() + ["runtime error: bad index"])
        with self.assertRaises(ValueError):
            self.read(self.expected()[1:])


if __name__ == "__main__":
    unittest.main()
