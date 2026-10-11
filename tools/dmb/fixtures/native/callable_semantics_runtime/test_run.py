import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("callable_contract", Path(__file__).with_name("run.py"))
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
            self.assertEqual(len(result["markers"]), 13)

    def test_equal_but_wrong_values_rejected(self):
        for index, replacement in [(0, "DQ_CALL copy_length 1"),
                                   (2, "DQ_CALL original_value 99"),
                                   (4, "DQ_CALL safe_null 0"),
                                   (8, "DQ_CALL catch_number 41"),
                                   (10, "DQ_CALL explicit_array_methods 7"),
                                   (11, "DQ_CALL implicit_array_methods 13")]:
            lines = list(contract.EXPECTED)
            lines[index] = replacement
            with self.assertRaises(ValueError):
                self.read(lines)

    def test_retained_scenario_declares_each_value_and_exact_edits(self):
        spec = importlib.util.spec_from_file_location("callable_retained_contract", Path(__file__).with_name("run_retained.py"))
        retained = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(retained)
        steps = retained.contract.read_steps(Path(__file__).with_name("scenarios.json"), retained.LABELS, "DQ_CALL")
        source = Path(__file__).with_name("probe.dm").read_text(encoding="utf-8")
        for step in steps:
            source = retained.contract.apply_step(source, step)
            self.assertIn("/var/const/callable_fixture_resource = 'contract-resource.txt'", source)
            self.assertIn("file2text(callable_fixture_resource)", source)
            markers = retained.contract.expected_markers(step["expected"], retained.LABELS, "DQ_CALL")
            self.assertEqual(len(markers), 13)
        self.assertIn("return marker + 5", source)
        self.assertIn("var/added = 7", source)

    def test_runtime_missing_duplicate_and_extra_markers_rejected(self):
        for lines in [contract.EXPECTED + ["runtime error: Cannot read .loaded"],
                      contract.EXPECTED[1:],
                      contract.EXPECTED + ["DQ_CALL finished"],
                      contract.EXPECTED + ["DQ_CALL invented 42"]]:
            with self.assertRaises(ValueError):
                self.read(lines)


if __name__ == "__main__":
    unittest.main()
