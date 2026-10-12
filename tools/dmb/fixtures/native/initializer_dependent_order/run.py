"""Tiny ordered initializer effects/dependent read; reference compilation precedes runtime.

Forward runtime asserts values and effect trace. Reverse is compile-only observation;
no runtime order is inferred from successful compilation. No prompt/full-suite proof.
"""
import argparse,importlib.util,json,os,re,sys,time,uuid
from pathlib import Path
HERE=Path(__file__).resolve().parent;BENCH=HERE.parents[2]/'bench'
def load(name,file):
    spec=importlib.util.spec_from_file_location(name,file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m

def observations(file):
    raw=file.read_bytes()
    if len(raw)>1024*1024:raise ValueError('tiny log exceeds1MiB')
    text=raw.decode('utf-16' if raw.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig')
    markers=[line[line.index('DQ_INIT_ORDER '):] for line in text.splitlines() if 'DQ_INIT_ORDER ' in line]
    if len(markers)!=3 or not markers[0].startswith('DQ_INIT_ORDER values first=11 second=12 trace=first=11;second=12; resource=') or markers[1:]!=['DQ_INIT_ORDER PASS','DQ_INIT_ORDER finished']:
        raise ValueError('dependent initializer values/effect order did not satisfy forward assertions')
    if re.search(r'runtime error:',text,re.I):raise ValueError('fixture logged runtime')
    return {'markers':markers,'runtimes':{}}

def reference_only(arguments):
    parser=argparse.ArgumentParser();parser.add_argument('--dm',type=Path,required=True);parser.add_argument('--dm-sha256',required=True);parser.add_argument('--output-root',type=Path,required=True);args=parser.parse_args(arguments)
    sys.path.insert(0,str(BENCH));from upgrade_owned_job import OwnedJob
    from machine_slot_command import slot_command
    h=load('order_iteration',BENCH/'native-iteration.py');common=load('order_common',HERE.parent/'power_retirement_runtime/run.py')
    h.safe_e(args.output_root);args.output_root.mkdir(parents=True,exist_ok=True);root=args.output_root/uuid.uuid4().hex;root.mkdir()
    job=OwnedJob(4_000_000_000);h._owned_job=job;deadline=time.monotonic()+120
    receipt={'schema':1,'kind':'initializer_order_BYOND_compile_only','runtime':'not run','cases':{},'inputClosureAuthenticated':False,'acceptedRuntimeBaseline':False}
    try:
        dm=args.dm.resolve(strict=True);h.regular(dm)
        if h.sha(dm)!=args.dm_sha256 or not re.fullmatch('[0-9a-f]{64}',args.dm_sha256):raise ValueError('DM pin mismatch')
        receipt['compiler']={'path':str(dm),'sha256':args.dm_sha256}
        names=common.fixture_files(('first.dm','second.dm','contract-resource.txt'));hashes={n:h.sha(HERE/n) for n in names};receipt['sourceHashes']=hashes
        for variant in ('forward','reverse'):
            source=root/variant;source.mkdir();common.copy_fixture_files(HERE,source,names,hashes,h.sha)
            if variant=='reverse':
                reverse=(HERE/'reverse.dme').read_bytes();(source/'probe.dme').write_bytes(reverse);receipt['reverseManifestSha256']=h.sha(HERE/'reverse.dme')
            plan=slot_command('dm_compile',[str(dm),str(source/'probe.dme')],HERE.parents[4],os.environ,label='dependent initializer '+variant+' reference')
            previous_environment=dict(os.environ)
            try:
                os.environ.clear();os.environ.update(plan['environment'])
                result=h.run_child(Path(plan['command'][0]),plan['command'][1:],root/(variant+'-compile'),min(deadline,time.monotonic()+30))
            finally:
                os.environ.clear();os.environ.update(previous_environment)
            receipt['cases'][variant]={'execution':result,'machineSlot':plan['evidence'],'manifestSha256':h.sha(source/'probe.dme'),'outputs':{}}
            if result['exit']==0:
                for suffix in ('.dmb','.rsc'):
                    file=source/('probe'+suffix);h.regular(file);receipt['cases'][variant]['outputs'][suffix]={'path':str(file),'sha256':h.sha(file),'bytes':file.stat().st_size}
            for name,digest in hashes.items():
                if h.sha(HERE/name)!=digest or (name!='probe.dme' and h.sha(source/name)!=digest):raise ValueError('source changed')
        if h.sha(dm)!=args.dm_sha256:raise ValueError('DM changed')
    except Exception as e:receipt['error']=str(e)
    finally:
        receipt['cleanup']=job.close();(root/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(root/'receipt.json');return 0 if 'error' not in receipt and receipt['cleanup']['reaped'] and all(v['execution']['exit']==0 for v in receipt['cases'].values()) else 1

def main():
    args=sys.argv[1:]
    if '--reference-only' in args:
        args.remove('--reference-only');return reference_only(args)
    if os.name!='nt':raise ValueError('Windows owned fixture required')
    sys.path.insert(0,str(BENCH));from upgrade_owned_job import OwnedJob
    admission_parser=argparse.ArgumentParser(add_help=False)
    admission_parser.add_argument('--reference-receipt',type=Path,required=True)
    admission_parser.add_argument('--reference-receipt-sha256',required=True)
    admitted,remaining=admission_parser.parse_known_args(args)
    from recover_iteration_source import absolute_nonreparse,regular,sha
    reference_file=absolute_nonreparse(admitted.reference_receipt);regular(reference_file)
    if not reference_file.is_relative_to(Path('E:/dq-cache')) or reference_file.stat().st_size>1024*1024:
        raise ValueError('bounded owned reference receipt required')
    if sha(reference_file)!=admitted.reference_receipt_sha256:raise ValueError('reference receipt pin mismatch')
    reference=json.loads(reference_file.read_text(encoding='utf-8-sig'))
    if reference.get('kind')!='initializer_order_BYOND_compile_only' or reference.get('error') or reference.get('cleanup',{}).get('reaped') is not True or set(reference.get('cases',{}))!={'forward','reverse'} or any(case['execution']['exit']!=0 for case in reference['cases'].values()):
        raise ValueError('both source-only controls must compile successfully before runtime')
    for name,digest in reference['sourceHashes'].items():
        if sha(HERE/name)!=digest:raise ValueError('fixture differs from reference capture')
    if sha(HERE/'reverse.dme')!=reference['reverseManifestSha256']:raise ValueError('reverse control changed')
    requested_dm=remaining[remaining.index('--dm')+1]
    requested_dm_sha=remaining[remaining.index('--dm-sha256')+1]
    if Path(requested_dm).resolve()!=Path(reference['compiler']['path']) or requested_dm_sha!=reference['compiler']['sha256']:
        raise ValueError('runtime BYOND differs from compile-only reference')
    common=load('order_common_runtime',HERE.parent/'power_retirement_runtime/run.py');old_load=common.load;h=None;evidence=None;job=OwnedJob(4_000_000_000);deadline=time.monotonic()+300
    def bounded_load(name,file):
        nonlocal h,evidence
        module=old_load(name,file)
        if file.name=='native-iteration.py':
            h=module;h._owned_job=job;original=h.run_child
            def child(executable,arguments,directory,child_deadline,**kwargs):
                nonlocal evidence
                evidence=directory.parent
                return original(executable,arguments,directory,min(deadline,child_deadline),**kwargs)
            h.run_child=child
        return module
    try:
        common.load=bounded_load
        sys.argv=[sys.argv[0],*remaining]
        return common.main(fixture_directory=HERE,observation_reader=observations,asset_files=('first.dm','second.dm','contract-resource.txt'),scope=__doc__)
    finally:
        cleanup=job.close()
        if evidence is not None:(evidence/'owned-job.json').write_text(json.dumps(cleanup,indent=2))
        if h is not None:h._owned_job=None
        if not cleanup['reaped']:raise RuntimeError('owned fixture children not reaped')
if __name__=='__main__':raise SystemExit(main())
