"""Captured-root focused compiler pair using the existing recapture issuer.

Compile-only preparation; runtime-suite consumes the resulting pairs separately.
Matching enumerated source bytes does not establish complete implicit read coverage.
The caller supplies its existing owned-Job launcher and aggregate deadline.
"""
import json
import os
from pathlib import Path
import re
import time
import sys
from recapture_iteration_baseline import (verify_source, file_version, write, sha)
from recover_iteration_source import absolute_nonreparse, regular
import semantic_configuration
from iteration_structural import authenticate_source_snapshot
from focused_pair_results import memory_bytes, observed_record, compare, passing_acceptance


def capture(root, output, byond, native, template, pins, defines, launch, deadline):
    """launch(command,cwd,log,deadline) must bound/reap its owned child tree.

    Both compiler invocations use the SAME authenticated source root and ordered
    defines. Native workers are fixed at two; no daemon or compiler cache is used.
    Output must be a new directory outside the immutable captured source domain.
    """
    root = absolute_nonreparse(Path(root))
    output = Path(os.path.abspath(output))
    absolute_nonreparse(output.parent)
    if not root.is_relative_to(Path('E:/dq-cache')) or not output.is_relative_to(Path('E:/dq-cache')):
        raise ValueError('focused capture roots must stay below E:/dq-cache')
    source = root / 'source'
    if output.exists() or output.is_relative_to(source):
        raise ValueError('focused capture requires new output outside source')
    if not 0 < deadline - time.monotonic() <= 900:
        raise ValueError('focused pair aggregate deadline must be at most 900s')
    for value in defines:
        if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*(?:=.*)?', value):
            raise ValueError('invalid ordered define')
    tools = {'byond': Path(byond), 'native': Path(native), 'template': Path(template)}
    tools = {name: absolute_nonreparse(tool) for name, tool in tools.items()}
    for tool in tools.values():
        regular(tool)
    byond, native, template = (tools[name] for name in ('byond', 'native', 'template'))
    if any(sha(tool, deadline) != pins.get(name) for name, tool in tools.items()):
        raise ValueError('focused compiler/template pin mismatch')
    version = file_version(byond)
    if version != '5.0.516.1687':
        raise ValueError('unsupported pinned BYOND version')
    closure, snapshot_path = root / 'input-closure.json', root / 'source-snapshot.json'
    closure_sha, snapshot_sha = sha(closure, deadline), sha(snapshot_path, deadline)
    snapshot = json.loads(snapshot_path.read_text(encoding='utf-8-sig'))
    authenticate_source_snapshot(snapshot, closure, {'source_closure_manifest_sha256': closure_sha}, sha)
    rows = json.loads(closure.read_text(encoding='utf-8-sig'))
    if {row['path']: row['sha256'] for row in rows if row['tree'] == 'source'} != snapshot['files']:
        raise ValueError('captured snapshot differs from closure')
    verify_source(source, snapshot['files'], deadline)
    output.mkdir(parents=True, exist_ok=False)
    flags = ['-D' + value for value in defines]
    byond_result = launch([str(byond), *flags, 'comparison.dme'], source, output / 'byond.log', deadline)
    if byond_result['exit_code'] != 0 or byond_result['timeout']:
        raise ValueError('focused BYOND compile failed')
    pair = output / 'byond'
    pair.mkdir()
    for suffix in ('.dmb', '.rsc'):
        artifact = source / ('comparison' + suffix)
        byond_result[suffix + '_sha256'] = sha(artifact, deadline)
        artifact.rename(pair / ('world' + suffix))
    byond_result.update(producer='byond', compiler_sha256=pins['byond'])
    verify_source(source, snapshot['files'], deadline)
    args = ['--no-daemon', '--no-cache', '--workers', '2', '--engine-template', str(template),
            '--bootstrap-catalog', '--exact-inputs', '--output-store', str(output / 'store'),
            '--artifact-directory', str(output / 'native'), '--compile-result-file', str(output / 'native-result.json'), *flags]
    native_result = launch([str(native), 'compile', 'comparison.dme', *args], source, output / 'native.log', deadline)
    if native_result['exit_code'] != 0 or native_result['timeout']:
        raise ValueError('focused native compile failed')
    native_result.update(producer='native', compiler_sha256=pins['native'])
    verify_source(source, snapshot['files'], deadline)
    if sha(closure, deadline) != closure_sha or sha(snapshot_path, deadline) != snapshot_sha:
        raise ValueError('captured source authority changed')
    if any(sha(tool, deadline) != pins[name] for name, tool in tools.items()):
        raise ValueError('focused tool changed')
    evidence = output / 'configuration-evidence.json'
    version_path = output / 'byond-version.json'
    write(evidence, [byond_result, native_result])
    write(version_path, {'file_version': version, 'compiler_sha256': pins['byond']})
    configuration, _ = semantic_configuration.command_configuration('comparison.dme', args, sha)
    pin = {'schema': 1, 'snapshot_id': snapshot_sha, 'dmb_sha256': byond_result['.dmb_sha256'],
           'rsc_sha256': byond_result['.rsc_sha256'], 'source_closure_manifest_sha256': closure_sha,
           'semantic_configuration': configuration,
           'configuration_evidence': [{'path': str(evidence), 'sha256': sha(evidence, deadline)}],
           'byond_version_evidence': {'path': str(version_path), 'sha256': sha(version_path, deadline)}}
    semantic_configuration.authenticate_pin(pin, configuration, sha)
    authenticate_source_snapshot(snapshot, closure, pin, sha)
    write(output / 'focused-source-pin.json', pin)
    return {'schema': 1, 'kind': 'focused_same_captured_roster_pair',
            'sourceRosterAuthenticated': True, 'inputClosureAuthenticated': False,
            'implicitCompilerReads': 'unissued', 'acceptedRuntimeBaseline': False,
            'pin': str(output / 'focused-source-pin.json'), 'configuration': configuration,
            'orderedDefines': list(defines), 'sourceRoot': str(source),
            'runtime': 'not run', 'byond': byond_result, 'native': native_result}


def main():
    import argparse
    import subprocess
    from upgrade_owned_job import OwnedJob
    from watchdog import terminate_owned
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepared-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    for name in ('byond', 'native', 'template'):
        parser.add_argument('--' + name, type=Path, required=True)
        parser.add_argument('--' + name + '-sha256', required=True)
    parser.add_argument('--checkout', type=Path, required=True)
    for name in ('bun', 'bash', 'dd'):
        parser.add_argument('--' + name, type=Path, required=True)
        parser.add_argument('--' + name + '-sha256', required=True)
    parser.add_argument('--security', choices=('trusted', 'safe', 'ultrasafe'), required=True)
    parser.add_argument('--define', action='append', default=[])
    parser.add_argument('--focus', action='append', required=True)
    parser.add_argument('--require-snapshot-runtime-abi', action='store_true',
                        help='Decline incoherent captured DM/Rust bindings before compiler launch; not DLL provenance')
    parser.add_argument('--job-memory-mib', type=int, default=4096)
    parser.add_argument('--seconds', type=int, default=900)
    args = parser.parse_args()
    if os.name != 'nt' or not 1 <= args.seconds <= 900:
        raise ValueError('Windows owned Job and aggregate watchdog 1..900 required')
    if any(not re.fullmatch(r'/datum/unit_test/[A-Za-z0-9_/]+', value) for value in args.focus):
        raise ValueError('focus requires exact absolute unit-test paths')
    if 'UNIT_TESTS' not in args.define:
        raise ValueError('focused captured pair requires explicit UNIT_TESTS define')
    pins = {name: getattr(args, name + '_sha256') for name in ('byond', 'native', 'template')}
    if any(not re.fullmatch('[0-9a-f]{64}', value) for value in pins.values()):
        raise ValueError('pins require lowercase SHA256')
    if args.output.exists():
        raise ValueError('focused output must be new; preexisting paths are never owned')
    for name in ('byond', 'native', 'template'):
        setattr(args, name, absolute_nonreparse(getattr(args, name)))
    args.checkout = absolute_nonreparse(args.checkout)
    args.prepared_root = absolute_nonreparse(args.prepared_root)
    args.output = absolute_nonreparse(args.output)
    if args.require_snapshot_runtime_abi:
        from snapshot_runtime_library import preflight
        preflight(args.prepared_root)
    job_bytes = memory_bytes(args.job_memory_mib)
    deadline = time.monotonic() + args.seconds
    job = OwnedJob(memory_bytes=job_bytes)
    child = None
    report = {'schema': 1, 'status': 'preparing', 'focus': args.focus,
              'inputClosureAuthenticated': False, 'runtime': 'not run', 'job_memory_bytes': job_bytes}
    try:
        def launch(command, cwd, log, deadline):
            nonlocal child
            remaining = min(300, deadline - time.monotonic())
            if remaining <= 0:
                raise TimeoutError('focused captured pair watchdog expired')
            started = time.monotonic()
            with log.open('xb') as stream:
                child = subprocess.Popen(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT,
                    creationflags=subprocess.CREATE_NO_WINDOW | 0x00000004)
                job.add(child)
                job.resume(child)
                try:
                    code = child.wait(timeout=remaining)
                except subprocess.TimeoutExpired:
                    cleanup = terminate_owned(child)
                    raise TimeoutError('focused compiler exceeded300s: ' + str(cleanup))
            return {'command': command, 'exit_code': code, 'timeout': False,
                    'seconds': time.monotonic() - started, 'log': str(log), 'reaped': True}
        report.update(capture(args.prepared_root, args.output, args.byond, args.native,
                              args.template, pins, args.define, launch, deadline))
        report['status'] = 'passed'
    except Exception as error:
        report.update(status='failed', error=str(error))
    finally:
        cleanup = job.close()
        report['owned_child_cleanup'] = cleanup
        if not cleanup.get('reaped'):
            report.update(status='failed', error='owned Job failed to reap')
        if args.output.is_dir():
            write(args.output / 'focused-pair-receipt.json', report)
    if report['status'] == 'passed':
        job = OwnedJob(memory_bytes=job_bytes)
        runtime = {'schema': 1, 'status': 'running', 'focus': args.focus,
                   'sourceRosterAuthenticated': True, 'inputClosureAuthenticated': False,
                   'implicitCompilerReads': 'unissued', 'acceptedRuntimeBaseline': False, 'job_memory_bytes': job_bytes}
        try:
            for name in ('bun', 'bash', 'dd'):
                tool = absolute_nonreparse(getattr(args, name))
                regular(tool)
                if sha(tool, deadline) != getattr(args, name + '_sha256'):
                    raise ValueError(name + ' executable pin mismatch')
                setattr(args, name, tool)
            adapter = Path(__file__).with_name('focused_pair_runtime_capture.ts')
            adapted = launch([str(args.bun), str(adapter), str(args.output), sha(args.output / 'focused-pair-receipt.json', deadline)],
                             Path(args.checkout).resolve(strict=True), args.output / 'runtime-adapter.log', deadline)
            if adapted['exit_code'] != 0:
                raise ValueError('focused runtime capture issuer rejected pair')
            captures = {}
            for line in (args.output / 'runtime-adapter.log').read_text(encoding='utf-8-sig').splitlines():
                if line.startswith('{'):
                    row = json.loads(line)
                    if row.get('backend') in ('native', 'byond'):
                        if row['backend'] in captures:
                            raise ValueError('duplicate runtime capture')
                        captures[row['backend']] = row
            if set(captures) != {'native', 'byond'}:
                raise ValueError('runtime capture issuer did not return both pairs')
            suite = Path(__file__).resolve().parent.parent / 'bench/runtime-suite.py'
            runtime['executions'] = {}
            for backend in ('byond', 'native'):
                remaining = min(300, int(deadline - time.monotonic()))
                if remaining < 1:
                    raise TimeoutError('focused runtime aggregate watchdog')
                command = [sys.executable, str(suite), '--checkout', str(args.checkout),
                           '--output', str(args.output / (backend + '-runtime')), '--backend', backend,
                           '--security', args.security, '--workers', '2', '--seconds', str(remaining),
                           '--job-memory-bytes', str(job_bytes),
                           '--focused-compiled-output', captures[backend]['capture'],
                           '--focused-compiled-output-sha256', captures[backend]['sha256']]
                for name in ('bash', 'byond', 'dd'):
                    command += ['--' + name + '-exe', str(getattr(args, name)), '--' + name + '-sha256', getattr(args, name + '_sha256')]
                if backend == 'native':
                    command += ['--native-exe', str(args.native), '--native-sha256', args.native_sha256,
                                '--template', str(args.template), '--template-sha256', args.template_sha256]
                for value in args.define:
                    command += ['--define', value]
                for value in args.focus:
                    command += ['--focus', value]
                result = launch(command, Path(args.checkout).resolve(strict=True), args.output / (backend + '-runtime.log'), deadline)
                runtime['executions'][backend] = result
            verify_source(args.prepared_root / 'source', json.loads((args.prepared_root / 'source-snapshot.json').read_text())['files'], deadline)
            records = {backend: observed_record(args.output / (backend + '-runtime/build.log'), args.checkout, backend,
                       getattr(args, backend + '_sha256'), args.focus, deadline) for backend in ('byond', 'native')}
            runtime['comparison'] = compare(records['byond'], records['native'])
            runtime['parity'] = runtime['comparison']['parity']
            runtime['all_tests_passed'] = passing_acceptance(runtime['comparison'], runtime['executions'])
            runtime['status'] = 'passed' if runtime['parity'] and runtime['all_tests_passed'] else 'failed'
            if not runtime['parity']:
                runtime['error'] = 'observed focused test records or boot cleanliness differ'
            elif not runtime['all_tests_passed']:
                runtime['error'] = 'matching observations do not establish all-tests-pass acceptance'
        except Exception as error:
            runtime.update(status='failed', error=str(error))
        finally:
            runtime['owned_child_cleanup'] = job.close()
            if not runtime['owned_child_cleanup'].get('reaped'):
                runtime['status'] = 'failed'
            write(args.output / 'focused-runtime-pair-receipt.json', runtime)
        report['status'] = runtime['status']
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
