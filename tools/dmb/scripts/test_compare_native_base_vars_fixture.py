import json
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from compare_native_base_vars_fixture import compare, observe, rows

def declaration(**changes):
    row = {"row":"base_var_declaration", "rel":"code/a.dm", "line":2, "owner":"/obj", "name":"value", "vtype":"", "base":True, "list_init":False}
    row.update(changes)
    return row

class BaseVarsFixtureTests(unittest.TestCase):
    def test_all_fields_and_multiplicity_are_compared(self):
        original = declaration()
        self.assertTrue(compare([original, original], [original, original])["matched"])
        report = compare([original, original], [original])
        self.assertFalse(report["matched"])
        self.assertEqual(report["differences"][0]["reference_count"], 2)
        for changed in [declaration(line=3), declaration(vtype="/datum"), declaration(base=False), declaration(list_init=True), declaration(name="other")]:
            self.assertFalse(compare([original], [changed])["matched"])

    def test_order_is_not_normalized_away(self):
        a, b = declaration(), declaration(name="second")
        result = compare([a,b], [b,a])
        self.assertFalse(result["matched"])
        self.assertEqual(result["differences"], [])
        self.assertEqual(result["order_difference_count"], 2)

    def test_record_rows_keep_exact_legacy_tuple_fields(self):
        record = {"row":"record_proc", "rel":"a.dm", "line":3, "name":"read"}
        self.assertEqual(rows(json.dumps(record), "old"), [record])
        self.assertFalse(compare([record], [{**record,"name":"write"}])["matched"])

    def test_empty_reference_requires_deliberate_opt_in(self):
        with self.assertRaises(ValueError):
            compare([], [])
        self.assertTrue(compare([], [], allow_empty_reference=True)["matched"])

    def test_malformed_unknown_or_extra_fields_never_become_clean_rows(self):
        for text in ["log noise", "[]", '{"row":"unknown"}', json.dumps({**declaration(),"model":{}}), json.dumps(declaration(line=True)), json.dumps(declaration(base=1)), json.dumps(declaration(vtype=None)), json.dumps(declaration(owner="obj")), json.dumps(declaration(rel=""))]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                rows(text, "native")
        with self.assertRaisesRegex(ValueError,"duplicate"):
            rows(json.dumps(declaration())[:-1] + ',"line":3}', "native")

    def test_executables_receive_argument_arrays_without_shell_interpretation(self):
        result = SimpleNamespace(returncode=0,stdout=json.dumps(declaration()),stderr="")
        executable = Path("name;echo injected.exe")
        with patch("compare_native_base_vars_fixture.digest", return_value="same"), patch("compare_native_base_vars_fixture.Path.is_file", return_value=True), patch("compare_native_base_vars_fixture.subprocess.run",return_value=result) as run:
            observed, _ = observe(executable,None,Path("fixture with spaces"),60,"native")
        self.assertEqual(observed,[declaration()])
        self.assertEqual(run.call_args.args[0], [str(executable.resolve()),str(Path("fixture with spaces").resolve())])
        self.assertNotIn("shell",run.call_args.kwargs)

    def test_failed_or_changed_executable_is_not_compared(self):
        for status, hashes in [(1,["same"]),(0,["before","after"])]:
            with patch("compare_native_base_vars_fixture.digest",side_effect=hashes), patch("compare_native_base_vars_fixture.Path.is_file",return_value=True), patch("compare_native_base_vars_fixture.subprocess.run",return_value=SimpleNamespace(returncode=status,stdout="",stderr="failure")):
                with self.assertRaises(ValueError):
                    observe(Path("native.exe"),None,Path("fixture"),60,"native")

if __name__ == "__main__":
    unittest.main()
