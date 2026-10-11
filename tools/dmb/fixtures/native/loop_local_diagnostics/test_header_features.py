"""No compiler or runtime processes; inspector contract parsing only."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("header_features", Path(__file__).with_name("header_features.py"))
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class HeaderFlags(unittest.TestCase):
    def test_world_and_extension_flags_do_not_replace_header(self):
        text = "header=Header { flags: 65, extended_flags: Some(4) } world=World { flags: 99 }\nclass_flags={12: 1}\n"
        self.assertEqual(helper.header_flags(text), 65)

    def test_missing_truncated_and_ambiguous_header_decline(self):
        for text in ["world=World { flags: 65 }", "header=Header { flags: 65",
                     "header=Header { flags: 65, flags: 0 }"]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                helper.header_flags(text)

    def test_hex_debug_value_has_exact_bits(self):
        self.assertEqual(helper.header_flags("header=Header { flags: 0x80000041 } world=None"), 0x80000041)


if __name__ == "__main__":
    unittest.main()
