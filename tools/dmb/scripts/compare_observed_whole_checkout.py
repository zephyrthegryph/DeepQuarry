"""Compare only captured private artifacts. Never open source/oracle after the observation."""
from pathlib import Path,PureWindowsPath,PurePosixPath
import argparse,hashlib,json,re,struct
BOUND=64*1024*1024
NAMES=['actions','auto_tracked','declare_ids','declare','deps','derived_reads','plans','reads','stats','system_accessors','tracked_lists','ui_types']
PHASES=['reader_declarations','variable_declarations','settings_prelude','body','keyword_overrides','sleep_graph','purity_graph']
ORACLE='77ae3e3e8b7667527873fa84e4ebc460260c40d280e08a12366ec38be0e880e2'
def require(condition,message):
 if not condition:raise ValueError(message)
def digest(payload):return hashlib.sha256(payload).hexdigest()
def journal(payload,header):
 require(len(payload)<=BOUND and len(payload)>=40,'journal bounds')
 require(payload[:8]==b'DQGENJ01','actual journal magic')
 count,length=struct.unpack_from('<QQ',payload,8);native_hash=int.from_bytes(payload[24:40],'little')
 require(length==len(payload)==header['journal_length'] and count==header['journal_records'],'actual journal extents/counts')
 require(f'{native_hash:032x}'==header['journal_records_hash'],'actual journal digest metadata differs')
 # The real write_phase API validates this XXH3 digest before AND after copy.
 # Capture hashes bind the copied bytes; this decoder never mints/replays native authority.
 records=[];at=40;generator=None;names=[]
 for index in range(count):
  require(at+17<=len(payload),'truncated journal record')
  kind,line,plen,tlen=struct.unpack_from('<BIIQ',payload,at);at+=17
  require(kind in (1,2,3) and at+plen+tlen<=len(payload),'record kind/extent')
  path=payload[at:at+plen].decode('utf8');at+=plen;start=at;text=payload[at:at+tlen];at+=tlen
  require(kind!=1 or line==0,'file record line')
  if kind==3:
   require(tlen==0 and path in NAMES and path not in names,'actual generator witness')
   generator=path;names.append(path)
  else:require(generator is not None,'record before actual generator witness')
  records.append(dict(kind=kind,line=line,path=path,generator=generator,start=start,length=tlen,text=text))
 require(at==len(payload),'unconsumed journal tail')
 require(set(names)==set(filter(None,header['names'])) and len(names)==len(list(filter(None,header['names']))),'phase witness roster')
 return records
class Captured:
 def __init__(self,root):
  self.root=Path(root);self.capture_bytes=(self.root/'capture.json').read_bytes();self.capture_sha256=digest(self.capture_bytes);self.capture=json.loads(self.capture_bytes);self.files={}
  require(self.capture.get('completed')is True and self.capture.get('callback_ran')is True,'no actual completed observed frame')
  require(self.capture.get('oracle_sha256')==ORACLE,'wrong independent oracle')
  for name,expected in self.capture['artifacts_sha256'].items():
   require(Path(name).name==name and '/'not in name and '\\'not in name,'private artifact name')
   data=(self.root/name).read_bytes();require(len(data)<=BOUND and digest(data)==expected,'captured artifact changed: '+name);self.files[name]=data
 def data(self,name):require(name in self.files,'missing captured artifact '+name);return self.files[name]
 def json(self,name):return json.loads(self.data(name))
 def invocation(self,label):
  value=self.json(label+'.invocation.json');require(value['sha256']==ORACLE and value['ran_inside_actual_observation']is True,'unbound oracle invocation')
  require(value['status']in(0,1),'legacy operation did not finish semantically')
  return value
 def verify_again(self):
  require((self.root/'capture.json').read_bytes()==self.capture_bytes,'capture manifest changed during comparison')
  for name,data in self.files.items():require((self.root/name).read_bytes()==data,'private artifact changed during comparison: '+name)
def parse_analyze(data,ci):
 text=data.decode('utf8');lines=text.splitlines();require(bool(lines),'empty Analyze output')
 terminal=[line for line in lines if line=='All ratchet lints passed.'or line.startswith('Ratchet lints failed: ')]
 require(len(terminal)==1 and lines[-1]==terminal[0],'missing/ambiguous final actual Analyze judgment')
 unused=[line for line in lines if re.fullmatch(r'allow annotations: \d+ unused',line)]
 require(len(unused)==1,'whole-registry unused-ALLOW footer absent')
 groups=[line[len('::group::'):]for line in lines if line.startswith('::group::')];ends=lines.count('::endgroup::');depth=0
 for line in lines:
  if line.startswith('::group::'):depth+=1
  elif line=='::endgroup::':depth-=1;require(depth>=0,'CI end before actual group')
 require(depth==0,'unterminated actual CI group')
 require((bool(groups)and len(groups)==ends)if ci else not groups and not ends,'actual CI grouping does not match request')
 # Preserve EVERY line and opaque/multiline note; do not select named finding families.
 return dict(lines=lines,ordered_groups=groups,unused_footer=unused[0],terminal=terminal[0],site_line_count=sum(bool(re.match(r'.+:\d+(?::\d+)?:',line))for line in lines),line_count=len(lines))
def analyze(c,expected_bodies):
 h=c.json('report-header.json');checker=c.json('native-checker.json');mode=c.capture['mode'];require(mode in('raw','ci'),'Analyze mode')
 require(h['schema']=='joined-report-input-observation-v1'and h['kind']=='observed_combined_preparation_inputs_only','wrong observation scope')
 require(h['analysis_context']=='original_analyze0290','actual Original Analyze environment')
 require(h['full_checker_parity']is False and h['full_policy_parity']is False,'producer cannot assert independent parity')
 binding=h['binding'];require(binding['options']==dict(raw=mode=='raw',ci=mode=='ci',unused=True),'actual options differ')
 roster=binding['original_archive_bodies'];require(type(roster)is int and roster>0,'actual original archive input roster count absent or invalid')
 if expected_bodies is not None:require(roster==expected_bodies,'independently supplied original archive count differs from observed input roster')
 scope=checker['scope_completion'];require(scope['scope']=='whole_input_current_ordered_producers'and scope['visited_bodies']==roster and scope['completed_phase_order']==PHASES,'whole actual BODY/phase traversal not completed')
 for key in ['semantic_revision','source_revision']:
  require(binding['frame'][key]==binding['checker_frame'][key]==checker[key],'mixed native report/Checker frame')
 inputs=c.json('combined-preparation-inputs.json');require('policy_directories'in inputs and 'files'in inputs and 'negative_files'in inputs,'actual combined closure categories absent')
 invocation=c.invocation('legacy-analyze');require(invocation['arguments']==['check','--'+mode,'--no-cache','--no-selftest','--unused','--root',c.capture['root']],'oracle request omitted or changed purpose')
 old=c.data('legacy-analyze.stdout');new=c.data('native-analyze.stdout');old_err=c.data('legacy-analyze.stderr');new_err=c.data('native-analyze.stderr')
 old_rows=parse_analyze(old,mode=='ci');new_rows=parse_analyze(new,mode=='ci')
 require((invocation['status']==0)==c.capture['native_clean']==binding['clean'],'dirty/clean status differs')
 equal=old==new and old_err==new_err
 return dict(scope='whole actual observed input frame; independent Analyze '+mode+' only',completed=True,exact_stdout_equal=old==new,exact_stderr_equal=old_err==new_err,all_rows_equal=equal,reference=old_rows,native=new_rows,actual_visited_bodies=scope['visited_bodies'],full_checker_parity=False,whole_policy_qualified=equal)
def expected_generator_text(rows,diags,names,diagnostic_only_ui_root=None):
 out=[]
 for name in names:
  group=[row for row in rows if row['generator']==name];findings=[d for d in diags if d['generator']==name]
  # Ordinary GenOut.diags attaches to the last files() result for these two producers.
  position=len(group)-1 if name in ('derived_reads','ui_types')else 0
  if not group and findings:
   require(name=='ui_types' and diagnostic_only_ui_root is not None,'missing real generator output row')
   # The caller supplies this DATA label only AFTER all12 sealed journal
   # witnesses, exact desired/target roster and diagnostics have validated.
   # Match PathBuf::join display without normalizing captured root spelling.
   root=diagnostic_only_ui_root
   require(isinstance(root,str) and (PureWindowsPath(root).is_absolute()or PurePosixPath(root).is_absolute()),'captured absolute UI display root absent')
   separator='\\'if PureWindowsPath(root).is_absolute()else'/'
   has_separator=root.endswith(('\\','/'))if separator=='\\'else root.endswith('/')
   display=root+(''if has_separator else separator)+'tgui/packages/tgui/interfaces/generated'
   for d in findings:out.append(f"{d['relative']}:{d['line']}: [gen/{name}] {d['message']}\n")
   out.append(f'fresh {display}\n')
   continue
  for i,row in enumerate(group):
   if i==position:
    for d in findings:out.append(f"{d['relative']}:{d['line']}: [gen/{name}] {d['message']}\n")
   path=row['path'];state=row['state']
   if state=='fresh':out.append(f'fresh {path}\n')
   elif state=='stale':out.append(f'{path}:1: [gen/{name}] stale -- run `analyze gen {name}` (every build.sh target that compiles DM does; the file is not committed)\n')
   elif state=='not_included':out.append(f'deepquarry.dme:1: [gen/{name}] {path} is generated but not #included -- add it to deepquarry.dme\n')
   else:raise ValueError('CHECK-only cannot report written/unknown state')
 return ''.join(out).encode('utf8')
def generation(c):
 h=c.json('generation-header.json');report=c.json('native-generation-report.json')
 require(h['schema']=='native-generation-check-observation-v1'and h['check_only']is True,'not actual CHECK observation')
 require(set(h['requested_names'])==set(NAMES)and len(h['requested_names'])==12,'not all12 actual generator roles')
 require(report['schema']=='native-generation-v1'and report['committed']is False and report['changed']==[]and report['cleanup']==[],'mutation/cleanup or foreign report')
 rows=report['rows'];diags=report['diagnostics'];require(report['clean']==c.capture['native_clean']==(not diags and all(row['state']=='fresh'for row in rows)),'actual native generation verdict differs from exhaustive rows');require(all(row['generator']in NAMES for row in rows)and all(d['generator']in NAMES for d in diags),'foreign result rows')
 archive={(row['slot'],row['index']):row for row in c.json('target-archives.json')};final_names=[];byte_gaps=[];target_checks=[];journal_files={};final_diagnostics=[]
 for slot,header in enumerate(h['phases']):
  if header is None:continue
  inputs=c.json(f'phase{slot}-inputs.json');require('files'in inputs and 'negative_files'in inputs,'missing actual phase input closure')
  require(header['slot']==slot and header['role']==['bootstrap_provenance_only','final_stage0','final_stage1'][slot],'actual phase role')
  data=c.data(f'phase{slot}-journal.bin');records=journal(data,header);targets=c.json(f'phase{slot}-targets.json')
  if slot:
   final_names.extend(filter(None,header['names']))
   final_diagnostics.extend(dict(generator=r['generator'],relative=r['path'],line=r['line'],message=r['text'].decode('utf8'))for r in records if r['kind']==2)
  files=[r for r in records if r['kind']==1];seen=set()
  for index,target in enumerate(targets):
   own=archive[(slot,index)];require(own['path']==target['path'],'target archive owner mismatch')
   extent=target['desired_extent'];matched=[r for r in files if[r['start'],r['length']]==extent and r['generator']==target['generator']and str(PureWindowsPath(c.capture['root'])/r['path'])==target['path']]
   require(len(matched)==1,'desired extent is not exact actual owned journal file')
   r=matched[0];key=(r['generator'],r['path']);require(key not in seen,'duplicate actual target');seen.add(key)
   previous=None if own['archived']is None else c.data(own['archived']);same=previous==r['text'];normal_identity=previous is not None and previous.replace(b'\r\n',b'\n')==previous
   if slot:
    journal_files[(target['generator'],target['path'])]=r
    actual=[row for row in rows if row['generator']==target['generator']and row['path']==target['path']];require(len(actual)==1,'target row was omitted/duplicated in actual report')
    state=actual[0]['state'];qualified=state=='fresh'and same and normal_identity
    if not qualified:byte_gaps.append(dict(generator=target['generator'],path=target['path'],state=state,reason='stale_or_absent_has_no_reference_desired_export'if state!='fresh'else'CRLF_normalization_is_not_identity'if not normal_identity else'native_desired_differs_from_actual_target'))
    target_checks.append(dict(generator=target['generator'],path=target['path'],state=state,exact_actual_target_equals_native_desired=same,legacy_normalization_identity=normal_identity,exact_desired_transitivity_candidate=qualified))
  require(len(files)==len(targets),'actual journal file omitted from target proof')
 require(len(final_names)==12 and set(final_names)==set(NAMES),'final phase witnesses do not complete exactly all12')
 require(sorted(final_diagnostics,key=lambda row:row['generator'])==diags,'whole ordered generation diagnostics differ from actual final journals')
 require(set(journal_files)=={(row['generator'],row['path'])for row in rows},'report/desired file roster mismatch')
 # No physical row may be invented: this label is only legacy report text.
 diagnostic_only_ui_root=c.capture['root']if 'ui_types'in final_names and not any(row['generator']=='ui_types'for row in rows)and any(d['generator']=='ui_types'for d in diags)else None
 comparisons=[];all_equal=True;stderr_empty=True
 for index in range(6):
  names=NAMES[index*2:index*2+2];label=f'legacy-gen-{index}';invocation=c.invocation(label)
  require(invocation['arguments']==['gen','--check','--root',c.capture['root'],*names],'missing/changed actual reference generator names')
  expected=expected_generator_text(rows,diags,names,diagnostic_only_ui_root);actual=c.data(label+'.stdout');error=c.data(label+'.stderr')
  expected_status=int(any(row['state']!='fresh'for row in rows if row['generator']in names)or any(d['generator']in names for d in diags))
  equal=actual==expected and invocation['status']==expected_status;all_equal &= equal;stderr_empty &= not error
  comparisons.append(dict(names=names,exact_stdout_equal=actual==expected,status_equal=invocation['status']==expected_status,stderr_empty=not error,expected_stdout=expected.decode('utf8'),actual_stdout=actual.decode('utf8'),actual_stderr=error.decode('utf8')))
 qualified=all_equal and stderr_empty and not byte_gaps
 return dict(scope='all12 actual CHECK source/target/desired journal observations',completed=True,all12_roles_completed=True,all_ordered_state_finding_output_bytes_equal=all_equal,reference_preparation_stderr_empty=stderr_empty,exact_desired_bytes_qualified=qualified,whole_generation_qualified=qualified,target_checks=target_checks,desired_byte_gaps=byte_gaps,comparisons=comparisons,full_checker_parity=False,universal_parity=False)
def main():
 a=argparse.ArgumentParser();a.add_argument('capture',type=Path);a.add_argument('--expected-bodies',type=int);a=a.parse_args();require(a.expected_bodies is None or a.expected_bodies>0,'positive independently supplied roster count required')
 try:
  c=Captured(a.capture);result=generation(c)if c.capture['mode']=='gen'else analyze(c,a.expected_bodies);c.verify_again();result['capture_sha256']=c.capture_sha256;result['qualification_only']=True
 except(Exception)as error:
  result=dict(completed=False,whole_policy_qualified=False,whole_generation_qualified=False,error=type(error).__name__+': '+str(error),scope='no completed qualification; preserve underlying capture and all provisional evidence')
 with(a.capture/'comparison.json').open('x',encoding='utf8',newline='\n')as output:json.dump(result,output,indent=2)
 print(json.dumps({k:v for k,v in result.items()if isinstance(v,(str,bool,int))}));return 0 if result.get('whole_policy_qualified',result.get('whole_generation_qualified',False))else 1
if __name__=='__main__':raise SystemExit(main())
