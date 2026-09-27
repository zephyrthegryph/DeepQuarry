import tempfile
import unittest
from pathlib import Path

from declaration_census import find_instance_declarations


class DeclarationCensusTest(unittest.TestCase):
    def test_rejects_production_override_but_allows_test_fixture(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "deepquarry.dme").write_text(
                '#include "code\\body.dm"\n#include "code\\modules\\unit_tests\\fixture.dm"\n',
                encoding="utf-8",
            )
            (root / "code/modules/unit_tests").mkdir(parents=True)
            (root / "code/body.dm").write_text(
                "/datum/proc/om_declare(datum/object_model/archetype/A)\n"
                "/datum/body/om_declare(datum/object_model/archetype/A)\n"
                "\tA.add(/datum/object_model/behaviour/x)\n",
                encoding="utf-8",
            )
            (root / "code/modules/unit_tests/fixture.dm").write_text(
                "/datum/test/om_declare(datum/object_model/archetype/A)\n",
                encoding="utf-8",
            )
            failures = find_instance_declarations(root)
            self.assertEqual(len(failures), 1)
            self.assertIn("code/body.dm:2", failures[0])


if __name__ == "__main__":
    unittest.main()
