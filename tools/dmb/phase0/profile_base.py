"""Run ONE bounded Phase 0 scenario against immutable frozen sources.
No scenario is launched on import. Run cold and daemon-body separately.
"""
import argparse
import ctypes
import errno
import shutil
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import threading
import time
from trace_records import is_build_trace

EDIT = Path("code/datums/interactions/tools.dm")
PATTERN = re.compile(rb"(?m)(^/proc/tool_skill_factor\(mob/actor, quality\)\r?\n\s*return )1(?=\r?$)")


def digest(file, deadline=None):
    value=hashlib.sha256()
    with Path(file).open("rb") as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b""):
            if deadline is not None and time.monotonic()>=deadline:return None
            value.update(chunk)
    return value.hexdigest()


def kill_tree(process):
    if process.poll() is not None:return
    if os.name=="nt":
        subprocess.run(["taskkill","/PID",str(process.pid),"/T","/F"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=5)
    else:os.killpg(process.pid,signal.SIGKILL)


def main():
    if os.name=="nt":ctypes.windll.kernel32.SetErrorMode(3)
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario",choices=("cold","daemon-body"),required=True)
    parser.add_argument("--source",default="D:/dmb-native-v2-phase0/frozen/source")
    parser.add_argument("--compiler",required=True)
    parser.add_argument("--daemon")
    parser.add_argument("--builtins",required=True)
    parser.add_argument("--output",required=True,help="New dedicated run directory")
    parser.add_argument("--samply",help="Optional sampler path; disabled by default at user request")
    parser.add_argument("--xperf-directory",default="C:/Program Files (x86)/Windows Kits/10/Windows Performance Toolkit")
    parser.add_argument("--timeout",type=float,default=300)
    parser.add_argument("--sample-rate",type=int,default=100)
    parser.add_argument("--define",action="append",default=[])
    parser.add_argument("--manifest",default="comparison.dme")
    args=parser.parse_args()
    if not 20<=args.timeout<=300:parser.error("Overall timeout must be20..300seconds")
    if not 1<=args.sample_rate<=500:parser.error("Sample rate must be1..500Hz")
    if args.scenario=="daemon-body" and not args.daemon:parser.error("daemon-body requires --daemon")
    started=time.monotonic(); start_unix=time.time()
    root=Path(args.output).resolve();root.mkdir(parents=True,exist_ok=False)
    source=Path(args.source).resolve(); mirror=root/"source"; mirror.mkdir()
    env=os.environ.copy();env.pop("GIT_WORK_TREE",None)
    if os.name=="nt" and args.samply:
        xperf=Path(args.xperf_directory)/"xperf.exe"
        if not xperf.is_file():raise FileNotFoundError(f"Windows sampling requires {xperf}")
        env["PATH"]=str(xperf.parent)+os.pathsep+env.get("PATH","")
    env.update(DM_BUILD_TRACE="1",DM_DAEMON_WORKERS="1",DM_COMPILER_WORKERS="2",DM_MEMORY_LIMIT_MB="0",GIT_DIR=str(root/"isolated.git"))
    processes=[]; handles=[]; events=[]; timed_out=threading.Event()
    phase_deadline=started+args.timeout-15
    receipt={"arguments":vars(args),"started_unix":start_unix,"scenario":args.scenario,
             "os_cache":"uncontrolled; application caches new/empty", "events":events,
             "profile_scope":"cold whole command" if args.scenario=="cold" else "daemon startup+baseline+body edit; filter body interval from events",
             "tools":{},"status":"started", "compiler_memory_limit_mb": 0,
             "compiler_workers": 2, "daemon_workers": 1,
             "sampling_enabled":bool(args.samply),
             "sampling_gate":"pending sampled frames" if args.samply else "deferred at user request; built-in timing only",
             "watchdog_scope":"input preparation and each command separately; daemon spans baseline/body commands",
             "phase_budget_seconds":args.timeout,
             "storage":{"source":str(source),"source_drive":source.drive,
                        "run":str(root),"run_drive":root.drive,
                        "cache_drive":root.drive,"published_drive":root.drive},
             "mirror":{"copied_files":0,"copied_bytes":0,"hardlinked_files":0,"hardlinked_bytes":0}}
    def event(name,**fields):events.append(dict(name=name,elapsed=time.monotonic()-started,unix=time.time(),**fields))
    def remaining():
        value=phase_deadline-time.monotonic()
        if timed_out.is_set() or value<=0:raise TimeoutError("overall deadline; cleanup reserve15seconds")
        return value
    def watchdog():
        timed_out.set()
        for process in tuple(processes):
            try:kill_tree(process)
            except (OSError,subprocess.TimeoutExpired):pass
    timer=threading.Timer(args.timeout-15,watchdog);timer.daemon=True;timer.start()
    def arm_watchdog(phase):
        nonlocal timer,phase_deadline
        remaining();timer.cancel();phase_deadline=time.monotonic()+args.timeout-15
        timer=threading.Timer(args.timeout-15,watchdog);timer.daemon=True;timer.start()
        event("phase_deadline_armed",phase=phase,budget_seconds=args.timeout)
    def hidden():
        if os.name!="nt":return None
        info=subprocess.STARTUPINFO();info.dwFlags|=subprocess.STARTF_USESHOWWINDOW;info.wShowWindow=0;return info
    def launch(command,name):
        arm_watchdog(name);out=(root/(name+".stdout.log")).open("wb");err=(root/(name+".stderr.log")).open("wb");handles.extend((out,err))
        process=subprocess.Popen(command,cwd=mirror,env=env,stdout=out,stderr=err,startupinfo=hidden(),
                                 creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if os.name=="nt" else 0,
                                 start_new_session=os.name!="nt")
        processes.append(process);event(name+"_start",pid=process.pid,command=command);return process
    def wait(process,name):
        code=process.wait(timeout=remaining());event(name+"_end",exit_code=code)
        if code:raise RuntimeError(f"{name} exited{code}")
    try:
        for name,file in (("compiler",args.compiler),("daemon",args.daemon),("builtins",args.builtins),("samply",args.samply)):
            if file:
                receipt["tools"][name]={"path":str(Path(file).resolve()),"sha256":digest(file,started+args.timeout-15)}
        # Version probes are part of the bounded future run, not run while preparing
        # this harness. Preserve unsupported --version exits instead of guessing.
        for name,file in (("compiler",args.compiler),("daemon",args.daemon),("samply",args.samply)):
            if file:
                try:
                    version=subprocess.run([str(Path(file).resolve()),"--version"],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=min(2,remaining()),startupinfo=hidden())
                    receipt["tools"][name]["version_probe"]={"exit_code":version.returncode,"text":version.stdout.decode(errors="replace")[:4096]}
                except (OSError,subprocess.TimeoutExpired) as error:receipt["tools"][name]["version_probe_error"]=str(error)
        preparation_started=time.monotonic()
        event("input_preparation_start")
        # Frozen inputs are linked read-only by convention; edited body is copied.
        # Cross-volume runs copy immutable bytes when links are impossible.
        # No .git/cache/old binary outputs enter the new application-cache context.
        for current,dirs,files in os.walk(source):
            remaining();rel=Path(current).relative_to(source)
            dirs[:]=[name for name in dirs if name not in (".git",".cache","target","node_modules")
                     and not (rel==Path(".") and name in ("data","code-live-reference"))]
            destination=mirror/rel;destination.mkdir(exist_ok=True)
            for name in files:
                remaining();relative=rel/name
                if Path(name).suffix.lower() in (".dmb",".rsc"):continue
                origin=Path(current)/name; target=destination/name; size=origin.stat().st_size
                copied=relative==EDIT
                if copied:shutil.copyfile(origin,target)
                else:
                    try:os.link(origin,target)
                    except OSError as error:
                        if error.errno!=errno.EXDEV and getattr(error,"winerror",None)!=17:raise
                        shutil.copyfile(origin,target);copied=True
                kind="copied" if copied else "hardlinked"
                receipt["mirror"][kind+"_files"]+=1;receipt["mirror"][kind+"_bytes"]+=size
        git=subprocess.run(["git","init","--bare",str(root/"isolated.git")],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=remaining(),startupinfo=hidden())
        if git.returncode:raise RuntimeError(git.stderr.decode(errors="replace"))
        receipt["input_preparation_seconds"]=time.monotonic()-preparation_started
        event("inputs_prepared",edited_input_sha256=digest(mirror/EDIT),seconds=receipt["input_preparation_seconds"])
        defines=args.define or ["-DCBT","-DCIBUILDING","-DCITESTING"]
        command=[str(Path(args.compiler).resolve()),"build-project",args.manifest,str(Path(args.builtins).resolve()),str(root/"published"),*defines]
        sampler=([str(Path(args.samply).resolve()),"record","--rate",str(args.sample_rate),"--keep-etl","--save-only","--no-open","--unstable-presymbolicate","--windows-symbol-cache",str(root/"symbol-cache"),"--symbol-dir",str(Path(args.compiler).resolve().parent),"--output",str(root/"profile.json"),"--"] if args.samply else [])
        if args.scenario=="cold":
            timing=root/"compiler-timing.json"
            wrapper=[sys.executable,str(Path(__file__).with_name("timed_command.py").resolve()),str(timing)]
            wait(launch(sampler+wrapper+command,"cold_capture"),"cold_capture")
            execution=json.loads(timing.read_text(encoding="utf-8"))
            receipt["compiler_execution"]=execution
            if execution.get("status")!="completed" or execution.get("exit_code")!=0:
                raise RuntimeError("sampled compiler failed; see compiler-timing.json")
        else:
            # Reserve an ephemeral loopback port; failure/race is visible, not retried
            # with another compiler/cache context.
            with socket.socket() as reserve:reserve.bind(("127.0.0.1",0));port=reserve.getsockname()[1]
            daemon=launch(sampler+[str(Path(args.daemon).resolve()),str(port),str(root/"daemon-cache")],"daemon")
            while True:
                remaining()
                if daemon.poll() is not None:raise RuntimeError("sampled daemon exited before readiness")
                try:
                    with socket.create_connection(("127.0.0.1",port),timeout=min(1,remaining())) as connection:
                        connection.sendall(b'{"command":"ping"}\n');connection.settimeout(1);reply=connection.recv(65536)
                        if not reply:raise OSError("empty ping")
                    break
                except OSError:time.sleep(.1)
            client=[command[0],"build-project-daemon",f"127.0.0.1:{port}",*command[2:]]
            wait(launch(client,"baseline"),"baseline")
            edited=mirror/EDIT;before=edited.read_bytes()
            if len(PATTERN.findall(before))!=1:raise RuntimeError("isolated literal-return edit not found exactly once")
            edited.write_bytes(PATTERN.sub(rb"\g<1>2",before));event("body_edit_written",sha256=digest(edited))
            wait(launch(client,"body"),"body")
            # Ask sampler to stop and save. If backend ignores the signal, deadline
            # cleanup kills it and receipt explicitly marks the profile unavailable.
            event("sampler_stop_requested")
            arm_watchdog("sampler_finalization")
            if args.samply:
                if os.name=="nt":daemon.send_signal(signal.CTRL_BREAK_EVENT)
                else:daemon.send_signal(signal.SIGINT)
                try:daemon.wait(timeout=remaining())
                except subprocess.TimeoutExpired:kill_tree(daemon)
            else:
                kill_tree(daemon)
        receipt["status"]="completed"
    except Exception as error:
        receipt["status"]="timeout" if timed_out.is_set() or isinstance(error,(TimeoutError,subprocess.TimeoutExpired)) else "failed"
        receipt["error"]=str(error)
    finally:
        timer.cancel()
        for process in reversed(processes):
            try:kill_tree(process)
            except (OSError,subprocess.TimeoutExpired) as error:event("cleanup_error",error=str(error))
        for handle in handles:
            try:handle.close()
            except OSError as error:event("log_close_error",error=str(error))
        receipt["elapsed_seconds"]=time.monotonic()-started
        receipt["profile_present"]=(root/"profile.json").exists()
        receipt["outputs"]=[]
        try:
            for path in (root/"published").glob("**/*"):
                if time.monotonic()>=phase_deadline+14:
                    receipt["output_inventory_truncated"]=True;break
                if path.is_file() and path.suffix.lower() in (".dmb",".rsc"):
                    try:receipt["outputs"].append({"path":str(path),"sha256":digest(path,phase_deadline+14)})
                    except OSError as error:receipt["outputs"].append({"path":str(path),"hash_error":str(error)})
        except OSError as error:receipt["output_inventory_error"]=str(error)
        # Optional receipt enrichment cannot prevent the primary receipt write.
        try:
            with (root/"stages.log").open("w",encoding="utf-8") as stages:
                for log in sorted(root.glob("*.log")):
                    if log.name=="stages.log":continue
                    with log.open(encoding="utf-8",errors="replace") as stream:
                        for line in stream:
                            if time.monotonic()>=phase_deadline+14:
                                receipt["stage_summary_truncated"]=True;break
                            if is_build_trace(line):stages.write(log.name+": "+line)
        except OSError as error:receipt["stage_summary_error"]=str(error)
        receipt["elapsed_including_receipts_seconds"]=time.monotonic()-started
        (root/"receipt.json").write_text(json.dumps(receipt,indent=2)+"\n",encoding="utf-8")
    if receipt["status"]!="completed":raise SystemExit(1)

if __name__=="__main__":main()
