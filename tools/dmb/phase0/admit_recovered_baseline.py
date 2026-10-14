"""Admit completed baseline capture after explicit compiler-output domain filtering.

Preserves failed capture and every lock. No compilers run. All non-output source
bytes and both compiler output pairs must still match their actual receipts.
"""
import argparse
import json
import os
import re
from pathlib import Path
import time

from recapture_iteration_baseline import (absolute_nonreparse, file_version, sha,
    verify_source, write, semantic_configuration, authenticate_source_snapshot, regular)

ALLOWED_OUTPUTS = {".dmbc/build.lock", ".dmbc/comparison.last-run.json", ".dmbc/comparison.stats.json"}


SESSION_OUTPUT = re.compile(r"\.dmbc/input-sessions/[0-9a-f]{32}/[0-9a-f]{32}\.bin")


def output_file(name):
    return name in ALLOWED_OUTPUTS or SESSION_OUTPUT.fullmatch(name) is not None


def output_roster(source, deadline):
    roster = {}
    directories_seen = 0
    for current, directories, files in os.walk(source / ".dmbc", followlinks=False):
        directory = absolute_nonreparse(Path(current))
        directories_seen += 1
        if directories_seen > 128:
            raise ValueError("compiler-output directory roster exceeds admission bound")
        key = directory.relative_to(source).as_posix()
        if key not in (".dmbc", ".dmbc/input-sessions") and not re.fullmatch(r"\.dmbc/input-sessions/[0-9a-f]{32}", key):
            raise ValueError("unknown compiler-output directory")
        for name in directories:
            absolute_nonreparse(directory / name)
        for name in files:
            path = directory / name
            regular(path)
            key = path.relative_to(source).as_posix()
            if not output_file(key) or len(roster) >= 256:
                raise ValueError("unknown or excessive compiler-output leaves")
            size = path.stat().st_size
            if SESSION_OUTPUT.fullmatch(key) and size > 32 * 1024 * 1024:
                raise ValueError("session-output exceeds producer32MiB record limit")
            roster[key] = {"sha256": sha(path, deadline), "bytes": size}
    if not ALLOWED_OUTPUTS.issubset(roster):
        raise ValueError("known root compiler-output leaves are missing")
    return roster


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepared-root", type=Path, required=True)
    parser.add_argument("--capture-name", default="recapture")
    parser.add_argument("--output-name", default="filtered-admission")
    args = parser.parse_args()
    deadline = time.monotonic() + 180
    root = absolute_nonreparse(args.prepared_root)
    if not root.is_relative_to(Path("E:/dq-cache")):
        raise ValueError("prepared root must be E:/dq-cache")
    for name in (args.capture_name, args.output_name):
        if Path(name).name != name or name in (".", ".."):
            raise ValueError("requires contained basename")
    capture, output = root / args.capture_name, root / args.output_name
    source = root / "source"
    failed_path = capture / "recapture.json"
    failed_sha = sha(failed_path, deadline)
    failed = json.loads(failed_path.read_text())
    if failed.get("status") != "failed" or failed.get("error") != "source closure differs: .dmbc/comparison.last-run.json":
        raise ValueError("not the specific compiler-metadata closure failure")
    closure_path, snapshot_path = root / "input-closure.json", root / "source-snapshot.json"
    closure_sha, snapshot_sha = sha(closure_path, deadline), sha(snapshot_path, deadline)
    if closure_sha != failed["source_closure_sha256"]:
        raise ValueError("original closure no longer matches capture")
    closure = json.loads(closure_path.read_text())
    files = json.loads(snapshot_path.read_text())["files"]
    if {row["path"]: row["sha256"] for row in closure if row["tree"] == "source"} != files:
        raise ValueError("original closure/snapshot mismatch")
    excluded = {key: value for key, value in files.items() if Path(key).parts[0] == ".dmbc"}
    actual_outputs = output_roster(source, deadline)
    if not ALLOWED_OUTPUTS.issubset(excluded) or len(excluded) > 256 or not all(output_file(key) for key in excluded):
        raise ValueError("original excluded roster contains unknown/excessive producer output")
    filtered = {key: value for key, value in files.items() if key not in excluded}
    verify_source(source, filtered, deadline)
    rows = [row for row in closure if row["tree"] != "source" or row["path"] not in excluded]
    evidence = []
    for producer in ("byond", "native"):
        record = failed[producer]
        if record["exit_code"] != 0 or record["timeout"] is not False or record["producer"] != producer:
            raise ValueError("compiler did not complete successfully")
        if sha(Path(record["command"][0]), deadline) != record["compiler_sha256"]:
            raise ValueError("compiler binary changed")
        for suffix in (".dmb", ".rsc"):
            pair = capture / producer / (("world" if producer == "byond" else "comparison") + suffix)
            if sha(pair, deadline) != record[suffix + "_sha256"]:
                raise ValueError("completed compiler output pair changed")
        evidence.append(record)
    native_args = failed["native"]["command"][3:]
    configuration, template = semantic_configuration.command_configuration("comparison.dme", native_args, sha)
    if sha(template, deadline) != failed["compiler_sha256"]["template"]:
        raise ValueError("engine template changed")
    version_path = capture / "byond-version.json"
    version = json.loads(version_path.read_text())
    if file_version(Path(failed["byond"]["command"][0])) != version["file_version"]:
        raise ValueError("binary version metadata changed")
    if sha(failed_path, deadline) != failed_sha or sha(closure_path, deadline) != closure_sha or sha(snapshot_path, deadline) != snapshot_sha:
        raise ValueError("source admission receipts changed")
    output.mkdir()
    filtered_closure, filtered_snapshot = output / "input-closure.json", output / "source-snapshot.json"
    write(filtered_closure, rows)
    write(filtered_snapshot, {"files": filtered})
    evidence_path = output / "configuration-evidence.json"
    write(evidence_path, evidence)
    pin = {"schema": 1, "snapshot_id": sha(filtered_snapshot),
           "dmb_sha256": failed["byond"][".dmb_sha256"], "rsc_sha256": failed["byond"][".rsc_sha256"],
           "source_closure_manifest_sha256": sha(filtered_closure), "semantic_configuration": configuration,
           "configuration_evidence": [{"path": str(evidence_path), "sha256": sha(evidence_path)}],
           "byond_version_evidence": {"path": str(version_path), "sha256": sha(version_path)}}
    semantic_configuration.authenticate_pin(pin, configuration, sha)
    authenticate_source_snapshot({"files": filtered}, filtered_closure, pin, sha)
    write(output / "byond-structural-pin.json", pin)
    write(output / "scenarios.json", [{"name": "cold", "project": "comparison.dme", "arguments":
        ["--bootstrap-catalog", "--engine-template", str(template), "-DCIBUILDING", "-DCITESTING", "-DDM_VERSION=516", "-DDM_BUILD=1687"]}])
    write(output / "admission.json", {"schema": 1, "status": "passed", "failed_capture": str(failed_path),
        "failed_capture_sha256": failed_sha, "original_closure_sha256": closure_sha,
        "original_snapshot_sha256": snapshot_sha, "excluded_producer_output_files": excluded,
        "current_producer_output_roster": actual_outputs,
        "producer_evidence": "session.rs SessionRecords::open: namespace configuration identity formatted032x; Session::store: content identity formatted032x.bin; latest records are discovery hints requiring configuration/input validation",
        "policy": "only three named metadata leaves plus bounded typed session-output grammar; same output domain as native-iteration.isolate; locks untouched",
        "verified_source_files": len(filtered), "historical_snapshot_equivalence": "not asserted",
        "compiler_children": "reused completed successful evidence; not rerun", "runtime": "not run"})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
