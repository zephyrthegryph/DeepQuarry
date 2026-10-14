"""Pure protocol fixtures, with no compiler or runtime subprocesses."""
import copy
from pathlib import Path
import unittest
from cached_scenarios import SEQUENCE, validate


class CachedScenarioChecks(unittest.TestCase):
    def scenarios(self):
        parent = Path("parent").resolve()
        journal = Path("derivative").resolve()
        scenarios = []
        for index, name in enumerate(SEQUENCE):
            scenario = {"name": name, "project": "project.dme", "_semantic_configuration": {"engine": "pin"},
                        "input_journal": str(parent if index < 2 else journal), "no_cache": index == 3}
            if index >= 2:
                scenario["_edited_snapshot"] = {"journal": journal, "snapshot_id": "edited-index",
                    "provenance": {"variant_receipt_sha256": "variant"}}
            scenarios.append(scenario)
        return parent, scenarios

    def test_exact_sequence_and_explicit_disk_cache_scope(self):
        parent, scenarios = self.scenarios()
        self.assertTrue(validate(scenarios, parent, [8]))
        self.assertEqual(scenarios[2]["_cache_protocol"]["cache_state"], "parent_populated")
        self.assertEqual(scenarios[3]["_cache_protocol"]["cache_state"], "disabled")
        self.assertIn("not_resident_daemon", scenarios[2]["_cache_protocol"]["process_state"])

    def test_wrong_sequence_worker_parent_or_missing_derivative_pin_rejected(self):
        parent, original = self.scenarios()
        for mutate in (
            lambda values: values.reverse(),
            lambda values: values[0].update(input_journal="other"),
            lambda values: values[2].pop("_edited_snapshot"),
            lambda values: values[2].update(no_cache=True),
            lambda values: values[3].update(no_cache="false"),
            lambda values: values[3]["_edited_snapshot"].update(snapshot_id="different"),
        ):
            scenarios = copy.deepcopy(original)
            mutate(scenarios)
            with self.assertRaises(ValueError):
                validate(scenarios, parent, [8])
        with self.assertRaises(ValueError):
            validate(original, parent, [1, 8])


if __name__ == "__main__":
    unittest.main()
