import copy
from pathlib import Path
import unittest
from compare_compile_errors import matches, normalize, template_admission


class CompileErrorTests(unittest.TestCase):
    def result(self, code):
        return {"exit_code": code, "timed_out": False, "diagnostics": [
            {"file": "probe.dme", "line": 7, "severity": "error", "message": "value: undefined var"}
        ]}

    def test_only_native_source_exit_can_match(self):
        reference = self.result(4294967295)
        self.assertTrue(matches(reference, self.result(2), True))
        for code in (None, 0, 1, 70, 75):
            self.assertFalse(matches(reference, self.result(code), True))
        self.assertFalse(matches(reference, self.result(2), False))

    def test_wording_order_duplicate_count_and_unknown_formats_are_exact(self):
        reference = self.result(1)
        candidate = self.result(2)
        candidate["diagnostics"][0]["message"] = "value: bad variable"
        self.assertFalse(matches(reference, candidate, True))
        candidate = self.result(2)
        candidate["diagnostics"].append(copy.deepcopy(candidate["diagnostics"][0]))
        self.assertFalse(matches(reference, candidate, True))
        reference["diagnostics"].append({"file": None, "line": None, "severity": "unrecognized diagnostic", "message": "fatal error"})
        candidate["diagnostics"] = copy.deepcopy(reference["diagnostics"])
        self.assertFalse(matches(reference, candidate, True))
        reference = self.result(1)
        reference["diagnostics"].append({"file": "probe.dme", "line": 8, "severity": "error", "message": "another error"})
        candidate = self.result(2)
        candidate["diagnostics"] = list(reversed(reference["diagnostics"]))
        self.assertFalse(matches(reference, candidate, True))

    def test_paths_normalize_but_message_and_unknown_diagnostics_survive(self):
        rows = normalize("E:\\owned\\probe.dme:7:error: value: undefined var\nFatal error strange format", Path("E:/owned"))
        self.assertEqual(rows[0], {"file": "probe.dme", "line": 7, "severity": "error", "message": "value: undefined var"})
        self.assertEqual(rows[1]["severity"], "unrecognized diagnostic")

    def test_template_proof_never_invents_capture_authority(self):
        actual = "a" * 64
        self.assertEqual(template_admission({}, actual)["status"], "unknown")
        self.assertEqual(template_admission({"engine_template_sha256": actual.upper()}, actual)["status"], "passed")
        for receipt in ({"template_sha256": "b" * 64}, {"template_sha256": "wrong"}, {"template_sha256": actual, "engine_template_sha256": "b" * 64}):
            with self.assertRaises(ValueError):
                template_admission(receipt, actual)


if __name__ == "__main__":
    unittest.main()
