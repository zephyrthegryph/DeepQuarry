"""Compare all seeded legacy visibility observations, including source notes.
No reference row is filtered; foreign families abort rather than disappear.
Native executable is a private original-owner/SAME-Db oracle, not a model pipe.
"""
import argparse, hashlib, json, os, re, subprocess
from pathlib import Path
PINNED='bafd54168a539e61d8c3f71d9778e92de76d7ffbf11c693541e10be10c9633ba'
LOC=re.compile(r'^(.+), line (\d+), column (\d+):$')
MSG=re.compile(r'^(error|warning|info|hint): (.+)$')
CROSS=re.compile(r'^(.*):(\d+):(\d+): (.*)$')
SAME=re.compile(r'^(\d+):(\d+): (.*)$')
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def inputs(root):return {str(p.relative_to(root)):digest(p) for p in sorted(root.rglob('*')) if p.is_file() and p.suffix in {'.dm','.dme','.toml'}}
def location(file,line,column,base):return dict(file=str((base/Path(file)).resolve()),line=int(line),column=int(column))
def family(message):
 if message=='var/SpacemanDMM_private has no effect here' or (' overrides private var ' in message) or (message.startswith('field ') and message.endswith(' is declared as private')):return 'private_var'
 if message=='var/SpacemanDMM_protected has no effect here' or (message.startswith('field ') and message.endswith(' is declared as protected')):return 'protected_var'
 if ' overrides final var ' in message:return 'final_var'
 if ' redeclares var ' in message:return 'variable_redeclaration'
 raise ValueError('unported/unknown reference observation, not filtered: '+message)
def reference(text,base):
 rows=[];point=None
 for line in text.splitlines():
  if match:=LOC.match(line):point=location(*match.groups(),base);continue
  if match:=MSG.match(line):
   assert point is not None,line
   name=family(match[2]);rows.append(dict(**point,severity=match[1],message=match[2],family=name,registration_tag=None if name=='variable_redeclaration' else name,notes=[]));continue
  if line.startswith('- '):
   assert rows,line
   value=line[2:]
   if match:=SAME.match(value):note=dict(file=rows[-1]['file'],line=int(match[1]),column=int(match[2]),message=match[3])
   elif match:=CROSS.match(value):note=dict(**location(match[1],match[2],match[3],base),message=match[4])
   else:note=dict(file=rows[-1]['file'],line=rows[-1]['line'],column=rows[-1]['column'],message=value)
   rows[-1]['notes'].append(note)
 return rows
def native(text):
 rows=[]
 for line in text.splitlines():
  row=json.loads(line);row['file']=str(Path(row['file']).resolve())
  for note in row['notes']:note['file']=str(Path(note['file']).resolve())
  rows.append(row)
 return rows
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--diagnostic-declarations',action='store_true');p.add_argument('--reference',type=Path,required=True);p.add_argument('--native',type=Path,required=True);p.add_argument('fixture',type=Path);a=p.parse_args();fixture=a.fixture.resolve();before=inputs(fixture.parent);assert digest(a.reference)==PINNED;native_sha=digest(a.native)
 flags=subprocess.BELOW_NORMAL_PRIORITY_CLASS if os.name=='nt' else 0
 old=subprocess.run([str(a.reference),'-e',str(fixture)],capture_output=True,text=True,timeout=60,creationflags=flags)
 new=subprocess.run([str(a.native),str(fixture)]+(['--diagnostic-declarations']if a.diagnostic_declarations else []),capture_output=True,text=True,timeout=60,creationflags=flags)
 assert old.returncode in (0,1),(old.returncode,old.stderr)
 assert new.returncode==0,('native unsupported/failure',new.returncode,new.stderr)
 assert before==inputs(fixture.parent),'fixture changed';assert digest(a.reference)==PINNED;assert digest(a.native)==native_sha
 expected=reference(old.stderr,fixture.parent);observed=native(new.stdout);assert expected,'empty old fixture cannot certify this cohort'
 if expected!=observed:print(json.dumps(dict(reference=expected,native=observed),indent=2));return 1
 print(json.dumps(dict(scope='all-variable-visibility-producer-categories/seeded-native-owner-fixture',declaration_profile='diagnostic-inherited-variable-v1'if a.diagnostic_declarations else 'strict',diagnostics=len(expected),matched=True,full_checker_parity=False,all_source_contexts_supported=False,input_hashes=before,reference_sha256=PINNED,native_sha256=native_sha)));return 0
if __name__=='__main__':raise SystemExit(main())
