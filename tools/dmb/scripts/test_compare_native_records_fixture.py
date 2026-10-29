import json
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from compare_native_records_fixture import compare, configuration, observe, rows


def site(**changes):
    result = {"rule": "records_data_only", "rel": "code/record.dm", "line": 2, "msg": "", "key": "", "ident": ""}
    result.update(changes)
    return result


class RecordsFixtureTests(unittest.TestCase):
    def test_all_site_fields_and_multiplicity_are_compared(self):
        original = site()
        self.assertTrue(compare([original, original], [original, original])["matched"])
        self.assertFalse(compare([original, original], [original])["matched"])
        for change in [dict(rel="code/other.dm"), dict(line=3), dict(msg="changed"), dict(key="other"), dict(ident="other")]:
            self.assertFalse(compare([original], [site(**change)])["matched"])

    def test_order_is_preserved(self):
        one, two = site(), site(line=4)
        report = compare([one, two], [two, one])
        self.assertFalse(report["matched"])
        self.assertEqual(report["differences"], [])
        self.assertEqual(report["order_difference_count"], 2)

    def test_partial_or_noisy_rows_do_not_count_as_a_clean_result(self):
        for value in ["noise", "[]", "{}", json.dumps(site(rule="base_var")), json.dumps(site(line=True)), json.dumps(site(rel="")), json.dumps(site(msg=None)), json.dumps({**site(), "extra": 1})]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                rows(value, "native")
        with self.assertRaisesRegex(ValueError, "duplicate"):
            rows(json.dumps(site())[:-1] + ',"line":7}', "old")

    def test_empty_reference_needs_explicit_opt_in(self):
        with self.assertRaises(ValueError):
            compare([], [])
        self.assertTrue(compare([], [], allow_empty_reference=True)["matched"])

    def test_native_receives_config_as_an_argument_without_shell_interpretation(self):
        result = SimpleNamespace(returncode=0, stdout=json.dumps(site()), stderr="")
        config = {"raw": "quoted = '$(arbitrary)'\n", "accessor_prefixes": ["get_", "set_"]}
        executable = Path("name;echo-not-a-command.exe")
        with patch("compare_native_records_fixture.digest", return_value="same"), patch("compare_native_records_fixture.Path.is_file", return_value=True), patch("compare_native_records_fixture.configuration", return_value=config), patch("compare_native_records_fixture.subprocess.run", return_value=result) as run:
            found, _ = observe(executable, None, Path("fixture with spaces"), 60, "native")
        self.assertEqual(found, [site()])
        self.assertEqual(run.call_args.args[0], [str(executable.resolve()), str(Path("fixture with spaces").resolve()), json.dumps(config, separators=(",", ":"))])
        self.assertNotIn("shell", run.call_args.kwargs)

    def test_reference_executes_its_own_config_parser(self):
        result = SimpleNamespace(returncode=0, stdout=json.dumps(site()), stderr="")
        with patch("compare_native_records_fixture.digest", return_value="same"), patch("compare_native_records_fixture.Path.is_file", return_value=True), patch("compare_native_records_fixture.configuration", side_effect=AssertionError("reference must resolve its own scope")), patch("compare_native_records_fixture.subprocess.run", return_value=result) as run:
            observe(Path("old.exe"), None, Path("fixture"), 60, "reference")
        self.assertEqual(len(run.call_args.args[0]), 2)

    def test_changed_or_failed_producer_is_not_a_result(self):
        for status, hashes in [(1, ["same"]), (0, ["before", "after"])]:
            with patch("compare_native_records_fixture.digest", side_effect=hashes), patch("compare_native_records_fixture.Path.is_file", return_value=True), patch("compare_native_records_fixture.configuration", return_value={"raw": "", "accessor_prefixes": []}), patch("compare_native_records_fixture.subprocess.run", return_value=SimpleNamespace(returncode=status, stdout="", stderr="failure")):
                with self.assertRaises(ValueError):
                    observe(Path("producer.exe"), None, Path("fixture"), 60, "native")

    def test_config_host_matches_legacy_string_array_filtering(self):
        raw = b'[lint.base_vars.lists]\nrecord_accessor_prefixes = ["get_", 1, "set_"]\n'
        with patch("compare_native_records_fixture.Path.read_bytes", return_value=raw):
            result = configuration(Path("fixture"))
        self.assertEqual(result, {"raw": raw.decode(), "accessor_prefixes": ["get_", "set_"]})


if __name__ == "__main__":
    unittest.main()
