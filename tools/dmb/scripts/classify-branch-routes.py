# Read-only bounded classification; never changes comparison or emitted code.
import re,json,collections,sys
if len(sys.argv)!=3: raise SystemExit("usage: classify_branch_routes.py PARITY.ndjson BRANCH_BODIES.txt")
rows=[json.loads(x) for x in open(sys.argv[1]) if x.strip()]
body=open(sys.argv[2]).read(); bodies={}
for b in body.split('PATH ')[1:]:
 path,*pieces=b.split('\n',1); sides=pieces[0].split('NEXT')[:2]; parsed=[]
 for side in sides:
  v=[]
  for l in side.splitlines():
   m=re.match(r'(\d+) ([0-9a-f]+) (.*?) targets(\[.*\])',l)
   if m:v.append((int(m[2],16),json.loads(m[4])))
  parsed.append(v)
 bodies[path]=parsed
results=collections.Counter(); unresolved=[]
for row in rows:
 if row.get('category')!='branch_or_switch_operands_only':continue
 path=row['path']; n,a=bodies[path]; dif=[x for x in rows if x.get('section')=='bytecode' and x.get('native_proc')==row['native_proc']]
 rules=set(); good=True
 def chase(v,t,op):
  seen=set()
  while t<len(v) and t not in seen and (v[t][0]==0xf or (op in (0xb2,0xb3) and v[t][0]==op)) and len(v[t][1])==1:
   seen.add(t);t=v[t][1][0]
  return t
 for d in dif:
  i=int(re.search(r'\[(\d+)\]',d['field'])[1]); x,y=d['native'],d['translated']
  if x.startswith('[Branch(') and y.startswith('[Branch('):
   nt=int(re.search(r'Branch\((\d+)\)',x)[1]);at=int(re.search(r'Branch\((\d+)\)',y)[1]);op=n[i][0]
   if chase(n,nt,op)==chase(a,at,op):rules.add('conditional_or_unconditional_chain')
   else:good=False
  elif 'Switch(' in x and 'Switch(' in y:
   def sw(s):
    pairs=re.findall(r'String\(Some\(\[([0-9, ]*)\]\)\), Instruction\((\d+)\)',s)
    pairs += re.findall(r'Number\((\d+)\), Instruction\((\d+)\)',s)
    if s.count("Instruction(")!=len(pairs)+1: return [], []
    if len({k for k,v in pairs})!=len(pairs): return [], [] # repeated keys need ordered dispatch proof
    return sorted(pairs), re.findall(r'Instruction\((\d+)\)\)\]$',s)
   if sw(x)==sw(y) and sw(x)[0]:rules.add('same_switch_key_routes')
   else:good=False
  else:good=False
 if good:results['+'.join(sorted(rules))]+=1
 else:unresolved.append(path)
print(results,'unresolved',len(unresolved));print('\n'.join(unresolved))
