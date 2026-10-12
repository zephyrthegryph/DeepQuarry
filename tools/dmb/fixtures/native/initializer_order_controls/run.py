"""Five exact ordering controls via existing paired initializer runner, never old receipts rewrite."""
import argparse,importlib.util,json,re,sys,time,uuid
from pathlib import Path
HERE=Path(__file__).resolve().parent
BENCH=HERE.parents[2]/'bench'
CONTROLS=(
 ('base','initializer_observable_order','E:/dq-cache/dmb-observable-order-reference/fed3234898374b7c94ebc6122ea9048c/receipt.json'),
 ('early_literal','initializer_vars_literal_order','E:/dq-cache/dmb-vars-literal-reference/137cef792ea9496e93353b07ab95d2d4/receipt.json'),
 ('early_numeric','initializer_proc_number_order','E:/dq-cache/dmb-proc-number-reference/e1ce034e547d489ca37b21415d79a7e3/receipt.json'),
 ('between','initializer_proc_between_order','E:/dq-cache/dmb-proc-between-reference/778d6fef286c4f59ab87fab0f2d8a573/receipt.json'),
 ('after','initializer_proc_after_order','E:/dq-cache/dmb-proc-after-reference/940132b2e75a4f8db07256da66d8048b/receipt.json'),
)
def load(name,file):
 spec=importlib.util.spec_from_file_location(name,file);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module

def main():
 p=argparse.ArgumentParser()
 p.add_argument('--native',type=Path,required=True);p.add_argument('--native-sha256',required=True)
 p.add_argument('--output-root',type=Path,required=True)
 args=p.parse_args();sys.path.insert(0,str(BENCH))
 from upgrade_owned_job import OwnedJob
 h=load('order_controls_iteration',BENCH/'native-iteration.py')
 h.safe_e(args.output_root);args.output_root.mkdir(parents=True,exist_ok=True)
 output=args.output_root/uuid.uuid4().hex;output.mkdir()
 receipt={'schema':1,'scope':'Five tiny ordering controls, not full suite or complete source closure','controls':{},'inputClosureAuthenticated':False,'acceptedRuntimeBaseline':False}
 job=OwnedJob(4_000_000_000);h._owned_job=job;deadline=time.monotonic()+900
 pins={}
 def pin(path,digest=None):
  path=path.resolve(strict=True);h.regular(path);actual=h.sha(path)
  if digest is not None and actual!=digest:raise ValueError('pin mismatch '+str(path))
  pins[str(path)]=actual;return path,actual
 try:
  pin(Path(sys.executable))
  for helper in (HERE.parent/'initializer_dependent_order/run.py', HERE.parent/'initializer_observable_order/run.py', HERE.parent/'power_retirement_runtime/run.py', BENCH/'machine_slot_command.py', BENCH/'upgrade_owned_job.py', BENCH/'native-iteration.py', BENCH/'native-fresh.py'):
   pin(helper)
  native,native_sha=pin(args.native,args.native_sha256)
  template,template_sha=pin(HERE.parent/'../native_template.bin','9221528efb715be5b8df23020989e0c2a53ea32bff9894747166dbe04d785540')
  dm,dm_sha=pin(Path('D:/Program Files (x86)/BYOND516/bin/dm.exe'),'8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0')
  dd,dd_sha=pin(Path('D:/Program Files (x86)/BYOND516/bin/dd.exe'),'2e3815875c4dcf3c50de70c1c6e017849efe8697c428f02ab9ee77c306c8abf0')
  for name,fixture,reference in CONTROLS:
   runner,runner_sha=pin(HERE.parent/fixture/'run.py');ref,ref_sha=pin(Path(reference))
   captured=json.loads(ref.read_text(encoding='utf-8-sig'))
   for source,digest in captured['sourceHashes'].items():pin(runner.parent/source,digest)
   pin(runner.parent/'reverse.dme',captured['reverseManifestSha256'])
   command=[str(runner),'--reference-receipt',str(ref),'--reference-receipt-sha256',ref_sha,'--native',str(native),'--native-sha256',native_sha,'--template',str(template),'--template-sha256',template_sha,'--dm',str(dm),'--dm-sha256',dm_sha,'--dd',str(dd),'--dd-sha256',dd_sha,'--output-root',str(output/name)]
   result=h.run_child(Path(sys.executable),command,output/(name+'-launcher'),min(deadline,time.monotonic()+305))
   text=(output/(name+'-launcher')/'stdout.log').read_text(encoding='utf-8-sig').strip()
   evidence=Path(text.splitlines()[-1]);h.regular(evidence)
   if not evidence.resolve().is_relative_to((output/name).resolve()):raise ValueError('foreign paired receipt')
   world=json.loads(evidence.read_text());cleanup=json.loads(evidence.with_name('owned-job.json').read_text())
   receipt['controls'][name]={'execution':result,'receipt':str(evidence),'sha256':h.sha(evidence),'complete':world.get('complete'),'matches':world.get('matches'),'byond':world.get('byond'),'native':world.get('native'),'cleanup':cleanup}
   if not cleanup.get('reaped'):raise ValueError('paired children not reaped')
  for path,digest in pins.items():
   if h.sha(Path(path))!=digest:raise ValueError('input changed '+path)
  receipt['complete']=True
 except Exception as error:receipt['error']=str(error)
 finally:
  receipt['pins']=pins;receipt['cleanup']=job.close();(output/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
 print(output/'receipt.json')
 return 0 if receipt.get('complete') and receipt['cleanup']['reaped'] and all(row['complete'] and row['matches'] for row in receipt['controls'].values()) else 1
if __name__=='__main__':raise SystemExit(main())
