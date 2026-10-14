"""Finalize Phase 0 parity evidence only after all six replay runs complete.

No worlds are launched. Raw files are copied, never rewritten. The existing
normalizer receives explicit --run directories with nested runtime logs joined.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys


def completion_proven(receipt):
    """Clean marker is pass-quality only; exact completion proof is independent."""
    return (receipt.get('status') in ('complete-results', 'complete-results-abnormal-exit')
            and receipt.get('suite_complete') is True
            and receipt.get('shutdown_complete') is True
            and receipt.get('selection_coverage_exact') is True
            and receipt.get('results_present') is True
            and type(receipt.get('exit_code')) is int
            and ((receipt['status'] == 'complete-results') == (receipt['exit_code'] == 0))
            and receipt.get('stop_reason') is None)


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def supplied(value):
    label, sep, path = value.partition('=')
    if not sep or not label:
        raise ValueError('Expected LABEL=DIRECTORY')
    return label, Path(path).resolve()


def preserved_observations(report):
    """Finite observations, never a statistical/equivalence acceptance test."""
    from normalize_runtime import normalize
    runs = {run['label']: run for run in report['runs']}
    producers = ('byond', 'native')
    missing = [f'{p}:preserved' for p in producers if f'{p}:preserved' not in runs]
    result = {'method': 'Preserved observation versus three exact-label observations; absent signature/count is descriptive, not statistical proof.',
              'missing_preserved': missing, 'tests': [], 'runtime_identities': [],
              'new_crosscompiler_divergences': [], 'dropped_crosscompiler_divergences': [],
              'equality_claim': False, 'coverage_complete': report['comparison_coverage_complete'] and not missing and all(runs[f'{p}:preserved']['coverage'].get('complete', False) for p in producers)}
    def signature(run, name):
        row = run['tests'].get(name)
        if row is None:
            return None
        # Keep original full messages separately. Existing normalizer strips the
        # stack after first line, so this comparison normalizes EVERY line.
        message = '\n'.join(normalize(line) for line in str(row.get('message', '')).splitlines())
        return (row.get('status'), message, row.get('runtimes'))
    names = sorted(set().union(*(run['tests'] for run in runs.values())))
    for name in names:
        per = {}
        for producer in producers:
            old = runs.get(f'{producer}:preserved')
            repeats = [runs.get(f'{producer}:{n}') for n in (1, 2, 3)]
            observed = [signature(run, name) if run else None for run in repeats]
            preserved = signature(old, name) if old else None
            stable = len(set(observed)) == 1 and None not in observed
            per[producer] = {'preserved_signature': preserved, 'preserved_test_missing': preserved is None, 'observed_signatures': observed,
                             'stable_observations': stable,
                             'preserved_absent_from_observations': old is not None and preserved not in observed,
                             'stable_deviation': old is not None and stable and preserved != observed[0],
                             'variable_observations': len(set(observed)) > 1,
                             'original_messages': {label: run['tests'].get(name, {}).get('message', '') for label, run in runs.items() if label.startswith(producer + ':')}}
        old_b = per['byond']['preserved_signature']; old_n = per['native']['preserved_signature']
        old_present = not missing and old_b is not None and old_n is not None
        old_difference = old_present and old_b != old_n
        both_stable = all(per[p]['stable_observations'] for p in producers)
        new_difference = both_stable and per['byond']['observed_signatures'][0] != per['native']['observed_signatures'][0]
        if old_present and both_stable and new_difference and not old_difference:
            result['new_crosscompiler_divergences'].append(name)
        if old_present and both_stable and old_difference and not new_difference:
            result['dropped_crosscompiler_divergences'].append(name)
        result['tests'].append({'test': name, 'producers': per,
                                'preserved_crosscompiler_difference': old_difference if old_present else None,
                                'current_stable_crosscompiler_difference': new_difference if both_stable else None})
    for row in report['identities']:
        per = {}
        for producer in producers:
            label = f'{producer}:preserved'
            old = row['counts'].get(label)
            observed = [row['counts'].get(f'{producer}:{n}') for n in (1, 2, 3)]
            stable = None not in observed and len(set(observed)) == 1
            per[producer] = {'preserved_count': old, 'observed_counts': observed,
                             'preserved_count_absent_from_observations': old is not None and old not in observed,
                             'stable_deviation': old is not None and stable and old != observed[0],
                             'variable_observations': len(set(observed)) > 1,
                             'outside_observed_range': old is not None and None not in observed and (old < min(observed) or old > max(observed))}
        result['runtime_identities'].append({key: row[key] for key in ('message', 'procedure', 'source', 'line')} | {'producers': per})
    result['missing_tests'] = [row['test'] for row in result['tests'] if any(None in row['producers'][p]['observed_signatures'] for p in producers)]
    result['acceptance'] = 'No automatic pass: incomplete coverage, missing observations and finite normalized comparisons require explicit review.'
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--replay-root', type=Path, required=True)
    parser.add_argument('--output-root', type=Path, required=True)
    parser.add_argument('--run', action='append', default=[], help='Explicit LABEL=DIRECTORY override')
    parser.add_argument('--preserved', action='append', default=[], help='LABEL=preserved raw run directory')
    parser.add_argument('--snapshot-receipt', type=Path, required=True)
    args = parser.parse_args()
    selected = dict(supplied(value) for value in args.run)
    receipts = {}
    for file in sorted(args.replay_root.glob('*/receipt.json')):
        receipt = json.loads(file.read_text(encoding='utf-8-sig'))
        label = f"{receipt['producer']}:{receipt['repetition']}"
        if label in receipts:
            raise ValueError(f'Duplicate receipt {label}')
        if not completion_proven(receipt):
            raise ValueError(f'{label} not complete; finalization refused')
        receipts[label] = (file, receipt)
        selected.setdefault(label, file.parent)
    pinned = json.loads(Path(__file__).with_name('frozen-reference.json').read_text())
    fixture_hash = pinned['external_runtime_inputs'][0]['sha256'].lower()
    for label, (_, receipt) in receipts.items():
        if receipt.get('baseline_eligible') is False or receipt.get('constraint_fixture_sha256', '').lower() != fixture_hash:
            raise ValueError(f'{label} runtime overlay not eligible or pinned fixture identity missing/mismatched')
    expected = {f'{producer}:{n}' for producer in ('byond', 'native') for n in (1, 2, 3)}
    if set(receipts) != expected:
        raise ValueError(f'Need six complete receipts; present {sorted(receipts)}')
    for label, directory in map(supplied, args.preserved):
        if label in selected or label.rpartition(':')[2] != 'preserved':
            raise ValueError('Preserved labels must be unique PRODUCER:preserved')
        selected[label] = directory
    out = args.output_root.resolve()
    if out.exists():
        raise ValueError('Use a new output directory; existing evidence is never overwritten')
    if not args.snapshot_receipt.is_file():
        raise ValueError('Frozen snapshot receipt required')
    out.mkdir(parents=True)
    evidence = []
    excluded_logs = []
    command = [sys.executable, str(Path(__file__).with_name('normalize_runtime.py'))]
    for label, source in sorted(selected.items()):
        target = out / 'inputs' / label.replace(':', '-')
        target.mkdir(parents=True)
        files = []
        tests = source / 'unit_tests.json'
        if not tests.is_file():
            raise ValueError(f'Missing tests: {tests}')
        files.append((tests, 'unit_tests.json'))
        structured = list(source.rglob('runtime.log.json'))
        if len(structured) > 1:
            raise ValueError(f'Multiple runtime logs for {label}; supply --run with an unambiguous evidence directory')
        if structured:
            files.append((structured[0], 'runtime.log.json'))
        raw = list(source.rglob('runtime-errors.log'))
        # Runtime mirrors can contain a historical top-level log. Only the
        # sibling of this run's unique structured channel is attributable to
        # the current invocation; never combine inherited events with it.
        selected_raw = [path for path in raw if structured and path.parent == structured[0].parent]
        if structured and len(selected_raw) == 1:
            files.append((selected_raw[0], 'runtime-errors.log'))
            for path in raw:
                if path != selected_raw[0]:
                    excluded_logs.append({'label': label, 'path': str(path),
                                          'bytes': path.stat().st_size, 'sha256': sha256(path),
                                          'reason': 'Not a sibling of the selected run-specific structured log.'})
        elif len(raw) == 1 and not structured:
            files.append((raw[0], 'runtime-errors.log'))
        elif raw and structured:
            raise ValueError(f'No attributable sibling raw runtime log for {label}')
        elif len(raw) > 1:
            raise ValueError(f'Multiple raw runtime logs for {label}')
        for name in ('stdout.log', 'stderr.log'):
            if (source / name).is_file():
                files.append((source / name, name))
        if label in receipts:
            files.append((receipts[label][0], 'receipt.json'))
        for original, name in files:
            destination = target / name
            shutil.copyfile(original, destination)
            evidence.append({'label': label, 'original': str(original), 'copy': str(destination),
                             'bytes': destination.stat().st_size, 'sha256': sha256(destination)})
        command.extend(['--run', f'{label}={target}'])
    snapshot = out / 'snapshot-receipt.json'
    shutil.copyfile(args.snapshot_receipt, snapshot)
    command.extend(['--output', str(out / 'normalized.json')])
    engine_manifest = Path(__file__).with_name('frozen-engine.json')
    pinned_engine = json.loads(engine_manifest.read_text())
    pinned_files = {row['path'].replace('\\', '/').lower(): row['sha256'].lower() for row in pinned_engine['files']}
    closure_coverage = {}
    for label, (_, receipt) in receipts.items():
        audit = receipt.get('engine_closure') or receipt.get('engine_closure_audit')
        if not audit:
            closure_coverage[label] = {'status': 'missing audit', 'prelaunch_proven': False}
            continue
        observed = {row['path'].replace('\\', '/').lower(): str(row.get('sha256', '')).lower() for row in audit.get('files', [])}
        matches = observed == pinned_files and audit.get('matched') is not False
        if audit.get('manifest_sha256') and audit['manifest_sha256'].lower() != sha256(engine_manifest):
            matches = False
        closure_coverage[label] = {'status': 'matched' if matches else 'mismatched',
                                  'phase': audit.get('phase'), 'checked_utc': audit.get('checked_utc'),
                                  'prelaunch_proven': matches and audit.get('phase') == 'before-launch'}
        if not matches:
            raise ValueError(f'{label} engine closure audit mismatches pinned engine')
    exit_outcomes = {}
    for producer in ('byond', 'native'):
        values = [receipts[f'{producer}:{n}'][1]['exit_code'] for n in (1, 2, 3)]
        exit_outcomes[producer] = {'exit_codes': values, 'stable': len(set(values)) == 1,
                                   'variable': len(set(values)) > 1,
                                   'normal_exit_gate_passed': all(value == 0 for value in values)}
    normal_exit_gate = all(value['normal_exit_gate_passed'] for value in exit_outcomes.values())
    manifest = {'normal_exit_gate_passed': normal_exit_gate, 'exit_outcomes': exit_outcomes, 'engine_closure_coverage': closure_coverage, 'pinned_engine_manifest_sha256': sha256(engine_manifest), 'evidence': evidence, 'excluded_logs': excluded_logs, 'snapshot_receipt': str(snapshot),
                'snapshot_sha256': sha256(snapshot), 'normalizer_command': command,
                'receipts': {label: value for label, (_, value) in receipts.items()},
                'seed_policy': 'Preserved compiled seeds; receipt/log observations only, no inferred override.'}
    (out / 'evidence.json').write_text(json.dumps(manifest, indent=2) + '\n')
    subprocess.run(command, check=True)
    report = json.loads((out / 'normalized.json').read_text())
    baseline = preserved_observations(report)
    (out / 'preserved-comparison.json').write_text(json.dumps(baseline, indent=2) + '\n')
    tests = report['test_distributions']
    identities = report['identities']
    counts = {
        'tests': len(tests),
        'new_stable_crosscompiler_divergences': len(baseline['new_crosscompiler_divergences']),
        'dropped_stable_crosscompiler_divergences': len(baseline['dropped_crosscompiler_divergences']), 'missing_tests': sum(row['missing'] for row in tests),
        'stable_test_differences': sum(row['deterministic_difference'] for row in tests),
        'variable_test_observations': sum(row['nondeterministic'] for row in tests),
        'runtime_identities': len(identities),
        'stable_located_runtime_differences': sum(row['selected_channel_deterministic_difference'] for row in identities),
        'variable_runtime_identities': sum(row['nondeterministic'] for row in identities),
    }
    lines = ['# Phase 0 runtime parity observations', '',
             'Six complete result observations (exact selection coverage, suite/shutdown markers); preserved runs included separately.', '',
             f"Normal-exit gate passed: **{normal_exit_gate}**. Completed result data does not erase a terminal crash.",
             f"Exit outcomes: {exit_outcomes}", '',
             f"Engine closure prelaunch proof: {sum(row['prelaunch_proven'] for row in closure_coverage.values())}/6 runs; missing or post-run audits are coverage limitations.", '',
             f"Coverage complete: **{report['comparison_coverage_complete']}**. Equality is **not claimed**.",
             'Normalization is heuristic; counts are observations from three runs, not proof of distribution equivalence.', '',
             '| Observation | Count |', '| --- | ---: |']
    lines.extend(f'| {name.replace("_", " ")} | {count} |' for name, count in counts.items())
    lines.extend(['', 'Every test status, normalized message and runtime-count distribution is in normalized.json.',
                  'preserved-comparison.json checks full multiline messages (same line-wise reference/time/number normalization),',
                  'preserved signature/count absence, stable deviations and variable observations separately.',
                  'An observation outside the three-run range is descriptive, not statistical evidence.',
                  'Selected replay pins the same1089 eligible types; original runs lacked an explicit selection/tier filter.',
                  'Full original test objects and runtime logs remain in inputs/; evidence.json records hashes,',
                  'source-snapshot receipt, engine/pair identities, seed policy and exact normalization invocation.',
                  'Unknown runtime ownership or missing source/procedure coverage is retained explicitly;',
                  'per-test runtime totals are not added to event totals.'])
    (out / 'REPORT.md').write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
