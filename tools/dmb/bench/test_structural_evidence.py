import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


def module(name, file):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(file))
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value


evidence = module('structural_evidence', 'structural_evidence.py')
protocol = module('protocol', 'protocol.py')


def fixture():
    return {'schema_version': 1, 'snapshot_id': 'snapshot',
            'semantic_configuration_sha256': 'a' * 64,
            'tool_complete': True, 'traversal_complete': True,
            'signature_algorithm': 'md5-length-framed-v1',
            'categories': {name: {'discrepancy_count': 1} for name in protocol.STRUCTURAL_CATEGORIES},
            'category_signatures': {name: ['1' * 32] for name in protocol.STRUCTURAL_CATEGORIES},
            'uncovered': {'opaque_value': {'occurrence_count': 1}},
            'uncovered_signatures': {'opaque_value': ['2' * 32]}}


class StructuralEvidenceTests(unittest.TestCase):
    def reference(self, directory, full):
        path = Path(directory) / 'report.json'
        path.write_text(json.dumps(full), encoding='utf-8')
        return evidence.compact(dict(full, report=str(path), report_sha256=evidence.sha(path)))

    def test_compact_omits_signatures_preserves_counts(self):
        value = evidence.compact(fixture())
        self.assertNotIn('category_signatures', value)
        self.assertNotIn('uncovered_signatures', value)
        self.assertEqual(value['uncovered']['opaque_value'], {'occurrence_count': 1, 'unique_case_count': 1})

    def test_authenticated_reference_and_old_full_compatibility(self):
        full = fixture()
        with tempfile.TemporaryDirectory() as directory:
            ref = self.reference(directory, full)
            self.assertEqual(evidence.load(ref, 'snapshot', 'a' * 64), full)
        self.assertIs(evidence.load(full, 'snapshot', 'a' * 64), full)

    def test_changed_report_hash_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            ref = self.reference(directory, fixture())
            Path(ref['report']).write_text('{}', encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                evidence.load(ref)

    def test_reference_configuration_tamper_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            ref = self.reference(directory, fixture()); ref['semantic_configuration_sha256'] = 'b' * 64
            with self.assertRaisesRegex(ValueError, 'configuration mismatch'):
                evidence.load(ref, 'snapshot', 'a' * 64)

    def test_improved_case_subset_and_changed_cases(self):
        previous = fixture(); current = fixture()
        current['category_signatures']['bytecode'] = []
        current['categories']['bytecode']['discrepancy_count'] = 0
        self.assertEqual(protocol.structural_no_regression(previous, current), 'passed')
        current['uncovered_signatures']['opaque_value'] = ['3' * 32]
        self.assertEqual(protocol.structural_no_regression(previous, current), 'failed')

    def test_same_snapshot_different_configuration_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            ref = self.reference(directory, fixture())
            with self.assertRaisesRegex(ValueError, 'configuration mismatch'):
                evidence.load(ref, 'snapshot', 'b' * 64)


if __name__ == '__main__':
    unittest.main()
