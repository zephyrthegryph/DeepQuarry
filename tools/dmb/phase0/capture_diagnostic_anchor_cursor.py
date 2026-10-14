"""Bounded pinned BYOND compile-only diagnostic cursor discovery; no runtime."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time
from capture_diagnostic_errors import PIN, terminate_owned
from recapture_iteration_baseline import file_version
from recover_iteration_source import absolute_nonreparse, regular, sha

FIXTURES = Path(__file__).resolve().parent.parent / "fixtures/native/diagnostic_anchor_cursor"
CASES = ("blank_comments", "same_line", "following_statement", "nested_expression", "eof", "eof_no_newline")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--byond", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mixed", action="store_true", help="probe authenticated mixed text|anything forms")
    parser.add_argument("--mask-matrix", action="store_true", help="probe pure/null/text/object anything type masks")
    args = parser.parse_args()
    compiler = absolute_nonreparse(args.byond)
    regular(compiler)
    output = absolute_nonreparse(args.output)
    if output.drive.casefold() != "e:" or not output.is_relative_to(Path("E:/dq-cache")):
        raise ValueError("owned output must be beneath E:/dq-cache")
    before = {"sha256": sha(compiler), "file_version": file_version(compiler)}
    if before != {"sha256": PIN, "file_version": "5.0.516.1687"}:
        raise ValueError("pinned BYOND identity differs")
    output.mkdir(parents=True, exist_ok=False)
    deadline = time.monotonic() + 60
    receipt = {"schema": "diagnostic-cursor-discovery-v1", "status": "running", "compiler": str(compiler),
        "compiler_before": before, "producer_sha256": sha(Path(__file__)), "aggregate_watchdog_s": 60,
        "child_watchdog_s": 10, "cases": [], "scope": "compile-only actual diagnostic coordinates; no native or DD"}
    def save(): (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    def run(command, directory, log):
        remaining = deadline - time.monotonic()
        if remaining <= 0: raise TimeoutError("aggregate deadline exhausted")
        started = time.monotonic()
        with log.open("xb") as stream:
            child = subprocess.Popen(command, cwd=directory, stdout=stream, stderr=subprocess.STDOUT,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
            cleanup = None
            try:
                code, timed_out = child.wait(timeout=min(10, remaining)), False
            except subprocess.TimeoutExpired:
                cleanup = terminate_owned(child)
                code, timed_out = child.returncode, True
        return {"command": command, "seconds": time.monotonic() - started, "exit_code": code,
            "timed_out": timed_out, "cleanup": cleanup, "log": str(log), "log_sha256": sha(log)}
    save()
    try:
        receipt["version"] = run([str(compiler)], output, output / "version.log")
        if receipt["version"]["timed_out"] or not re.search(r"DM compiler version 516\.1687\b", (output / "version.log").read_text(errors="replace")):
            raise ValueError("version banner missing")
        for name in (("type_masks",) if args.mask_matrix else CASES):
            source = FIXTURES / ("eof.dm" if name == "eof_no_newline" else f"{name}.dm")
            payload = source.read_bytes()
            if args.mixed: payload = payload.replace(b" as anything", b" as text|anything")
            if name == "eof_no_newline": payload = payload.rstrip(b"\r\n")
            directory = output / name
            directory.mkdir()
            copied = directory / "probe.dm"
            copied.write_bytes(payload)
            manifest = directory / "probe.dme"
            manifest.write_text('#include "probe.dm"\n', encoding="utf-8")
            inputs = {copied.name: sha(copied), manifest.name: sha(manifest)}
            result = run([str(compiler), str(manifest)], directory, directory / "byond.log")
            text = (directory / "byond.log").read_text(errors="replace")
            entry = {"name": name, "source": str(source), "source_sha256": sha(source),
                "source_transform": {"mixed_filter": "replace exact bytes ' as anything' with ' as text|anything'" if args.mixed else None,
                    "strip_final_newline": name == "eof_no_newline"},
                "inputs": inputs, "source_unchanged": all(sha(directory / file) == digest for file, digest in inputs.items()),
                "byond": result, "diagnostics": text, "outputs": {}}
            for suffix in ("dmb", "rsc"):
                artifact = manifest.with_suffix("." + suffix)
                entry["outputs"][suffix] = {"path": str(artifact), "sha256": sha(artifact), "bytes": artifact.stat().st_size} if artifact.exists() else {"status": "absent"}
            receipt["cases"].append(entry)
            save()
            if result["timed_out"] or not entry["source_unchanged"]: raise ValueError("probe failed admission")
        receipt["compiler_after"] = {"sha256": sha(compiler), "file_version": file_version(compiler)}
        if receipt["compiler_after"] != before: raise ValueError("compiler changed")
        receipt["status"] = "captured"
    except Exception as error:
        receipt["status"], receipt["error"] = "failed", str(error)
    save()
    return 0 if receipt["status"] == "captured" else 1

if __name__ == "__main__": raise SystemExit(main())
