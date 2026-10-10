import importlib.util
from pathlib import Path
import tempfile
import hashlib
import unittest
from types import SimpleNamespace
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("runtime_contract_run", HERE / "run.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class RuntimeContractHelperTests(unittest.TestCase):
    def test_runtime_archive_mutation_preserves_authenticated_acquisition(self):
        with tempfile.TemporaryDirectory(dir="E:/dq-cache") as directory:
            root = Path(directory)
            acquired = {}
            hashes = {}
            sha = lambda file: hashlib.sha256(file.read_bytes()).hexdigest()
            for extension in ("dmb", "rsc"):
                file = root / ("compiled." + extension)
                file.write_bytes(b"compiled " + extension.encode())
                acquired[extension] = str(file)
                hashes[extension] = {"sha256": sha(file)}
            dmb, evidence = helper.runtime_copies(acquired, hashes, root / "runtime", lambda file: None, sha)
            dmb.with_suffix(".rsc").write_bytes(b"DD mutable archive")
            for extension in ("dmb", "rsc"):
                self.assertEqual(sha(Path(acquired[extension])), hashes[extension]["sha256"])
                self.assertEqual(evidence[extension]["initial_sha256"], hashes[extension]["sha256"])
            self.assertNotEqual(sha(dmb.with_suffix(".rsc")), hashes["rsc"]["sha256"])
            with self.assertRaises(FileExistsError):
                helper.runtime_copies(acquired, hashes, root / "runtime", lambda file: None, sha)

    def test_matching_compiler_outputs_are_insufficient_without_expected_values(self):
        with tempfile.TemporaryDirectory(dir="E:/dq-cache") as directory:
            log = Path(directory) / "probe.log"
            expected = helper.expected_markers([3, 18, 15, 9, 11, 21, 22, 0, 14])
            log.write_text("\n".join(expected) + "\n", encoding="utf-8")
            self.assertTrue(helper.observations(log, expected)["matches_expected"])
            wrong = expected.copy()
            wrong[0] = "DQ_CONTRACT inherited 99"
            log.write_text("\n".join(wrong) + "\n", encoding="utf-8")
            first = helper.observations(log, expected)
            second = helper.observations(log, expected)
            self.assertEqual(first, second)
            self.assertFalse(first["matches_expected"])
            log.write_text("\n".join(expected) + "\nruntime error: invalid proc call\n", encoding="utf-8")
            self.assertFalse(helper.observations(log, expected)["matches_expected"])

    def test_cumulative_edits_and_full_expectations_are_exact_and_bounded(self):
        source = (HERE / "probe.dm").read_text(encoding="utf-8")
        steps = helper.read_steps(HERE / "scenarios.json")
        self.assertEqual(len(steps), 11)
        resource = (HERE / "contract-resource.txt").read_text(encoding="utf-8")
        initial = source
        for step in steps:
            source = helper.apply_step(source, step)
            self.assertEqual(len(helper.expected_markers(step["expected"])), 10)
            if "resource_before" in step:
                before_source = source
                resource = helper.apply_step(resource, {"before": step["resource_before"], "after": step["resource_after"]})
                self.assertEqual(source, before_source)
                self.assertEqual(int(resource), step["expected"][-1])
            if step["name"] in ("initial", "unchanged"):
                self.assertEqual(source, initial)
            if step["name"] == "structural_add":
                self.assertIn("var/extra_value = 13", source)
                self.assertIn("/proc/added()", source)
        self.assertNotIn("var/extra_value", source)
        self.assertNotIn("/proc/added()", source)
        self.assertIn("var/inherited_value = 9", source)
        self.assertIn("child/measure(delta = 6)", source)
        self.assertIn("var/static/counter = 40", source)
        with self.assertRaisesRegex(ValueError, "one exact"):
            helper.apply_step("duplicate duplicate", {"before": "duplicate", "after": "x"})
        self.assertEqual(int(resource), 29)
        with self.assertRaisesRegex(ValueError, "nine integer"):
            helper.expected_markers([0] * 7)

    def test_owned_namespace_matches_probe_daemon_and_client_despite_ambient_namespace(self):
        launch = SimpleNamespace(_daemon_namespace="previous", Endpoint=lambda name: ("endpoint", name))
        with patch.dict(helper.os.environ, {"DMB_DAEMON_NAMESPACE": "foreign"}):
            namespace, endpoint, environment = helper.owned_daemon_route(launch, Path("E:/owned/cache"))
            other, _, _ = helper.owned_daemon_route(launch, Path("E:/owned/cache"))
        self.assertRegex(namespace, r"^runtime-contract-[0-9a-f]{32}$")
        self.assertNotEqual(namespace, other)
        self.assertEqual(endpoint, ("endpoint", namespace))
        self.assertEqual(environment["DMB_DAEMON_NAMESPACE"], namespace)
        self.assertEqual(environment["DMB_CACHE_DIR"], "E:\\owned\\cache")
        self.assertEqual(launch._daemon_namespace, other)

    def test_actual_daemon_route_cannot_silently_become_one_shot_or_byond(self):
        retained = helper.compile_arguments(Path("E:/owned/probe.dme"), Path("E:/owned/retained"), Path("E:/template.bin"), True)
        fresh = helper.compile_arguments(Path("E:/owned/probe.dme"), Path("E:/owned/fresh"), Path("E:/template.bin"), False)
        self.assertNotIn("--no-daemon", retained)
        self.assertNotIn("--no-cache", retained)
        self.assertIn("--no-daemon", fresh)
        self.assertIn("--no-cache", fresh)
        for arguments in (retained, fresh):
            self.assertEqual(arguments[arguments.index("--workers") + 1], "2")
            self.assertIn("--compile-result-file", arguments)


if __name__ == "__main__":
    unittest.main()
