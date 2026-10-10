"""Pinned compile-only sized-array matrix. Positive and negative results remain evidence."""
import argparse
import json
from pathlib import Path
import re
import time

from capture_diagnostic_errors import PIN, run
from recapture_iteration_baseline import file_version
from recover_iteration_source import absolute_nonreparse, regular, sha

SCHEMA = "dm-local-sized-array-initializers-v1"
FIXTURES = Path(__file__).resolve().parent.parent / "fixtures/native/local_sized_array_initializers"
CASES = ("explicit_list", "explicit_null", "implicit", "multidim_list", "scalar", "nonliteral", "multidim_implicit")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--byond", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    compiler = absolute_nonreparse(args.byond)
    regular(compiler)
    output = absolute_nonreparse(args.output)
    if output.drive.casefold() != "e:" or not output.is_relative_to(Path("E:/dq-cache")):
        raise ValueError("capture output must be beneath E:/dq-cache")
    if sha(compiler) != PIN:
        raise ValueError("compiler differs from pinned BYOND516.1687")
    version_metadata = file_version(compiler)
    if version_metadata != "5.0.516.1687":
        raise ValueError("pinned compiler file version differs")
    output.mkdir(parents=True, exist_ok=False)
    deadline = time.monotonic() + 360
    receipt = {"schema": SCHEMA, "status": "running",
        "producer_sha256": sha(Path(__file__)),
        "compiler": str(compiler), "compiler_sha256": PIN,
        "file_version": version_metadata, "child_watchdog_s": 30,
        "aggregate_admission_deadline_s": 360, "cases": [],
        "scope": "actual compile-only sized-array capture; allocation/overwrite semantics not yet decoded; no native or runtime execution"}
    receipt_path = output / "receipt.json"
    def save():
        receipt_path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    def execute(command, directory, log):
        # Shared helper bounds each child to30s and terminates only its owned tree.
        if deadline - time.monotonic() < 30:
            raise TimeoutError("sized-array corpus aggregate admission budget exhausted")
        return run(command, directory, log)
    save()
    try:
        version, banner = execute([str(compiler)], output, output / "version.log")
        version["log_sha256"] = sha(output / "version.log")
        receipt["version"] = version
        if version["timed_out"] or not re.search(r"DM compiler version 516\.1687\b", banner):
            raise ValueError("pinned compiler banner missing")
        fixtures = FIXTURES
        for name in CASES:
            source = fixtures / f"{name}.dm"
            regular(source)
            source_sha = sha(source)
            directory = output / name
            directory.mkdir()
            copied = directory / source.name
            copied.write_bytes(source.read_bytes())
            manifest = directory / f"{name}.dme"
            manifest.write_text(f'#include "{source.name}"\n', encoding="utf-8")
            inputs = {copied.name: sha(copied), manifest.name: sha(manifest)}
            if inputs[copied.name] != source_sha:
                raise ValueError("source changed while copying")
            result, diagnostics = execute([str(compiler), str(manifest)], directory, directory / "byond.log")
            result["log_sha256"] = sha(directory / "byond.log")
            stable = sha(source) == source_sha and all(sha(directory / path) == digest for path, digest in inputs.items())
            entry = {"name": name, "source": str(source), "source_sha256": source_sha,
                "inputs": inputs, "source_unchanged": stable, "defines": [],
                "byond": result, "outputs": {}}
            for suffix in ("dmb", "rsc"):
                artifact = manifest.with_suffix("." + suffix)
                if artifact.exists():
                    regular(artifact)
                    entry["outputs"][suffix] = {"path": str(artifact), "bytes": artifact.stat().st_size, "sha256": sha(artifact)}
                else:
                    entry["outputs"][suffix] = {"status": "absent"}
            entry["diagnostics"] = diagnostics
            entry["status"] = "captured" if stable and not result["timed_out"] and ((result["exit_code"] == 0 and "sha256" in entry["outputs"]["dmb"]) or (result["exit_code"] != 0 and entry["outputs"]["dmb"].get("status") == "absent")) else "failed"
            receipt["cases"].append(entry)
            save()
            if entry["status"] not in ("captured", "captured_negative"):
                raise ValueError(f"sized-array case {name} not admitted; diagnostics preserved")
        if sha(compiler) != PIN or file_version(compiler) != version_metadata:
            raise ValueError("compiler changed during capture")
        receipt["status"] = "captured"
    except Exception as error:
        receipt["status"] = "failed"
        receipt["error"] = str(error)
    save()
    return 0 if receipt["status"] == "captured" else 1


if __name__ == "__main__":
    raise SystemExit(main())
