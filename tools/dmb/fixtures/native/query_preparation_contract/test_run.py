import importlib.util
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("query_prepare_contract", HERE / "run.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class Contract(unittest.TestCase):
    def test_symbol_comes_from_exact_returned_owner_and_spelling(self):
        rows = [{"name":"known", "owner_path":"/", "name_symbol":"abcdef0123456789"}]
        self.assertEqual(m.discovered_symbol(rows, "known"), int("abcdef0123456789",16))
        for bad in ([], rows * 2, [dict(rows[0], owner_path="/datum")], [dict(rows[0],name_symbol="wrong")]):
            with self.assertRaises(ValueError): m.discovered_symbol(bad, "known")
    def test_preparation_requires_exact_pins_and_honest_retention(self):
        import json
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "row.json"
            value = {"schema":"dm-query-preparation-v1", "retained":False,"complete":False,
                "semantic_revision":"1"*32,"source_revision":"2"*32}
            path.write_text(json.dumps(value))
            self.assertFalse(m.prepared(path,False)["retained"])
            with self.assertRaises(ValueError): m.prepared(path,True)
            value["source_revision"]="missing"
            path.write_text(json.dumps(value))
            with self.assertRaises(ValueError): m.prepared(path,False)

if __name__ == "__main__": unittest.main()
