"""Owned Windows build/runtime cohort; result evidence is not source-closure proof.

Uses the repository build entrypoint and existing suite runner, never scans tests.
No invocation occurs on import. All executable/template identities are explicit.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import stat
import sys
import time

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from upgrade_owned_job import OwnedJob

HEX = re.compile(r"^[0-9a-f]{64}$")
COMPILE_SECONDS = 300
COHORT_SECONDS = 1800
JOB_BYTES = 4_000_000_000


def owned_cache_path(value, cache_root=Path('E:/dq-cache')):
    """Resolve containment and reject existing reparse ancestors before creation.

    This is an admission check, not a concurrent hostile-filesystem guarantee.
    No path returned by this helper is recursively deleted by this runner.
    """
    if not value.is_absolute(): raise ValueError('owned cache path must be absolute')
    for candidate in [value, *value.parents, cache_root, *cache_root.parents]:
        try: metadata = candidate.lstat()
        except FileNotFoundError: continue
        if stat.S_ISLNK(metadata.st_mode) or getattr(metadata, 'st_file_attributes', 0) & 0x400:
            raise ValueError('owned cache path has a reparse ancestor')
    resolved = value.resolve(strict=False)
    root = cache_root.resolve(strict=True)
    try: relative = resolved.relative_to(root)
    except ValueError: raise ValueError('owned cache path escaped E:/dq-cache') from None
    if not relative.parts: raise ValueError('owned cache path must be below E:/dq-cache')
    return resolved


def parser():
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument('--checkout', type=Path, required=True)
    value.add_argument('--output', type=Path, required=True, help='new owned E:/dq-cache directory')
    value.add_argument('--backend', choices=['native', 'byond'], required=True)
    for name in ['bash', 'byond', 'dd']:
        value.add_argument('--' + name + '-exe', type=Path, required=True)
        value.add_argument('--' + name + '-sha256', required=True)
    for name in ['native', 'template']:
        value.add_argument('--' + name + '-exe' if name == 'native' else '--template', type=Path)
        value.add_argument('--' + name + '-sha256')
    value.add_argument('--workers', type=int, default=2)
    value.add_argument('--seconds', type=int,
                       help='owned cohort watchdog, 1..1800 seconds; interrupted worlds are excluded')
    value.add_argument('--security', choices=['trusted', 'safe', 'ultrasafe'], required=True)
    value.add_argument('--focus', action='append', default=[])
    value.add_argument('--tier', choices=['normal', 'all', 'exhaustive'])
    value.add_argument('--batch-size', type=int)
    value.add_argument('--resume', type=Path)
    value.add_argument('--resume-sha256')
    value.add_argument('--plan', type=Path)
    value.add_argument('--plan-sha256')
    value.add_argument('--focused-compiled-output', type=Path)
    value.add_argument('--focused-compiled-output-sha256')
    value.add_argument('--suite-compiled-output', type=Path)
    value.add_argument('--suite-compiled-output-sha256')
    value.add_argument('--define', action='append', default=[])
    value.add_argument('--cargo-target', type=Path, help='optional existing owned E:/dq-cache target')
    value.add_argument('--cargo-home', type=Path, help='optional existing owned E:/dq-cache Cargo home')
    return value


def validate(args):
    if args.seconds is None:
        args.seconds = COMPILE_SECONDS if args.suite_compiled_output or args.focused_compiled_output else COHORT_SECONDS
    if not 1 <= args.seconds <= COHORT_SECONDS:
        raise ValueError('cohort seconds must be1..1800')
    suite_replay = bool(args.suite_compiled_output)
    if suite_replay != bool(args.suite_compiled_output_sha256):
        raise ValueError('suite compiled output requires both path and SHA256')
    if suite_replay and (not args.tier or args.focus or args.focused_compiled_output or args.resume or args.resume_sha256 or args.plan or args.plan_sha256):
        raise ValueError('captured suite output requires new inventory; no focus/resume/plan')
    if suite_replay and not HEX.fullmatch(args.suite_compiled_output_sha256 or ''):
        raise ValueError('captured suite output requires lowercase SHA256')
    replay = bool(args.focused_compiled_output)
    if replay != bool(args.focused_compiled_output_sha256):
        raise ValueError('focused compiled output requires both path and SHA256')
    if replay and (not args.focus or args.tier or args.batch_size is not None or args.resume or args.resume_sha256 or args.plan or args.plan_sha256):
        raise ValueError('captured output is focused-only; no tier/batches/resume/plan')
    if replay and not HEX.fullmatch(args.focused_compiled_output_sha256 or ''):
        raise ValueError('captured output requires lowercase SHA256')
    if replay and args.seconds > COMPILE_SECONDS:
        raise ValueError('captured focused output requires overall watchdog <=300 seconds')
    suite = args.tier is not None
    if suite == bool(args.focus):
        raise ValueError('select exactly one of --focus or --tier')
    if suite and (args.batch_size is None or not 1 <= args.batch_size <= 32):
        raise ValueError('suite requires batch-size 1..32')
    if not suite and (args.batch_size is not None or args.resume or args.plan):
        raise ValueError('focused runs cannot have suite plan/resume')
    if args.resume and args.plan:
        raise ValueError('resume and plan are exclusive')
    for name in ['resume', 'plan']:
        if bool(getattr(args, name)) != bool(getattr(args, name + '_sha256')):
            raise ValueError(name + ' requires its explicit SHA256')
    if args.backend == 'native' and not all([args.native_exe, args.native_sha256, args.template, args.template_sha256]):
        raise ValueError('native requires explicit compiler and template pins')
    if args.backend == 'byond' and any([args.native_exe, args.native_sha256, args.template, args.template_sha256]):
        raise ValueError('BYOND does not consume native pins')
    if not 1 <= args.workers <= 8:
        raise ValueError('workers must be1..8')
    if any(not name.startswith('/datum/unit_test/') for name in args.focus):
        raise ValueError('focus must name absolute unit-test paths')
    if any(not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*(?:=.*)?', name) for name in args.define):
        raise ValueError('invalid define')
    return suite


def command(args, suite):
    if not suite and not args.define:
        result = [str(args.bash_exe), 'tools/dq_focused_test.sh', *args.focus]
        if args.focused_compiled_output:
            result += [f'--focused-compiled-output={args.focused_compiled_output}',
                       f'--focused-compiled-output-sha256={args.focused_compiled_output_sha256}']
        return result
    result = [str(args.bash_exe), 'tools/build/build.sh', 'dm-test']
    if suite:
        # Normal aliases preserve historical normal checkpoints/protocol.
        result += [f'--{"normal" if args.tier == "normal" else "suite"}-batches={args.batch_size}', f'--tier={args.tier}']
        if args.resume:
            prefix = 'normal' if args.tier == 'normal' else 'suite'
            result += [f'--{prefix}-resume={args.resume}', f'--{prefix}-resume-sha256={args.resume_sha256}']
        if args.plan:
            result += [f'--normal-plan={args.plan}', f'--normal-plan-sha256={args.plan_sha256}']
    else:
        result += ['--focus=' + ','.join(args.focus)]
        if args.focused_compiled_output:
            result += [f'--focused-compiled-output={args.focused_compiled_output}',
                       f'--focused-compiled-output-sha256={args.focused_compiled_output_sha256}']
    if args.suite_compiled_output:
        result += [f'--suite-compiled-output={args.suite_compiled_output}',
                   f'--suite-compiled-output-sha256={args.suite_compiled_output_sha256}']
    return result + ['-D' + define for define in args.define]


def hash_file(file):
    digest = hashlib.sha256()
    with file.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def pin(file, expected):
    if not file.is_absolute() or not file.is_file() or file.is_symlink() or not HEX.fullmatch(expected or ''):
        raise ValueError('pin requires absolute regular file and lowercase SHA256')
    actual = hash_file(file)
    if actual != expected:
        raise ValueError('pinned bytes differ: ' + str(file))
    return {'path': str(file.resolve()), 'sha256': actual, 'bytes': file.stat().st_size}


def write_receipt(file, receipt):
    temporary = file.with_suffix('.writing')
    temporary.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf8')
    os.replace(temporary, file)


def admitted_compile(captured, args):
    actual = captured.get('compilation')
    if not isinstance(actual, dict) or actual.get('actualBackend') != args.backend or actual.get('requestedBackend') != args.backend or actual.get('fallback') is not None:
        raise ValueError('actual compiler backend differs or fallback occurred')
    expected = args.native_sha256 if args.backend == 'native' else args.byond_sha256
    if actual.get('compiler', {}).get('sha256') != expected:
        raise ValueError('actual compiler differs from explicit pin')
    return actual


def find_compile_receipt(log, checkout, args):
    marker = ':: Compiler attempt evidence: '
    with log.open('rb') as stream:
        stream.seek(max(0, log.stat().st_size - 65536))
        lines = stream.read(65536).decode('utf8', errors='replace').splitlines()
    for line in lines:
        if marker not in line:
            continue
        candidate = Path(line.split(marker, 1)[1].strip())
        if not candidate.is_absolute():
            candidate = checkout / candidate
        candidate = candidate.resolve(strict=True)
        candidate.relative_to((checkout / 'data/compiler-attempts').resolve())
        if candidate.is_symlink() or candidate.stat().st_size > 65536:
            raise ValueError('invalid compiler receipt')
        captured = json.loads(candidate.read_text(encoding='utf8'))
        return str(candidate), admitted_compile(captured, args)
    return None


def preserve_focused_output(args, checkout, receipt, job, env, remaining):
    """Ordinary acquire/stable-copy through existing TS issuers, bounded by caller Job."""
    if remaining <= 0: raise TimeoutError('Cohort expired before output preservation')
    directory = args.output / 'preserved-output'
    attempt = Path(receipt['compile_receipt'])
    expected = hash_file(attempt)
    helper = checkout / 'tools/dmb/bench/preserve_focused_output.ts'
    command = [str(args.bash_exe), '-lc', 'exec bun run "$@"', 'focused-capture', str(helper), str(attempt), expected, str(directory)]
    with (args.output / 'preservation.log').open('xb') as log:
        child = subprocess.Popen(command, cwd=checkout, env=env, stdout=log, stderr=subprocess.STDOUT,
                                 creationflags=subprocess.CREATE_NO_WINDOW | 0x00000004)
        try:
            job.add(child); job.resume(child)
            if child.wait(timeout=min(30, remaining)) != 0: raise ValueError('Focused output preservation failed')
        finally:
            if child.poll() is None: child.kill()
            child.wait(timeout=5)
    if hash_file(attempt) != expected: raise ValueError('Compiler attempt changed during preservation')
    result = directory / 'preservation.json'
    value = json.loads(result.read_text(encoding='utf8'))
    if value.get('sharedInputClosure') is not False: raise ValueError('Invalid preservation closure scope')
    receipt['preserved_output'] = value
    receipt['preservation_receipt'] = pin(result, hash_file(result))


def finalize_code(code, cleanup):
    return 70 if code == 0 and (not cleanup or not cleanup.get('reaped')) else code


def strict_environment(inherited):
    """Copy caller configuration while removing build/admission bypasses."""
    env = dict(inherited)
    for name in ['DQ_PREBUILT_VERDIGRIS', 'DQ_SKIP_VERDIGRIS_ABI_CHECK', 'DQ_WIP_TREE',
                 'DQ_ALLOW_UNREACHABLE_DM', 'DQ_NATIVE_COMPILER', 'DQ_NATIVE_ENGINE_TEMPLATE']:
        env.pop(name, None)
    return env


def main(argv=None):
    args = parser().parse_args(argv)
    suite = validate(args)
    if os.name != 'nt':
        raise ValueError('this owned-job runner requires Windows')
    args.output = owned_cache_path(args.output)
    args.output.mkdir(parents=True, exist_ok=False)
    checkout = args.checkout.absolute()
    log = args.output / 'build.log'
    receipt_file = args.output / 'receipt.json'
    receipt = {'schema': 1, 'kind': 'bounded_runtime_suite', 'status': 'preparing', 'backend': args.backend,
        'tier': args.tier, 'focus': args.focus, 'command': command(args, suite), 'checkout': str(checkout),
        'compilation_performed': not bool(args.focused_compiled_output or args.suite_compiled_output),
        'historical_same_generation': bool(args.focused_compiled_output or args.suite_compiled_output),
        'compile_watchdog_seconds': None if args.focused_compiled_output or args.suite_compiled_output else min(COMPILE_SECONDS, args.seconds), 'dd_watchdog_seconds': 300, 'cohort_watchdog_seconds': args.seconds,
        'inputClosureAuthenticated': False, 'acceptedRuntimeBaseline': False,
        'runner_sha256': hash_file(Path(__file__)), 'log': str(log), 'pins': {}, 'owned_child_cleanup': None}
    write_receipt(receipt_file, receipt)
    child = None
    job = None
    code = 70
    started = time.monotonic()
    try:
        checkout = checkout.resolve(strict=True)
        if not (checkout / 'tools/build/build.sh').is_file(): raise ValueError('checkout has no repository build entrypoint')
        for name in ['bash', 'byond', 'dd']:
            receipt['pins'][name] = pin(getattr(args, name + '_exe'), getattr(args, name + '_sha256'))
        # Runtime lookup is the pinned DreamMaker's sibling, never a PATH fallback.
        if os.path.normcase(str(args.dd_exe.resolve())) != os.path.normcase(str(args.byond_exe.resolve().parent / 'dreamdaemon.exe')):
            raise ValueError('DD must be the pinned DreamMaker sibling dreamdaemon.exe')
        if args.backend == 'native':
            receipt['pins']['native'] = pin(args.native_exe, args.native_sha256)
            receipt['pins']['template'] = pin(args.template, args.template_sha256)
        if args.focused_compiled_output:
            args.focused_compiled_output = owned_cache_path(args.focused_compiled_output)
            receipt['pins']['focused_compiled_output'] = pin(args.focused_compiled_output, args.focused_compiled_output_sha256)
            receipt['command'] = command(args, suite)
        if args.suite_compiled_output:
            args.suite_compiled_output = owned_cache_path(args.suite_compiled_output)
            receipt['pins']['suite_compiled_output'] = pin(args.suite_compiled_output, args.suite_compiled_output_sha256)
            receipt['command'] = command(args, suite)
        for name in ['resume', 'plan']:
            if getattr(args, name):
                receipt['pins'][name] = pin(getattr(args, name), getattr(args, name + '_sha256'))
        if args.resume:
            if args.resume.stat().st_size > 32 * 1024 * 1024: raise ValueError('resume checkpoint exceeds32MiB')
            checkpoint = json.loads(args.resume.read_text(encoding='utf8'))
            admitted_compile(checkpoint, args)
            captured_tier = 'normal' if checkpoint.get('schema') == 1 and checkpoint.get('kind') == 'historical_normal_suite_resume' else checkpoint.get('tier')
            if captured_tier != args.tier: raise ValueError('checkpoint tier differs from requested tier')
        env = strict_environment(os.environ)
        cargo_target = owned_cache_path(args.cargo_target or args.output / 'cargo-target')
        cargo_home = owned_cache_path(args.cargo_home or args.output / 'cargo-home')
        env.update(DQ_COMPILER=args.backend, DM_EXE=str(args.byond_exe), DQ_DD_SECURITY=args.security,
            DQ_DD_WATCHDOG_MINUTES='5', DQ_FOCUS_TIMEOUT_MINUTES='5', BUN_RUNTIME_TRANSPILER_CACHE_PATH='0',
            MSYS2_ARG_CONV_EXCL='--focus=',
            CARGO_BUILD_JOBS='1', CARGO_TARGET_DIR=str(cargo_target), CARGO_HOME=str(cargo_home), DQ_ICON_WORKERS='4')
        receipt['build_configuration'] = {'workers': args.workers if args.backend == 'native' else None,
            'ordered_extra_defines': args.define, 'security': args.security, 'cargo_home': str(cargo_home), 'cargo_target': str(cargo_target)}
        if args.backend == 'native':
            env.update(DQ_NATIVE_COMPILER=str(args.native_exe), DQ_NATIVE_ENGINE_TEMPLATE=str(args.template),
                DQ_NATIVE_WORKERS=str(args.workers), DQ_NATIVE_NO_DAEMON='1', DQ_NATIVE_RUN_ROOT=str(args.output / 'runs'),
                DQ_NATIVE_OUTPUT_STORE=str(args.output / 'store'), DMB_CACHE_DIR=str(args.output / 'cache'))
        spec = importlib.util.spec_from_file_location('suite_error_mode', checkout / 'tools/dmb/fixtures/native/power_retirement_runtime/run.py')
        mode = importlib.util.module_from_spec(spec); spec.loader.exec_module(mode)
        job = OwnedJob(memory_bytes=JOB_BYTES)
        with log.open('xb') as output, mode.hidden_error_mode():
            child = subprocess.Popen(receipt['command'], cwd=checkout, env=env, stdout=output, stderr=subprocess.STDOUT,
                creationflags=subprocess.CREATE_NO_WINDOW | 0x00000004)  # CREATE_SUSPENDED
            job.add(child)
            job.resume(child)
            receipt['status'] = 'running'; receipt['root_pid'] = child.pid
            write_receipt(receipt_file, receipt)
            compilation_complete = bool(args.resume or args.focused_compiled_output or args.suite_compiled_output)
            while True:
                receipt['owned_memory'] = job.memory()
                if not receipt.get('actual_compilation'):
                    captured = find_compile_receipt(log, checkout, args)
                    if captured:
                        receipt['compile_receipt'], receipt['actual_compilation'] = captured
                        compilation_complete = True
                        write_receipt(receipt_file, receipt)
                elapsed = time.monotonic() - started
                if elapsed >= args.seconds or not compilation_complete and elapsed >= COMPILE_SECONDS:
                    code = 124
                    raise TimeoutError('owned cohort or compilation watchdog expired')
                try:
                    code = child.wait(timeout=.2)
                    break
                except subprocess.TimeoutExpired:
                    pass
            if code == 0 and not receipt.get('actual_compilation'):
                captured = find_compile_receipt(log, checkout, args)
                if not captured:
                    raise ValueError('successful build lacks actual compiler evidence')
                receipt['compile_receipt'], receipt['actual_compilation'] = captured
        if code == 0 and args.focus and not args.focused_compiled_output and not args.suite_compiled_output:
            preserve_focused_output(args, checkout, receipt, job, env, args.seconds - (time.monotonic() - started))
        for value in receipt['pins'].values():
            pin(Path(value['path']), value['sha256'])
    except Exception as error:
        receipt['error'] = str(error)
        if code == 0: code = 70
    finally:
        if args.suite_compiled_output and receipt['pins'].get('suite_compiled_output'):
            try:
                owned_cache_path(args.suite_compiled_output)
                pin(args.suite_compiled_output, args.suite_compiled_output_sha256)
            except Exception as error:
                receipt['captured_output_recheck_error'] = str(error)
                if code == 0: code = 70
        if args.focused_compiled_output and receipt['pins'].get('focused_compiled_output'):
            try:
                owned_cache_path(args.focused_compiled_output)
                pin(args.focused_compiled_output, args.focused_compiled_output_sha256)
            except Exception as error:
                receipt['captured_output_recheck_error'] = str(error)
                if code == 0: code = 70
        if job:
            receipt['owned_child_cleanup'] = job.close()
        if child:
            try:
                if child.poll() is None: child.kill()  # Exact Popen handle only, including failed assignment.
                receipt['root_returncode'] = child.wait(timeout=5)
            except Exception as error:
                receipt['owned_child_cleanup'] = {**(receipt['owned_child_cleanup'] or {}), 'reaped': False, 'root_reap_error': str(error)}
        code = finalize_code(code, receipt['owned_child_cleanup'])
        receipt.update(status='completed' if code == 0 else 'failed', exit_code=code, wall_seconds=time.monotonic() - started)
        write_receipt(receipt_file, receipt)
    print(json.dumps(receipt))
    return code


if __name__ == '__main__':
    sys.exit(main())
