#!/usr/bin/env python3
"""Whole-checkout native ported Checker query; no Analyze/combined parity claim.

Launched only by the ignored Rust test using shared/test_scratch.rs. Uses the
existing prepare-query + NativeOriginalOrderedChecker protocol, original_checker0290
in both requests, actual full deepquarry.dme and actual SpacemanDMM.toml. No source
copy, synthetic recipe, standalone DreamChecker, fallback, new grant, or cap change.
The ordinary public preparation/capture and 512 KiB query output limits still apply;
a preparation refusal is evidence of that boundary, not a grammar result.
"""
import argparse
import ctypes
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import time
import uuid

CONTEXT = "original_checker0290"

def actual_path(path):
    if os.name == "nt":
        import nt
        return nt._getfinalpathname(str(path))
    return str(path.resolve(strict=True))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--scratch-root", type=Path, required=True)
    args = parser.parse_args()
    binary = args.binary.resolve(strict=True)
    repository = args.repository.resolve(strict=True)
    scratch = args.scratch_root.resolve(strict=True)
    if not re.fullmatch(r"run-[0-9]+-[0-9]+", scratch.parent.name) or list(scratch.iterdir()):
        raise ValueError("fresh shared/test_scratch.rs dir() child required")
    project = repository / "deepquarry.dme"
    config = repository / "SpacemanDMM.toml"
    if not (repository / ".git").exists() or not (repository / "tools/dmb/Cargo.toml").is_file():
        raise ValueError("repository must be the actual compiler checkout, not a synthetic fixture")
    manifest_bytes = project.read_bytes()
    if not config.is_file():
        raise ValueError("actual checkout SpacemanDMM.toml is required")
    environment = actual_path(project)
    configuration = str(Path(environment).with_name("SpacemanDMM.toml"))
    namespace = f"native-checker-checkout-{os.getpid()}-{uuid.uuid4().hex[:12]}"
    env = os.environ.copy()
    env.update(DMB_DAEMON_NAMESPACE=namespace, DMB_DAEMON_DIR=str(scratch / "daemon"),
               DMB_CACHE_DIR=str(scratch / "cache"), DM_COMPILER_CACHE_ROOT=str(scratch / "cache"),
               DMB_DAEMON_IDLE_EXIT_SECS="60", DQ_PRIORITY="low")
    for key in ("DMB_DAEMON_AUTOSTART", "DMB_PREPARE_TIMEOUT_SECONDS", "DMB_UNIFIED_ANALYSIS"):
        env.pop(key, None)
    flags = subprocess.BELOW_NORMAL_PRIORITY_CLASS if os.name == "nt" else 0
    if os.name == "nt":
        kernel = ctypes.windll.kernel32
        kernel.GetCurrentProcess.restype = ctypes.c_void_p
        kernel.SetPriorityClass.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        if not kernel.SetPriorityClass(kernel.GetCurrentProcess(), flags):
            raise OSError("cannot set BelowNormal coordinator priority")
    deadline = time.monotonic() + 300
    calls = []
    evidence = {"project": environment, "configuration": configuration, "context": CONTEXT,
                "manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
                "manifest_bytes": len(manifest_bytes), "namespace": namespace,
                "combined_proof": False, "full_checker_parity": False, "workers": 2}

    def remaining():
        seconds = math.floor(deadline - time.monotonic())
        if seconds < 1:
            raise TimeoutError("300-second preparation/query operation budget expired")
        return min(300, seconds)

    def invoke(label, command, timeout):
        result = subprocess.run([str(binary), *command], cwd=repository, env=env,
                                capture_output=True, text=True, encoding="utf-8", errors="replace",
                                timeout=timeout, creationflags=flags)
        (scratch / (label + ".stdout")).write_text(result.stdout, encoding="utf-8")
        (scratch / (label + ".stderr")).write_text(result.stderr, encoding="utf-8")
        calls.append({"stage": label, "returncode": result.returncode})
        if result.returncode:
            raise RuntimeError(f"{label} failed ({result.returncode}): {result.stderr}")
        return result

    try:
        intent = {"analysis_context": CONTEXT, "files": [
            {"path": configuration, "role": "configuration", "required": True},
            {"path": environment, "role": "dm_source", "required": True},
        ]}
        evidence["stage"] = "prepare"
        seconds = remaining()
        prepared = invoke("prepare", ["prepare-query", str(project), "--workers", "2",
            "--exact-inputs", "--no-cache", "--request-timeout-seconds", str(seconds),
            "--policy-inputs-json", json.dumps(intent)], seconds + 25)
        rows = [json.loads(line) for line in prepared.stdout.splitlines() if line.strip()]
        pins = [row for row in rows if row.get("row") == "query_prepared"]
        if len(pins) != 1 or pins[0].get("retained") is not True:
            raise AssertionError("actual complete retained prepare receipt was not issued")
        pins = pins[0]
        for key in ("semantic_revision", "source_revision", "policy_revision"):
            if not re.fullmatch(r"[0-9a-fA-F]{32}", pins.get(key) or ""):
                raise AssertionError(f"missing actual preparation pin: {key}")
        evidence["pins"] = pins
        seconds = remaining()
        query = {"timeout_seconds": seconds, "analysis_context": CONTEXT,
                 "project": str(project), "defines": {}, "bootstrap_catalog": False,
                 "expected_revision": pins["semantic_revision"],
                 "expected_source_revision": pins["source_revision"],
                 "expected_policy_revision": pins["policy_revision"], "queries": [],
                 "source_queries": [{"NativeOriginalOrderedChecker": {
                     "environment": environment, "configuration": configuration}}]}
        request = scratch / "checker-query.json"
        request.write_text(json.dumps(query), encoding="utf-8")
        evidence["stage"] = "ordered_checker"
        result = invoke("ordered-checker", ["query", str(request)], seconds + 25)
        reply = json.loads(result.stdout)
        for key, pin in (("revision", "semantic_revision"), ("source_revision", "source_revision"),
                         ("policy_revision", "policy_revision")):
            assert reply[key] == pins[pin], (key, reply)
        assert reply["publication_pair"] is None
        [row] = [json.loads(line) for line in reply["jsonl"].splitlines() if line.strip()]
        assert row["row"] == "source_native_original_ordered_checker"
        assert row["full_checker_parity"] is False
        assert row["coverage"] == "selected_original_checker_phases"
        assert row["configuration_present"] is True and row["configuration_explicit"] is True
        assert row["environment"] == environment
        assert project.read_bytes() == manifest_bytes, "manifest changed during observation"
        evidence.update(stage="completed", diagnostic_count=len(row["diagnostics"]))
        print(json.dumps(evidence))
    except BaseException as error:
        evidence["failure"] = str(error)
        raise
    finally:
        evidence["calls"] = calls
        (scratch / "evidence.json").write_text(json.dumps(evidence, indent=2), encoding="utf-8")
        # Existing cooperative exact-namespace retirement; never kill a daemon.
        # A timeout leaves its evidence and ordinary idle retirement intact.
        try:
            retired = subprocess.run([str(binary), "--daemon-retire"], cwd=repository, env=env,
                                     capture_output=True, text=True, encoding="utf-8", errors="replace",
                                     timeout=20, creationflags=flags)
            (scratch / "retire.stdout").write_text(retired.stdout, encoding="utf-8")
            (scratch / "retire.stderr").write_text(retired.stderr, encoding="utf-8")
        except subprocess.TimeoutExpired:
            (scratch / "retire.stderr").write_text("owned cooperative retirement client timed out; no process killed\n")

if __name__ == "__main__":
    main()
