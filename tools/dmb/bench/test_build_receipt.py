"""Synthetic receipt admission; no compiler invocation."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import build_receipt


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


class BuildReceiptTests(unittest.TestCase):
    def test_exact_prototype_receipt_and_rejections(self):
        cache = Path("E:/dq-cache/dmb-protocol-checks")
        cache.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=cache) as directory:
            executable = Path(directory) / "compiler.exe"
            executable.write_bytes(b"synthetic compiler")
            path = Path(directory) / "receipt.json"
            value = dict(exit_code=0, binary_sha256=sha(executable), dmbc_opt_level=1,
                         dmbc_codegen_units=256, lto=False, acceptance_profile=False)
            path.write_text(json.dumps(value))
            proof = build_receipt.authenticate(path, executable, sha)
            self.assertEqual(proof["dmbc_opt_level"], 1)
            self.assertFalse(proof["benchmark_acceptance_admitted"])
            self.assertFalse(proof["declared_acceptance_profile"])
            for changes in ({"exit_code": 124}, {"exit_code": False},
                            {"binary_sha256": "0" * 64}, {"dmbc_opt_level": 0},
                            {"acceptance_profile": "false"}):
                path.write_text(json.dumps(dict(value, **changes)))
                with self.assertRaises(ValueError):
                    build_receipt.authenticate(path, executable, sha)

    def test_receipt_mutation_rejected(self):
        cache = Path("E:/dq-cache/dmb-protocol-checks")
        cache.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=cache) as directory:
            path = Path(directory) / "receipt.json"
            path.write_text('{"exit_code":0}')
            calls = iter(("first", "changed"))
            with self.assertRaisesRegex(ValueError, "changed"):
                build_receipt.authenticate(path, path, lambda _: next(calls))


if __name__ == "__main__":
    unittest.main()
