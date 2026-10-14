"""Owned paired current-game diagnostic; not full input closure or runtime acceptance."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import socket
import sys
import time
import uuid
from urllib.parse import urlencode

HERE = Path(__file__).resolve().parent
BENCH = HERE.parents[2] / 'bench'
sys.path.insert(0, str(BENCH))
from upgrade_owned_job import OwnedJob


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def admit_runtime(result, queue, rows, focus, log):
    # The pinned Windows frontend returned different small codes for identical
    # orderly failure shutdowns. Exact issued products authorize diagnostics,
    # never the code alone; NTSTATUS crashes are outside this bounded range.
    if type(result['exit']) is not int or not 0 <= result['exit'] <= 65535:
        raise ValueError('unexpected runtime exit; not an ordinary test failure')
    if re.search(r'runtime error:|Runtime in .+?\.dm,\d+:|unhandled exception|access violation|fatal error', log, re.IGNORECASE):
        raise ValueError('runtime log contains a crash or runtime error')
    if result['exit'] != 0 and not all(marker in log for marker in ('Shutdown complete', 'Test run failed!', 'Unit Tests failed!')):
        raise ValueError('nonzero runtime exit lacks orderly test-failure shutdown evidence')
    order = list(rows)
    automatic = 'ownership_framework_checks'
    if not order or order[0] != focus[0] or set(order) != set(focus) | {automatic}:
        raise ValueError('runtime did not issue exact requested tests with diagnostic first')
    if not queue.get('queue_scan_complete') or not queue.get('map_scan_complete'):
        raise ValueError('diagnostic scan incomplete')
    expected_failures = set(focus[1:3])
    failures = set()
    for name, row in rows.items():
        if row.get('name') != name or row.get('status') not in (0, 1) or row.get('runtimes') != 0 or row.get('runtime_errors') or row.get('runtime_errors_truncated'):
            raise ValueError('runtime row missing, skipped, or has runtime errors: ' + name)
        if row['status'] == 1:
            failures.add(name)
    if failures != expected_failures:
        raise ValueError('runtime failures differ from the explicit paired baseline')
    return order


def admit_reference_pins(prior, current):
    """Pinned receipt evidence must identify an actually completed BYOND child.

    The prior native/template pins were preparation context, not BYOND inputs.
    Current native/template pins are independently authenticated by the caller.
    """
    if (prior.get('executions', {}).get('byond-compile', {}).get('exit') != 0
            or not isinstance(prior.get('byond', {}).get('diagnostic'), dict)
            or not isinstance(prior.get('byond', {}).get('results'), dict)):
        raise ValueError('prior reference lacks actual BYOND compilation/runtime evidence')
    previous = prior.get('pinned_inputs', {})
    for name in ('dm', 'dd', 'library'):
        if not isinstance(previous.get(name), dict) or previous[name] != current.get(name):
            raise ValueError('prior BYOND/runtime consumed pins differ: ' + name)
    return {'prior_native_context': previous.get('native'), 'current_native': current.get('native'),
            'native_compiler_changed': previous.get('native') != current.get('native'),
            'scope': 'BYOND reference reused; native compiler independently pinned for this comparison'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--checkout', type=Path, required=True)
    p.add_argument('--output-root', type=Path, required=True)
    p.add_argument('--source-roster', type=Path, required=True, help='JSON array of {path: checkout-relative, sha256}; positive roster only')
    p.add_argument('--source-roster-sha256', required=True)
    p.add_argument('--generated-ready', action='store_true', required=True, help='analyze gen already completed through build entry point')
    p.add_argument('--prior-reference', type=Path, help='preserved prior diagnostic receipt; admitted anew, never rewritten')
    p.add_argument('--prior-reference-sha256')
    for name in ('native', 'template', 'dm', 'dd', 'library'):
        p.add_argument('--' + name, type=Path, required=True)
        p.add_argument('--' + name + '-sha256', required=True)
    a = p.parse_args()
    if bool(a.prior_reference) != bool(a.prior_reference_sha256):
        raise ValueError('prior reference requires exact receipt SHA')
    h = load('refresh_iteration', BENCH / 'native-iteration.py')
    fresh = load('refresh_fresh', BENCH / 'native-fresh.py')
    core = load('refresh_core', HERE.parent / 'power_retirement_runtime/run.py')
    checkout = h.safe_e(a.checkout).resolve(strict=True)
    parent = h.safe_e(a.output_root).resolve()
    if not parent.is_relative_to(Path('E:/dq-cache').resolve()):
        raise ValueError('owned E cache output required')
    parent.mkdir(parents=True, exist_ok=True)
    root = parent / uuid.uuid4().hex
    root.mkdir()
    receipt = {'schema': 1, 'scope': __doc__, 'complete': False, 'inputClosureAuthenticated': False,
               'executions': {}, 'root': str(root), 'defines': ['CBT', 'CIBUILDING', 'CITESTING', 'DEBUG']}
    job = None
    owned_manifest = None
    owned_manifest_hash = None
    owned_manifest_name = None
    old_cwd = Path.cwd()
    old_job = h._owned_job
    deadline = time.monotonic() + 1230
    try:
        for name in ('native', 'template', 'dm', 'dd', 'library'):
            file = getattr(a, name).resolve(strict=True)
            h.regular(file)
            expected = getattr(a, name + '_sha256')
            if h.sha(file) != expected:
                raise ValueError('pin mismatch: ' + name)
            setattr(a, name, file)
            core.record_pin(receipt, name, file, expected)
        if a.library != (checkout / 'verdigris.dll').resolve(strict=True):
            raise ValueError('runtime library must be the actual current checkout DLL used by -cd')
        if h.sha(a.source_roster) != a.source_roster_sha256 or a.source_roster.stat().st_size > 4 * 1024 * 1024:
            raise ValueError('bounded source roster pin mismatch')
        roster = json.loads(a.source_roster.read_text(encoding='utf8'))
        if not isinstance(roster, list) or not 1 <= len(roster) <= 50000:
            raise ValueError('bounded source roster required')
        def validate_sources():
            for row in roster:
                relative = Path(row['path'])
                file = (checkout / relative).resolve(strict=True)
                if relative.is_absolute() or not file.is_relative_to(checkout):
                    raise ValueError('source roster escape')
                h.regular(file)
                if h.sha(file) != row['sha256']:
                    raise ValueError('source roster changed: ' + row['path'])
        validate_sources()
        receipt['positive_source_roster_sha256'] = a.source_roster_sha256
        abi = re.search(r'#define VERDIGRIS_ABI "([0-9a-f]+)"', (checkout / 'code/__defines/verdigris/_bindings.dm').read_text())
        if not abi or abi.group(1).encode() not in a.library.read_bytes():
            raise ValueError('current generated Verdigris ABI mismatch')
        manifest_id = root.name
        if a.prior_reference:
            if h.sha(a.prior_reference) != a.prior_reference_sha256:
                raise ValueError('prior reference receipt changed before manifest creation')
            manifest_id = a.prior_reference.resolve().parent.name
            if not re.fullmatch('[0-9a-f]{32}', manifest_id):
                raise ValueError('prior reference owned manifest identity malformed')
        manifest = checkout / ('.dq-refresh-probe-' + manifest_id + '.dme')
        with manifest.open('x', encoding='utf8') as writer:
            writer.write('#include "' + str(checkout / 'deepquarry.dme').replace('\\', '/') + '"\n#include "' + str(HERE / 'probe.dm').replace('\\', '/') + '"\n')
        owned_manifest = manifest
        owned_manifest_name = manifest.name
        owned_manifest_hash = h.sha(manifest)
        shutil.copyfile(manifest, root / 'derived-manifest.dme')
        protected = {str(file): h.sha(file) for file in (manifest, HERE / 'probe.dm', checkout / 'deepquarry.dme', checkout / 'code/__defines/verdigris/_bindings.dm')}
        receipt['protected_files'] = protected
        focus = ['/datum/unit_test/dq_refresh_queue_diagnostic'] + [
            '/datum/unit_test/' + name for name in ('dq_service_real_machine_and_pda_lifecycle', 'dq_lifecycle_sandbox/representative',
            'dq_damage_flavour_bands', 'mech_construction', 'dq_body_factor_combine_math', 'dq_verdigris_loaded', 'type_list_cached_per_type', 'dq_boot_bind_power_machines')]
        focus_file = root / 'focus.txt'
        focus_file.write_text('\n'.join(focus) + '\n')
        receipt['requested_focus_order'] = focus
        if a.prior_reference:
            if h.sha(a.prior_reference) != a.prior_reference_sha256:
                raise ValueError('prior reference receipt changed')
            prior = fresh.read_json(a.prior_reference, 4 * 1024 * 1024)
            if not prior.get('owned_cleanup', {}).get('reaped') or prior.get('positive_source_roster_sha256') != a.source_roster_sha256 or prior.get('requested_focus_order') != focus or prior.get('defines') != receipt['defines'] or prior.get('executions', {}).get('byond-compile', {}).get('exit') != 0:
                raise ValueError('prior reference is not reaped matching current positive source/configuration')
            compiler_comparison = admit_reference_pins(prior, receipt['pinned_inputs'])
            prior_root = a.prior_reference.resolve().parent
            if prior.get('protected_files', {}).get(str(manifest)) != owned_manifest_hash:
                raise ValueError('prior manifest exact path/bytes differ')
            if h.sha(prior_root / 'derived-manifest.dme') != owned_manifest_hash:
                raise ValueError('preserved manifest bytes differ')
            for file in (HERE / 'probe.dm', checkout / 'deepquarry.dme', checkout / 'code/__defines/verdigris/_bindings.dm'):
                if prior.get('protected_files', {}).get(str(file)) != h.sha(file):
                    raise ValueError('prior reference source binding changed')
            queue = fresh.read_json(prior_root / 'byond/runtime/queue.json', 4 * 1024 * 1024)
            rows = fresh.read_json(prior_root / 'byond/runtime/results.json', 4 * 1024 * 1024)
            if queue != prior.get('byond', {}).get('diagnostic') or rows != prior.get('byond', {}).get('results'):
                raise ValueError('prior reference products differ from pinned receipt')
            log_file = prior_root / 'byond/runtime/probe.log'
            raw = log_file.read_bytes()
            if len(raw) > 16 * 1024 * 1024:
                raise ValueError('prior log exceeds bound')
            log = raw.decode('utf-16' if raw.startswith((b'\xff\xfe', b'\xfe\xff')) else 'utf-8-sig')
            order = admit_runtime(prior['executions']['byond-runtime'], queue, rows, focus, log)
            # Authenticate the preserved compiler products now, without claiming
            # the old failed receipt had a previously absent output-hash field.
            products = list((prior_root / 'checkout-products').glob('*.dmb'))
            if len(products) != 1 or products[0].stem != '.dq-refresh-probe-' + prior_root.name:
                raise ValueError('prior uniquely owned compiled products unavailable')
            products.append(products[0].with_suffix('.rsc'))
            for file in products:
                h.regular(file)
            receipt['prior_reference'] = {'receipt': str(a.prior_reference.resolve()), 'sha256': a.prior_reference_sha256,
                'compiler_comparison': compiler_comparison,
                'admission': 'current revalidation of preserved products; original receipt unchanged',
                'product_hashes_at_admission': {str(file): h.sha(file) for file in products}, 'log_sha256': h.sha(log_file)}
            receipt['byond'] = {**prior['byond'], 'actual_test_order': order}
        job = OwnedJob(4_000_000_000)
        h._owned_job = job
        os.chdir(checkout)
        def run(label, executable, arguments, runtime=False):
            with core.hidden_error_mode():
                result = h.run_child(executable, arguments, root / label, min(deadline, time.monotonic() + 300), cache_directory=root / 'cache')
            receipt['executions'][label] = result
            if not runtime and result['exit'] != 0:
                raise ValueError(label + ' failed')
            return result
        defines = ['-D' + value for value in receipt['defines']]
        for backend in ('byond', 'native'):
            if backend == 'byond' and a.prior_reference:
                continue
            output = root / backend
            output.mkdir()
            if backend == 'byond':
                run('byond-compile', a.dm, [*defines, str(manifest)])
                if not re.search(r'\b516\.1687\b', (root / 'byond-compile/stdout.log').read_text(encoding='utf-8-sig')):
                    raise ValueError('BYOND version banner mismatch')
                pair = {ext: str(manifest.with_suffix('.' + ext)) for ext in ('dmb', 'rsc')}
            else:
                run('native-compile', a.native, ['compile', str(manifest), *defines, '--workers', '2', '--engine-template', str(a.template), '--bootstrap-catalog', '--no-daemon', '--no-cache', '--exact-inputs', '--artifact-directory', str(output / 'artifacts'), '--output-store', str(output / 'store'), '--compile-result-file', str(output / 'compile.json')])
                result = fresh.read_json(output / 'compile.json', 65536)
                run('native-acquire', a.native, ['acquire', '--output-store', str(output / 'store'), '--pair-id', result['pair_id'], '--slots', str(output / 'slots'), '--result-file', str(output / 'acquired.json')])
                pair = fresh.read_json(output / 'acquired.json', 65536)
                fresh.admit_pair(result, pair, output / 'artifacts' / manifest.name, output / 'store', output / 'slots', h.regular, h.sha)
                receipt['native_pair'] = result
            runtime = output / 'runtime'
            runtime.mkdir()
            for ext in ('dmb', 'rsc'):
                shutil.copyfile(pair[ext], runtime / ('probe.' + ext))
            shutil.copyfile(a.library, runtime / 'verdigris.dll')
            if h.sha(runtime / 'verdigris.dll') != a.library_sha256:
                raise ValueError('runtime DLL copy mismatch')
            compiled_hashes = {ext: h.sha(Path(pair[ext])) for ext in ('dmb', 'rsc')}
            stored_hashes = {}
            if backend == 'native':
                for ext in ('dmb', 'rsc'):
                    stored = output / 'store/pairs' / result['pair_id'] / ('deepquarry.' + ext)
                    stored_hashes[str(stored)] = h.sha(stored)
                    if stored_hashes[str(stored)] != compiled_hashes[ext]:
                        raise ValueError('store/acquisition mismatch before runtime')
            params = {'test-focus': str(focus_file), 'unit-tests-file': str(runtime / 'results.json'),
                      'test-exact-automatic-rows': '1',
                      'refresh-diagnostic-file': str(runtime / 'queue.json'), 'log-directory': 'refresh-' + root.name + '-' + backend,
                      'spritesheet-dir': str(runtime / 'spritesheets') + '/'}
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
                listener.bind(('127.0.0.1', 0))
                port = listener.getsockname()[1]
            # Port selection is sampled, not a reservation; bind failure remains a failed run.
            execution = run(backend + '-runtime', a.dd, [str(runtime / 'probe.dmb'), str(port), '-close', '-trusted', '-invisible', '-logself', '-cd', str(checkout), '-params', urlencode(params)], runtime=True)
            receipt[backend] = {'diagnostic': fresh.read_json(runtime / 'queue.json', 4 * 1024 * 1024), 'results': fresh.read_json(runtime / 'results.json', 4 * 1024 * 1024), 'port': port}
            log = runtime / 'probe.log'
            if log.stat().st_size > 16 * 1024 * 1024:
                raise ValueError('runtime log exceeds diagnostic bound')
            raw_log = log.read_bytes()
            text = raw_log.decode('utf-16' if raw_log.startswith((b'\xff\xfe', b'\xfe\xff')) else 'utf-8-sig')
            receipt[backend]['actual_test_order'] = admit_runtime(execution, receipt[backend]['diagnostic'], receipt[backend]['results'], focus, text)
            for ext, expected in compiled_hashes.items():
                if h.sha(Path(pair[ext])) != expected:
                    raise ValueError('compiled/acquired pair changed during runtime')
            for file, expected in stored_hashes.items():
                if h.sha(Path(file)) != expected:
                    raise ValueError('immutable store pair changed during runtime')
            for file in (a.library, runtime / 'verdigris.dll'):
                if h.sha(file) != a.library_sha256:
                    raise ValueError('runtime library changed')
            receipt[backend]['compiled_hashes'] = compiled_hashes
            validate_sources()
        for file, expected in protected.items():
            if h.sha(Path(file)) != expected:
                raise ValueError('protected input changed')
        if h.sha(a.source_roster) != a.source_roster_sha256:
            raise ValueError('source roster changed')
        if a.prior_reference:
            if h.sha(a.prior_reference) != a.prior_reference_sha256:
                raise ValueError('prior receipt changed during native run')
            for file, expected in receipt['prior_reference']['product_hashes_at_admission'].items():
                if h.sha(Path(file)) != expected:
                    raise ValueError('preserved reference pair changed')
        for name in ('native', 'template', 'dm', 'dd', 'library'):
            if h.sha(getattr(a, name)) != getattr(a, name + '_sha256'):
                raise ValueError('pinned input changed')
        receipt['complete'] = True
    except Exception as error:
        receipt['error'] = str(error)
    finally:
        if job is not None:
            receipt['owned_cleanup'] = job.close()
            if not receipt['owned_cleanup'].get('reaped'):
                receipt['complete'] = False
                receipt.setdefault('error', 'owned job cleanup did not prove reaping')
        if owned_manifest is not None and (job is None or receipt.get('owned_cleanup', {}).get('reaped')):
            try:
                if owned_manifest.parent != checkout or owned_manifest.name != owned_manifest_name or not re.fullmatch(r'\.dq-refresh-probe-[0-9a-f]{32}\.dme', owned_manifest.name) or h.sha(owned_manifest) != owned_manifest_hash:
                    raise ValueError('owned manifest cleanup authority changed')
                preserved = root / 'checkout-products'
                preserved.mkdir()
                for extension in ('dmb', 'rsc', 'dmb-pair.json'):
                    file = owned_manifest.with_suffix('.' + extension)
                    if file.exists():
                        h.regular(file)
                        shutil.copyfile(file, preserved / file.name)
                        if h.sha(file) != h.sha(preserved / file.name):
                            raise ValueError('owned output changed during preservation')
                        file.unlink()
                owned_manifest.unlink()
                receipt['owned_checkout_cleanup'] = {'removed': True}
            except Exception as error:
                receipt['complete'] = False
                receipt['owned_checkout_cleanup'] = {'removed': False, 'error': str(error)}
        h._owned_job = old_job
        os.chdir(old_cwd)
        (root / 'receipt.json').write_text(json.dumps(receipt, indent=2), encoding='utf8')
    return 0 if receipt['complete'] else 1


if __name__ == '__main__':
    sys.exit(main())
