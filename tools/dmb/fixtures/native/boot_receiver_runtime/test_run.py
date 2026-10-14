import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("boot_contract", Path(__file__).with_name("run.py"))
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)


class ContractTests(unittest.TestCase):
    def read(self, lines, encoding="utf-8"):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "probe.log"
            file.write_text("\n".join(lines), encoding=encoding)
            return contract.observations(file)

    def test_exact_contract_and_utf16_logs(self):
        for encoding in ["utf-8", "utf-16"]:
            result = self.read(contract.EXPECTED, encoding)
            self.assertEqual(result["runtimes"], [])
            self.assertEqual(len(result["markers"]), 15)

    def test_equal_but_wrong_null_or_constructor_order_rejected(self):
        for index, replacement in [(0, "DQ_BOOT early_cache_null 1"),
                                   (1, "DQ_BOOT early_cache_typed 1"),
                                   (3, "DQ_BOOT null_not 0"),
                                   (8, "DQ_BOOT callback 18")]:
            lines = list(contract.EXPECTED)
            lines[index] = replacement
            with self.assertRaises(ValueError):
                self.read(lines)

    def test_runtime_missing_duplicate_and_extra_markers_rejected(self):
        for lines in [contract.EXPECTED + ["runtime error: Cannot read .loaded"],
                      contract.EXPECTED[1:],
                      contract.EXPECTED + ["DQ_BOOT finished"],
                      contract.EXPECTED + ["DQ_BOOT early_cache_direct 42"]]:
            with self.assertRaises(ValueError):
                self.read(lines)


if __name__ == "__main__":
    unittest.main()
