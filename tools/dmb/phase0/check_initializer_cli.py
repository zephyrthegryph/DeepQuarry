"""Bounded CLI oracle for authenticated user-procedure initializer domain cases.
No runtime execution. Captured negative diagnostics must remain located source errors.
"""
import argparse
import json
from pathlib import Path
import re
import sys
import time

from capture_diagnostic_errors import PIN, run
from compare_compile_errors import normalize
from recapture_iteration_baseline import file_version
from recover_iteration_source import absolute_nonreparse, regular, sha
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "bench"))
import build_receipt

SCHEMAS = {"dm-user-proc-initializer-domain-capture-v1": {"global", "static", "local", "nested_list", "new_argument"},
           "dm-user-proc-instance-override-capture-v1": {"reopened", "inherited"},
           "dm-initializer-receiver-contexts-v1": {"scalar_proc_default"}}


def load_cases(path):
    before = sha(path)
    value = json.loads(path.read_text())
    if value.get("compiler_sha256") != PIN or value.get("defines") not in (None, []):
        raise ValueError("capture compiler/defines differ from pinned cases")
    allowed = SCHEMAS.get(value.get("schema"))
    if allowed is None or not 1 <= len(value["cases"]) <= 16:
        raise ValueError("unsupported or oversized capture receipt")
    cases = []
    for entry in value["cases"]:
        if entry["name"] not in allowed:
            continue
        result = entry.get("result", entry.get("byond"))
        if result is None or result.get("timed_out") or len(result["command"]) != 2 or entry.get("defines") not in (None, []):
            raise ValueError("capture has no admitted bounded compile evidence")
        if sha(absolute_nonreparse(Path(result["command"][0]))) != PIN:
            raise ValueError("actual captured command executable differs")
        manifest = absolute_nonreparse(Path(result["command"][1]))
        directory = manifest.parent
        if manifest.suffix != ".dme" or not 1 <= len(entry["inputs"]) <= 2:
            raise ValueError("unsupported tiny input closure")
        inputs = {}
        for name, digest in entry["inputs"].items():
            if Path(name).name != name or Path(name).suffix not in (".dm", ".dme"):
                raise ValueError("escaped or unsupported input")
            source = absolute_nonreparse(directory / name)
            regular(source)
            if sha(source) != digest:
                raise ValueError("captured source bytes differ")
            inputs[name] = (source, digest)
        if manifest.name not in inputs:
            raise ValueError("manifest missing from captured inputs")
        source_names = [name for name in inputs if name.endswith(".dm")]
        if len(source_names) != 1 or manifest.read_text().strip() != f'#include "{source_names[0]}"':
            raise ValueError("capture is not a closed single-literal-include tiny fixture")
        log = absolute_nonreparse(Path(result["log"]))
        regular(log)
        if result.get("log_sha256") and sha(log) != result["log_sha256"]:
            raise ValueError("captured diagnostic log differs")
        diagnostics = normalize(log.read_text(errors="replace"), directory)
        if diagnostics != result["diagnostics"]:
            raise ValueError("captured diagnostic rows differ from actual log")
        errors = [row for row in diagnostics if row["severity"] == "error"]
        negative = result["exit_code"] != 0
        if negative and (not errors or any(row["line"] is None or row["message"] not in
                ("=: expected a constant expression", ": expected a constant expression") for row in errors)):
            raise ValueError("negative case is outside authenticated initializer contract")
        cases.append((entry["name"], manifest.name, inputs, errors, negative))
    if sha(path) != before:
        raise ValueError("capture receipt changed during authentication")
    return value, before, cases


def publication_paths(artifacts, store, source_root):
    published, internal_resources = [], []
    for root in (artifacts, store, source_root):
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            # PairStore resources are immutable cache blobs, not a generation.
            # Match only its actual direct resources/<u128hex>-<bytes>.rsc layout;
            # every DMB and pair manifest remains publication evidence.
            resource = re.fullmatch(r"[0-9a-f]{32}-(0|[1-9][0-9]*)\.rsc", path.name)
            if path.parent == store / "resources" and resource and path.stat().st_size == int(resource[1]):
                regular(absolute_nonreparse(path))
                internal_resources.append(path)
                continue
            if path.suffix in (".dmb", ".rsc") or path.name == "pair.json" or path.name.endswith(".dmb-pair.json"):
                published.append(path)
    return published, internal_resources


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--compiler-build-receipt", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, action="append", required=True)
    parser.add_argument("--version-receipt", type=Path, required=True)
    parser.add_argument("--engine-template", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    compiler, template, output = map(absolute_nonreparse,
                                    (args.compiler, args.engine_template, args.output))
    regular(compiler)
    regular(template)
    if output.drive.casefold() != "e:" or not output.is_relative_to(Path("E:/dq-cache")):
        raise ValueError("output must be a new owned E:/dq-cache directory")
    compiler_evidence = build_receipt.authenticate(args.compiler_build_receipt, compiler, sha)
    version_path = absolute_nonreparse(args.version_receipt)
    version_before = sha(version_path)
    version = json.loads(version_path.read_text())
    byond = absolute_nonreparse(Path(version["compiler"]))
    regular(byond)
    version_log = absolute_nonreparse(Path(version["version"]["log"]))
    if (version.get("compiler_sha256") != PIN or sha(byond) != PIN
            or file_version(byond) != "5.0.516.1687"
            or version.get("file_version") != "5.0.516.1687"
            or sha(version_log) != version["version"]["log_sha256"]
            or not re.search(r"DM compiler version 516\.1687\b", version_log.read_text())):
        raise ValueError("actual pinned BYOND version evidence differs")
    cases, receipts = [], []
    for path in args.receipt:
        path = absolute_nonreparse(path)
        _value, digest, rows = load_cases(path)
        receipts.append({"path": str(path), "sha256": digest})
        cases.extend(rows)
    if not 1 <= len(cases) <= 16 or len({row[0] for row in cases}) != len(cases):
        raise ValueError("bounded unique oracle case roster required")
    template_hash = sha(template)
    output.mkdir(parents=True, exist_ok=False)
    report = {"schema": "dm-user-proc-initializer-cli-oracle-v1", "status": "running",
              "compiler": compiler_evidence, "template_sha256": template_hash,
              "capture_receipts": receipts, "version_receipt_sha256": version_before,
              "child_watchdog_s": 30, "cases": [], "scope": "compile-only CLI diagnostics/output admission; no runtime"}
    def save():
        (output / "receipt.json").write_text(json.dumps(report, indent=2) + "\n")
    save()
    deadline = time.monotonic() + 540
    try:
        for name, manifest, inputs, expected, negative in cases:
            if deadline - time.monotonic() < 30:
                raise TimeoutError("aggregate oracle budget exhausted")
            directory = output / name
            source_root = directory / "source"
            source_root.mkdir(parents=True)
            for filename, (source, digest) in inputs.items():
                (source_root / filename).write_bytes(source.read_bytes())
                if sha(source) != digest or sha(source_root / filename) != digest:
                    raise ValueError("source changed during independent copy")
            artifacts, store = directory / "artifacts", directory / "store"
            machine = directory / "compile-result.json"
            command = [str(compiler), "compile", str(source_root / manifest), "--no-daemon", "--no-cache",
                       "--workers", "1", "--engine-template", str(template), "--bootstrap-catalog",
                       "--exact-inputs", "--artifact-directory", str(artifacts), "--output-store", str(store),
                       "--compile-result-file", str(machine)]
            result, text = run(command, source_root, directory / "native.log")
            diagnostics = normalize(text, source_root)
            published, internal_resources = publication_paths(artifacts, store, source_root)
            stable = all(sha(source) == digest and sha(source_root / filename) == digest
                         for filename, (source, digest) in inputs.items())
            if negative:
                matched = result["exit_code"] == 2 and not machine.exists() and not published
                matched = matched and all(row in diagnostics for row in expected)
                matched = matched and not any(row["severity"] in
                    ("native unsupported", "internal compiler error", "unrecognized diagnostic") for row in diagnostics)
            else:
                matched = result["exit_code"] == 0 and machine.exists() and bool(published)
            row = {"name": name, "negative": negative, "expected_diagnostics": expected,
                   "native": result, "diagnostics": diagnostics, "source_unchanged": stable,
                   "published_paths": [str(path) for path in published],
                   "internal_resource_cache_paths": [str(path) for path in internal_resources],
                   "status": "passed" if matched and stable and not result["timed_out"] else "failed"}
            report["cases"].append(row)
            save()
            if row["status"] != "passed":
                raise ValueError(f"CLI oracle {name} failed; actual evidence preserved")
        if sha(compiler) != compiler_evidence["compiler_sha256"] or sha(template) != template_hash or sha(byond) != PIN or sha(version_path) != version_before:
            raise ValueError("compiler/template/version authority changed")
        report["status"] = "passed"
    except Exception as error:
        report["status"] = "failed"
        report["error"] = str(error)
    save()
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
