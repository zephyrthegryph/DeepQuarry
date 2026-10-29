#!/usr/bin/env python3
"""Actual daemon diagnostic profile proof; caller supplies official Rust scratch.
No compiler build/publication, external process killing, or shared namespace.
"""
import argparse,hashlib,json,re
from pathlib import Path
from unified_daemon_smoke import Smoke,json_rows,request
SOURCE="/datum/base\n    var/SpacemanDMM_private/p=null\n/datum/base/child\n    var/p=null\n"
def args(smoke,project,engine,command,diagnostic=False):
    values=[command,str(project),'--engine-template',str(engine),'--bootstrap-catalog','--workers','2','--exact-inputs','--request-timeout-seconds','45','--policy-inputs-json',json.dumps(smoke.policy_intent)]
    if diagnostic:values.append('--diagnostic-declarations')
    if command=='compile':values+=['--output-store',str(smoke.root/'pairs'),'--artifact-directory',str(smoke.root/'artifacts')]
    return values

def prepared(smoke,project,engine):
    result=smoke.run(args(smoke,project,engine,'prepare-query',True));rows=[r for r in json_rows(result.stdout)if r.get('row')=='query_prepared'];assert len(rows)==1 and rows[0]['retained'] is True,result.stdout
    return rows[0]

def question(project,configuration=None):return {'NativeConfiguredVariableVisibility':{'environment':str(project),'configuration':None if configuration is None else str(configuration)}}

def observe(smoke,project,engine,pins,count):
    rows=smoke.query(project,engine,pins,[question(project)]);assert len(rows)==1,rows;row=rows[0];ds=row['diagnostics'];assert len(ds)==count,row
    assert row['declaration_profile']=='native-diagnostic-inherited-variable-v1' and row['native_declaration_error_count']==1,row
    assert row['full_checker_parity'] is False and row['all_source_contexts_supported'] is False,row
    assert ds[0]['registration_tag'] is None and ds[0]['severity']=='error' and ds[0]['origin']['line']==4,ds
    assert 'redeclares var' in ds[0]['message'] and ds[0]['notes'][0]['source']['line']==2,ds
    if count==2:assert ds[1]['registration_tag']=='private_var' and ds[1]['severity']=='error' and ds[1]['origin']['line']==4,ds
    assert row['policy_revision']==pins['policy_revision'] and row['source_revision']==pins['source_revision'],row
    return row

def rejected(result,why):assert result.returncode!=0 and why in result.stderr,(why,result.returncode,result.stdout,result.stderr)
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--binary',type=Path,required=True);parser.add_argument('--scratch-root',type=Path,required=True);parser.add_argument('--repository',type=Path,required=True);a=parser.parse_args()
    smoke=Smoke(a.binary,a.scratch_root,a.repository);before=hashlib.sha256(smoke.binary.read_bytes()).hexdigest()
    try:
        root=smoke.root/'fixture';root.mkdir();project=root/'p.dme';project.write_text(SOURCE,encoding='utf8',newline='\n');config=root/'SpacemanDMM.toml';engine=smoke.repository/'tools/dmb/fixtures/native_template.bin'
        smoke.policy_intent={'files':[{'path':str(project),'role':'dm_source','required':True},{'path':str(config),'role':'configuration','required':False}],'search_folders':[]}
        rejected(smoke.run(args(smoke,project,engine,'prepare-query'),success=False),'duplicate definition')
        pins=prepared(smoke,project,engine);first=observe(smoke,project,engine,pins,2)
        rejected(smoke.query(project,engine,pins,[question(root/'foreign.dme')],success=False),'not an original compiled source')
        rejected(smoke.query(project,engine,pins,[question(project,root/'foreign.toml')],success=False),'configuration')
        rejected(smoke.query(project,engine,pins,[{'SemanticTypesPage':{'start':0,'limit':1}}],success=False),'diagnostic declaration frame admits only')
        foreign=dict(pins,policy_revision='0'*32);rejected(smoke.query(project,engine,foreign,[question(project)],success=False),'policy query revision is stale')
        # A profile can never license Compile, and ordinary Compile still rejects
        # this SAME original source after the checker projection was admitted.
        rejected(smoke.run(args(smoke,project,engine,'compile',True),success=False),'diagnostic_declarations requires')
        rejected(smoke.run(args(smoke,project,engine,'compile'),success=False),'duplicate definition')
        assert observe(smoke,project,engine,pins,2)['diagnostics']==first['diagnostics']
        # Queries are deliberately as-of prepared state, with no live disk mix.
        config.write_text("[diagnostics]\nprivate_var='off'\nvariable_redeclaration='off'\n",encoding='utf8',newline='\n')
        assert observe(smoke,project,engine,pins,2)['diagnostics']==first['diagnostics']
        changed=prepared(smoke,project,engine);assert changed['source_revision']==pins['source_revision'] and changed['semantic_revision']==pins['semantic_revision'] and changed['policy_revision']!=pins['policy_revision'],(pins,changed)
        observe(smoke,project,engine,changed,1);rejected(smoke.query(project,engine,pins,[question(project)],success=False),'policy query revision is stale')
        # Valid selected mode must transfer the SAME frontend once and publish
        # current ordinary query ownership; it must not expose the stale old
        # RetainedSemanticTree.entry left from an earlier compile/prepare.
        project.write_text(SOURCE.replace('    var/p=null','    p=null'),encoding='utf8',newline='\n')
        valid=prepared(smoke,project,engine);valid_rows=smoke.query(project,engine,valid,[question(project)])
        assert len(valid_rows)==1 and valid_rows[0]['declaration_profile']=='strict-native-declarations' and valid_rows[0]['native_declaration_error_count']==0 and valid_rows[0]['diagnostics']==[],valid_rows
        assert smoke.query(project,engine,valid,[{'SemanticTypesPage':{'start':0,'limit':1}}]),'valid consuming transfer did not expose current original type owner'
        rejected(smoke.query(project,engine,changed,[question(project)],success=False),'revision is stale')
        assert hashlib.sha256(smoke.binary.read_bytes()).hexdigest()==before,'private binary changed during IPC proof'
        print(json.dumps({'test':'actual_private_daemon_diagnostic_declarations','passed':True,'original_source':SOURCE,'first_pins':pins,'changed_pins':changed,'first_diagnostics':first['diagnostics'],'calls':smoke.calls,'native_sha256':before,'coverage':'inherited-variable-only; no runtime ABI admission; full checker parity false'}))
    finally:smoke.retire()
if __name__=='__main__':main()
