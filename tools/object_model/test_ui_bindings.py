import copy
import json
import unittest
from pathlib import Path

from ui_bindings import generate, validate


class UiBindingsTests(unittest.TestCase):
    def setUp(self):
        self.document = json.loads((Path(__file__).parent / "ui_schemas.json").read_text(encoding="utf-8"))

    def test_fixture_roundtrip(self):
        dm, ts = generate(self.document)
        self.assertIn('"value" = list("type" = "number", "min" = 0, "max" = 10)', dm)
        self.assertIn('description?: string', ts)
        self.assertIn('set: { value: number }', ts)
        self.assertIn("revision: number", ts)

    def test_rejects_reserved_and_invalid_fields(self):
        bad = copy.deepcopy(self.document)
        bad["interfaces"][0]["data"]["revision"] = {"type": "number"}
        with self.assertRaises(ValueError):
            validate(bad)
        bad = copy.deepcopy(self.document)
        bad["interfaces"][0]["actions"]["set"]["value"]["type"] = "unknown"
        with self.assertRaises(ValueError):
            validate(bad)


if __name__ == "__main__":
    unittest.main()
