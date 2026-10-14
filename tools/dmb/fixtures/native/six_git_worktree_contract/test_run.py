import importlib.util
from pathlib import Path
import unittest
import ast
spec=importlib.util.spec_from_file_location("six_contract",Path(__file__).with_name("run.py"))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class Policy(unittest.TestCase):
    def test_resume_uses_stable_thread_entry_identity(self):
        source=(m.BENCH/"upgrade_owned_job.py").read_text()
        tree=ast.parse(source)
        self.assertEqual(sum(isinstance(row,ast.ClassDef) and row.name=="ThreadEntry" for row in tree.body),1)
        owner=next(row for row in tree.body if isinstance(row,ast.ClassDef) and row.name=="OwnedJob")
        resume=next(row for row in owner.body if isinstance(row,ast.FunctionDef) and row.name=="resume")
        self.assertFalse(any(isinstance(row,ast.ClassDef) for row in ast.walk(resume)))

    def test_isolated_edits(self):
        self.assertNotEqual(m.revision(0,True),m.BASE)
        self.assertIn("/proc/added()",m.revision(1,True))
        for i in range(2,6): self.assertEqual(m.revision(i,True),m.BASE)
        for i in range(6): self.assertEqual(m.revision(i,False),m.BASE)
if __name__=="__main__": unittest.main()
