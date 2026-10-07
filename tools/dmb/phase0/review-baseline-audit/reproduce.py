from pathlib import Path
import hashlib,json,subprocess,sys,time
root=Path('D:/dmb-native-v2-phase0/parity-final-corrected-20261007-b')
out=Path('E:/dmb-native-v2-phase0/review-baseline-audit')
script=Path('C:/Users/bmene/.codex/worktrees/native-v2/CHOMPStation2/tools/dmb/phase0/normalize_runtime.py')
evidence=json.loads((root/'evidence.json').read_text())
command=[sys.executable,str(script),*evidence['normalizer_command'][2:]]
command[-1]=str(out/'normalized-reproduced.json')
start=time.monotonic()
subprocess.run(command,check=True)
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
files=[script,root/'evidence.json',root/'normalized.json',root/'preserved-comparison.json',root/'snapshot-receipt.json',out/'normalized-reproduced.json']
for index,value in enumerate(command):
 if value=='--run':
  d=Path(command[index+1].partition('=')[2])
  files.extend(p for p in d.iterdir() if p.is_file())
for producer in ('byond','native'):
 d=Path('D:/dmb-native-v2-phase0/frozen')
 files.extend([d/'pairs'/producer/'world.dmb',d/'pairs'/producer/'world.rsc',d/'preserved'/producer/'runtime-errors.log'])
receipt={'operation':'offline normalization of preserved channels; no worlds or compilers launched','command':command,'seconds':time.monotonic()-start,'files':[{'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(set(files))]}
old=json.loads((root/'normalized.json').read_text());new=json.loads((out/'normalized-reproduced.json').read_text())
receipt['normalized_structural_equality']=old==new
receipt['normalized_byte_equality']=sha(root/'normalized.json')==sha(out/'normalized-reproduced.json')
(out/'provenance.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'structural_equal':receipt['normalized_structural_equality'],'byte_equal':receipt['normalized_byte_equality'],'seconds':receipt['seconds'],'hash':sha(out/'normalized-reproduced.json'),'files':len(receipt['files'])}))
