import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("nested_map_contract", HERE / "run.py")
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)
class NestedMapTests(unittest.TestCase):
    def test_exact_values_reject_equal_wrong_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "probe.log"
            log.write_text("\n".join(contract.EXPECTED), encoding="utf-8")
            self.assertEqual(contract.observations(log)["runtimes"], [])
            for label, wrong in [("nested_amount", 1), ("leaf_scalar", 0)]:
                markers = [f"DQ_NESTED {label} {wrong}" if line.startswith(f"DQ_NESTED {label} ") else line for line in contract.EXPECTED]
                log.write_text("\n".join(markers), encoding="utf-8")
                with self.assertRaises(ValueError):
                    contract.observations(log)
    def test_extra_map_transport_rejects_mutated_source(self):
        sha = lambda file: hashlib.sha256(file.read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, target = root / "source", root / "target"
            source.mkdir()
            target.mkdir()
            names = contract.launcher.fixture_files(("contract-resource.txt", "probe.dmm"))
            for name in names:
                (source / name).write_bytes(name.encode())
            hashes = {name: sha(source / name) for name in names}
            contract.launcher.copy_fixture_files(source, target, names, hashes, sha)
            self.assertEqual(sha(target / "probe.dmm"), hashes["probe.dmm"])
            (source / "probe.dmm").write_bytes(b"changed map")
            other = root / "other"
            other.mkdir()
            with self.assertRaisesRegex(ValueError, "changed before copy"):
                contract.launcher.copy_fixture_files(source, other, names, hashes, sha)
    def test_retained_edits_preserve_nested_map_oracle(self):
        spec = importlib.util.spec_from_file_location("nested_retained", HERE / "run_retained.py")
        retained = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(retained)
        source = (HERE / "probe.dm").read_text()
        steps = retained.contract.read_steps(HERE / "scenarios.json", retained.LABELS, "DQ_NESTED")
        for step in steps:
            source = retained.contract.apply_step(source, step)
            if "asset_edit" not in step:
                self.assertEqual(step["expected"][:4], [1, 1, 7, 11])
        self.assertIn("return 17", source)
        self.assertIn("var/unrelated = 23", source)
    def test_assets_are_explicit_map_and_resource(self):
        self.assertEqual(contract.launcher.fixture_files(("probe.dmm", "contract-resource.txt")),
            ("probe.dm", "probe.dme", "probe.dmm", "contract-resource.txt"))
        self.assertIn('/obj/item{amount = 7}', (HERE / "probe.dmm").read_text())
        self.assertIn('new child_type()', (HERE / "probe.dm").read_text())
if __name__ == "__main__":
    unittest.main()
