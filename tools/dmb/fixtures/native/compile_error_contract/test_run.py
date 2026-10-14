import ast
import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("compile_error_contract", HERE / "run.py")
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)


class ContractTests(unittest.TestCase):
    def test_existing_paired_driver_and_source_roster(self):
        driver = contract.driver()
        self.assertEqual(driver.HERE, HERE)
        self.assertEqual(driver.CASES, contract.CASES)
        self.assertEqual(driver.ORIGINAL_CASES, contract.CASES)
        self.assertEqual(len(set(contract.CASES)), 14)
        self.assertEqual(driver.DEFAULT_OUTPUT_ROOT, Path("E:/dq-cache/dmb-compile-error-contract"))
        for case in contract.CASES:
            source = HERE / (case + ".dm")
            self.assertTrue(source.is_file())
            self.assertLess(source.stat().st_size, 2048)
            self.assertEqual((HERE / (case + ".dme")).read_text(),
                             '#include "' + case + '.dm"\n')
        ast.parse((HERE / "run.py").read_text())

    def test_rejected_internal_or_executor_failure_is_not_source(self):
        driver = contract.driver()
        self.assertEqual(driver.native_exit_class(2), "Source")
        self.assertEqual(driver.native_exit_class(70), "Internal")
        self.assertEqual(driver.native_exit_class(1), "Infrastructure")
        self.assertEqual(driver.native_exit_class(64), "InvalidRequest")
        self.assertEqual(driver.native_exit_class(75), "Cancelled")
        self.assertEqual(driver.native_exit_class(-9), "OtherFailure")
        self.assertEqual(driver.native_exit_class(None), "OtherFailure")
        self.assertEqual(driver.native_exit_class(0), "Accepted")

    def test_multiline_initializer_is_authored_across_three_lines(self):
        source = (HERE / "undefined_initializer_multiline.dm").read_text().splitlines()
        self.assertTrue(source[0].endswith("formerly_missing_initializer("))
        self.assertEqual(source[1:3], ["    1,", "    2)"])


if __name__ == "__main__":
    unittest.main()
