import json,re,sys
CASES={'basic','allowed','exempt','hidden'}
def pairs(rows):
 out={}
 for key,value in rows:
  if key in out:raise ValueError('duplicate field '+key)
  out[key]=value
 return out
def load(path,prefix):
 text=open(path,encoding='utf-8').read()
 out={}
 for line in text.splitlines():
  at=line.find(prefix)
  if at<0:continue
  row=json.loads(line[at+len(prefix):],object_pairs_hook=pairs,parse_constant=lambda value:(_ for _ in ()).throw(ValueError(value)))
  case=row['case']
  if case not in CASES or case in out:raise ValueError('unexpected/duplicate case')
  out[case]=row
 if out.keys()!=CASES:raise ValueError('missing complete case records')
 return text,out
old_text,old=load(sys.argv[1],'SHARED_DECL_WORKSPACE_OLD=')
native_text,native=load(sys.argv[2],'NATIVE_DECL_WORKSPACE_FULL=')
for text,name in [(old_text,'shared_decl_policy_preserves_entire_original_lifecycle_ancestry_raw_facts_allow_and_reports'),(native_text,'actual_original_decl_complete_hidden_code_over_130_files_preserves_entire_sites_and_allow_trace')]:
 summaries=re.findall(r'test result: (\w+)\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured;',text)
 if summaries!=[('ok','1','0','0','0')]:raise ValueError('not exactly one successful selected test')
 statuses=re.findall(r'^test ([^\n]+?) \.\.\. (ok|FAILED|ignored)$',text,re.M)
 if len(statuses)!=1 or statuses[0][1]!='ok' or statuses[0][0].split('::')[-1]!=name:raise ValueError('wrong selected test')
for case in sorted(CASES):
 expected=old[case]['record']
 for field in ['sites','notes','allow_used']:
  if expected[field]!=native[case][field]:raise ValueError(case+': entire ordered '+field+' differs')
 if old[case]['source_text']!=native[case]['source_text']:raise ValueError(case+': complete as-of source text differs')
print('PASS: all four complete original/native declaration records, ordered sites/notes/ALLOW/source text')
