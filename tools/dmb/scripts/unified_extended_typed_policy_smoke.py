"""Real native IPC compared with a separately built old Engine.scan oracle.

Findings only cross process boundaries. No model is serialized/reparsed, no
compiler is built/published, and only this test's unique daemon is retired.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess

from unified_daemon_smoke import Smoke

SOURCE = '''/atom
    var/native_policy_value
    var/list/native_policy_items = list()
/atom/proc/Initialize()
    return
/proc/after(owner, delay, handler)
    return
/obj/native_policy/Initialize()
    . = ..()
    after(src, 1, null)
/datum/record/native_policy/proc/business()
    return
/datum/record/native_policy/proc/set_value()
    return
/datum/native_policy_static
    var/static/native_policy_danger
/proc/req_bool(value)
    return value
/proc/native_policy_check(holder)
    req_bool(1)
    holder.native_policy_danger
/mob/native_policy/proc/player_check(mob/P)
    P.key = "player"
/datum/native_policy_implicit
    var/reference
    proc/store(datum/native_policy_implicit/P)
        reference = P
/atom
    var/include_eof_policy_value'''
CONFIG = '''[lint.base_vars.lists]
record_accessor_prefixes = ["get_", "set_"]
'''
ORDER = ['init', 'decl', 'base_vars', 'requirement_bool', 'untyped_member', 'player_link', 'untyped']


def reference(oracle, root):
    flags = subprocess.BELOW_NORMAL_PRIORITY_CLASS if os.name == 'nt' else 0
    run = subprocess.run([str(oracle), str(root), *ORDER], capture_output=True, text=True,
                         timeout=60, creationflags=flags)
    if run.returncode:
        raise RuntimeError(f'independent old engine failed: {run.stdout}\n{run.stderr}')
    value = json.loads(run.stdout)
    assert [row['name'] for row in value] == ORDER
    return value


def observe(smoke, project, engine, pins, root, config):
    # Full untyped's manifest contract selects the ORIGINAL provider key. Read
    # that scalar path from the current native occurrence issuer; do not infer
    # a Windows alias from text equality or reconstruct any semantic model.
    page = smoke.query(project, engine, pins, [{'OccurrencesPage': {'start': 0, 'limit': 1}}])
    assert len(page) == 1 and len(page[0]['items']) == 1, page
    provider_source = Path(page[0]['items'][0]['path'])
    assert provider_source.name == 'compiled.dm' and provider_source.parent.name == 'code', page
    provider_root = provider_source.parent.parent
    if os.name == 'nt' and provider_root != root:
        unissued = smoke.query(project, engine, pins, [{'NativeAnalyzePolicyFixture': {
            'root': str(root), 'configuration': str(config), 'lints': ['untyped'],
        }}], success=False)
        assert unissued.returncode != 0 and 'manifest alias' in unissued.stderr, unissued.stderr
    rows = smoke.query(project, engine, pins, [{'NativeAnalyzePolicyFixture': {
        'root': str(provider_root), 'configuration': str(config), 'lints': list(reversed(ORDER)),
    }}])
    assert len(rows) == 1 and rows[0]['row'] == 'source_native_analyze_policy_fixture', rows
    row = rows[0]
    assert row['full_policy_parity'] is False and row['baseline_applied'] is False, row
    assert row['policy_revision'] == pins['policy_revision'], row
    assert row['requested_lints'] == list(reversed(ORDER)), row
    assert [run['name'] for run in row['results']] == ORDER, row
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--oracle', type=Path, required=True)
    parser.add_argument('--scratch-root', type=Path, required=True)
    parser.add_argument('--repository', type=Path, required=True)
    args = parser.parse_args()
    smoke = Smoke(args.binary, args.scratch_root, args.repository)
    try:
        root = smoke.root / 'source'
        (root / 'code').mkdir(parents=True)
        (root / 'tools/ci').mkdir(parents=True)
        project = root / 'deepquarry.dme'
        source = root / 'code/compiled.dm'
        config = root / 'tools/ci/lint_scopes.toml'
        source.write_text(SOURCE, encoding='utf8', newline='\n')
        project.write_text('#include "code/compiled.dm"\n', encoding='utf8', newline='\n')
        config.write_text(CONFIG, encoding='utf8', newline='\n')
        smoke.policy_intent = {'files': [
            {'path': str(source), 'role': 'dm_source', 'required': True},
            {'path': str(config), 'role': 'configuration', 'required': True},
        ], 'search_folders': [str(root / 'code')]}
        engine = smoke.repository / 'tools/dmb/fixtures/native_template.bin'
        first = smoke.prepare(project, engine)
        expected = reference(args.oracle.resolve(strict=True), root)
        assert all(run['sites'] for run in expected), 'each old policy must have real seeded findings'
        initial = observe(smoke, project, engine, first, root, config)
        assert initial['results'] == expected, {'reference': expected, 'native': initial}
        assert observe(smoke, project, engine, first, root, config) == initial
        config.write_text(CONFIG + '\n[lint.init]\nexempt_files=["code/compiled.dm"]\n'
                          '[lint.decl]\nexempt_files=["code/compiled.dm"]\n'
                          '[lint.base_vars]\nexempt_files=["code/compiled.dm"]\n'
                          '[lint.requirement_bool]\nexempt_files=["code/compiled.dm"]\n'
                          '[lint.untyped_member]\nexempt_files=["code/compiled.dm"]\n'
                          '[lint.player_link]\nexempt_files=["code/compiled.dm"]\n'
                          '[lint.untyped]\nexempt_files=["code/compiled.dm"]\n',
                          encoding='utf8', newline='\n')
        changed = smoke.prepare(project, engine)
        assert changed['source_revision'] == first['source_revision'], 'configuration changed compiler source facts'
        assert changed['policy_revision'] != first['policy_revision'], 'configuration did not change policy pin'
        stale = smoke.query(project, engine, first, [{'NativeAnalyzePolicyFixture': {
            'root': str(root), 'configuration': str(config), 'lints': ORDER,
        }}], success=False)
        assert stale.returncode != 0, 'old configuration receipt remained admitted'
        updated = observe(smoke, project, engine, changed, root, config)
        expected_changed = reference(args.oracle, root)
        assert updated['results'] == expected_changed, {'reference': expected_changed, 'native': updated}
        assert updated['results'] != initial['results'], 'seeded exemption edit had no observable effect'
        # Separate source-only invalidation, with the configuration held fixed.
        config.write_text(CONFIG, encoding='utf8', newline='\n')
        source_before = smoke.prepare(project, engine)
        before_rows = observe(smoke, project, engine, source_before, root, config)
        source.write_text(SOURCE.replace('var/static/native_policy_danger', 'var/native_policy_danger')
                          .replace('/proc/req_bool(value)\n    return value\n', '')
                          .replace('    req_bool(1)\n', '')
                          .replace('        reference = P\n', '        return\n')
                          .replace('    P.key = "player"\n', ''), encoding='utf8', newline='\n')
        source_after = smoke.prepare(project, engine)
        assert source_after['source_revision'] != source_before['source_revision'], 'source edit reused compiler pin'
        assert source_after['policy_revision'] != source_before['policy_revision'], 'source edit reused policy pin'
        source_rows = observe(smoke, project, engine, source_after, root, config)
        expected_source = reference(args.oracle, root)
        assert source_rows['results'] == expected_source, {'reference': expected_source, 'native': source_rows}
        assert source_rows['results'] != before_rows['results'], 'source-only edit did not invalidate findings'
        for name in ['requirement_bool', 'untyped_member', 'player_link', 'untyped']:
            assert not next(row for row in source_rows['results'] if row['name'] == name)['sites'], name
        (smoke.root / 'extended-typed-evidence.json').write_text(json.dumps({
            'initial': initial, 'changed': updated, 'source_changed': source_rows, 'calls': smoke.calls,
            'independent_old_engine': str(args.oracle), 'full_policy_parity': False,
        }, indent=2), encoding='utf8')
    finally:
        smoke.retire()
    print(f'native typed-policy IPC matches independent old Engine.scan for {len(ORDER)} admitted policies')


if __name__ == '__main__':
    main()
