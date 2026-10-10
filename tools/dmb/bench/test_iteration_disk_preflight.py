"""Synthetic headroom checks; no disk inventory or compiler process is started."""
import ast
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import Mock


class DiskPreflightTests(unittest.TestCase):
    def setUp(self):
        source = Path(__file__).with_name("native-iteration.py").read_text(encoding="utf-8")
        tree = ast.parse(source)
        function = next(node for node in tree.body if isinstance(node, ast.FunctionDef)
                        and node.name == "disk_preflight")
        self.disk = Mock()
        namespace = {"shutil": SimpleNamespace(disk_usage=self.disk)}
        exec(compile(ast.Module(body=[function], type_ignores=[]), str(__file__), "exec"), namespace)
        self.check = namespace["disk_preflight"]

    def test_floor_boundary_and_failure_report_observed_bytes(self):
        destination = Mock()
        destination.exists.return_value = True
        for free, status in [(15, "failed"), (16, "passed"), (17, "passed")]:
            self.disk.return_value = SimpleNamespace(free=free, total=100)
            result = self.check(destination, 16)
            self.assertEqual(result["status"], status)
            self.assertEqual(result["free_bytes"], free)
            self.assertEqual(result["required_free_bytes"], 16)
            self.assertIn("no reservation", result["policy"])

    def test_uncreated_output_uses_existing_ancestor_without_creating_it(self):
        ancestor = Mock()
        ancestor.exists.return_value = True
        destination = Mock()
        destination.parent = ancestor
        destination.exists.return_value = False
        self.disk.return_value = SimpleNamespace(free=20, total=100)
        result = self.check(destination, 16)
        self.disk.assert_called_once_with(ancestor)
        destination.mkdir.assert_not_called()
        self.assertEqual(result["status"], "passed")


if __name__ == "__main__":
    unittest.main()
