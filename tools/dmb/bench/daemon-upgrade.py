"""Bounded actual-client dual-generation upgrade; requires namespace-aware binaries.
No direct Retire command, runtime gate or performance acceptance.
"""
import argparse
import ctypes
from ctypes import wintypes
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import threading
import time
import uuid
from upgrade_owned_job import OwnedJob
from session_acceptance import bounded_policy

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module

L = load("upgrade_lifecycle", Path(__file__).with_name("daemon-lifecycle.py"))
I = L.iteration

def hello(endpoint, job, deadline):
    handle = endpoint.kernel.CreateFileW(endpoint.name, 0xc0000000, 0, None, 3, 0, None)
    if handle == ctypes.c_void_p(-1).value: return None
    pipe = L.Pipe.__new__(L.Pipe); pipe.endpoint = endpoint; pipe.deadline = deadline
    try:
        pid = wintypes.ULONG()
        if not endpoint.kernel.GetNamedPipeServerProcessId(handle, ctypes.byref(pid)):
            raise ctypes.WinError(ctypes.get_last_error())
        image = job.image(pid.value)
        pipe._adopt_handle(handle); handle = None
        pipe.send({"Hello": {"version": 4, "compiler": 0}})
        reply = pipe.receive()
        if not isinstance(reply, dict) or "Hello" not in reply: raise RuntimeError("invalid isolated Hello")
        return pid.value, image, reply["Hello"]
    finally:
        if handle is not None: endpoint.kernel.CloseHandle(handle)
        elif hasattr(pipe, "file"): pipe.close()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("old", "new", "template"):
        parser.add_argument("--" + name, required=True)
        parser.add_argument("--" + name + "-sha256", required=True)
    parser.add_argument("--source", help="existing captured real project root; copied by the shared source isolation core")
    parser.add_argument("--project", default="world.dme", help="contained relative manifest in --source")
    parser.add_argument("--job-memory-mib", type=int, default=4096)
    parser.add_argument("--total-workers", type=int, default=2, help="concurrent old/new generation worker budget (2..8)")
    parser.add_argument("--overall-seconds", type=int, default=1800)
    parser.add_argument("--output-root", default="E:/dq-cache/dmb-upgrade")
    args = parser.parse_args()
    if os.name != "nt": raise RuntimeError("owned Windows job harness required")
    if not 1 <= args.overall_seconds <= 3600: raise ValueError("overall deadline must be 1..3600 seconds")
    job_bytes = bounded_policy(args.total_workers, 2, args.job_memory_mib)
    pins = {name: I.safe_e(getattr(args, name)) for name in ("old", "new", "template")}
    for name, path in pins.items():
        I.regular(path)
        if I.sha(path) != getattr(args, name + "_sha256"): raise ValueError("pinned input mismatch: " + name)
    if args.old_sha256 == args.new_sha256: raise ValueError("distinct compiler generations required")
    root = I.safe_e(args.output_root) / uuid.uuid4().hex
    if not root.is_relative_to(Path("E:/dq-cache")): raise ValueError("owned E cache root required")
    root.mkdir(parents=True); source = root / "source"
    manifest = Path(args.project)
    if manifest.is_absolute() or manifest.drive or ".." in manifest.parts: raise ValueError("manifest must be contained relative path")
    source_proof = None
    if args.source:
        captured = I.safe_e(args.source)
        I.regular(captured / manifest)
        source_proof = {"captured_root": str(captured), "manifest_sha256": I.sha(captured / manifest),
            "isolated_files": I.isolate(captured, source)}
    else:
        if manifest != Path("world.dme"): raise ValueError("synthetic upgrade requires world.dme")
        source.mkdir()
    project = source / manifest
    if not args.source: project.write_text('/world/name = "upgrade"\n' + ''.join('/proc/probe_%d()\n    return %d\n' % (n,n) for n in range(512)), encoding="utf-8")
    namespace = "upgrade-" + uuid.uuid4().hex
    endpoint = I.Endpoint(); endpoint.name += "-" + namespace
    endpoint.probe()  # Never probes or retires the default user endpoint.
    env = os.environ.copy(); env["DMB_DAEMON_NAMESPACE"] = namespace; env["DMB_CACHE_DIR"] = str(root / "cache")
    env.pop("DMB_DAEMON_AUTOSTART", None)
    deadline = time.monotonic() + args.overall_seconds; job = OwnedJob(job_bytes); owned = []
    report = {"schema_version": 1, "status": "running", "namespace": namespace,
        "scope": "actual new-client draining upgrade plus fresh byte oracles; not six-worktree/runtime/performance acceptance",
        "source": source_proof or {"kind": "synthetic", "procedures": 512},
        "overall_seconds": args.overall_seconds, "per_child_seconds": 300,
        "pins": {name: {"path":str(path), "sha256":I.sha(path)} for name,path in pins.items()},
        "memory_scope": "owned Windows job configured commit limit including inherited autostart descendants"}
    first_diagnostic = threading.Event(); completed = threading.Event(); old_result = {}; thread = None
    def start(exe, arguments, name):
        out = (root / (name + ".stdout")).open("xb"); err = (root / (name + ".stderr")).open("xb")
        try: child = subprocess.Popen([str(exe), *arguments], env=env, stdout=out, stderr=err, creationflags=subprocess.CREATE_NO_WINDOW | 0x4)
        finally: out.close(); err.close()
        owned.append(child); job.add(child); job.resume(child); return child
    generation_workers = max(1, args.total_workers // 2)
    report["total_worker_budget"] = args.total_workers
    report["owned_job_memory_limit_bytes"] = job_bytes
    def command(name, fresh=False):
        values = ["compile", str(project), "--engine-template", str(pins["template"]), "--bootstrap-catalog", "--workers", str(generation_workers), "--exact-inputs", "--artifact-directory", str(root/name/"artifacts"), "--output-store", str(root/name/"store")]
        return values + (["--no-daemon", "--no-cache"] if fresh else [])
    try:
        # Prove the new binary honors the isolated endpoint before giving its
        # normal client permission to retire/autostart any server.
        preflight = start(pins["new"], ["--serve-daemon"], "namespace-preflight")
        startup_deadline = min(deadline, time.monotonic() + 20)
        while not endpoint.probe(preflight):
            if preflight.poll() is not None or time.monotonic() >= startup_deadline:
                raise RuntimeError("new compiler lacks required isolated namespace")
            time.sleep(.02)
        report["namespace_preflight_cleanup"] = L.terminate_owned(preflight)
        if not report["namespace_preflight_cleanup"]["reaped"]: raise RuntimeError("preflight not reaped")
        old = start(pins["old"], ["--serve-daemon"], "old-daemon")
        startup_deadline = min(deadline, time.monotonic() + 20)
        while not endpoint.probe(old):
            if old.poll() is not None or time.monotonic() >= startup_deadline: raise RuntimeError("namespace unsupported or old daemon startup failed")
            time.sleep(.02)
        def build_old():
            pipe = None
            try:
                pipe = L.Pipe(endpoint, old); pipe.deadline = min(deadline, time.monotonic() + 300)
                request = dict(command="Compile", project=str(project), defines={}, workers=generation_workers, engine_template=str(pins["template"]), bootstrap_catalog=True, progress_enabled=True, output_store=str(root/"old"/"store"), exact_inputs=True, no_cache=False, cache_root=str(root/"cache"), record_inputs=None, replay_inputs=None, artifact_directory=str(root/"old"/"artifacts"), no_daemon=False, trace_path=None)
                pipe.send({"Build":request})
                while True:
                    reply = pipe.receive()
                    if isinstance(reply,dict) and "Diagnostic" in reply: first_diagnostic.set()
                    if isinstance(reply,dict) and "Rejected" in reply: raise RuntimeError(str(reply))
                    if isinstance(reply,dict) and "Completed" in reply:
                        if "Published" not in reply["Completed"]: raise RuntimeError("old compile did not publish a pair")
                        old_result["reply"] = reply; break
            except Exception as error: old_result["error"] = str(error)
            finally:
                if pipe: pipe.close()
                completed.set()
        thread = threading.Thread(target=build_old); thread.start()
        while not first_diagnostic.wait(.02):
            if completed.is_set() or time.monotonic() >= deadline: raise RuntimeError("no active old-build window")
        if completed.is_set(): raise RuntimeError("old build already completed; no drain proof")
        new_deadline = min(deadline, time.monotonic() + 300)
        new = start(pins["new"], command("new"), "new-client")
        observed_drain = False; replacement = None
        while new.poll() is None:
            if time.monotonic() >= new_deadline: raise TimeoutError("new client exceeded bounded deadline")
            try: answer = hello(endpoint, job, min(deadline, time.monotonic()+2))
            except OSError: answer = None  # Old generation can exit between connect and Hello.
            if answer:
                pid, image, greeting = answer
                if pid == old.pid and greeting.get("retiring") and not completed.is_set(): observed_drain = True
                elif pid != old.pid:
                    if Path(image).resolve() != pins["new"].resolve() or I.sha(Path(image)) != args.new_sha256: raise RuntimeError("replacement image differs")
                    replacement = {"pid":pid, "image":image, "hello":greeting}
            time.sleep(.01)
        if replacement is None and new.returncode == 0:
            answer = hello(endpoint, job, min(deadline, time.monotonic() + 2))
            if answer:
                pid, image, greeting = answer
                if pid == old.pid or Path(image).resolve() != pins["new"].resolve() or I.sha(Path(image)) != args.new_sha256:
                    raise RuntimeError("completed client has no exact new-generation endpoint")
                replacement = {"pid": pid, "image": image, "hello": greeting}
        new.wait(timeout=max(.01, deadline-time.monotonic()))
        thread.join(timeout=max(.01, deadline-time.monotonic()))
        report.update(old_build=old_result, new_exit=new.returncode, drain_observed_before_old_completion=observed_drain, replacement=replacement)
        if thread.is_alive() or old_result.get("error") or not observed_drain or new.returncode != 0 or replacement is None: raise RuntimeError("upgrade/drain proof incomplete")
        if old.wait(timeout=max(.01, deadline-time.monotonic())) != 0: raise RuntimeError("old daemon failed while draining")
        for generation in ("old", "new"):
            fresh = generation + "-fresh"; child = start(pins[generation], command(fresh, True), fresh)
            if child.wait(timeout=max(.01, min(300, deadline-time.monotonic()))) != 0: raise RuntimeError("fresh oracle failed")
            report[generation+"_hashes"] = I.check_outputs(root/generation, root/fresh, manifest)
        if source_proof and I.sha(project) != source_proof["manifest_sha256"]: raise RuntimeError("isolated manifest changed")
        if any(I.sha(path) != report["pins"][name]["sha256"] for name,path in pins.items()): raise RuntimeError("pinned tool changed")
        report["status"] = "passed"
    except Exception as error: report.update(status="failed", error=str(error))
    finally:
        report["owned_job_cleanup"] = job.close()
        if thread: thread.join(timeout=5)
        report["cleanup"] = [L.terminate_owned(child) for child in owned]
        if not report["owned_job_cleanup"]["reaped"] or any(not item.get("reaped") for item in report["cleanup"]): report.update(status="failed", error="owned process not reaped")
        (root/"receipt.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
        print(json.dumps({"receipt":str(root/"receipt.json"),"status":report["status"]}))
    return 0 if report["status"] == "passed" else 1

if __name__ == "__main__": raise SystemExit(main())
