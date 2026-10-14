"""Explicit, unrun migration of completed owned r6 evidence; never remove raw reports."""
import argparse
import importlib.util
import json
from pathlib import Path
import os

spec = importlib.util.spec_from_file_location('evidence', Path(__file__).with_name('structural_evidence.py'))
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)
MARKER = '.dmb-benchmark-owned.json'


def checked_run(path, cohorts):
    path = Path(path).absolute()
    for component in (path, *path.parents):
        info = component.lstat()
        if component.is_symlink() or getattr(info, 'st_file_attributes', 0) & 0x400:
            raise ValueError('migration refuses reparse ancestor')
    path = path.resolve(strict=True)
    if path.drive.lower() != 'e:' or path.parent not in cohorts:
        raise ValueError('migration run outside explicit E: cohorts')
    marker = json.loads((path / MARKER).read_text(encoding='utf-8'))
    if marker != {'schema': 1, 'owner': str(path.parent), 'path': str(path)}:
        raise ValueError('migration run marker mismatch')
    return path


def compact_row(row, cohorts):
    if row.get('measurement_revision') != 6 or row.get('kind') != 'run':
        return None
    if row.get('oracle') != 'passed' or row.get('structural_invocation_finished') is not True:
        return None
    run = checked_run(row['artifact_directory'], cohorts)
    diff = row.get('structural_diff', {})
    if diff.get('evidence_format') == 'structural-report-reference-v1':
        return None
    report = run / 'structural-diff.json'
    if Path(diff.get('report', '')).resolve() != report.resolve() or evidence.sha(report) != diff.get('report_sha256'):
        raise ValueError('migration report reference/hash mismatch')
    summary = evidence.compact(diff)
    # Validate authoritative raw identity before reducing stored evidence.
    evidence.load(summary, row['snapshot_id'], row['semantic_configuration_sha256'])
    return run, summary


def checked_results(value):
    path = Path(value).absolute()
    if path.drive.lower() != 'e:' or path == Path('E:/'):
        raise ValueError('migration results must be a contained E: file')
    for component in (path, *path.parents):
        if component.is_symlink() or getattr(component.lstat(), 'st_file_attributes', 0) & 0x400:
            raise ValueError('migration results reparse ancestor')
    if not path.is_file() or path.stat().st_nlink != 1:
        raise ValueError('migration results must be a unique regular file')
    temporary = path.with_name(path.name + '.compact-tmp')
    if temporary.exists() or temporary.is_symlink():
        raise ValueError('migration temporary path already exists')
    return path.resolve(strict=True)


def replace_json(path, value):
    if path.exists() and (path.is_symlink() or getattr(path.lstat(), 'st_file_attributes', 0) & 0x400 or path.stat().st_nlink != 1):
        raise ValueError('migration refuses shared/reparse metadata')
    temporary = path.with_name(path.name + '.compact-tmp')
    with temporary.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, indent=2, allow_nan=False)
    os.replace(temporary, path)


def migrate(cohorts, results):
    cohorts = {Path(path).resolve(strict=True) for path in cohorts}
    for cohort in cohorts:
        if cohort.drive.lower() != 'e:':
            raise ValueError('migration cohort must be on E:')
        for component in (cohort, *cohort.parents):
            if component.is_symlink() or getattr(component.lstat(), 'st_file_attributes', 0) & 0x400:
                raise ValueError('migration cohort reparse ancestor')
        marker = json.loads((cohort / MARKER).read_text(encoding='utf-8'))
        if marker != {'schema': 1, 'owner': str(cohort.parent), 'path': str(cohort)}:
            raise ValueError('migration cohort marker mismatch')
    # Results are streamed one line at a time; all historical non-r6 bytes pass
    # through unchanged. Only rows authenticated to explicit owned cohorts change.
    results = [checked_results(path) for path in results]
    for path in results:
        temporary = path.with_name(path.name + '.compact-tmp')
        with path.open('rb') as source, temporary.open('xb') as target:
            for line in source:
                row = json.loads(line)
                if row.get('measurement_revision') == 6 and row.get('kind') == 'run' and Path(row.get('artifact_directory', '')).parent.resolve() in cohorts:
                    candidate = compact_row(row, cohorts)
                    if candidate:
                        run, summary = candidate
                        admission = run / 'structural-admission.json'
                        replace_json(admission, summary)
                        summary['admission_report'] = str(admission)
                        summary['admission_report_sha256'] = evidence.sha(admission)
                        row['structural_diff'] = summary
                        receipt = json.loads((run / 'receipt.json').read_text(encoding='utf-8'))
                        if receipt.get('snapshot_id') != row['snapshot_id'] or receipt.get('semantic_configuration_sha256') != row['semantic_configuration_sha256']:
                            raise ValueError('migration receipt/row identity mismatch')
                        receipt['structural_diff'] = summary
                        replace_json(run / 'receipt.json', receipt)
                        line = (json.dumps(row, separators=(',', ':'), allow_nan=False) + '\n').encode('utf-8')
                target.write(line)
        os.replace(temporary, path)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cohort', type=Path, action='append', required=True)
    parser.add_argument('--results', type=Path, action='append', required=True)
    args = parser.parse_args()
    migrate(args.cohort, args.results)
