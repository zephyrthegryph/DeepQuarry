"""Bounded actual CLI selected-reference demand; no runtime/performance claim."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from upgrade_owned_job import OwnedJob
from watchdog import terminate_owned

spec = importlib.util.spec_from_file_location("query_iteration", HERE / "native-iteration.py")
I = importlib.util.module_from_spec(spec)
spec.loader.exec_module(I)


def selected_rows(jsonl, ordinal):
    rows = [json.loads(line) for line in jsonl.splitlines() if line.strip()]
    return [row for row in rows if row.get("row") in ("selected_reference", "selected_reference_summary")
            and row.get("declaration") == ordinal]


def store_roster(store):
    result = {}
    for path in sorted(store.rglob("*")):
        if path.is_file():
            I.regular(path)
            result[str(path.relative_to(store))] = {"bytes": path.stat().st_size, "sha256": I.sha(path)}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("compiler", "template"):
        parser.add_argument("--" + name, required=True)
        parser.add_argument("--" + name + "-sha256", required=True)
    parser.add_argument("--output-root", default="E:/dq-cache/dmb-query-selected")
    args = parser.parse_args()
    root = I.safe_e(args.output_root) / uuid.uuid4().hex
    if not root.is_relative_to(Path("E:/dq-cache")): raise ValueError("owned root must be beneath E:/dq-cache")
    pins = {name: I.safe_e(getattr(args, name)) for name in ("compiler", "template")}
    for name, path in pins.items():
        I.regular(path)
        if I.sha(path) != getattr(args, name + "_sha256"): raise ValueError("pin mismatch: " + name)
    root.mkdir(parents=True)
    source = root / "source"; source.mkdir()
    project = source / "probe.dme"
    initial = ''.join(f"/proc/query_{n}(x=1)\n    return x + 1\n" for n in range(270))
    project.write_text(initial, encoding="utf-8")
    namespace = "query-" + uuid.uuid4().hex
    endpoint = None
    env = os.environ.copy(); env["DMB_DAEMON_NAMESPACE"] = namespace; env["DMB_CACHE_DIR"] = str(root / "cache")
    env["DMB_DAEMON_AUTOSTART"] = "0"
    report = {"schema_version": 1, "status": "running", "scope": "actual compile/query clients, fresh output and selected-reference equality; not shared input closure/runtime/performance acceptance",
              "inputClosureAuthenticated": False, "harness": {"path": str(Path(__file__).resolve()), "sha256": I.sha(Path(__file__))}, "namespace": namespace, "executions": {}, "sources": [],
              "pins": {name: {"path": str(path), "sha256": I.sha(path)} for name, path in pins.items()}}
    deadline = time.monotonic() + 300
    previous = I._owned_job, I._daemon_namespace
    job = OwnedJob(4_000_000_000); I._owned_job = job; I._daemon_namespace = namespace
    daemon = None
    def run(label, arguments, expected=0):
        result = I.run_child(pins["compiler"], arguments, root / label, deadline,
                             require_owned=True, cache_directory=root / "cache")
        report["executions"][label] = result
        if (result["exit"] == 0) != (expected == 0): raise ValueError(label + " unexpected client status")
        return result
    def query(label, questions, pins_reply=None, expected=0, timeout_seconds=None):
        request = {"project": str(project), "defines": {}, "engine_template": str(pins["template"]), "bootstrap_catalog": True,
                   "expected_revision": pins_reply["revision"] if pins_reply else None,
                   "expected_source_revision": pins_reply["source_revision"] if pins_reply else None,
                   "queries": [], "source_queries": questions}
        if timeout_seconds is not None: request["timeout_seconds"] = timeout_seconds
        file = root / (label + ".json"); file.write_text(json.dumps(request), encoding="utf-8")
        run(label, ["query", str(file)], expected)
        if expected: return None
        return json.loads((root / label / "stdout.log").read_text(encoding="utf-8-sig"))
    def compile_source(label, fresh=False):
        directory = root / label
        arguments = ["compile", str(project), "--engine-template", str(pins["template"]), "--bootstrap-catalog", "--workers", "2",
                     "--exact-inputs", "--artifact-directory", str(directory / "artifacts"), "--output-store", str(directory / "store"),
                     "--compile-result-file", str(root / (label + "-pair.json"))]
        if fresh: arguments += ["--no-daemon", "--no-cache"]
        run(label, arguments)
        result = json.loads((root / (label + "-pair.json")).read_text())
        if result.get("kind") != "native_pair": raise ValueError("compiler did not issue native pair")
        return result
    def demand(label, discovery):
        cursor = 0; candidates = []
        while True:
            page_reply = query(label + "-page-" + str(cursor), [{"OccurrencesPage": {"start": cursor, "limit": 128}}], discovery)
            page = json.loads(page_reply["jsonl"])
            candidates += [item for item in page["items"] if item["target"].get("kind") == "Proc"]
            cursor = page["next_cursor"]
            if cursor is None: break
            if cursor > 4096: raise ValueError("unexpected unbounded occurrence inventory")
        target = max(candidates, key=lambda item: item["start"])
        if target["occurrence"] <= 256: raise ValueError("fixture failed to reach uncaptured high ordinal")
        reply = query(label, [{"SelectedReferences": {"ordinal": target["occurrence"]}}], discovery)
        envelope = json.loads(reply["jsonl"])
        rows = selected_rows(envelope["captured_jsonl"], target["occurrence"])
        if not rows or not any(row["row"] == "selected_reference" for row in rows): raise ValueError("demand returned no actual references")
        return reply, target["occurrence"], rows
    try:
        endpoint = I.Endpoint(pins["compiler"], args.compiler_sha256, namespace, owned_job=job)
        endpoint.probe()
        report["daemon_endpoint_descriptor"] = endpoint.descriptor
        with (root / "daemon.stdout").open("xb") as out, (root / "daemon.stderr").open("xb") as err:
            daemon = subprocess.Popen([str(pins["compiler"]), "--serve-daemon"], env=env, stdout=out, stderr=err,
                                      creationflags=subprocess.CREATE_NO_WINDOW | 0x4)
        job.add(daemon); job.resume(daemon)
        ready = min(deadline, time.monotonic() + 20)
        while not endpoint.probe(daemon):
            if daemon.poll() is not None or time.monotonic() >= ready: raise TimeoutError("owned daemon readiness timeout")
            time.sleep(.05)
        for revision, text in enumerate((initial, "// current shift\n" + initial.replace("return x + 1", "return x + 2"))):
            project.write_text(text, encoding="utf-8")
            source_sha = I.sha(project); report["sources"].append(source_sha)
            if revision:
                query("stale-source", [{"SelectedReferences": {"ordinal": ordinal}}], discovery, expected=1)
            retained = compile_source("retained-" + str(revision))
            discovery = query("discover-" + str(revision), [])
            if not revision:
                for invalid in (0, 301):
                    label = "invalid-budget-" + str(invalid)
                    query(label, [], discovery, expected=1, timeout_seconds=invalid)
                    if "query timeout_seconds must be 1..300" not in (root / label / "stderr.log").read_text(encoding="utf-8-sig"):
                        raise ValueError("query budget rejection omitted exact diagnostic")
                query("explicit-budget", [], discovery, timeout_seconds=30)
            before = store_roster(root / ("retained-" + str(revision)) / "store")
            reply, ordinal, rows = demand("demand-" + str(revision), discovery)
            if discovery["publication_pair"] != retained["pair_id"]: raise ValueError("compiled generation association differs")
            for field in ("revision", "source_revision"):
                if reply[field] != discovery[field]: raise ValueError("demand answered another current revision")
            if store_roster(root / ("retained-" + str(revision)) / "store") != before: raise ValueError("query published or modified store outputs")
            after = query("after-" + str(revision), [], discovery)
            for field in ("revision", "source_revision", "publication_pair", "snapshot_outcome", "last_request_outcome"):
                if after[field] != discovery[field]: raise ValueError("query changed current snapshot: " + field)
            fresh = compile_source("fresh-" + str(revision), fresh=True)
            for field in ("pair_id", "dmb_hash", "rsc_hash", "dmb_bytes", "rsc_bytes"):
                if fresh[field] != retained[field]: raise ValueError("fresh output mismatch: " + field)
            run("fresh-analysis-" + str(revision), ["analyze", "--resolved", "--no-daemon", "--no-cache", str(project),
                "--engine-template", str(pins["template"]), "--bootstrap-catalog", "--workers", "2"])
            fresh_rows = selected_rows((root / ("fresh-analysis-" + str(revision)) / "stdout.log").read_text(encoding="utf-8-sig"), ordinal)
            if fresh_rows != rows: raise ValueError("demand references differ from fresh existing producer")
            if I.sha(project) != source_sha: raise ValueError("source changed during current revision")
        for name, path in pins.items():
            if I.sha(path) != getattr(args, name + "_sha256"): raise ValueError("pin changed: " + name)
        report["status"] = "passed"
    except Exception as error:
        report.update(status="failed", error=str(error))
    finally:
        if daemon: report["daemon_cleanup"] = terminate_owned(daemon)
        report["job_cleanup"] = job.close()
        I._owned_job, I._daemon_namespace = previous
        report["reaped"] = report["job_cleanup"].get("reaped", False)
        (root / "receipt.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(root / "receipt.json")
    return 0 if report["status"] == "passed" and report["reaped"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
