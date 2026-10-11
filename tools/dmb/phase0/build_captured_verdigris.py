"""Ordinary source-pinned Cargo build; root executes only after coherent capture."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import sys
import time
from recapture_iteration_baseline import verify_source, write
from recover_iteration_source import absolute_nonreparse, regular, sha
from snapshot_runtime_library import preflight


def pin(file):
    regular(file)
    return {"path": str(file.resolve()), "sha256": sha(file), "bytes": file.stat().st_size}


def e_directory(value):
    directory = absolute_nonreparse(Path(value))
    if not directory.is_relative_to(Path('E:/')) or not directory.is_dir():
        raise ValueError('requires an existing nonreparse E: dependency directory')
    return directory


def validate_roster(files):
    if any(key == '.dmbc' or key.startswith('.dmbc/') for key in files):
        raise ValueError('prepared source roster includes .dmbc compiler outputs; reissue filtered canonical capture first')
    if 'verdigris/rust-toolchain.toml' not in files or 'verdigris/Cargo.lock' not in files:
        raise ValueError('prepared source roster lacks pinned Rust toolchain/lock inputs')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepared-root', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--target-directory', required=True, type=Path)
    parser.add_argument('--cargo', required=True, type=Path)
    parser.add_argument('--cargo-sha256', required=True)
    parser.add_argument('--cargo-home', type=Path, default=Path('E:/dq-cache/dmb-native-v2/cargo-home'))
    parser.add_argument('--rustup-home', type=Path, default=Path('E:/rustup'))
    args = parser.parse_args()
    if os.name != 'nt':
        raise ValueError('Windows owned Job required')
    root = absolute_nonreparse(args.prepared_root)
    source = root / 'source'
    output = absolute_nonreparse(args.output)
    target = absolute_nonreparse(args.target_directory)
    if output.exists() or target.exists() or not all(p.is_relative_to(Path('E:/dq-cache')) for p in (root, output, target)):
        raise ValueError('requires fresh independent E: output and target paths')
    if target.is_relative_to(source) or output.is_relative_to(source):
        raise ValueError('build output must stay outside captured source')
    cargo = absolute_nonreparse(args.cargo)
    cargo_home = e_directory(args.cargo_home)
    rustup_home = e_directory(args.rustup_home)
    if pin(cargo)['sha256'] != args.cargo_sha256:
        raise ValueError('Cargo pin mismatch')
    abi = preflight(root)
    snapshot = pin(root / 'source-snapshot.json')
    closure = pin(root / 'input-closure.json')
    files = json.loads(Path(snapshot['path']).read_text(encoding='utf-8-sig'))['files']
    validate_roster(files)
    rows = json.loads(Path(closure['path']).read_text(encoding='utf-8-sig'))
    if {row['path']: row['sha256'] for row in rows if row['tree'] == 'source'} != files:
        raise ValueError('captured roster and closure differ')
    deadline = time.monotonic() + 300
    verify_source(source, files, deadline)
    output.mkdir()
    bench = Path(__file__).resolve().parent.parent / 'bench'
    sys.path.insert(0, str(bench))
    spec = importlib.util.spec_from_file_location('captured_build_iteration', bench / 'native-iteration.py')
    h = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(h)
    from upgrade_owned_job import OwnedJob
    job = OwnedJob(4_000_000_000)
    old_job, old_cwd = h._owned_job, Path.cwd()
    old_env = {key: os.environ.get(key) for key in ('CARGO_TARGET_DIR', 'CARGO_BUILD_JOBS',
               'CARGO_HOME', 'RUSTUP_HOME', 'RUSTUP_AUTO_INSTALL', 'CARGO_NET_OFFLINE')}
    command = [str(cargo), 'build', '--locked', '--offline', '-j1', '--release', '--target',
               'i686-pc-windows-msvc', '--package', 'verdigris', '--lib']
    receipt = {'schema': 'captured-verdigris-build-v1', 'command': command,
               'cwd': str(source / 'verdigris'), 'sourceRoot': str(source), 'workers': 1,
               'sourceSnapshotSha256': snapshot['sha256'], 'sourceClosureSha256': closure['sha256'],
               'snapshot': snapshot, 'closure': closure, 'cargo': pin(cargo), 'inputsBefore': files,
               'targetDirectory': str(target), 'abi': abi, 'exit': None, 'timeout': False,
               'bindings': pin(source / 'code/__defines/verdigris/_bindings.dm'),
               'rustAbi': pin(source / 'verdigris/ffi/src/abi.rs'),
               'inputClosureAuthenticated': False, 'child_watchdog_seconds': 300,
               'job_memory_bytes': 4_000_000_000}
    receipt['dependencyEnvironment'] = {'CARGO_HOME': str(cargo_home), 'RUSTUP_HOME': str(rustup_home),
                                       'RUSTUP_AUTO_INSTALL': '0', 'CARGO_NET_OFFLINE': 'true'}
    try:
        h._owned_job = job
        os.environ['CARGO_TARGET_DIR'] = str(target)
        os.environ['CARGO_BUILD_JOBS'] = '1'
        os.environ.update(receipt['dependencyEnvironment'])
        os.chdir(source / 'verdigris')
        child = h.run_child(cargo, command[1:], output / 'cargo', deadline)
        receipt['exit'] = child['exit']
        if child['exit'] != 0:
            raise ValueError('ordinary captured Cargo build failed')
        verify_source(source, files, deadline)
        receipt['inputsAfter'] = files
        receipt['library'] = pin(target / 'i686-pc-windows-msvc/release/verdigris.dll')
        if abi.encode() not in Path(receipt['library']['path']).read_bytes():
            raise ValueError('built library does not carry current generated ABI')
        if pin(cargo) != receipt['cargo'] or pin(root / 'source-snapshot.json') != snapshot or pin(root / 'input-closure.json') != closure:
            raise ValueError('captured build authority changed')
    except Exception as error:
        receipt['error'] = str(error)
        receipt['timeout'] = isinstance(error, TimeoutError)
    finally:
        os.chdir(old_cwd)
        h._owned_job = old_job
        for key, value in old_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        receipt['owned_job_cleanup'] = job.close()
        write(output / 'runtime-build-receipt.json', receipt)
        print(output / 'runtime-build-receipt.json')
    return 0 if receipt['exit'] == 0 and 'error' not in receipt and receipt['owned_job_cleanup'].get('reaped') else 1


if __name__ == '__main__':
    raise SystemExit(main())
