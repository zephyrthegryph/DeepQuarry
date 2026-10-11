"""Prepare a small descriptor for the existing six-worktree iteration harness; never launch it.

Registration/HEAD agreement is not source closure. The harness must authenticate
the captured roster after isolation before starting its owned daemon.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

from session_acceptance import session_edit_coverage
from worktree_authority import _registrations


def prepare(roots, registrations, options):
    roots = [Path(root).resolve() for root in roots]
    if len(roots) != 6 or len({str(root).casefold() for root in roots}) != 6:
        raise ValueError("six distinct explicit worktree roots required")
    selected = []
    for root in roots:
        if not root.is_relative_to(Path('E:/projects/dq-wt').resolve()):
            raise ValueError("worktrees must be under E:/projects/dq-wt")
        matches = [row for row in registrations if str(Path(row['worktree']).resolve()).casefold() == str(root).casefold()]
        if len(matches) != 1 or 'prunable' in matches[0]:
            raise ValueError(f"registered live worktree required: {root}")
        selected.append(dict(matches[0]))
    if len({row['HEAD'] for row in selected}) != 1:
        raise ValueError("prepare six worktrees at one explicit source revision; foreign differing revisions are not interchangeable")
    pins = {}
    for name in ('edits', 'scenarios', 'source_snapshot', 'input_closure', 'byond_pin', 'build_receipt'):
        file = Path(getattr(options, name)).resolve()
        if file.stat().st_size > 4 * 1024 * 1024:
            raise ValueError(f"bounded preparation JSON exceeded: {name}")
        data = file.read_bytes()
        pins[name] = {'path': str(file), 'sha256': hashlib.sha256(data).hexdigest()}
        json.loads(data)
    coverage = session_edit_coverage(json.loads(Path(options.edits).read_text(encoding='utf8')), len(roots))
    argv = [sys.executable, str(Path(__file__).with_name('native-iteration.py'))]
    for name in ('compiler', 'inspector', 'template', 'byond_dmb', 'byond_pin', 'build_receipt', 'edits', 'scenarios', 'source_snapshot', 'input_closure'):
        argv.extend(['--' + name.replace('_', '-'), str(Path(getattr(options, name)).resolve())])
    argv.extend(['--worktree-sources', str(Path(options.output).resolve() / 'worktrees.json'),
                 '--workers', '2', '--total-workers', '2', '--require-owned-daemon',
                 '--byte-oracles-only', '--overall-seconds', '1800',
                 '--owned-memory-budget-bytes', '4000000000'])
    return {'schema': 'dm-six-worktree-preparation-v1', 'status': 'prepared_not_executed',
            'worktrees': selected, 'inputs': pins, 'required_edit_coverage': coverage,
            'argv': argv, 'captured_source_authenticated': False,
            'scope': 'registered same-HEAD roots and shared edit-assignment admission only; classification describes requested coverage, not executed acceptance'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkout', required=True)
    parser.add_argument('--root', action='append', required=True)
    parser.add_argument('--output', required=True, help='new small descriptor directory under E:/dq-cache')
    for name in ('compiler', 'inspector', 'template', 'byond-dmb', 'byond-pin', 'build-receipt', 'edits', 'scenarios', 'source-snapshot', 'input-closure'):
        parser.add_argument('--' + name, required=True)
    options = parser.parse_args()
    output = Path(options.output).resolve()
    if not output.is_relative_to(Path('E:/dq-cache').resolve()) or output.exists():
        raise ValueError('new owned E:/dq-cache descriptor directory required')
    environment = {key: value for key, value in os.environ.items() if not key.upper().startswith('GIT_')}
    result = subprocess.run(['git', '-C', options.checkout, 'worktree', 'list', '--porcelain', '-z'],
                            capture_output=True, timeout=10, check=True, env=environment,
                            creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
    if len(result.stdout) > 1024 * 1024:
        raise ValueError('worktree registration output exceeded bound')
    descriptor = prepare(options.root, _registrations(result.stdout.decode('utf8')), options)
    output.mkdir(parents=True)
    (output / 'worktrees.json').write_text(json.dumps([row['worktree'] for row in descriptor['worktrees']], indent=2), encoding='utf8')
    (output / 'preparation.json').write_text(json.dumps(descriptor, indent=2), encoding='utf8')
    print(json.dumps({'descriptor': str(output / 'preparation.json'), 'status': descriptor['status']}))


if __name__ == '__main__':
    main()
