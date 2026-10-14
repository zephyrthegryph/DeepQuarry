import copy
from pathlib import Path
import unittest
import tempfile
import json
import hashlib
from types import SimpleNamespace
from unittest.mock import patch
from compare_compile_errors import matches, normalize, template_admission, corpus_cases, compare_corpus


class CompileErrorTests(unittest.TestCase):
    def test_requested_corpus_coverage_cannot_silently_drop_unknown_cases(self):
        admitted = [{"name": "known"}]
        for requested in (["known", "missing"], ["known", "known"]):
            args = SimpleNamespace(corpus=Path("unused"), case=requested)
            with patch("compare_compile_errors.corpus_cases", return_value=admitted), \
                    patch("compare_compile_errors.run") as launch:
                with self.assertRaisesRegex(ValueError, "requested corpus case"):
                    compare_corpus(args, {"byond": "a" * 64})
                launch.assert_not_called()

    def test_corpus_authenticates_source_manifest_capture_and_compiler(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = b'var/value = "bad\ntext"\n'
            manifest = b'#include "source.dm"\n'
            digest = lambda data: hashlib.sha256(data).hexdigest()
            capture = json.dumps({"compiler_sha256": "a" * 64, "source_sha256": digest(source)}).encode()
            for name, data in [("source.dm", source), ("probe.dme", manifest), ("capture.json", capture)]:
                (root / name).write_bytes(data)
            entry = {"name": "quoted", "root": ".", "source": "source.dm", "manifest": "probe.dme",
                     "capture": "capture.json", "capture_sha256": digest(capture),
                     "files": {"source.dm": digest(source), "probe.dme": digest(manifest)}}
            descriptor = root / "corpus.json"
            descriptor.write_text(json.dumps({"schema": 1, "cases": [entry]}))
            self.assertEqual(corpus_cases(descriptor, "a" * 64)[0]["name"], "quoted")
            with self.assertRaises(ValueError):
                corpus_cases(descriptor, "b" * 64)
            (root / "probe.dme").write_bytes(b'#include "other.dm"')
            with self.assertRaises(ValueError):
                corpus_cases(descriptor, "a" * 64)
            (root / "probe.dme").write_bytes(manifest)
            (root / "source.dm").write_bytes(b"changed")
            with self.assertRaises(ValueError):
                corpus_cases(descriptor, "a" * 64)
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
