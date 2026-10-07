"""Bounded compile-only diagnostic parity on frozen tiny invalid inputs.

Never rewrites diagnostic wording or equates unsupported semantics to source errors.
Both executables see the same source path/bytes and command-line defines.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

DIAGNOSTIC = re.compile(
    r"^(.*?):(\d+):(error|warning(?: \([^)]*\))?|native unsupported|internal compiler error):\s?(.*)$"
)
UNLOCATED = re.compile(r"^(error|native unsupported|internal compiler error):\s?(.*)$")
DEFAULT_CASES = ["outer_field-corrected", "outer_constant-corrected",
                 "receiver_constant", "lexical_constant"]


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def normalize(text, directory):
    records = []
    for line in text.splitlines():
        match = DIAGNOSTIC.match(line)
        if match:
            file, number, severity, message = match.groups()
            file = file.replace("\\", "/")
            prefix = directory.as_posix().rstrip("/") + "/"
            if file.casefold().startswith(prefix.casefold()):
                file = file[len(prefix):]
            # Normalize path separators only. Message, severity, order and
            # duplicate diagnostic count remain exactly as emitted.
            records.append({"file": file, "line": int(number),
                            "severity": severity, "message": message})
        elif (match := UNLOCATED.match(line)):
            records.append({"file": None, "line": None,
                            "severity": match[1], "message": match[2]})
    return records


def run(command, directory, log, timeout):
    started = time.perf_counter()
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    with log.open("wb") as stream:
        try:
            process = subprocess.run(command, cwd=directory, stdout=stream,
                                     stderr=subprocess.STDOUT, timeout=timeout,
                                     creationflags=flags, check=False)
            code, timed_out = process.returncode, False
        except subprocess.TimeoutExpired:
            code, timed_out = None, True
    text = log.read_bytes().decode("utf-8", errors="replace")
    return {"command": command, "exit_code": code, "timed_out": timed_out,
            "seconds": time.perf_counter() - started,
            "log": str(log), "diagnostics": normalize(text, directory)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--byond", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--engine-template", type=Path, required=True)
    parser.add_argument("--fixtures", type=Path, default=Path(__file__).resolve().parent.parent /
                        "fixtures/phase1/native_modified_instances")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--case", action="append")
    parser.add_argument("--define", action="append", default=[])
    parser.add_argument("--timeout", type=float, default=60)
    args = parser.parse_args()
    if not 0 < args.timeout <= 60:
        parser.error("tiny-fixture watchdog must be between 0 and 60 seconds")
    for name in ("byond", "native", "engine_template", "fixtures", "output"):
        setattr(args, name, getattr(args, name).resolve())
    args.output.mkdir(parents=True, exist_ok=False)
    fixture_receipt = json.loads((args.fixtures / "receipt.json").read_text(encoding="utf-8-sig"))
    compiler_identities = {"byond": sha(args.byond), "native": sha(args.native),
                           "engine_template": sha(args.engine_template)}
    if compiler_identities["byond"] != fixture_receipt["compiler_sha256"]:
        raise ValueError("BYOND executable differs from captured fixture compiler")
    results = []
    default_cases = (["bare", "outer_visible"] if (args.fixtures / "bare/probe.dme").is_file()
                     else DEFAULT_CASES)
    for case in args.case or default_cases:
        if Path(case).name != case:
            raise ValueError("case must be a fixture basename")
        # Flat scalar controls and self-contained per-case captures share the
        # same comparison path; do not assume a particular fixture layout.
        original = args.fixtures / f"{case}.dm"
        if not original.is_file():
            original = args.fixtures / case / "probe.dme"
        source_hash = sha(original)
        source_key = original.relative_to(args.fixtures).as_posix()
        if source_hash != fixture_receipt["files"][source_key]:
            raise ValueError(f"captured source hash mismatch: {case}")
        directory = args.output / case
        directory.mkdir()
        source = directory / "probe.dme"
        source.write_bytes(original.read_bytes())
        defines = [f"-D{define}" for define in args.define]
        reference = run([str(args.byond), *defines, str(source)], directory,
                        directory / "byond.log", args.timeout)
        candidate = run([str(args.native), "compile", "--no-daemon", str(source),
                         "--workers", "1", "--engine-template", str(args.engine_template),
                         "--bootstrap-catalog", *defines], directory,
                        directory / "native.log", args.timeout)
        unchanged = sha(source) == source_hash
        # An empty diagnostic vector or successful compile cannot certify an
        # invalid fixture. Timeouts and internal/unsupported failures stay failed.
        passed = (unchanged and not reference["timed_out"] and not candidate["timed_out"]
                  and reference["exit_code"] != 0 and candidate["exit_code"] != 0
                  and any(row["severity"] == "error" for row in reference["diagnostics"])
                  and reference["diagnostics"] == candidate["diagnostics"])
        results.append({"case": case, "source_sha256": source_hash, "defines": args.define,
                        "source_unchanged": unchanged, "passed": passed,
                        "byond": reference, "native": candidate})
        print(f"{case}: {'PASS' if passed else 'DIFF'} "
              f"({len(reference['diagnostics'])}/{len(candidate['diagnostics'])} diagnostics)")
    report = {"schema": 1, "compiler_sha256": compiler_identities,
              "fixture_receipt_sha256": sha(args.fixtures / "receipt.json"),
              "results": results, "passed": all(result["passed"] for result in results)}
    (args.output / "comparison.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
