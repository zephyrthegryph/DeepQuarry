import hashlib
from pathlib import Path
import tempfile
import unittest

from check_build_oracle import diagnostics, pair, require_pinned_tools


class BuildOracle(unittest.TestCase):
    def test_complete_pair_compares_resource_bytes_too(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            results = []
            for name, resource in (("captured", b"one"), ("fresh", b"two")):
                slot = root / name
                generation = slot / "generations" / ("a" * 64)
                generation.mkdir(parents=True)
                (slot / "HEAD").write_text("a" * 64 + "\n")
                (generation / "world.dmb").write_bytes(b"same")
                (generation / "world.rsc").write_bytes(resource)
                results.append(pair(slot))
            self.assertEqual(results[0]["dmb"], results[1]["dmb"])
            self.assertNotEqual(results[0]["rsc"], results[1]["rsc"])

    def test_only_named_trace_records_are_excluded(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "stderr.log"
            path.write_text("DM_BUILD_TRACE timing 1.0s\ndm-compiled resource byte hashing: 1.234s\n"
                            "dm-compiled compiler: invalid\nfile.dm:1:error: bad\n  detail\n")
            self.assertEqual(diagnostics(path), ["dm-compiled compiler: invalid", "file.dm:1:error: bad", "  detail"])

    def test_changed_compiler_is_rejected_before_launch(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            receipt = {"tools": {}, "arguments": {}}
            for name in ("compiler", "builtins"):
                file = root / name
                file.write_bytes(name.encode())
                receipt["tools"][name] = {"path": str(file), "sha256": hashlib.sha256(file.read_bytes()).hexdigest()}
                receipt["arguments"][name] = str(file)
            require_pinned_tools(receipt)
            (root / "compiler").write_bytes(b"rebuilt")
            with self.assertRaisesRegex(ValueError, "changed"):
                require_pinned_tools(receipt)


if __name__ == "__main__":
    unittest.main()
