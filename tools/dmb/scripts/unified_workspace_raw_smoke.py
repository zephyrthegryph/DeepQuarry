"""Prepare once, page exact original-byte raw findings, refresh policy-only changes."""
import argparse,json,os,subprocess
from pathlib import Path
from unified_daemon_smoke import Smoke

def reference(oracle,root):
    flags=subprocess.BELOW_NORMAL_PRIORITY_CLASS if os.name=='nt' else 0
    p=subprocess.run([str(oracle),str(root)],capture_output=True,text=True,timeout=60,creationflags=flags)
    if p.returncode:raise RuntimeError(p.stdout+'\n'+p.stderr)
    return json.loads(p.stdout)

def pages(smoke,project,engine,pins,root,config,names):
    cursor=None;seen=[];aggregate=None;offset=0
    while True:
        question={'NativeWorkspaceRawPolicy':{'root':str(root),'configuration':str(config),'lints':names,'cursor':cursor,'limit':7}}
        rows=smoke.query(project,engine,pins,[question]);assert len(rows)==1,rows
        row=rows[0];assert row['row']=='source_native_workspace_raw_policy' and row['snapshot_as_of']=='policy_revision'
        assert row['policy_revision']==pins['policy_revision'] and row['offset']==offset
        assert row['count']==len(row['items']) and row['count']<=7
        if aggregate is None:aggregate=row['aggregate_id']
        assert aggregate==row['aggregate_id'];seen.extend(row['items']);offset+=row['count']
        cursor=row['next_cursor']
        if cursor is None:assert offset==row['total_items'];break
        assert row['count']>0
    runs=[{'name':name,'sites':[],'allow_used':[],'notes':[]} for name in names]
    by_name={run['name']:run for run in runs}
    for item in seen:
        key,payload={'site':('sites','site'),'allow':('allow_used','allow'),'note':('notes','text')}[item['kind']]
        by_name[item['lint']][key].append(item[payload])
    return runs

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--binary',type=Path,required=True);p.add_argument('--oracle',type=Path,required=True);p.add_argument('--scratch-root',type=Path,required=True);p.add_argument('--repository',type=Path,required=True);a=p.parse_args()
    smoke=Smoke(a.binary,a.scratch_root,a.repository)
    try:
        root=smoke.root/'workspace';(root/'code').mkdir(parents=True);(root/'tools/ci').mkdir(parents=True)
        project=root/'deepquarry.dme';compiled=root/'code/compiled.dm';extra=root/'code/extra.dm';config=root/'tools/ci/lint_scopes.toml'
        project.write_text('#include "code/compiled.dm"\n',encoding='utf8',newline='\n')
        compiled.write_text('/proc/compiled()\n    return\n',encoding='utf8',newline='\n')
        extra.write_bytes(b'// original invalid UTF8: \xff\n/proc/extra()\n' + b'    sleep(1)\n' * 25)
        smoke.policy_intent={'workspace':{'root':str(root),'recursive_roots':[str(root/'code'),str(root/'code/optional')],'configuration':str(config)}}
        engine=smoke.repository/'tools/dmb/fixtures/native_template.bin'
        first=smoke.prepare(project,engine);expected=reference(a.oracle,root);names=[run['name']for run in expected]
        assert any(run['sites']for run in expected),'old raw oracle must have real seeded findings'
        assert pages(smoke,project,engine,first,root,config,names)==expected
        # Disk edits alone do not mix a new raw view into a pinned old compiler.
        extra.write_text('/proc/extra()\n    return\n',encoding='utf8',newline='\n')
        assert pages(smoke,project,engine,first,root,config,names)==expected
        changed=smoke.prepare(project,engine)
        assert changed['source_revision']==first['source_revision'] and changed['semantic_revision']==first['semantic_revision']
        assert changed['policy_revision']!=first['policy_revision']
        q={'NativeWorkspaceRawPolicy':{'root':str(root),'configuration':str(config),'lints':names,'cursor':None,'limit':7}}
        assert smoke.query(project,engine,first,[q],success=False).returncode!=0
        assert pages(smoke,project,engine,changed,root,config,names)==reference(a.oracle,root)
        before=changed
        config.write_text('[lint.scheduler]\nexempt_prefixes=["code/"]\n',encoding='utf8',newline='\n')
        changed=smoke.prepare(project,engine);assert changed['policy_revision']!=before['policy_revision'];assert changed['source_revision']==first['source_revision']
        assert smoke.query(project,engine,before,[q],success=False).returncode!=0
        assert pages(smoke,project,engine,changed,root,config,names)==reference(a.oracle,root)
        before=changed
        (root/'code/optional').mkdir();(root/'code/optional/new.dm').write_text('/proc/new_source()\n    spawn(1)\n        return\n',encoding='utf8',newline='\n')
        changed=smoke.prepare(project,engine);assert changed['policy_revision']!=before['policy_revision'];assert changed['source_revision']==first['source_revision']
        assert smoke.query(project,engine,before,[q],success=False).returncode!=0
        assert pages(smoke,project,engine,changed,root,config,names)==reference(a.oracle,root)
        (smoke.root/'workspace-raw-evidence.json').write_text(json.dumps({'initial':first,'latest':changed,'calls':smoke.calls,'independent_old_engine':str(a.oracle),'whole_semantic_parity':False},indent=2),encoding='utf8')
    finally:smoke.retire()
    print('workspace raw pages match actual old Engine.scan across policy-only refreshes')
if __name__=='__main__':main()
