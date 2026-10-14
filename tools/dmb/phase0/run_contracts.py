"""Capture pinned reference/native contract fixtures without opening GUI windows."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def run(command, cwd, log, timeout):
    started = time.perf_counter()
    flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
    with log.open('wb') as stream:
        try:
            process = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT,
                                     timeout=timeout, creationflags=flags)
            return {'exit_code': process.returncode, 'seconds': time.perf_counter()-started,
                    'timed_out': False, 'command': [str(x) for x in command], 'log': str(log)}
        except subprocess.TimeoutExpired:
            return {'exit_code': None, 'seconds': time.perf_counter()-started,
                    'timed_out': True, 'command': [str(x) for x in command], 'log': str(log)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--fixtures', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--dreammaker', type=Path, required=True)
    parser.add_argument('--dreamdaemon', type=Path, required=True)
    parser.add_argument('--compiler', type=Path)
    parser.add_argument('--builtins', type=Path)
    parser.add_argument('--case', action='append', default=[], help='Select explicit case identifiers')
    parser.add_argument('--observe-preprocess', action='store_true', help='Run optional value-observation wrappers')
    args = parser.parse_args()
    if args.output.exists():
        parser.error('output must be a new directory; prior evidence is never overwritten')
    args.output.mkdir(parents=True)
    if os.name == 'nt':
        ctypes.windll.kernel32.SetErrorMode(3)
    cases = []
    for group in ('preprocess', 'link'):
        manifest = json.loads((args.fixtures/group/'manifest.json').read_text())
        for case in manifest['cases']:
            root = case.get('root', case.get('manifest'))
            if root:
                cases.append((group, root, case))
    results = []
    for group, root, case in cases:
        name = group+'-'+case.get('id', Path(root).stem)
        if args.case and name not in args.case:
            continue
        observe = group == 'preprocess' and args.observe_preprocess and bool(case.get('runtime_manifest'))
        if observe:
            root = case['runtime_manifest']
        runtime_case = group == 'link' or observe
        capture_name = 'phase0-preprocess.json' if observe else 'phase0-link.json'
        work = args.output/name
        shutil.copytree(args.fixtures/group, work/'source', ignore=shutil.ignore_patterns(
            '*.dmb', '*.rsc', '*.log', 'phase0-link.json'))
        source = work/'source'/root
        record = {'case': name, 'source': str(source), 'source_sha256': sha(source),
                  'expected_compile_error': case.get('expected_compile_error', case.get('id') == 'diagnostics')}
        compile_result = run([str(args.dreammaker), str(source)], source.parent,
                             work/'byond-compile.log', 60)
        record['byond_compile'] = compile_result
        record['reference_compile_outcome_matches'] = (
            not compile_result['timed_out'] and
            (compile_result['exit_code'] != 0) == record['expected_compile_error'])
        if compile_result['exit_code'] == 0 and runtime_case:
            record['byond_runtime'] = run([str(args.dreamdaemon), str(source.with_suffix('.dmb')),
                                          '0', '-trusted', '-close'], source.parent,
                                         work/'byond-runtime.log', 30)
            capture = source.parent/capture_name
            if capture.exists():
                shutil.copy2(capture, work/'byond-observations.json')
            record['reference_runtime_capture_complete'] = (
                record['byond_runtime']['exit_code'] == 0 and
                not record['byond_runtime']['timed_out'] and capture.exists())
        if args.compiler:
            if not args.builtins:
                parser.error('--builtins is required with --compiler')
            output = work/'native'
            record['native_compile'] = run([str(args.compiler), 'build-project', str(source),
                                            str(args.builtins), str(output)], source.parent,
                                           work/'native-compile.log', 60)
            if record['native_compile']['exit_code'] == 0 and runtime_case:
                identity = (output/'HEAD').read_text().strip().splitlines()[-1]
                generation = output/'generations'/identity
                slot = work/'native-slot'
                shutil.copytree(source.parent, slot)
                shutil.copy2(generation/'world.dmb', slot/'world.dmb')
                shutil.copy2(generation/'world.rsc', slot/'world.rsc')
                (slot/capture_name).unlink(missing_ok=True)
                record['native_runtime'] = run([str(args.dreamdaemon), str(slot/'world.dmb'),
                                               '0', '-trusted', '-close'], slot,
                                              work/'native-runtime.log', 30)
                capture = slot/capture_name
                if capture.exists():
                    shutil.copy2(capture, work/'native-observations.json')
                    if (work/'byond-observations.json').exists():
                        record['observations_equal'] = json.loads(capture.read_text()) == json.loads(
                            (work/'byond-observations.json').read_text())
                record['native_runtime_capture_complete'] = (
                    record['native_runtime']['exit_code'] == 0 and
                    not record['native_runtime']['timed_out'] and capture.exists())
        results.append(record)
        (args.output/'results.json').write_text(json.dumps(results, indent=2))
        print(name, json.dumps(record.get('observations_equal')), flush=True)
    (args.output/'tools.json').write_text(json.dumps({str(path): sha(path) for path in
        (args.dreammaker, args.dreamdaemon, args.compiler) if path}, indent=2))


if __name__ == '__main__':
    main()
