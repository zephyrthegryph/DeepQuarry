"""Compare a captured build with a fresh build of the same private source paths.

Never launches a world. Each compiler invocation has a five-minute watchdog.
The source must be the isolated mirror from profile_base, not a live checkout.
"""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from trace_records import is_build_trace


def pair(root):
    identity = (root / "HEAD").read_text().strip().splitlines()[-1]
    result = {}
    for extension in ("dmb", "rsc"):
        path = root / "generations" / identity / ("world." + extension)
        with path.open("rb") as stream:
            result[extension] = {"sha256": hashlib.file_digest(stream, "sha256").hexdigest(),
                                 "bytes": path.stat().st_size}
    return result


def diagnostics(path):
    # Build tracing is timing evidence rather than a user diagnostic. Everything
    # else on stderr remains significant, including order and complete messages.
    return [line for line in path.read_text(errors="replace").splitlines()
            if not is_build_trace(line)]


def require_pinned_tools(receipt):
    for name in ("compiler", "builtins"):
        pinned = receipt["tools"][name]
        with Path(pinned["path"]).open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if actual != pinned["sha256"]:
            raise ValueError(f"Captured {name} changed; refuse a cross-producer oracle")
        if Path(receipt["arguments"][name]).resolve() != Path(pinned["path"]).resolve():
            raise ValueError(f"Captured {name} arguments and tool identity disagree")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    receipt = json.loads((args.profile / "receipt.json").read_text())
    if receipt["status"] != "completed":
        parser.error("Only completed captured builds can be compared")
    require_pinned_tools(receipt)
    mirror = (args.profile / "source").resolve()
    if not mirror.is_dir():
        parser.error("Captured private source mirror missing")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    env = os.environ.copy()
    env.pop("GIT_WORK_TREE", None)
    env["GIT_DIR"] = str(output / "isolated.git")
    env["DM_BUILD_TRACE"] = "1"
    env["DM_MEMORY_LIMIT_MB"] = "0"
    env["DM_COMPILER_WORKERS"] = "2"
    if os.name == "nt":
        ctypes.windll.kernel32.SetErrorMode(3)
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    subprocess.run(["git", "init", "--bare", env["GIT_DIR"]], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=10,
                   creationflags=flags)
    arguments = receipt["arguments"]
    command = [str(Path(arguments["compiler"]).resolve()), "build-project",
               arguments["manifest"], str(Path(arguments["builtins"]).resolve()),
               str(output / "published"), *(arguments["define"] or
                    ["-DCBT", "-DCIBUILDING", "-DCITESTING"])]
    evidence = {"command": command, "source": str(mirror),
                "method": "Same private source paths, independent Git/cache and output roots",
                "status": "started"}
    started = time.perf_counter()
    child = None
    try:
        with (output / "stdout.log").open("wb") as stdout, (output / "stderr.log").open("wb") as stderr:
            child = subprocess.Popen(command, cwd=mirror, env=env, stdout=stdout,
                                     stderr=stderr, creationflags=flags)
            evidence["pid"] = child.pid
            evidence["exit_code"] = child.wait(timeout=285)
        if evidence["exit_code"] != 0:
            raise RuntimeError("Fresh compiler failed")
        evidence["captured"] = pair(args.profile / "published")
        evidence["fresh"] = pair(output / "published")
        log = "body.stderr.log" if arguments["scenario"] == "daemon-body" else "compiler.stderr.log"
        evidence["captured_diagnostics"] = diagnostics(args.profile / log)
        evidence["fresh_diagnostics"] = diagnostics(output / "stderr.log")
        evidence["bytes_equal"] = evidence["captured"] == evidence["fresh"]
        evidence["diagnostics_equal"] = evidence["captured_diagnostics"] == evidence["fresh_diagnostics"]
        evidence["status"] = "equal" if evidence["bytes_equal"] and evidence["diagnostics_equal"] else "different"
    except Exception as error:
        evidence["status"] = "timeout" if isinstance(error, subprocess.TimeoutExpired) else "failed"
        evidence["error"] = str(error)
    finally:
        if child is not None and child.poll() is None:
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(child.pid), "/T", "/F"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
            else:
                child.kill()
            child.wait(timeout=5)
        evidence["elapsed_seconds"] = time.perf_counter() - started
        (output / "oracle.json").write_text(json.dumps(evidence, indent=2) + "\n")
    if evidence["status"] != "equal":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
