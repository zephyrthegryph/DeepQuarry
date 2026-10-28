import unittest
from pathlib import Path
from compare_native_checker_fixture import reference_rows, native_rows


class CheckerOracleTests(unittest.TestCase):
    def test_preserves_duplicate_diagnostics_and_ordered_notes(self):
        block = "first.dm, line 2, column 2:\nwarning: seeded\n- one\n- two\n\n"
        rows = reference_rows(block * 2, Path("fixtures/project.dme").resolve())
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["notes"], ["one", "two"])
        self.assertEqual(rows[0]["column"], 2)

    def test_native_schema_does_not_silently_drop_foreign_families(self):
        with self.assertRaises(ValueError):
            native_rows('{"family":"unported"}')


if __name__ == "__main__":
    unittest.main()
