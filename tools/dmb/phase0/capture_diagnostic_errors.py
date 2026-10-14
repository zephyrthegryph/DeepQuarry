"""Capture three compile-only errors; never invokes native or DreamDaemon.

The emitted descriptor uses compare_compile_errors.py's existing schema. Source
fixtures are candidates until pinned BYOND actually emits located error rows.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

from compare_compile_errors import normalize, sha
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "bench"))
from watchdog import terminate_owned

PIN = "8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0"
CASES = ("unknown_local", "invalid_parameter", "unterminated_expression")


def run(command, directory, log):
    started = time.perf_counter()
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    with log.open("xb") as stream:
        child = subprocess.Popen(command, cwd=directory, stdout=stream,
                                 stderr=subprocess.STDOUT, creationflags=flags)
        cleanup = None
        try:
            code = child.wait(timeout=30)
            timed_out = False
        except subprocess.TimeoutExpired:
            cleanup = terminate_owned(child)
            code, timed_out = child.returncode, True
    text = log.read_bytes().decode("utf-8", errors="replace")
    return {"command": command, "exit_code": code, "timed_out": timed_out,
            "seconds": time.perf_counter() - started, "cleanup": cleanup,
            "log": str(log), "diagnostics": normalize(text, directory)}, text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--byond", type=Path, required=True)
    parser.add_argument("--engine-template", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    compiler, template, output = (path.resolve() for path in
                                  (args.byond, args.engine_template, args.output))
    if output.drive.casefold() != "e:" or not output.is_relative_to(Path("E:/dq-cache")):
        raise ValueError("capture output must be beneath E:/dq-cache")
    if sha(compiler) != PIN:
        raise ValueError("BYOND executable differs from pinned 516.1687 compiler")
    template_sha = sha(template)
    output.mkdir(parents=True, exist_ok=False)
    version, text = run([str(compiler)], output, output / "version.log")
    if version["timed_out"] or not re.search(r"DM compiler version 516\.1687\b", text):
        raise ValueError("pinned compiler version banner missing")
    fixtures = Path(__file__).resolve().parent.parent / "fixtures/native_compiler/diagnostic_errors"
    entries, failures = [], []
    for name in CASES:
        directory = output / name
        directory.mkdir()
        files = {}
        for suffix in ("dm", "dme"):
            file = f"{name}.{suffix}"
            destination = directory / file
            destination.write_bytes((fixtures / file).read_bytes())
            files[file] = sha(destination)
        result, _ = run([str(compiler), str(directory / f"{name}.dme")], directory, directory / "byond.log")
        unchanged = all(sha(directory / file) == digest for file, digest in files.items())
        accepted = (unchanged and not result["timed_out"] and result["exit_code"] not in (None, 0)
                    and any(row["severity"] == "error" and row["line"] is not None
                            for row in result["diagnostics"]))
        capture = {"compiler_sha256": PIN, "compiler_version": "516.1687",
                   "engine_template_sha256": template_sha, "source_sha256": files[f"{name}.dm"],
                   "files": files, "source_unchanged": unchanged, "captured_source_error": accepted,
                   "runtime": "not run", "byond": result}
        receipt = directory / "capture.json"
        receipt.write_text(json.dumps(capture, indent=2) + "\n", encoding="utf-8")
        if accepted:
            entries.append({"name": name, "root": name, "capture": "capture.json",
                            "capture_sha256": sha(receipt), "source": f"{name}.dm",
                            "manifest": f"{name}.dme", "defines": [], "files": files})
        else:
            failures.append(name)
    stable = sha(compiler) == PIN and sha(template) == template_sha
    (output / "capture-summary.json").write_text(json.dumps({"schema": 1, "failed_cases": failures,
        "compiler_template_unchanged": stable, "native": "not run"}, indent=2), encoding="utf-8")
    if failures or not stable:
        return 1
    (output / "diagnostic_corpus.json").write_text(json.dumps({"schema": 1, "cases": entries}, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
