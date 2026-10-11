import importlib.util
from pathlib import Path
import unittest
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("protected_entry", HERE / "run.py")
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)


class CorpusTests(unittest.TestCase):
    def test_same_bounded_driver_and_exact_source_roster(self):
        helper = contract.driver()
        self.assertEqual(helper.HERE, HERE)
        self.assertEqual(helper.ORIGINAL_CASES, contract.CASES)
        self.assertEqual(helper.CASES, contract.CASES)
        for name in contract.CASES:
            self.assertEqual((HERE / (name + ".dme")).read_text(),
                             '#include "' + name + '.dm"\n')
            self.assertTrue((HERE / (name + ".dm")).read_text().startswith('/proc/probe('))

    def test_entry_and_control_topology_remain_distinct(self):
        entering = (HERE / "goto_into_try.dm").read_text()
        control = (HERE / "goto_within_try.dm").read_text()
        self.assertLess(entering.index("goto inside"), entering.index("try"))
        self.assertLess(control.index("try"), control.index("goto inside"))
        self.assertIn("for(var/item in items)", (HERE / "goto_into_iterator.dm").read_text())
        self.assertEqual((HERE / "nested_catch_return.dm").read_text().count("catch(var/"), 2)


if __name__ == "__main__":
    unittest.main()
