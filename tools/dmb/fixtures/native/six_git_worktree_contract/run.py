"""Tiny actual Git worktree isolation contract; no DeepQuarry performance claim."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid
HERE = Path(__file__).resolve().parent
BENCH = HERE.parents[2] / "bench"
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module
REJECTED = "/proc/probe()\n    return formerly_missing()\n"
BASE = "/datum/control\n    var/value = 7\n/proc/probe()\n    return 7\n"
def revision(index, changed):
    if not changed: return BASE
    if index == 0: return BASE.replace("return 7", "return 9")
    if index == 1: return BASE + "/datum/control\n    var/extra = 11\n/proc/added()\n    return 11\n"
    return BASE

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ("native", "template"):
        parser.add_argument("--"+name, type=Path, required=True)
        parser.add_argument("--"+name+"-sha256", required=True)
    parser.add_argument("--output-root", type=Path, default=Path("E:/dq-cache/dmb-six-git-contract"))
    args=parser.parse_args()
    if os.name != "nt": raise ValueError("Windows owned Job required")
    sys.path.insert(0,str(BENCH))
    h=load("six_git_iteration",BENCH/"native-iteration.py")
    core=load("six_git_core",HERE.parent/"incremental_runtime_contract/run.py")
    fresh=load("six_git_fresh",BENCH/"native-fresh.py")
    from upgrade_owned_job import OwnedJob
    from watchdog import terminate_owned
    parent=h.safe_e(args.output_root); parent.mkdir(parents=True,exist_ok=True)
    root=parent/uuid.uuid4().hex;root.mkdir()
    started=time.monotonic();deadline=started+200
    cleanup_deadline=started+240
    receipt={"schema":1,"complete":False,"scope":"tiny six registered Git roots, same daemon, fresh byte oracle; not large-project acceptance", "job_memory_bytes":4*1024**3,"overall_seconds":240,"child_seconds":30,"total_workers":2,"children":{},"roots":[],"pins":{}}
    job=daemon=None;previous=(h._owned_job,h._daemon_namespace)
    registered=[];repo=root/"repo"
    worktree_parent=h.safe_e(Path("E:/projects/dq-wt"))
    if not worktree_parent.is_dir(): raise ValueError("worktree parent missing")
    def git(*arguments):
        result=subprocess.run(["git",*arguments],capture_output=True,text=True,timeout=max(.01,min(30,deadline-time.monotonic())),creationflags=subprocess.CREATE_NO_WINDOW)
        receipt.setdefault("git",[]).append({"arguments":arguments,"exit":result.returncode,"stdout":result.stdout,"stderr":result.stderr})
        if result.returncode: raise ValueError("owned Git operation failed")
        return result.stdout.strip()
    try:
        for name in ("native","template"):
            path=getattr(args,name).resolve(strict=True);h.regular(path)
            if h.sha(path)!=getattr(args,name+"_sha256"): raise ValueError("pin mismatch")
            setattr(args,name,path);receipt["pins"][name]={"path":str(path),"sha256":h.sha(path)}
        repo.mkdir();git("init",str(repo))
        (repo/"probe.dm").write_text(BASE);(repo/"probe.dme").write_text('#include "probe.dm"\n')
        git("-C",str(repo),"add","probe.dm","probe.dme")
        git("-C",str(repo),"-c","user.name=Owned fixture","-c","user.email=fixture@invalid","commit","-m","Tiny source authority")
        commit=git("-C",str(repo),"rev-parse","HEAD");receipt["revision"]=commit
        for i in range(6):
            path=worktree_parent/("six-contract-"+root.name+"-"+str(i))
            if path.exists(): raise ValueError("refuse existing worktree target")
            git("-C",str(repo),"worktree","add","--detach",str(path),commit)
            registered.append(path);receipt["roots"].append(str(path))
        roster=git("-C",str(repo),"worktree","list","--porcelain")
        if any("worktree "+str(path).replace("\\","/") not in roster.replace("\\","/") for path in registered): raise ValueError("registration missing")
        job=OwnedJob(receipt["job_memory_bytes"]);h._owned_job=job
        cache=root/"cache";namespace,endpoint,environment=core.owned_daemon_route(h,cache,args.native,args.native_sha256,owned_job=job)
        environment["DMB_DAEMON_MAX_WORKERS"]="2"
        environment["DMB_DAEMON_SOFT_PRIVATE_BYTES"]=str(2*1024**3)
        receipt["namespace"]=namespace;receipt["daemon_endpoint_descriptor"]=endpoint.descriptor;endpoint.probe()
        def compile_one(i,changed,retained,phase=None):
            path=registered[i];source=revision(i,changed)
            if (path/"probe.dm").read_text()!=source: raise ValueError("source admission mismatch")
            before={name:h.sha(path/name) for name in ("probe.dm","probe.dme")}
            label=(phase or ("edited" if changed else "initial"))+"/"+("retained" if retained else "fresh")+str(i)
            output=root/label;output.mkdir(parents=True)
            arguments=core.compile_arguments(path/"probe.dme",output,args.template,retained)
            arguments[arguments.index("--workers")+1]="1"
            result=h.run_child(args.native,arguments,output/"logs",min(deadline,time.monotonic()+30),require_owned=retained,cache_directory=cache)
            receipt["children"][label]={"result":result,"arguments":arguments,"source_sha256":before}
            if result["exit"]!=0 or any(h.sha(path/name)!=digest for name,digest in before.items()): raise ValueError("compile/source failure")
            published=fresh.read_json(output/"compile-result.json",65536)
            acquired_file=output/"acquired.json";slots=output/"slots"
            acquire_arguments=["acquire","--output-store",str(output/"store"),"--pair-id",published["pair_id"],"--slots",str(slots),"--result-file",str(acquired_file)]
            acquired_result=h.run_child(args.native,acquire_arguments,output/"acquire",min(deadline,time.monotonic()+30),cache_directory=cache)
            receipt["children"][label]["acquire"]={"result":acquired_result,"arguments":acquire_arguments}
            if acquired_result["exit"]: raise ValueError("acquire failed")
            acquired=fresh.read_json(acquired_file,65536)
            hashes=fresh.admit_pair(published,acquired,output/"artifacts/probe.dme",output/"store",slots,h.regular,h.sha)
            receipt["children"][label]["pair"]={"published":published,"acquired":acquired,"outputs":hashes}
            return {extension:{key:row[key] for key in ("sha256","bytes")} for extension,row in hashes.items()}
        def reject_one(retained):
            path=registered[0]
            if (path/"probe.dm").read_text()!=REJECTED: raise ValueError("rejected source admission mismatch")
            label="source-error/"+("retained" if retained else "fresh")
            output=root/label;output.mkdir(parents=True)
            before={name:h.sha(path/name) for name in ("probe.dm","probe.dme")}
            arguments=core.compile_arguments(path/"probe.dme",output,args.template,retained)
            arguments[arguments.index("--workers")+1]="1"
            result=h.run_child(args.native,arguments,output/"logs",min(deadline,time.monotonic()+30),require_owned=retained,cache_directory=cache)
            diagnostics=(output/"logs/stderr.log").read_text(encoding="utf-8")
            errors=[line for line in diagnostics.splitlines() if ":error:" in line]
            receipt["children"][label]={"result":result,"arguments":arguments,"source_sha256":before,"source_errors":errors}
            if result["exit"]!=2 or not errors: raise ValueError("source rejection class/diagnostics differs")
            if any(h.sha(path/name)!=digest for name,digest in before.items()): raise ValueError("rejected source moved")
            pairs=output/"store/pairs"
            if (output/"compile-result.json").exists() or (pairs.exists() and any(pairs.iterdir())):
                raise ValueError("source failure published a pair")
            return errors
        # Independent serial fresh oracles precede daemon startup; no shared source edits race.
        oracles={}
        for changed in (False,True):
            for i,path in enumerate(registered):
                (path/"probe.dm").write_text(revision(i,changed));oracles[(i,changed)]=compile_one(i,changed,False)
        (registered[0]/"probe.dm").write_text(REJECTED)
        rejected_oracle=reject_one(False)
        for path in registered: (path/"probe.dm").write_text(BASE)
        with (root/"daemon.stdout").open("xb") as out,(root/"daemon.stderr").open("xb") as err:
            daemon=subprocess.Popen([str(args.native),"--serve-daemon"],stdout=out,stderr=err,env=environment,creationflags=subprocess.CREATE_NO_WINDOW|0x4)
        job.add(daemon);job.resume(daemon)
        ready=min(deadline,time.monotonic()+20)
        while not endpoint.probe(daemon):
            if daemon.poll() is not None or time.monotonic()>=ready: raise ValueError("daemon unavailable")
            time.sleep(.05)
        for changed in (False,True):
            for i,path in enumerate(registered): (path/"probe.dm").write_text(revision(i,changed))
            with ThreadPoolExecutor(max_workers=2) as pool:
                futures=[pool.submit(compile_one,i,changed,True) for i in range(6)]
                for i,future in enumerate(futures):
                    if future.result()!=oracles[(i,changed)]: raise ValueError("fresh byte oracle differs")
            if daemon.poll() is not None or not endpoint.probe(daemon): raise ValueError("daemon ownership lost")
        # A genuine source failure must not poison independent roots or the
        # previous successful pair; restored source then uses the ordinary path.
        previous_outputs=receipt["children"]["edited/retained0"]["pair"]["outputs"]
        (registered[0]/"probe.dm").write_text(REJECTED)
        with ThreadPoolExecutor(max_workers=2) as pool:
            failed=pool.submit(reject_one,True)
            unaffected=[pool.submit(compile_one,i,True,True,"during-error") for i in range(1,6)]
            if failed.result()!=rejected_oracle: raise ValueError("retained/fresh source diagnostics differ")
            for i,future in enumerate(unaffected,1):
                if future.result()!=oracles[(i,True)]: raise ValueError("source error contaminated another root")
        for row in previous_outputs.values():
            path=Path(row["acquired_path"]);h.regular(path)
            if h.sha(path)!=row["sha256"]: raise ValueError("source failure changed previous pair")
        (registered[0]/"probe.dm").write_text(revision(0,True))
        with ThreadPoolExecutor(max_workers=2) as pool:
            recovered=[pool.submit(compile_one,i,True,True,"recovery") for i in range(6)]
            for i,future in enumerate(recovered):
                if future.result()!=oracles[(i,True)]: raise ValueError("source-error recovery differs from fresh")
        if daemon.poll() is not None or not endpoint.probe(daemon): raise ValueError("daemon lost after recovery")
        for name in ("native","template"):
            if h.sha(getattr(args,name))!=receipt["pins"][name]["sha256"]: raise ValueError("pin moved")
        receipt["complete"]=True
    except Exception as error: receipt["error"]=str(error)
    finally:
        if daemon is not None: receipt["daemon_cleanup"]=terminate_owned(daemon)
        if job is not None: receipt["job_cleanup"]=job.close()
        if any(not receipt.get(key,{}).get("reaped",False) for key in ("daemon_cleanup","job_cleanup")): receipt["complete"]=False
        h._owned_job,h._daemon_namespace=previous
        # Only roots created and registered by this invocation are removable.
        deadline=cleanup_deadline
        for path in reversed(registered):
            try: git("-C",str(repo),"worktree","remove","--force",str(path))
            except Exception as error: receipt["complete"]=False;receipt.setdefault("cleanup_errors",[]).append(str(error))
        (root/"receipt.json").write_text(json.dumps(receipt,indent=2));print(root/"receipt.json")
    return 0 if receipt["complete"] else 1
if __name__=="__main__": raise SystemExit(main())
