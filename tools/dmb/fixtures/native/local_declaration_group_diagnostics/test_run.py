import importlib.util
from pathlib import Path
import unittest
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("local_group", HERE / "run.py")
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)

class CorpusTests(unittest.TestCase):
    def test_explicit_corpus_and_existing_launcher(self):
        driver = contract.driver()
        self.assertEqual(driver.HERE, HERE)
        self.assertEqual(driver.CASES, driver.ORIGINAL_CASES)
        self.assertEqual(len(driver.CASES), 9)
        for name in driver.CASES:
            self.assertEqual((HERE / (name + ".dme")).read_text(),
                             '#include "' + name + '.dm"\n')
            self.assertIn("/proc/probe()", (HERE / (name + ".dm")).read_text())

if __name__ == "__main__":
    unittest.main()
