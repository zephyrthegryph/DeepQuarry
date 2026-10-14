"""Paired compile-only lexical-scope candidates; no runtime or semantic assertion."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from capture_diagnostic_errors import PIN
from recapture_iteration_baseline import file_version
from recover_iteration_source import absolute_nonreparse, regular, sha

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "bench"))
from upgrade_owned_job import OwnedJob

FIXTURES = Path(__file__).resolve().parent.parent / "fixtures/native/lexical_shadowing"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--byond", type=Path, required=True)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--compiler-sha256", required=True)
    parser.add_argument("--engine-template", type=Path, required=True)
    parser.add_argument("--engine-template-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if os.name != "nt":
        raise ValueError("this capture requires the Windows owned-job watchdog")
    compiler, byond, template = [absolute_nonreparse(p) for p in (args.compiler, args.byond, args.engine_template)]
    for file in (compiler, byond, template): regular(file)
    if not all(re.fullmatch(r"[0-9a-f]{64}", digest) for digest in (args.compiler_sha256, args.engine_template_sha256)):
        raise ValueError("exact lowercase compiler/template SHA256 pins required")
    pins = {str(compiler): args.compiler_sha256, str(byond): PIN, str(template): args.engine_template_sha256}
    if any(sha(Path(file)) != digest for file, digest in pins.items()) or file_version(byond) != "5.0.516.1687":
        raise ValueError("actual compiler/template identity differs")
    output = absolute_nonreparse(args.output)
    if output.drive.casefold() != "e:" or not output.is_relative_to(Path("E:/dq-cache")):
        raise ValueError("owned output must be beneath E:/dq-cache")
    output.mkdir(parents=True, exist_ok=False)
    deadline = time.monotonic() + 210
    receipt = {"schema": "paired-lexical-shadowing-v1", "status": "running", "pins_before": pins,
        "byond_file_version": file_version(byond), "producer_sha256": sha(Path(__file__)), "cases": [],
        "scope": "compile-only candidate legality/error classification; no runtime, fallback or acceptance",
        "child_watchdog_s": 30, "aggregate_watchdog_s": 210}

    def save():
        (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")

    def run(command, cwd, prefix):
        remaining = deadline - time.monotonic()
        if remaining <= 0: raise TimeoutError("aggregate capture deadline exhausted")
        started = time.monotonic()
        stdout, stderr = prefix.with_suffix(".stdout.log"), prefix.with_suffix(".stderr.log")
        result = {"command": command, "cwd": str(cwd), "exit_code": None, "timed_out": False}
        job = OwnedJob()
        child = None
        try:
            with stdout.open("xb") as out, stderr.open("xb") as err:
                child = subprocess.Popen(command, cwd=cwd, stdout=out, stderr=err,
                    creationflags=subprocess.CREATE_NO_WINDOW | 0x4)
                job.add(child)
                job.resume(child)
                try: result["exit_code"] = child.wait(timeout=min(30, remaining))
                except subprocess.TimeoutExpired: result["timed_out"] = True
        finally:
            result["cleanup"] = job.close()
            if child is not None: child.wait(timeout=5)
            result.update(seconds=time.monotonic() - started, stdout=str(stdout), stderr=str(stderr),
                stdout_sha256=sha(stdout), stderr_sha256=sha(stderr))
        return result

    save()
    try:
        receipt["version"] = run([str(byond)], output, output / "version")
        banner = Path(receipt["version"]["stdout"]).read_text(errors="replace")
        if receipt["version"]["timed_out"] or not re.search(r"DM compiler version 516\.1687\b", banner):
            raise ValueError("pinned BYOND version banner missing")
        for name in ("nested", "sibling", "control"):
            directory = output / name
            directory.mkdir()
            roots = {backend: directory / backend for backend in ("byond", "native")}
            for root in roots.values():
                root.mkdir()
                (root / "probe.dm").write_bytes((FIXTURES / f"{name}.dm").read_bytes())
                (root / "probe.dme").write_bytes(b'#include "probe.dm"\n')
            inputs = {file: sha(roots["byond"] / file) for file in ("probe.dm", "probe.dme")}
            entry = {"name": name, "inputs": inputs, "same_source_bytes": True}
            receipt["cases"].append(entry)
            save()
            entry["byond"] = run([str(byond), str(roots["byond"] / "probe.dme")], roots["byond"], directory / "byond")
            artifacts, store = directory / "native-artifacts", directory / "native-store"
            machine = directory / "native-result.json"
            entry["native"] = run([str(compiler), "compile", str(roots["native"] / "probe.dme"), "--no-daemon", "--no-cache",
                "--workers", "1", "--engine-template", str(template), "--bootstrap-catalog", "--exact-inputs",
                "--artifact-directory", str(artifacts), "--output-store", str(store), "--compile-result-file", str(machine)],
                roots["native"], directory / "native")
            entry["source_unchanged"] = all(sha(root / file) == digest for root in roots.values() for file, digest in inputs.items())
            entry["outputs"] = {backend: {suffix: {"path": str(root / ("probe." + suffix)), "sha256": sha(root / ("probe." + suffix))}
                for suffix in ("dmb", "rsc") if (root / ("probe." + suffix)).exists()} for backend, root in roots.items()}
            entry["native_result"] = {"path": str(machine), "sha256": sha(machine)} if machine.exists() else None
            save()
            if not entry["source_unchanged"] or any(entry[backend]["timed_out"] or not entry[backend]["cleanup"]["reaped"] for backend in ("byond", "native")):
                raise ValueError("capture inputs moved or owned compile did not finish/reap")
        receipt["pins_after"] = {file: sha(Path(file)) for file in pins}
        receipt["byond_file_version_after"] = file_version(byond)
        if receipt["pins_after"] != pins or receipt["byond_file_version_after"] != receipt["byond_file_version"]:
            raise ValueError("compiler/template identity changed")
        receipt["status"] = "captured"
    except Exception as error:
        receipt.update(status="failed", error=str(error))
    finally: save()
    return 0 if receipt["status"] == "captured" else 1


if __name__ == "__main__":
    raise SystemExit(main())
