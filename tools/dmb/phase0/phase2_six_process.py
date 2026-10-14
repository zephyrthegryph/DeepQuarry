"""Bounded six-process one-shot acceptance, using a supplied built compiler.

No build, DreamMaker, DreamDaemon, profiler or administrator helper is launched.
The scratch directory must not exist. Every child has two lowering workers;
logs, hashes and process receipts stay in scratch for audit.
"""
from __future__ import annotations
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(65536), b""):
            value.update(block)
    return value.hexdigest()


def outputs(project: Path) -> dict[str, str]:
    return {suffix: digest(project.with_suffix(suffix)) for suffix in (".dmb", ".rsc")}


def invoke(executable: Path, engine: Path, project: Path, scratch: Path,
           environment: dict[str, str], label: str, oracle: bool = False) -> dict:
    command = [str(executable), "compile", "--no-daemon", str(project),
               "--engine-template", str(engine), "--bootstrap-catalog",
               "--workers", "2", "--output-store", str(scratch / "pairs")]
    if oracle:
        command.extend(("--no-cache", "--exact-inputs"))
    log = scratch / f"{label}.log"
    started = time.time_ns()
    with log.open("wb") as destination:
        process = subprocess.Popen(command, stdout=destination, stderr=subprocess.STDOUT,
                                   env=environment,
                                   creationflags=(subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0))
        try:
            code = process.wait(timeout=120)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            raise RuntimeError(f"{label}: compiler timed out; see {log}")
    receipt = {"label": label, "pid": process.pid, "started_ns": started,
               "finished_ns": time.time_ns(), "exit_code": code,
               "command": command, "log_sha256": digest(log)}
    if not code:
        receipt["outputs"] = outputs(project)
    (scratch / f"{label}.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    if code:
        raise RuntimeError(f"{label}: compiler exited {code}; see {log}")
    return receipt


def run(executable: Path, engine: Path, scratch: Path) -> dict:
    scratch.mkdir(parents=False, exist_ok=False)
    environment = dict(os.environ)
    environment["LOCALAPPDATA"] = str(scratch / "user")
    environment["XDG_CACHE_HOME"] = str(scratch / "user")
    projects = []
    for number in range(6):
        root = scratch / f"worktree-{number}"
        root.mkdir()
        project = root / "project.dme"
        project.write_text('#include "source.dm"\n', encoding="utf-8")
        (root / "source.dm").write_text(f"/proc/acceptance_probe()\n    return {number}\n", encoding="utf-8")
        projects.append(project)
    receipts = []
    def batch(label: str, targets: list[Path]) -> list[dict]:
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            jobs = [pool.submit(invoke, executable, engine, project, scratch,
                                environment, f"{label}-{index}")
                    for index, project in enumerate(targets)]
            return [job.result() for job in jobs]
    receipts.extend(batch("cold", projects))
    warm = batch("warm", projects)
    receipts.extend(warm)
    for index in range(6):
        if warm[index]["outputs"] != receipts[index]["outputs"]:
            raise RuntimeError(f"worktree {index}: warm output differs from cold")
    for number, project in enumerate(projects):
        (project.parent / "source.dm").write_text(f"/proc/acceptance_probe()\n    return {number + 10}\n", encoding="utf-8")
    edits = batch("body-edit", projects)
    receipts.extend(edits)
    for index, project in enumerate(projects):
        oracle = invoke(executable, engine, project, scratch, environment,
                        f"oracle-{index}", oracle=True)
        receipts.append(oracle)
        if oracle["outputs"] != edits[index]["outputs"]:
            raise RuntimeError(f"worktree {index}: cache edit differs from exact no-cache oracle")
    # All six calls target one configuration/worktree. The OS session lock must
    # serialize them; every completed output must equal its exact oracle.
    serialized = batch("same-session", [projects[0]] * 6)
    receipts.extend(serialized)
    if any(item["outputs"] != edits[0]["outputs"] for item in serialized):
        raise RuntimeError("same-session publication differs from exact oracle")
    return {"version": 1, "status": "PASS", "compiler_sha256": digest(executable),
            "engine_sha256": digest(engine), "workers_per_process": 2,
            "max_processes": 6, "receipts": receipts,
            "limits": "Tiny compiled fixture; no runtime or whole-project memory proof."}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--scratch", type=Path, required=True)
    args = parser.parse_args()
    report = run(args.compiler.resolve(strict=True), args.engine.resolve(strict=True),
                 args.scratch.resolve())
    (args.scratch / "acceptance.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("Six-process tiny compile/oracle/session acceptance PASS")


if __name__ == "__main__":
    main()
