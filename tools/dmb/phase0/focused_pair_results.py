"""Exact observed focused rows; timings are excluded from semantic comparison."""
import json
import re
from pathlib import Path
from recover_iteration_source import absolute_nonreparse, regular, sha


def memory_bytes(mib):
    if type(mib) is not int or not 4096 <= mib <= 6144:
        raise ValueError('job-memory-mib must be4096..6144')
    return mib * 1024 * 1024


def observed_record(log, checkout, backend, compiler_sha, focuses, deadline):
    if log.stat().st_size > 16 * 1024 * 1024:
        raise ValueError('focused runtime log exceeds16MiB')
    matches = re.findall(r'\(saved (data/test-runs/[^\s)]+\.json)\)', log.read_text(encoding='utf-8-sig'))
    if len(matches) != 1:
        raise ValueError('focused runtime must issue exactly one test record')
    root = absolute_nonreparse(checkout / 'data/test-runs')
    file = absolute_nonreparse(checkout / matches[0])
    if not file.is_relative_to(root) or file.stat().st_size > 8 * 1024 * 1024:
        raise ValueError('focused result path or size invalid')
    regular(file)
    before = sha(file, deadline)
    value = json.loads(file.read_text(encoding='utf-8-sig'))
    if sha(file, deadline) != before:
        raise ValueError('focused result changed')
    compilation = value.get('compilation', {})
    if (value.get('kind') != 'test' or compilation.get('actualBackend') != backend
            or compilation.get('fallback') is not None
            or compilation.get('compiler', {}).get('sha256') != compiler_sha):
        raise ValueError('focused record does not belong to pinned backend')
    if not set(focuses).issubset(value.get('tests', {})):
        raise ValueError('focused record omitted requested tests')
    return {'path': str(file), 'sha256': before, 'record': value}


def compare(reference, native):
    left, right = reference['record'], native['record']
    if set(left['tests']) != set(right['tests']):
        raise ValueError('observed test roster differs')
    def meaning(row):
        if (row.get('status') not in (0, 1, 2) or type(row.get('runtimes')) is not int
                or not isinstance(row.get('runtime_errors'), list)
                or row.get('runtime_errors_truncated') not in (False, 0)):
            raise ValueError('focused result has incomplete/truncated runtime evidence')
        return {key: row.get(key) for key in ('status', 'name', 'message', 'runtimes', 'runtime_errors')}
    differences = []
    for name in sorted(left['tests']):
        a, b = meaning(left['tests'][name]), meaning(right['tests'][name])
        if a != b:
            differences.append({'name': name, 'byond': a, 'native': b})
    if type(left.get('clean')) is not bool or type(right.get('clean')) is not bool:
        raise ValueError('observed boot cleanliness must be explicit')
    parity = not differences and left['clean'] == right['clean']
    all_passed = (left['clean'] and right['clean']
                  and all(row['status'] == 0 for record in (left, right) for row in record['tests'].values()))
    return {'matches': parity, 'parity': parity, 'all_tests_passed': all_passed,
            'differences': differences, 'byondClean': left.get('clean'), 'nativeClean': right.get('clean'),
            'observedRecords': {'byond': reference, 'native': native},
            'scope': 'exact observed focused rows and boot clean flags; timing excluded; implicit closure unissued'}
