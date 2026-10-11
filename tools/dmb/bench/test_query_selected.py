"""Pure selected-row extraction contract; never launches a compiler or daemon."""
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("selected_query_harness", Path(__file__).with_name("query-selected.py"))
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)


class SelectedRows(unittest.TestCase):
    def test_only_exact_current_procedure_rows_are_compared(self):
        expected = {"row": "selected_reference", "declaration": 270, "meaning": {"kind": "Missing"}}
        summary = {"row": "selected_reference_summary", "declaration": 270, "references": 1}
        unrelated = {"row": "selected_reference", "declaration": 269}
        coverage = {"row": "resolved_coverage", "declaration": 270}
        encoded = "\n".join(json.dumps(row) for row in (unrelated, expected, coverage, summary))
        self.assertEqual(harness.selected_rows(encoded, 270), [expected, summary])

    def test_invalid_output_is_not_silently_ignored(self):
        with self.assertRaises(json.JSONDecodeError):
            harness.selected_rows("not-json", 270)


if __name__ == "__main__":
    unittest.main()
