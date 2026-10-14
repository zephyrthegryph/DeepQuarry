"""Real owned-daemon query preparation; compiler-only correctness, no DD/timing claim."""
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
BENCH = HERE.parents[2] / "bench"

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def bounded(path):
    if path.stat().st_size > 1024 * 1024:
        raise ValueError("tiny evidence exceeds 1 MiB")
    return path.read_text(encoding="utf-8")

def rows(path):
    return [json.loads(line) for line in bounded(path).splitlines() if line.strip()]

def prepared(path, retained):
    values = rows(path)
    if len(values) != 1 or values[0].get("schema") != "dm-query-preparation-v1":
        raise ValueError("one actual preparation envelope required")
    value = values[0]
    if value.get("retained") is not retained or value.get("complete") is not False:
        raise ValueError("preparation retention/coverage differs")
    for field in ("semantic_revision", "source_revision"):
        if not re.fullmatch(r"[0-9a-f]{32}", value.get(field, "")):
            raise ValueError("missing exact current pin")
    return value

def discovered_symbol(items, name, owner="/"):
    matches = [row for row in items if row.get("name") == name and row.get("owner_path") == owner]
    if len(matches) != 1 or not re.fullmatch(r"[0-9a-f]{16}", matches[0].get("name_symbol", "")):
        raise ValueError("one exact current returned member symbol required")
    return int(matches[0]["name_symbol"], 16)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("native", "template"):
        parser.add_argument("--" + name, type=Path, required=True)
        parser.add_argument("--" + name + "-sha256", required=True)
    parser.add_argument("--output-root", type=Path, default=Path("E:/dq-cache/dmb-query-preparation-contract"))
    args = parser.parse_args()
    if os.name != "nt":
        raise ValueError("owned Windows pipe contract required")
    sys.path.insert(0, str(BENCH))
    h = load("query_contract_iteration", BENCH / "native-iteration.py")
    core = load("query_contract_runtime_core", HERE.parent / "incremental_runtime_contract/run.py")
    from upgrade_owned_job import OwnedJob
    from watchdog import terminate_owned
    parent = h.safe_e(args.output_root)
    parent.mkdir(parents=True, exist_ok=True)
    root = parent / uuid.uuid4().hex
    root.mkdir()
    receipt = {"schema":1, "complete":False, "scope":"owned-pipe query preparation and actual current host answers; no runtime or benchmark claim",
        "root":str(root), "pins":{}, "children":{}, "job_memory_bytes":4 * 1024 ** 3,
        "child_watchdog_seconds":30, "overall_watchdog_seconds":120}
    deadline = time.monotonic() + 120
    daemon = job = None
    previous_job, previous_namespace = h._owned_job, h._daemon_namespace
    try:
        for name in ("native", "template"):
            path = getattr(args, name).resolve(strict=True)
            h.regular(path)
            expected = getattr(args, name + "_sha256")
            if not re.fullmatch(r"[0-9a-f]{64}", expected) or h.sha(path) != expected:
                raise ValueError("pin mismatch: " + name)
            setattr(args, name, path)
            receipt["pins"][name] = {"path":str(path), "sha256":expected}
        source = root / "source"
        source.mkdir()
        receipt["fixture_sha256"] = {name:h.sha(HERE / name) for name in ("probe.dm", "probe.dme", "run.py")}
        for name in ("probe.dm", "probe.dme"):
            (source / name).write_bytes((HERE / name).read_bytes())
        project, cache = source / "probe.dme", root / "cache"
        job = OwnedJob(receipt["job_memory_bytes"])
        h._owned_job = job
        namespace, endpoint, environment = core.owned_daemon_route(h, cache, args.native, args.native_sha256, owned_job=job)
        receipt["daemon_namespace"] = namespace
        receipt["daemon_endpoint_descriptor"] = endpoint.descriptor
        endpoint.probe()  # refuses an existing foreign endpoint
        with (root / "daemon.stdout").open("xb") as out, (root / "daemon.stderr").open("xb") as err:
            daemon = subprocess.Popen([str(args.native), "--serve-daemon"], stdout=out, stderr=err,
                env=environment, creationflags=subprocess.CREATE_NO_WINDOW | 0x4)
        job.add(daemon)
        job.resume(daemon)
        receipt["owned_daemon_pid"] = daemon.pid
        ready_deadline = min(deadline, time.monotonic() + 20)
        while not endpoint.probe(daemon):
            if daemon.poll() is not None or time.monotonic() >= ready_deadline:
                raise ValueError("owned daemon unavailable")
            time.sleep(0.05)
        def run(label, arguments, expected_exit=None, retained=True):
            if retained and (daemon.poll() is not None or not endpoint.probe(daemon)):
                raise ValueError("owned daemon missing before request")
            folder = root / label
            result = h.run_child(args.native, arguments, folder, min(deadline, time.monotonic()+30),
                require_owned=retained, cache_directory=cache)
            receipt["children"][label] = {"result":result, "command":[str(args.native), *arguments],
                "stdout":str(folder / "stdout.log"), "stderr":str(folder / "stderr.log")}
            if expected_exit is not None and result["exit"] != expected_exit:
                raise ValueError(label + " exit differs")
            if retained and (daemon.poll() is not None or not endpoint.probe(daemon)):
                raise ValueError("owned daemon changed during request")
            return folder
        config = [str(project), "--workers", "1", "--exact-inputs", "--no-cache",
            "--engine-template", str(args.template), "--bootstrap-catalog"]
        prep = prepared(run("prepare", ["prepare-query", *config], 0)/"stdout.log", True)
        receipt["prepared"] = prep
        base = {"project":str(project), "defines":{}, "engine_template":str(args.template),
            "bootstrap_catalog":True, "expected_revision":prep["semantic_revision"],
            "expected_source_revision":prep["source_revision"], "queries":[], "source_queries":[], "timeout_seconds":20}
        def query(label, questions, stale=False):
            value = dict(base, source_queries=questions)
            if stale:
                value["expected_source_revision"] = "0" * 32
            path = root / (label + ".json")
            path.write_text(json.dumps(value), encoding="utf-8")
            return run(label, ["query", str(path), "--jsonl"], None if stale else 0)
        members, types = [], []
        for kind, target in (("SemanticMembersPage", members), ("SemanticTypesPage", types)):
            cursor = 0
            for page in range(16):
                output = query(kind+str(page), [{kind:{"start":cursor, "limit":128}}])
                values = rows(output/"stdout.log")
                envelope = values[-1]
                target.extend(envelope["items"])
                cursor = envelope["next_cursor"]
                if cursor is None:
                    break
            else:
                raise ValueError("tiny discovery exceeds 16 pages")
        if not types:
            raise ValueError("current type page empty")
        symbol = discovered_symbol(members, "query_known")
        query_wire = {"GlobalProc":symbol}
        result = rows(query("resolved", [{"ResolvedQueries":{"queries":[{"subject":"issued global", "query":query_wire}]}}])/"stdout.log")[-1]
        answer = json.loads(result["captured_jsonl"].strip())
        if json.loads(answer["query_wire"]) != query_wire or answer["answer"].get("status") != "known":
            raise ValueError("current global callable host answer unavailable")
        receipt["resolved_answer"] = answer
        stale = query("stale", [{"SemanticMembersPage":{"start":0,"limit":1}}], True)
        if receipt["children"]["stale"]["result"]["exit"] == 0 or "stale" not in bounded(stale/"stderr.log"):
            raise ValueError("stale source pin was not rejected")
        compile_result = run("compile_reject", ["compile", *config, "--artifact-directory",str(root/"artifacts"),
            "--output-store",str(root/"store")], 2)
        if ":error:" not in bounded(compile_result/"stderr.log"):
            raise ValueError("ordinary compile rejection lacks source diagnostic")
        receipt["one_shot"] = prepared(run("one_shot", ["prepare-query", *config, "--no-daemon"],0,False)/"stdout.log",False)
        # Resource staging may precede the ordinary source-error barrier. It is
        # not an executable pair; inspect only actual publication destinations.
        installed = [source / "probe.dmb", source / "probe.rsc", source / "probe.dmb-pair.json"]
        artifacts = root / "artifacts"
        pairs = root / "store" / "pairs"
        installed.extend(artifacts / name for name in ("probe.dmb", "probe.rsc", "probe.dmb-pair.json"))
        if any(path.exists() for path in installed) or (pairs.exists() and any(pairs.iterdir())):
            raise ValueError("preparation/rejected compilation published executable output")
        receipt["no_executable_publication"] = True
        for name in ("native", "template"):
            if h.sha(getattr(args,name)) != receipt["pins"][name]["sha256"]:
                raise ValueError("tool pin moved")
        for name in ("probe.dm", "probe.dme"):
            if h.sha(source/name) != receipt["fixture_sha256"][name]:
                raise ValueError("fixture source moved")
        receipt["complete"] = True
    except Exception as error:
        receipt["error"] = str(error)
    finally:
        if daemon is not None:
            receipt["daemon_cleanup"] = terminate_owned(daemon)
            if not receipt["daemon_cleanup"].get("reaped"):
                receipt["complete"] = False
        if job is not None:
            receipt["owned_job_cleanup"] = job.close()
            if not receipt["owned_job_cleanup"].get("reaped"):
                receipt["complete"] = False
        h._owned_job, h._daemon_namespace = previous_job, previous_namespace
        (root/"receipt.json").write_text(json.dumps(receipt,indent=2),encoding="utf-8")
        print(root/"receipt.json")
    return 0 if receipt["complete"] else 1

if __name__ == "__main__":
    raise SystemExit(main())
