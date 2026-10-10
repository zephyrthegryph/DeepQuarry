import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('refresh_probe', Path(__file__).with_name('run.py'))
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class AdmissionTests(unittest.TestCase):
    def test_prior_byond_consumed_pins_are_exact_and_new_native_is_independent(self):
        pins = {name: {'path': name, 'sha256': name} for name in ('dm', 'dd', 'library', 'native', 'template')}
        prior = {'executions': {'byond-compile': {'exit': 0}},
                 'byond': {'diagnostic': {}, 'results': {}}, 'pinned_inputs': pins}
        current = {**pins, 'native': {'path': 'new native', 'sha256': 'new'},
                   'template': {'path': 'new template', 'sha256': 'new template'}}
        admitted = helper.admit_reference_pins(prior, current)
        self.assertTrue(admitted['native_compiler_changed'])
        self.assertEqual(admitted['prior_native_context'], pins['native'])
        for name in ('dm', 'dd', 'library'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                helper.admit_reference_pins(prior, {**current, name: {'path': 'changed', 'sha256': 'changed'}})
        for missing in ({}, {**prior, 'executions': {'native-compile': {'exit': 0}}},
                        {**prior, 'executions': {'byond-compile': {'exit': 70}}},
                        {**prior, 'byond': {}}, {**prior, 'pinned_inputs': {}}):
            with self.assertRaises(ValueError):
                helper.admit_reference_pins(missing, current)

    def test_probe_and_runtime_parameters_match_actual_game_eligibility_contract(self):
        checkout = Path(__file__).resolve().parents[5]
        eligibility = (checkout / 'code/modules/unit_tests/unit_test.dm').read_text()
        definitions = (checkout / 'code/modules/unit_tests/_unit_tests.dm').read_text()
        probe = Path(__file__).with_name('probe.dm').read_text()
        runner = Path(__file__).with_name('run.py').read_text()
        self.assertIn('if(ispath(test_path, /datum/unit_test/focus_only))', eligibility)
        self.assertIn('if(dq_test_ineligibility(test_path))', eligibility)
        self.assertIn('/datum/unit_test/dq_refresh_queue_diagnostic/Run()', probe)
        self.assertNotIn('/datum/unit_test/focus_only/', probe)
        self.assertIn('#define TEST_EXACT_AUTOMATIC_ROWS_PARAMETER "test-exact-automatic-rows"', definitions)
        self.assertIn('world.params[TEST_EXACT_AUTOMATIC_ROWS_PARAMETER]', eligibility)
        self.assertIn("'test-exact-automatic-rows': '1'", runner)

    def test_only_expected_failures_with_first_diagnostic_are_admitted(self):
        focus = ['diagnostic', 'failure-a', 'failure-b', 'pass']
        rows = {name: {'name': name, 'status': int(name.startswith('failure')), 'runtimes': 0,
                       'runtime_errors': [], 'runtime_errors_truncated': False}
                for name in focus + ['ownership_framework_checks']}
        queue = {'queue_scan_complete': True, 'map_scan_complete': True}
        log = 'Shutdown complete\nTest run failed!\nUnit Tests failed!'
        self.assertEqual(helper.admit_runtime({'exit': 1}, queue, rows, focus, log), list(rows))
        self.assertEqual(helper.admit_runtime({'exit': 3296}, queue, rows, focus, log), list(rows))
        with self.assertRaises(ValueError):
            helper.admit_runtime({'exit': 0xC0000005}, queue, rows, focus, log)
        with self.assertRaises(ValueError):
            helper.admit_runtime({'exit': 1}, queue, rows, focus, 'Shutdown complete')
        with self.assertRaises(ValueError):
            helper.admit_runtime({'exit': 1}, queue, rows, focus, log + '\naccess violation')
        with self.assertRaises(ValueError):
            helper.admit_runtime({'exit': 1}, {**queue, 'queue_scan_complete': False}, rows, focus, log)
        shifted = dict(rows)
        first = shifted.pop('diagnostic')
        shifted['diagnostic'] = first
        with self.assertRaises(ValueError):
            helper.admit_runtime({'exit': 1}, queue, shifted, focus, log)
        rows['pass']['runtime_errors'] = ['captured error']
        with self.assertRaises(ValueError):
            helper.admit_runtime({'exit': 1}, queue, rows, focus, log)


if __name__ == '__main__':
    unittest.main()
