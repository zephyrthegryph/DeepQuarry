import importlib.util
from pathlib import Path
import unittest
spec=importlib.util.spec_from_file_location("six_contract",Path(__file__).with_name("run.py"))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class Policy(unittest.TestCase):
    def test_isolated_edits(self):
        self.assertNotEqual(m.revision(0,True),m.BASE)
        self.assertIn("/proc/added()",m.revision(1,True))
        for i in range(2,6): self.assertEqual(m.revision(i,True),m.BASE)
        for i in range(6): self.assertEqual(m.revision(i,False),m.BASE)
if __name__=="__main__": unittest.main()
