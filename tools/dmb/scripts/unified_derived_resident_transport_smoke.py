#!/usr/bin/env python3
"""Actual exclusive Derived resident IPC; build first, run outside Cargo.
No parser/oracle/source authority is reconstructed here. All source goes through
real native PrepareQuery and the public report coordinator. No UI or compiler
publication. Only Smoke's own unique private namespace is drained on exit.
"""
import argparse, copy, hashlib, json, os, subprocess, time
from pathlib import Path
from unified_daemon_smoke import Smoke

SOURCE = """/obj/probe
    var/value
/obj/probe/ui_data()
    return list(value)
/obj/probe/mutate()
    value = 7
/obj/probe/child/ui_data()
    // ALLOW(derived_reads): genuine repeated read retained for the resident control
    return list(value)
"""
NOTICE = "actual_resident_derived_transport_notice"

def report_request(smoke, root):
    return {"build": {"command": "PrepareQuery", "project": str(root / "deepquarry.dme"),
        "defines": {}, "workers": 1, "engine_template": None, "bootstrap_catalog": False,
        "progress_enabled": False, "output_store": None, "exact_inputs": True,
        "no_cache": False, "cache_root": str(smoke.root / "cache"), "record_inputs": None,
        "replay_inputs": None, "artifact_directory": None, "no_daemon": False,
        "trace_path": None, "timeout_seconds": 60,
        "policy_inputs": {"analysis_context": "original_analyze0290", "files": [],
            "search_folders": [], "workspace_generators": [], "workspace_auxiliary": ["derived_reads"],
            "workspace": {"root": str(root), "recursive_roots": [str(root / "code")],
                          "configuration": str(root / "tools/ci/lint_scopes.toml")}}},
        "lints": ["derived_reads"], "raw": True, "ci": False}

def call(smoke, request, name, success=False):
    path = smoke.root / (name + ".json")
    path.write_text(json.dumps(request), encoding="utf8", newline="\n")
    result = smoke.run(["analyze-check", str(path), "--jsonl"], success=success)
    rows = [json.loads(row) for row in result.stdout.splitlines() if row.strip()]
    assert len(rows) == 1, (result.returncode, result.stdout, result.stderr)
    row = rows[0]
    assert row["schema"] == "native-analyze-derived-report-v1", row
    assert row["complete"] and not row["full_policy_parity"] and not row["baseline"], row
    assert row["lints"] == ["derived_reads"] and row["preparation"]["kind"] == "current", row
    assert all(len(row["preparation"][key]) == 32 for key in
               ["semantic_revision", "source_revision", "policy_revision"]), row
    assert not row["clean"] and result.returncode != 0, row
    assert result.stderr.count(NOTICE) == 1, result.stderr
    assert row["allow_usage"], row
    return row, result

def live(smoke):
    records = [json.loads(path.read_text(encoding="utf8")) for path in
               (smoke.root / "daemon/live").glob("*.json")]
    rows = [row for row in records if row.get("namespace") == smoke.namespace]
    assert len(rows) == 1, rows
    return rows[0]["pid"]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--analyze", type=Path, required=True)
    parser.add_argument("--scratch-root", type=Path, required=True)
    parser.add_argument("--repository", type=Path, required=True)
    args = parser.parse_args()
    smoke = Smoke(args.binary, args.scratch_root, args.repository)
    before = hashlib.sha256(smoke.binary.read_bytes()).hexdigest()
    try:
        root = smoke.root / "fixture"
        (root / "code/_generated").mkdir(parents=True)
        (root / "tools/ci").mkdir(parents=True)
        (root / "tools/ci/lint_scopes.toml").write_text("", encoding="utf8", newline="\n")
        (root / "deepquarry.dme").write_text('#warn ' + NOTICE + '\n#include "code/probe.dm"\n', encoding="utf8", newline="\n")
        source = root / "code/probe.dm"
        bulk = ''.join(f"/obj/bulk_{n}\n    var/value\n/obj/bulk_{n}/ui_data()\n    return list(value)\n/obj/bulk_{n}/mutate()\n    value = 7\n" for n in range(256))
        source.write_text(SOURCE + bulk, encoding="utf8", newline="\n")
        (root / "code/_generated/reads.dm").write_text("// genuine stale raw generated source\n", encoding="utf8", newline="\n")
        request = report_request(smoke, root)
        first, result = call(smoke, request, "cold")
        assert len(result.stdout.encode("utf8")) > 65536, "real report must cross fragment boundary"
        pid = live(smoke)
        warm, _ = call(smoke, request, "warm")
        assert warm == first and live(smoke) == pid, "warm report must use SAME resident service"
        assert "code/_generated/reads.dm is stale" in first["text"]
        source.write_text(SOURCE + bulk + "/obj/new_value\n    var/extra\n/obj/new_value/ui_data()\n    return extra\n/obj/new_value/mutate()\n    extra = 7\n", encoding="utf8", newline="\n")
        changed, _ = call(smoke, request, "changed")
        assert changed["text"] != first["text"]
        assert changed["preparation"]["source_revision"] != first["preparation"]["source_revision"]
        assert live(smoke) == pid
        analyze=args.analyze.resolve(strict=True)
        analyze_before=hashlib.sha256(analyze.read_bytes()).hexdigest()
        native_request=smoke.root / "thin-native-request.json"
        native_request.write_text(json.dumps(request),encoding="utf8", newline="\n")
        flags=(subprocess.BELOW_NORMAL_PRIORITY_CLASS|subprocess.CREATE_NO_WINDOW) if os.name=="nt" else 0
        native=subprocess.run([str(analyze),"native-check","--dmbc",str(smoke.binary),str(native_request),"--jsonl"],cwd=smoke.root,env=smoke.env,capture_output=True,text=True,encoding="utf8",errors="replace",timeout=min(90,max(1,smoke.deadline-time.monotonic())),creationflags=flags)
        (smoke.root/"thin-native.stdout").write_text(native.stdout,encoding="utf8", newline="\n")
        (smoke.root/"thin-native.stderr").write_text(native.stderr,encoding="utf8", newline="\n")
        assert native.returncode==1,(native.returncode,native.stdout,native.stderr)
        assert json.loads(native.stdout)==changed,"both client layers must preserve exact current report"
        assert native.stderr.count(NOTICE)==1,native.stderr
        assert live(smoke)==pid,"thin Analyze client must reach the SAME resident service"
        assert hashlib.sha256(analyze.read_bytes()).hexdigest()==analyze_before
        # Mixed selection and mutation are rejected before any preparation or
        # notice output; no fallback to a generic/partial family is possible.
        for name, mutation in [("mixed", {"lints": ["derived_reads", "scheduler"]}),
                               ("baseline", {"baselineMode": "update"})]:
            wrong = copy.deepcopy(request); wrong.update(mutation)
            path = smoke.root / (name + ".json"); path.write_text(json.dumps(wrong), encoding="utf8", newline="\n")
            command = "analyze-baseline" if name == "baseline" else "analyze-check"
            rejected = smoke.run([command, str(path), "--jsonl"], success=False)
            assert rejected.returncode != 0 and not rejected.stdout and NOTICE not in rejected.stderr
        assert not (root / "tools/ci/derived_reads_baseline.txt").exists()
        assert hashlib.sha256(smoke.binary.read_bytes()).hexdigest() == before
        print(json.dumps({"test": "actual_derived_resident_transport", "passed": True,
            "same_daemon_pid": pid, "fragmented_report_bytes": len(result.stdout.encode("utf8")),
            "calls": smoke.calls, "binary_sha256": before, "analyze_sha256": analyze_before, "thin_native_client_passed": True,
            "scope": "exclusive Derived cold/warm/modified raw, actual current DTO/ALLOW/stale/notice and bounded wire; no full-family/default/baseline claim"}))
    finally:
        smoke.retire()

if __name__ == "__main__": main()
