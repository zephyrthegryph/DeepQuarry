#!/usr/bin/env python3
"""Actual-root raw-policy proof using built native CLI + independent old Engine.

No compilation, publication, fixture substitution, baseline edits or source
rewrites. The official Rust scratch owner supplies the disposable log/cache root.
"""
from __future__ import annotations
import argparse,json,os,subprocess,sys,time
from collections import deque
from pathlib import Path
from unified_daemon_smoke import Smoke,request,json_rows,assert_reply

RESOURCE_REFUSALS=(
 'workspace site bound exceeded','workspace finding count exceeds existing10000 bound',
 'shared result-family headroom exhausted','aggregate headroom exhausted',
 'findings exceed admitted result headroom','captured raw findings exceed count/retained-byte admission',
 'workspace wire result exceeds shared result-family headroom',
 'whole source normalization exceeds remaining input budget',
 'captured source view allocation exceeds remaining input-family budget',
)
def diagnostic_excerpt(value,limit=16384):
    """Bounded evidence survives the official scratch owner's cleanup."""
    if value is None:raw=b''
    elif isinstance(value,bytes):raw=value
    else:raw=value.encode('utf8',errors='replace')
    if len(raw)<=limit:kept=raw.decode('utf8',errors='replace')
    else:
        head=min(4096,limit//3);tail=limit-head-128
        kept=raw[:head].decode('utf8',errors='replace')+'\n[... diagnostic evidence truncated ...]\n'+raw[-tail:].decode('utf8',errors='replace')
    encoded=kept.encode('utf8')
    expanded=len(encoded)>limit
    if expanded:
        head=min(4096,limit//3);tail=limit-head-128
        kept=encoded[:head].decode('utf8',errors='ignore')+'\n[... diagnostic evidence truncated ...]\n'+encoded[-tail:].decode('utf8',errors='ignore')
    lines=kept.splitlines();progress=next((line[:512]for line in reversed(lines)if line.startswith(('native stage ','frontend '))),None)
    size=len(kept.encode('utf8'))+(len(progress.encode('utf8'))if progress else 0)
    return {'text':kept,'total_bytes':len(raw),'retained_bytes':size,'truncated':len(raw)>limit or expanded,'last_progress_line':progress}

class Actual(Smoke):
    def __init__(self,*args,total_seconds,request_seconds):
        super().__init__(*args);self.env['DM_COMPILER_CACHE_ROOT']=str(self.root/'compiler-cache');self.deadline=time.monotonic()+total_seconds;self.request_seconds=request_seconds;self.stderr_evidence_bytes=0;self.stderr_evidence_calls=deque()
    def run(self,args,*,success=True,cleanup=False,cleanup_deadline=None):
        now=time.monotonic();end=(cleanup_deadline or now+15) if cleanup else self.deadline
        seconds=min(15 if cleanup else self.request_seconds+20,end-now)
        if seconds<=0:raise TimeoutError('actual workspace coordinator budget exhausted')
        flags=subprocess.BELOW_NORMAL_PRIORITY_CLASS if os.name=='nt' else 0
        started=time.monotonic()
        index=len(self.calls)
        try:
            result=subprocess.run([str(self.binary),*args],cwd=self.root,env=self.env,text=True,encoding='utf8',errors='replace',capture_output=True,timeout=seconds,creationflags=flags)
        except subprocess.TimeoutExpired as error:
            stderr=diagnostic_excerpt(error.stderr);stdout=diagnostic_excerpt(error.stdout,4096)
            self._record_call({'args':args,'returncode':None,'status':'timeout','timeout_seconds':seconds,'seconds':time.monotonic()-started,'stderr_evidence':stderr,'stdout_timeout_evidence':stdout})
            (self.root/f'call-{index}.stderr').write_text(stderr['text'],encoding='utf8')
            (self.root/f'call-{index}.stdout').write_text(stdout['text'],encoding='utf8')
            raise TimeoutError(f'actual native call exceeded {seconds:.1f}s; last stage: '+str(stderr['last_progress_line'])) from error
        (self.root/f'call-{index}.stdout').write_text(result.stdout,encoding='utf8');(self.root/f'call-{index}.stderr').write_text(result.stderr,encoding='utf8')
        self._record_call({'args':args,'returncode':result.returncode,'status':'completed','seconds':time.monotonic()-started,'stderr_evidence':diagnostic_excerpt(result.stderr)})
        if success and result.returncode:raise RuntimeError(f'actual native CLI refused ({result.returncode}); see call-{index}.stderr: '+diagnostic_excerpt(result.stderr,4096)['text'])
        return result
    def _record_call(self,entry):
        self.calls.append(entry);self.stderr_evidence_calls.append(len(self.calls)-1)
        self.stderr_evidence_bytes+=entry['stderr_evidence']['retained_bytes']
        # One bounded diagnostic family across all pages/cohorts, not a fresh
        # unbounded log accumulator for every private CLI request.
        while self.stderr_evidence_bytes>1024*1024:
            old=self.calls[self.stderr_evidence_calls.popleft()]
            self.stderr_evidence_bytes-=old['stderr_evidence']['retained_bytes']
            del old['stderr_evidence'];old['stderr_evidence_evicted']=True
    def prepare_actual(self,project,engine):
        run=self.run(['prepare-query',str(project),'--engine-template',str(engine),'--bootstrap-catalog','--workers','2','--progress','--exact-inputs','--request-timeout-seconds',str(self.request_seconds),'--policy-inputs-json',json.dumps(self.policy_intent)])
        rows=[row for row in json_rows(run.stdout) if row.get('row')=='query_prepared']
        if len(rows)!=1 or rows[0].get('retained') is not True or not rows[0].get('policy_revision'):raise RuntimeError('actual main project did not issue an admitted retained workspace policy frame')
        return rows[0]
    def ask(self,project,engine,pins,question):
        value=request(project,engine,pins,[question]);value['timeout_seconds']=self.request_seconds
        path=self.root/f'query-{len(self.calls)}.json';path.write_text(json.dumps(value),encoding='utf8')
        run=self.run(['query',str(path)],success=False)
        if run.returncode:return None,run
        return assert_reply(json.loads(run.stdout),pins),run

def old_call(binary,args,log,seconds):
    flags=subprocess.BELOW_NORMAL_PRIORITY_CLASS if os.name=='nt' else 0
    run=subprocess.run([str(binary),*args],text=True,encoding='utf8',errors='replace',capture_output=True,timeout=seconds,creationflags=flags)
    log.with_suffix('.stdout').write_text(run.stdout,encoding='utf8');log.with_suffix('.stderr').write_text(run.stderr,encoding='utf8')
    if run.returncode:raise RuntimeError('actual independent old oracle failed: '+diagnostic_excerpt(run.stderr,4096)['text'])
    return json.loads(run.stdout)

def collect(smoke,project,engine,pins,root,config,names,limit):
    cursor=None;offset=0;aggregate=None;seen=[];page_count=0
    first_question={'NativeWorkspaceRawPolicy':{'root':str(root),'configuration':str(config),'lints':names,'cursor':None,'limit':limit}}
    first_row=None
    while True:
        q={'NativeWorkspaceRawPolicy':{'root':str(root),'configuration':str(config),'lints':names,'cursor':cursor,'limit':limit}}
        rows,run=smoke.ask(project,engine,pins,q)
        if rows is None:
            detail=run.stdout+'\n'+run.stderr
            return {'refused':True,'resource_refusal':any(message in detail for message in RESOURCE_REFUSALS),'detail':diagnostic_excerpt(detail)['text'],'diagnostic_bytes':len(detail.encode('utf8')),'lints':names},None
        if len(rows)!=1:raise RuntimeError('missing/extra native workspace page')
        row=rows[0]
        assert row['row']=='source_native_workspace_raw_policy' and row['snapshot_as_of']=='policy_revision'
        assert row['offset']==offset and row['count']==len(row['items']) and row['count']<=limit
        assert row['policy_revision']==pins['policy_revision'] and row['source_revision']==pins['source_revision']
        assert row['semantic_revision']==pins['semantic_revision'] and row['requested_lints']==names
        if aggregate is None:aggregate=row['aggregate_id'];first_row=row
        assert row['aggregate_id']==aggregate
        seen.extend(row['items']);offset+=row['count'];page_count+=1;cursor=row['next_cursor']
        if cursor is None:assert offset==row['total_items'];break
        assert row['count']>0
    # Same published frame and actual aggregate are checked again at the native
    # private guard, not inferred from command names or approximate timings.
    warm,_=smoke.ask(project,engine,pins,first_question)
    assert warm is not None and warm[0]==first_row
    runs=[{'name':name,'sites':[],'allow_used':[],'notes':[]} for name in names];index={run['name']:run for run in runs}
    for item in seen:
        field,payload={'site':('sites','site'),'allow':('allow_used','allow'),'note':('notes','text')}[item['kind']]
        index[item['lint']][field].append(item[payload])
    return {'refused':False,'lints':names,'aggregate_id':aggregate,'pages':page_count,'records':offset,'warm_first_page_exact':True},runs

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--binary',type=Path,required=True);p.add_argument('--oracle',type=Path,required=True);p.add_argument('--scratch-root',type=Path,required=True);p.add_argument('--repository',type=Path,required=True);p.add_argument('--project',type=Path);p.add_argument('--configuration',type=Path);p.add_argument('--engine-template',type=Path);p.add_argument('--request-seconds',type=int,default=180);p.add_argument('--total-seconds',type=int,default=900);p.add_argument('--page-limit',type=int,default=128);p.add_argument('--allow-scoped-native-project',action='store_true');p.add_argument('--evidence-out',type=Path);a=p.parse_args()
    if not(30<=a.request_seconds<=300 and 60<=a.total_seconds<=1800 and 1<=a.page_limit<=128):raise ValueError('bounded request/total/page limits required')
    repo=a.repository.resolve(strict=True);project=(a.project or repo/'deepquarry.dme').resolve(strict=True);config=(a.configuration or repo/'tools/ci/lint_scopes.toml').resolve(strict=True);engine=(a.engine_template or repo/'tools/dmb/fixtures/native_template.bin').resolve(strict=True);oracle=a.oracle.resolve(strict=True)
    main_project=project==repo/'deepquarry.dme'
    if not main_project and not a.allow_scoped_native_project:raise ValueError('non-main native project requires --allow-scoped-native-project and is labelled scoped raw proof only')
    if config!=(repo/'tools/ci/lint_scopes.toml').resolve(strict=True):raise ValueError('old Engine configuration is the actual root lint_scopes.toml; alternate native-only configuration cannot certify parity')
    if a.evidence_out is not None and not a.evidence_out.parent.is_dir():raise ValueError('evidence parent must already exist')
    smoke=Actual(a.binary,a.scratch_root,repo,total_seconds=a.total_seconds,request_seconds=a.request_seconds)
    evidence={'scope':'actual-repository/raw27-as-of-prepared-policy-frame','project':str(project),'root':str(repo),'main_project_requested':main_project,'main_project_prepare':False,'full_native_compiler_integration':False,'full_semantic_policy_parity':False,'production_default_cutover':False,'cohorts':[],'complete':False}
    if not main_project:evidence['scope']='actual-repository/raw27-with-explicitly-scoped-native-frontend'
    status=1
    try:
        print('Reading actual old raw27 metadata and findings...',flush=True)
        manifest=old_call(oracle,['--manifest'],smoke.root/'old-manifest',a.request_seconds)
        assert manifest['scope']=='actual-old-raw27-metadata' and len(manifest['lints'])==27
        names=manifest['lints'];assert len(set(names))==len(names)
        roots=[repo/name for name in manifest['recursive_roots']]
        assert all(path.is_relative_to(repo) for path in roots)
        smoke.policy_intent={'workspace':{'root':str(repo),'recursive_roots':[str(path)for path in roots],'configuration':str(config)}}
        evidence['manifest']=manifest;evidence['recursive_roots']=[str(path)for path in roots]
        expected=old_call(oracle,[str(repo)],smoke.root/'old-actual-findings',a.request_seconds)
        assert [run['name']for run in expected]==names
        evidence['old_counts']={run['name']:{'sites':len(run['sites']),'allow_used':len(run['allow_used']),'notes':len(run['notes'])}for run in expected}
        print('Preparing actual main DME once; source remains untouched...',flush=True)
        pins=smoke.prepare_actual(project,engine);evidence['pins']=pins;evidence['main_project_prepare']=main_project;evidence['frontend_scope']='actual_main_project' if main_project else 'explicit_scoped_native_project'
        print('Paging native raw27 findings on that same published frame...',flush=True)
        outcome,runs=collect(smoke,project,engine,pins,repo,config,names,a.page_limit);evidence['cohorts'].append(outcome)
        if runs is None:
            if not outcome['resource_refusal']:raise RuntimeError('non-resource native refusal; no fallback can certify the whole requested cohort')
            print('Combined cohort explicitly exhausted its resource bound; querying each lint on the SAME frame...',flush=True)
            runs=[]
            for name in names:
                outcome,one=collect(smoke,project,engine,pins,repo,config,[name],a.page_limit);evidence['cohorts'].append(outcome)
                if one is None:raise RuntimeError('single lint still refused; resource ceiling remains unchanged: '+name)
                runs.extend(one)
        # Do not filter, sort away, or normalize any old authored result rows.
        (smoke.root/'native-actual-findings.json').write_text(json.dumps(runs,indent=2),encoding='utf8')
        if runs!=expected:raise RuntimeError('actual old/native findings differ; inspect the two complete findings files')
        evidence['same_current_owner_proof']={'single_prepare':True,'fixed_semantic_source_policy_pins':True,'stable_private_issued_aggregate_per_cohort':True,'native_guard_checks_exact_capture_arc_source_map_and_same_db':True,'warm_first_page_exact':True,'direct_pointer_addresses_exported':False,'zero_scan_counter_claim':False}
        evidence['complete']=True;evidence['matched']=True;status=0
        print('Actual repository raw27 findings match independent old Engine.scan exactly.',flush=True)
    except Exception as error:
        evidence['failure']=str(error);print(str(error),file=sys.stderr,flush=True)
    finally:
        evidence['calls']=smoke.calls
        encoded=json.dumps(evidence,indent=2)
        (smoke.root/'actual-workspace-proof.json').write_text(encoded,encoding='utf8')
        if a.evidence_out is not None:a.evidence_out.write_text(encoded,encoding='utf8')
        smoke.retire()
    return status
if __name__=='__main__':raise SystemExit(main())
