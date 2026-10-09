"""Compact admission receipts referring to one authenticated full inspector report."""
import hashlib
import json
from pathlib import Path


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def compact(value):
    # Explicitly omit all signatures and potentially large examples/payloads.
    fields = ('schema_version', 'snapshot_id', 'semantic_configuration_sha256',
              'signature_algorithm', 'tool_complete', 'traversal_complete', 'complete',
              'semantic_coverage', 'total_discrepancies', 'unexplained_discrepancies',
              'parity_acceptance', 'structural_measurement_admission', 'native_pair_sha256',
              'no_regression', 'no_regression_basis', 'report', 'report_sha256',
              'error', 'exit_code', 'watchdog', 'wall_s', 'structural_check')
    result = {key: value[key] for key in fields if key in value}
    result['evidence_format'] = 'structural-report-reference-v1'
    for roster, signatures, count in (('categories', 'category_signatures', 'discrepancy_count'),
                                     ('uncovered', 'uncovered_signatures', 'occurrence_count')):
        result[roster] = {kind: {count: entry.get(count),
            'unique_case_count': len(value.get(signatures, {}).get(kind, []))}
            for kind, entry in value.get(roster, {}).items()}
    return result


def load(value, expected_snapshot=None, expected_configuration=None):
    """Load old enriched full evidence or a hash-authenticated compact reference."""
    if value.get('evidence_format') == 'structural-report-reference-v1':
        path = Path(value['report'])
        before = sha(path)
        if before != value.get('report_sha256'):
            raise ValueError('structural report hash mismatch')
        full = json.loads(path.read_text(encoding='utf-8'))
        if sha(path) != before:
            raise ValueError('structural report changed while loading')
        if full.get('schema_version') != value.get('schema_version') or full.get('snapshot_id') != value.get('snapshot_id'):
            raise ValueError('structural report reference identity mismatch')
        configuration = value.get('semantic_configuration_sha256')
        if not isinstance(configuration, str) or len(configuration) != 64:
            raise ValueError('structural reference configuration missing')
        if full.get('semantic_configuration_sha256', configuration) != configuration:
            raise ValueError('structural report reference configuration mismatch')
        full['semantic_configuration_sha256'] = configuration
    else:
        full = value
    if expected_snapshot is not None and full.get('snapshot_id') != expected_snapshot:
        raise ValueError('structural baseline snapshot mismatch')
    if expected_configuration is not None and full.get('semantic_configuration_sha256') != expected_configuration:
        raise ValueError('structural baseline configuration mismatch')
    return full


def validated_identity(descriptor, snapshot, configuration, descriptor_path=None):
    """Call only after full exact-case validation; retain no signature arrays."""
    if descriptor.get('evidence_format') != 'structural-report-reference-v1':
        return None
    if descriptor.get('snapshot_id') != snapshot or descriptor.get('semantic_configuration_sha256') != configuration:
        raise ValueError('validated structural identity scope mismatch')
    return {'snapshot_id': snapshot, 'semantic_configuration_sha256': configuration,
            'report': descriptor['report'], 'report_sha256': descriptor['report_sha256'],
            'descriptor_path': str(descriptor_path) if descriptor_path is not None else None,
            'descriptor_sha256': sha(descriptor_path) if descriptor_path is not None else None}


def same_report(identity, current_report, snapshot, configuration):
    """Evaluate exact report equality afresh, never a previous admission."""
    if identity is None:
        return False
    if identity['snapshot_id'] != snapshot or identity['semantic_configuration_sha256'] != configuration:
        raise ValueError('structural report identity scope mismatch')
    if identity['descriptor_path'] is not None and sha(identity['descriptor_path']) != identity['descriptor_sha256']:
        raise ValueError('structural baseline descriptor changed after preflight')
    if sha(identity['report']) != identity['report_sha256']:
        raise ValueError('structural baseline report changed after validation')
    return sha(current_report) == identity['report_sha256']
