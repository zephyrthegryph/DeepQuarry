#!/usr/bin/env python3
"""Real private daemon proof of Prepare -> Compile original owner reuse.
Addresses are opt-in debug observations, NEVER query or cache authority.
"""
import argparse,json,hashlib
from pathlib import Path
from unified_daemon_smoke import Smoke,json_rows
SOURCE="/datum/reuse_probe\n    var/value=null\n    proc/read()\n        return value\n"
PREFIX='native owner observation: '
def observations(result):
    return [json.loads(line.split(PREFIX,1)[1])for line in result.stderr.splitlines()if PREFIX in line]
def choose(result,phase):
    rows=[row for row in observations(result)if row['phase']==phase];assert len(rows)==1,(phase,result.stderr);return rows[0]
def prepare(smoke,project,engine):
    result=smoke.run(['prepare-query',str(project),'--diagnostic-declarations','--engine-template',str(engine),'--bootstrap-catalog','--workers','2','--exact-inputs','--request-timeout-seconds','45','--policy-inputs-json',json.dumps(smoke.policy_intent)])
    rows=[row for row in json_rows(result.stdout)if row.get('row')=='query_prepared'];assert len(rows)==1 and rows[0]['retained'] is True,result.stdout
    return rows[0],choose(result,'prepared')
def question(project):return {'NativeConfiguredVariableVisibility':{'environment':str(project),'configuration':None}}
def same_program(a,b):
    assert a['tree']==b['tree'] and a['declaration_syntax']==b['declaration_syntax'] and a['query_db']==b['query_db'],(a,b)
    assert a['body_inputs_complete'] and b['body_inputs_complete'] and a['body_inputs_total']==b['body_inputs_total']==1,(a,b)
    assert a['body_inputs']==b['body_inputs'],(a,b)
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--binary',type=Path,required=True);parser.add_argument('--scratch-root',type=Path,required=True);parser.add_argument('--repository',type=Path,required=True);args=parser.parse_args()
    smoke=Smoke(args.binary,args.scratch_root,args.repository);smoke.env['DMB_UNIFIED_TEST_OWNER_TRACE']='1';before=hashlib.sha256(smoke.binary.read_bytes()).hexdigest()
    try:
        root=smoke.root/'fixture';root.mkdir();project=root/'reuse.dme';config=root/'SpacemanDMM.toml';project.write_text(SOURCE,encoding='utf8',newline='\n');engine=smoke.repository/'tools/dmb/fixtures/native_template.bin'
        smoke.policy_intent={'files':[{'path':str(project),'role':'dm_source','required':True},{'path':str(config),'role':'configuration','required':False}],'search_folders':[]}
        pins,first=prepare(smoke,project,engine)
        rows=smoke.query(project,engine,pins,[question(project)]);assert len(rows)==1 and rows[0]['diagnostics']==[],rows
        # The actual checker has now parsed the original body through SAME Db.
        compiled=smoke.run(['compile',str(project),'--engine-template',str(engine),'--bootstrap-catalog','--workers','2','--exact-inputs','--request-timeout-seconds','45','--policy-inputs-json',json.dumps(smoke.policy_intent),'--output-store',str(smoke.root/'pairs'),'--artifact-directory',str(smoke.root/'artifacts')])
        entering=choose(compiled,'frontend');finished=choose(compiled,'compiled_source');same_program(first,entering);same_program(entering,finished)
        assert entering['source_mapping']!=first['source_mapping'],'same original program requires fresh current authority wrapper'
        assert entering['declaration_parsing_seconds']==finished['declaration_parsing_seconds']==0 and entering['tree_resolution_seconds']==finished['tree_resolution_seconds']==0,(entering,finished)
        assert first['native_rebuilds']==entering['native_rebuilds']==finished['native_rebuilds']==1,(first,entering,finished)
        assert entering['body_parser_computed']==finished['body_parser_computed']==1,(entering,finished)
        assert (smoke.root/'artifacts/reuse.dmb').is_file() and (smoke.root/'artifacts/reuse.rsc').is_file(),'real Compile did not produce its indivisible pair'
        # Configuration is a new policy closure, never a second source parser.
        config.write_text("[diagnostics]\nprivate_var='off'\n",encoding='utf8',newline='\n')
        updated,config_owner=prepare(smoke,project,engine);same_program(finished,config_owner)
        assert updated['source_revision']==pins['source_revision'] and updated['semantic_revision']==pins['semantic_revision'] and updated['policy_revision']!=pins['policy_revision'],(pins,updated)
        assert config_owner['native_rebuilds']==1 and config_owner['body_parser_computed']==1 and config_owner['declaration_parsing_seconds']==config_owner['tree_resolution_seconds']==0,config_owner
        assert smoke.query(project,engine,pins,[question(project)],success=False).returncode!=0,'stale policy pin survived current preparation'
        # Real source bytes change: a new original program/graph is required.
        project.write_text(SOURCE.replace('return value','return 123'),encoding='utf8',newline='\n')
        changed,changed_owner=prepare(smoke,project,engine)
        assert changed_owner['tree']!=config_owner['tree'] and changed_owner['declaration_syntax']!=config_owner['declaration_syntax'] and changed_owner['body_inputs']!=config_owner['body_inputs'],(config_owner,changed_owner)
        assert changed_owner['native_rebuilds']==2 and changed['source_revision']!=updated['source_revision'],(updated,changed,changed_owner)
        assert smoke.query(project,engine,updated,[question(project)],success=False).returncode!=0,'stale source pin survived source edit'
        assert hashlib.sha256(smoke.binary.read_bytes()).hexdigest()==before,'private compiler changed during proof'
        print(json.dumps({'test':'actual_ipc_original_prepare_compile_owner_reuse','passed':True,'observations':[first,entering,finished,config_owner,changed_owner],'calls':smoke.calls,'binary_sha256':before,'scope':'unchanged original program and actual resident Same-Db body graph; fresh current acquisitions/policy; not full checker parity'}))
    finally:smoke.retire()
if __name__=='__main__':main()
