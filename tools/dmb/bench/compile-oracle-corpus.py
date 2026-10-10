"""Compile-only BYOND/native corpus. Never launches DreamDaemon or builds tools."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, cwd, label, deadline):
    timeout = min(120, deadline - time.monotonic())
    if timeout <= 0:
        raise TimeoutError("corpus outer watchdog expired")
    started = time.monotonic()
    with (cwd / (label + ".stdout")).open("xb") as out, (cwd / (label + ".stderr")).open("xb") as err:
        child = subprocess.Popen(command, cwd=cwd, stdout=out, stderr=err)
        try:
            code = child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            # Only this still-owned child and its descendants; never name-wide kills.
            if os.name == "nt" and child.poll() is None:
                try:
                    subprocess.run(["taskkill", "/PID", str(child.pid), "/T", "/F"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   timeout=15, check=False)
                except (OSError, subprocess.TimeoutExpired):
                    pass
            if child.poll() is None:
                child.kill()
            child.wait(timeout=15)
            raise TimeoutError(label + " watchdog expired")
    return {"command": command, "exit": code, "seconds": time.monotonic() - started}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--byond", type=Path, required=True, help="pinned DreamMaker executable")
    parser.add_argument("--inspector", type=Path, required=True)
    parser.add_argument("--icon", type=Path, required=True, help="existing valid DMI, copied into the corpus")
    parser.add_argument("--output", type=Path, required=True, help="new directory beneath E:/dq-cache")
    args = parser.parse_args()
    root = args.output.resolve()
    cache = Path("E:/dq-cache").resolve()
    if root == cache or cache not in root.parents or root.exists():
        raise ValueError("output must be a new child of E:/dq-cache")
    tools = {name: getattr(args, name).resolve(strict=True) for name in ("native", "byond", "inspector", "icon")}
    root.mkdir(parents=True)
    deadline = time.monotonic() + 600
    receipt = {"scope": "compile-only diagnostic corpus; no runtime or broad parity admission",
               "tools": {name: {"path": str(path), "sha256": sha(path)} for name, path in tools.items()},
               "child_watchdog_seconds": 120, "outer_watchdog_seconds": 600, "cases": []}
    fixtures = Path(__file__).resolve().parents[1] / "fixtures" / "compile_oracle"
    try:
        for case in ("hidden_markers", "absolute_parameter", "relative_parameter", "receiver_operations", "prompt_matrix"):
            row = {"case": case}
            receipt["cases"].append(row)
            for mode in ("byond", "native"):
                directory = root / case / mode
                directory.mkdir(parents=True)
                shutil.copyfile(fixtures / (case + ".dm"), directory / "case.dm")
                shutil.copyfile(tools["icon"], directory / "probe.dmi")
                (directory / "payload.txt").write_bytes(b"compile oracle resource\n")
                (directory / "case.dme").write_text('#include "case.dm"\n', encoding="utf-8")
                closure = {p.name: sha(p) for p in sorted(directory.iterdir())}
                row.setdefault("source_closures", {})[mode] = closure
                native_output = root / case / "native-output"
                command = ([str(tools["byond"]), "case.dme"] if mode == "byond" else
                           [str(tools["native"]), "compile", "case.dme", "--no-daemon", "--no-cache",
                            "--workers", "2", "--artifact-directory", str(native_output),
                            "--output-store", str(root / case / "native-store"),
                            "-DDM_VERSION=516", "-DDM_BUILD=1687"])
                row[mode] = run(command, directory, "compile", deadline)
                if mode == "byond":
                    banner = (directory / "compile.stdout").read_text(errors="replace") + (directory / "compile.stderr").read_text(errors="replace")
                    row[mode]["pinned_version_verified"] = "516.1687" in banner
                    if not row[mode]["pinned_version_verified"]:
                        raise ValueError("DreamMaker did not report pinned version 516.1687")
                if row[mode]["exit"] == 0:
                    row[mode]["dmb_sha256"] = sha((directory if mode == "byond" else native_output) / "case.dmb")
            if row["source_closures"]["byond"] != row["source_closures"]["native"]:
                raise ValueError("compiler source closures differ")
            if row["byond"]["exit"] == row["native"]["exit"] == 0:
                directory = root / case
                snapshot = hashlib.sha256(json.dumps(row["source_closures"]["byond"], sort_keys=True).encode()).hexdigest()
                report = directory / "structural-diff.json"
                row["structural"] = run([str(tools["inspector"]), "structural-diff",
                    str(directory / "byond" / "case.dmb"), str(directory / "native-output" / "case.dmb"),
                    str(report), snapshot], directory, "inspect", deadline)
                if report.exists():
                    value = json.loads(report.read_text(encoding="utf-8"))
                    row["structural"].update({key: value.get(key) for key in
                        ("tool_complete", "semantic_coverage", "complete", "total_discrepancies")})
                    row["structural"]["categories"] = value.get("categories")
                    row["structural"]["report_sha256"] = sha(report)
        if any(sha(path) != receipt["tools"][name]["sha256"] for name, path in tools.items()):
            raise ValueError("tool or icon changed during corpus")
        receipt["status"] = "completed"
    except Exception as error:
        receipt.update(status="failed", error=str(error))
        raise
    finally:
        (root / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
