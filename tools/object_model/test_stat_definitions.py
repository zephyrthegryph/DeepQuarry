import copy
import unittest

from stat_definitions import generate


DOC = {"version": 1, "domains": [{"name": "test", "change_mask": 2, "stats": [
    {"name": "accuracy", "rule": "add", "baseline": 0, "min": -10, "max": 10},
    {"name": "speed", "rule": "multiply", "baseline": 1, "min": 0, "max": 5},
]}]}


class StatGenerationTests(unittest.TestCase):
    def test_named_api_and_compact_ids(self):
        output = generate(DOC)
        self.assertIn("#define OM_TEST_ACCURACY 1", output)
        self.assertIn("#define OM_TEST_SPEED 2", output)
        self.assertIn("/proc/get_accuracy()", output)
        self.assertIn("/proc/set_base_accuracy(value)", output)
        self.assertIn("/proc/add_accuracy(value)", output)
        self.assertIn("/proc/multiply_speed(value)", output)
        self.assertIn("change_mask = 2", output)

    def test_rejects_duplicate_names_and_bad_bounds(self):
        duplicate = copy.deepcopy(DOC)
        duplicate["domains"][0]["stats"].append(duplicate["domains"][0]["stats"][0])
        with self.assertRaises(ValueError):
            generate(duplicate)
        bounds = copy.deepcopy(DOC)
        bounds["domains"][0]["stats"][0]["baseline"] = 100
        with self.assertRaises(ValueError):
            generate(bounds)


if __name__ == "__main__":
    unittest.main()
