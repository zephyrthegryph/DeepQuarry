"""Actual bounded pool endpoint vs independent frozen original Engine.scan.
No build/publication/model transfer; scratch is supplied by official Rust guard.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tomllib
from unified_daemon_smoke import Smoke

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('binary','oracle','scratch-root','repository'):
        parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args();smoke=Smoke(args.binary,args.scratch_root,args.repository)
    try:
        root=smoke.root/'source'
        shutil.copytree(smoke.repository/'tools/analyze/fixtures/pool-whole',root)
        project=root/'deepquarry.dme';config=root/'tools/ci/lint_scopes.toml'
        roster=tomllib.loads((root/'raw_inputs.toml').read_text(encoding='utf8'))['sources']
        smoke.policy_intent={'files':[{'path':str(root/name),'role':'dm_source','required':True} for name in roster]+[
            {'path':str(config),'role':'configuration','required':True}], 'search_folders':[]}
        flags=subprocess.BELOW_NORMAL_PRIORITY_CLASS if os.name=='nt' else 0
        oracle=subprocess.run([str(args.oracle.resolve(strict=True)),str(root),'--oracle-only'],capture_output=True,
                              text=True,timeout=60,creationflags=flags)
        assert oracle.returncode==0,(oracle.stdout,oracle.stderr)
        expected=json.loads(oracle.stdout)
        assert len(expected)==1 and expected[0]['name']=='pool' and len(expected[0]['sites'])==10,expected
        engine=smoke.repository/'tools/dmb/fixtures/native_template.bin'
        pins=smoke.prepare(project,engine)
        question={'NativeAnalyzePolicyFixture':{'root':str(root),'configuration':str(config),'lints':['pool']}}
        rows=smoke.query(project,engine,pins,[question]);assert len(rows)==1,rows
        row=rows[0]
        assert row['row']=='source_native_analyze_policy_fixture' and row['scope']=='explicit_captured_files',row
        assert row['full_policy_parity'] is False and row['baseline_applied'] is False,row
        assert row['admission']=='native_semantic_findings' and row['results']==expected,(row,expected)
        assert row['policy_revision']==pins['policy_revision'],row
        assert smoke.query(project,engine,pins,[question])==rows
        # A different, uncaptured config cannot gain admission on a warm hit.
        invalid={'NativeAnalyzePolicyFixture':{'root':str(root),'configuration':str(root/'unissued.toml'),'lints':['pool']}}
        assert smoke.query(project,engine,pins,[invalid],success=False).returncode!=0
        assert smoke.query(project,engine,pins,[question])==rows
        (smoke.root/'pool-policy-evidence.json').write_text(json.dumps({'scope':'explicit_fixture_only','row':row,
             'independent_frozen_old':expected,'calls':smoke.calls,'full_workspace_coverage':False},indent=2),encoding='utf8')
    finally:
        smoke.retire()
    print('bounded pool-policy IPC matches independent frozen original Engine.scan; no workspace claim')

if __name__=='__main__':main()
