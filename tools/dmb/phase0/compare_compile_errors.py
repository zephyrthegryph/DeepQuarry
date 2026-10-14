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
DIAGNOSTIC_SHAPED = re.compile(
    r"(?:^|:)\s*(?:error|warning|fatal|native unsupported|internal compiler error)\b",
    re.IGNORECASE,
)
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
        elif DIAGNOSTIC_SHAPED.search(line):
            # Keep unsupported diagnostic formats as evidence and fail the gate
            # even when both producers happen to emit the same unknown format.
            records.append({"file": None, "line": None,
                            "severity": "unrecognized diagnostic", "message": line})
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


def matches(reference, candidate, source_unchanged):
    """Exact diagnostic parity also requires the native source-error contract."""
    return (source_unchanged and not reference["timed_out"] and not candidate["timed_out"]
            and reference["exit_code"] not in (None, 0) and candidate["exit_code"] == 2
            and any(row["severity"] == "error" for row in reference["diagnostics"])
            and not any(row["severity"] == "unrecognized diagnostic"
                        for result in (reference, candidate) for row in result["diagnostics"])
            and reference["diagnostics"] == candidate["diagnostics"])


def template_admission(receipt, actual):
    expected = [receipt[name] for name in ("engine_template_sha256", "template_sha256")
                if name in receipt]
    if not expected:
        return {"status": "unknown", "reason": "fixture capture has no engine-template hash authority", "actual_sha256": actual}
    if any(not isinstance(value, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", value) for value in expected):
        raise ValueError("invalid captured engine-template hash")
    expected = {value.lower() for value in expected}
    if len(expected) != 1 or actual.lower() not in expected:
        raise ValueError("engine template differs from fixture capture authority")
    return {"status": "passed", "actual_sha256": actual, "expected_sha256": expected.pop()}


def corpus_cases(descriptor, compiler_sha):
    raw = descriptor.read_bytes()
    value = json.loads(raw)
    if value.get("schema") != 1 or not isinstance(value.get("cases"), list) or not 1 <= len(value["cases"]) <= 32:
        raise ValueError("invalid bounded diagnostic corpus")
    cases = []
    for entry in value["cases"]:
        name = entry["name"]
        if Path(name).name != name or name in [case["name"] for case in cases]:
            raise ValueError("invalid/duplicate corpus case")
        root = (descriptor.parent / entry["root"]).resolve()
        capture = root / entry["capture"]
        if sha(capture) != entry["capture_sha256"]:
            raise ValueError("corpus capture changed")
        receipt = json.loads(capture.read_text(encoding="utf-8-sig"))
        if receipt["compiler_sha256"] != compiler_sha:
            raise ValueError("corpus compiler differs from pinned executable")
        files = entry["files"]
        if not isinstance(files, dict) or not 1 <= len(files) <= 32:
            raise ValueError("invalid corpus file roster")
        for file, digest in files.items():
            if Path(file).is_absolute() or ".." in Path(file).parts or sha(root / file) != digest:
                raise ValueError("corpus source/manifest changed")
        if entry["manifest"] not in files:
            raise ValueError("manifest missing from exact corpus roster")
        captured = receipt
        for component in entry.get("source_receipt_path", []):
            captured = captured[component]
        if captured["source_sha256"] != files[entry["source"]]:
            raise ValueError("source differs from captured compiler input")
        cases.append(dict(entry, root=root, receipt=receipt))
    if descriptor.read_bytes() != raw:
        raise ValueError("corpus descriptor changed during admission")
    return cases


def compare_corpus(args, identities):
    results = []
    cases = corpus_cases(args.corpus, identities["byond"])
    if args.case:
        requested = set(args.case)
        available = {entry["name"] for entry in cases}
        if len(requested) != len(args.case) or requested - available:
            raise ValueError("duplicate or unknown requested corpus case")
        cases = [entry for entry in cases if entry["name"] in requested]
    for entry in cases:
        if args.define != entry.get("defines", []):
            raise ValueError("defines differ from captured corpus configuration")
        directory = args.output / entry["name"]
        directory.mkdir()
        for file in entry["files"]:
            destination = directory / file
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes((entry["root"] / file).read_bytes())
        source = directory / entry["manifest"]
        defines = [f"-D{define}" for define in args.define]
        reference = run([str(args.byond), *defines, str(source)], directory, directory / "byond.log", args.timeout)
        candidate = run([str(args.native), "compile", "--no-daemon", "--no-cache", str(source), "--workers", "1",
                         "--engine-template", str(args.engine_template), "--bootstrap-catalog",
                         "--output-store", str(directory / "native-store"),
                         "--artifact-directory", str(directory / "native-artifacts"), *defines],
                        directory, directory / "native.log", args.timeout)
        unchanged = (sha(entry["root"] / entry["capture"]) == entry["capture_sha256"] and
                     all(sha(directory / file) == digest and sha(entry["root"] / file) == digest
                         for file, digest in entry["files"].items()))
        proof = template_admission(entry["receipt"], identities["engine_template"])
        results.append({"case": entry["name"], "files": entry["files"], "defines": args.define,
                        "source_unchanged": unchanged, "template_admission": proof,
                        "passed": matches(reference, candidate, unchanged), "byond": reference, "native": candidate})
    return {"schema": 1, "compiler_sha256": identities, "corpus_sha256": sha(args.corpus),
            "results": results, "passed": bool(results) and all(result["passed"] and
            result["template_admission"]["status"] == "passed" for result in results)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--byond", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--engine-template", type=Path, required=True)
    parser.add_argument("--fixtures", type=Path, default=Path(__file__).resolve().parent.parent /
                        "fixtures/phase1/native_modified_instances")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--case", action="append")
    parser.add_argument("--corpus", type=Path, help="bounded source/manifest/capture descriptor")
    parser.add_argument("--define", action="append", default=[])
    parser.add_argument("--timeout", type=float, default=60)
    args = parser.parse_args()
    if not 0 < args.timeout <= 60:
        parser.error("tiny-fixture watchdog must be between 0 and 60 seconds")
    for name in ("byond", "native", "engine_template", "fixtures", "output"):
        setattr(args, name, getattr(args, name).resolve())
    if args.output.drive.casefold() != "e:":
        raise ValueError("owned diagnostic outputs must reside on E:")
    args.output.mkdir(parents=True, exist_ok=False)
    if args.corpus:
        args.corpus = args.corpus.resolve()
        identities = {"byond": sha(args.byond), "native": sha(args.native), "engine_template": sha(args.engine_template)}
        report = compare_corpus(args, identities)
        if identities != {"byond": sha(args.byond), "native": sha(args.native), "engine_template": sha(args.engine_template)}:
            raise ValueError("compiler/template changed during corpus")
        (args.output / "comparison.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        return 0 if report["passed"] else 1
    fixture_receipt = json.loads((args.fixtures / "receipt.json").read_text(encoding="utf-8-sig"))
    compiler_identities = {"byond": sha(args.byond), "native": sha(args.native),
                           "engine_template": sha(args.engine_template)}
    if compiler_identities["byond"] != fixture_receipt["compiler_sha256"]:
        raise ValueError("BYOND executable differs from captured fixture compiler")
    template_proof = template_admission(fixture_receipt, compiler_identities["engine_template"])
    print(f"Template admission: {template_proof['status']}")
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
        candidate = run([str(args.native), "compile", "--no-daemon", "--no-cache", str(source),
                         "--workers", "1", "--engine-template", str(args.engine_template),
                         "--bootstrap-catalog", "--output-store", str(directory / "native-store"),
                         "--artifact-directory", str(directory / "native-artifacts"), *defines], directory,
                        directory / "native.log", args.timeout)
        unchanged = sha(source) == source_hash
        # An empty diagnostic vector or successful compile cannot certify an
        # invalid fixture. Timeouts and internal/unsupported failures stay failed.
        passed = matches(reference, candidate, unchanged)
        results.append({"case": case, "source_sha256": source_hash, "defines": args.define,
                        "source_unchanged": unchanged, "passed": passed,
                        "byond": reference, "native": candidate})
        print(f"{case}: {'PASS' if passed else 'DIFF'} "
              f"({len(reference['diagnostics'])}/{len(candidate['diagnostics'])} diagnostics)")
    report = {"schema": 1, "compiler_sha256": compiler_identities,
              "fixture_receipt_sha256": sha(args.fixtures / "receipt.json"),
              "results": results, "template_admission": template_proof,
              "passed": template_proof["status"] == "passed" and bool(results) and all(result["passed"] for result in results)}
    (args.output / "comparison.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
