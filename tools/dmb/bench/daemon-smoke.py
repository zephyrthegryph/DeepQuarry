"""Tiny owned-daemon four-revision correctness smoke; no performance acceptance."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid

HERE = Path(__file__).resolve().parent
BASE = "/datum/control\n    var/value = 7\n/datum/control/leaf\n    var/leaf_value = 5\n/proc/probe()\n    return 7\n"
REVISIONS = (
    ("initial", BASE),
    ("unchanged", BASE),
    ("body", BASE.replace("return 7", "return 9")),
    ("leaf-var", BASE.replace("return 7", "return 9") + "/datum/control/leaf\n    var/extra = 11\n"),
)


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("compiler", "template"):
        parser.add_argument("--" + name, required=True, type=Path)
        parser.add_argument("--" + name + "-sha256", required=True)
    parser.add_argument("--build-receipt", required=True, type=Path)
    parser.add_argument("--output-root", type=Path, default=Path("E:/dq-cache/dmb-daemon-smoke"))
    parser.add_argument("--overall-seconds", type=int, default=600)
    args = parser.parse_args()
    if os.name != "nt":
        raise ValueError("Windows owned Job is required")
    if not 300 <= args.overall_seconds <= 1200:
        raise ValueError("overall seconds must be between 300 and 1200")
    sys.path.insert(0, str(HERE))
    from upgrade_owned_job import OwnedJob
    from watchdog import terminate_owned
    from build_receipt import authenticate
    h = load("daemon_smoke_iteration", HERE / "native-iteration.py")
    fresh = load("daemon_smoke_fresh", HERE / "native-fresh.py")
    core = load("daemon_smoke_core", HERE.parent / "fixtures/native/incremental_runtime_contract/run.py")
    parent = h.safe_e(args.output_root)
    parent.mkdir(parents=True, exist_ok=True)
    root = parent / uuid.uuid4().hex
    root.mkdir()
    started = time.monotonic()
    deadline = started + args.overall_seconds - 15
    report = {"schema_version": 1, "status": "running", "scope": "tiny actual CLI daemon initial/unchanged/body/leaf-var fresh-byte parity; not real-project, six-worktree, runtime or performance acceptance",
              "overall_seconds": args.overall_seconds, "child_seconds": 300,
              "job_memory_bytes": 4 * 1024**3, "daemon_soft_private_bytes": 2 * 1024**3,
              "total_workers": 2, "children": {}, "rows": [], "pins": {}}
    previous = h._owned_job, h._daemon_namespace
    job = daemon = None
    try:
        for name in ("compiler", "template"):
            file = getattr(args, name).resolve(strict=True)
            h.regular(file)
            digest = getattr(args, name + "_sha256")
            if not re.fullmatch(r"[0-9a-f]{64}", digest) or h.sha(file) != digest:
                raise ValueError("pin mismatch: " + name)
            setattr(args, name, file)
            report["pins"][name] = {"path": str(file), "sha256": digest}
        report["build_receipt"] = authenticate(args.build_receipt, args.compiler, h.sha)
        namespace = "daemon-smoke-" + root.name
        h._daemon_namespace = namespace
        job = OwnedJob(report["job_memory_bytes"])
        h._owned_job = job
        endpoint = h.Endpoint(args.compiler, args.compiler_sha256, namespace, owned_job=job)
        report["daemon_endpoint_descriptor"] = endpoint.descriptor
        report["namespace"] = namespace
        endpoint.probe()  # An occupied endpoint is refused, never retired.
        cache = root / "cache"
        environment = os.environ.copy()
        environment.update(DMB_DAEMON_NAMESPACE=namespace, DMB_CACHE_DIR=str(cache),
                           DMB_DAEMON_MAX_WORKERS="2", DMB_DAEMON_SOFT_PRIVATE_BYTES=str(2 * 1024**3),
                           DMB_DAEMON_AUTOSTART="0")
        source = root / "source"
        source.mkdir()
        project = source / "probe.dme"
        project.write_text('#include "probe.dm"\n', encoding="utf-8")

        def compile_revision(label, text, retained):
            (source / "probe.dm").write_text(text, encoding="utf-8")
            before = {name: h.sha(source / name) for name in ("probe.dm", "probe.dme")}
            key = ("retained/" if retained else "fresh/") + label
            output = root / key
            output.mkdir(parents=True)
            arguments = core.compile_arguments(project, output, args.template, retained)
            result = h.run_child(args.compiler, arguments, output / "compile", min(deadline, time.monotonic() + 300),
                                 require_owned=retained, cache_directory=cache)
            row = {"arguments": arguments, "result": result, "source_sha256": before}
            report["children"][key] = row
            if result["exit"] != 0:
                raise ValueError(key + " compiler failed")
            if any(h.sha(source / name) != digest for name, digest in before.items()):
                raise ValueError(key + " source moved during compilation")
            published = fresh.read_json(output / "compile-result.json", 65536)
            acquired_file, slots = output / "acquired.json", output / "slots"
            acquire_args = ["acquire", "--output-store", str(output / "store"), "--pair-id", published["pair_id"],
                            "--slots", str(slots), "--result-file", str(acquired_file)]
            acquired_result = h.run_child(args.compiler, acquire_args, output / "acquire", min(deadline, time.monotonic() + 300), cache_directory=cache)
            row["acquire"] = {"arguments": acquire_args, "result": acquired_result}
            if acquired_result["exit"] != 0:
                raise ValueError(key + " acquisition failed")
            acquired = fresh.read_json(acquired_file, 65536)
            outputs = fresh.admit_pair(published, acquired, output / "artifacts/probe.dme", output / "store", slots, h.regular, h.sha)
            row.update(published=published, acquired=acquired, outputs=outputs)
            return {kind: {field: item[field] for field in ("sha256", "bytes")} for kind, item in outputs.items()}

        # Every fresh oracle completes before the one owned daemon is started.
        oracles = {label: compile_revision(label, text, False) for label, text in REVISIONS}
        with (root / "daemon.stdout").open("xb") as out, (root / "daemon.stderr").open("xb") as err:
            daemon = subprocess.Popen([str(args.compiler), "--serve-daemon"], stdout=out, stderr=err,
                                      env=environment, creationflags=subprocess.CREATE_NO_WINDOW | 0x4)
        job.add(daemon)
        job.resume(daemon)
        report["owned_daemon_pid"] = daemon.pid
        ready = min(deadline, time.monotonic() + 20)
        while not endpoint.probe(daemon):
            if daemon.poll() is not None or time.monotonic() >= ready:
                raise ValueError("owned daemon readiness failed")
            time.sleep(.05)
        for label, text in REVISIONS:
            if daemon.poll() is not None or not endpoint.probe(daemon):
                raise ValueError("owned daemon unavailable before " + label)
            actual = compile_revision(label, text, True)
            agrees = actual == oracles[label]
            report["rows"].append({"revision": label, "fresh": oracles[label], "retained": actual, "byte_equal": agrees})
            if not agrees:
                raise ValueError(label + " retained output differs from fresh")
        if not endpoint.probe(daemon):
            raise ValueError("owned daemon disappeared after final revision")
        for name in ("compiler", "template"):
            if h.sha(getattr(args, name)) != report["pins"][name]["sha256"]:
                raise ValueError("pin moved: " + name)
        report["status"] = "passed"
    except BaseException as error:
        report.update(status="failed", error=str(error))
    finally:
        if daemon is not None:
            report["daemon_cleanup"] = terminate_owned(daemon)
        if job is not None:
            report["job_cleanup"] = job.close()
        if (daemon is not None and report.get("daemon_cleanup", {}).get("reaped") is not True
                or job is not None and report.get("job_cleanup", {}).get("reaped") is not True):
            report.update(status="failed", cleanup_incomplete=True)
        h._owned_job, h._daemon_namespace = previous
        report["wall_seconds"] = time.monotonic() - started
        report["timing_admitted"] = False
        (root / "receipt.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(json.dumps({"receipt": str(root / "receipt.json"), "status": report["status"]}))
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
