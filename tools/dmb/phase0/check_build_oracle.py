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


def require_pinned_sources(mirror, snapshot):
    """Require capture-time hashes; current bytes cannot establish old identity."""
    files = snapshot.get("files")
    if not isinstance(files, dict) or not files:
        raise ValueError("Captured source snapshot must contain nonempty files hashes")
    for relative, digest in files.items():
        lexical = Path(relative)
        if lexical.is_absolute() or ".." in lexical.parts:
            raise ValueError("Captured source path escapes private mirror")
        path = (mirror / lexical).resolve()
        if not path.is_relative_to(mirror):
            raise ValueError("Captured source path escapes private mirror")
        if not isinstance(digest, str) or len(digest) != 64:
            raise ValueError("Captured source hash missing or invalid")
        with path.open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if actual != digest.lower():
            raise ValueError("Captured source changed: " + relative)
    # Include new files too: they can shadow resources or alter directory searches.
    actual = {p.relative_to(mirror).as_posix() for p in mirror.rglob("*") if p.is_file()}
    expected = {Path(p).as_posix() for p in files}
    if actual != expected:
        raise ValueError("Captured source inventory changed or snapshot incomplete")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--snapshot", type=Path, help="capture-time JSON {files:{relative:sha256}}; defaults to profile/source-snapshot.json")
    args = parser.parse_args()
    receipt = json.loads((args.profile / "receipt.json").read_text())
    if receipt["status"] != "completed":
        parser.error("Only completed captured builds can be compared")
    require_pinned_tools(receipt)
    mirror = (args.profile / "source").resolve()
    if not mirror.is_dir():
        parser.error("Captured private source mirror missing")
    snapshot_path = args.snapshot or args.profile / "source-snapshot.json"
    if not snapshot_path.is_file():
        parser.error("Capture-time source hashes missing; cannot certify historical oracle")
    snapshot_bytes = snapshot_path.read_bytes()
    snapshot = json.loads(snapshot_bytes)
    require_pinned_sources(mirror, snapshot)
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
                "source_snapshot_sha256": hashlib.sha256(snapshot_bytes).hexdigest(),
                "status": "started"}
    started = time.perf_counter()
    child = None
    try:
        require_pinned_sources(mirror, snapshot)
        require_pinned_tools(receipt)
        if snapshot_path.read_bytes() != snapshot_bytes:
            raise ValueError("Capture-time source snapshot changed before launch")
        with (output / "stdout.log").open("wb") as stdout, (output / "stderr.log").open("wb") as stderr:
            child = subprocess.Popen(command, cwd=mirror, env=env, stdout=stdout,
                                     stderr=stderr, creationflags=flags)
            evidence["pid"] = child.pid
            evidence["exit_code"] = child.wait(timeout=285)
        require_pinned_sources(mirror, snapshot)
        require_pinned_tools(receipt)
        if snapshot_path.read_bytes() != snapshot_bytes:
            raise ValueError("Capture-time source snapshot changed during oracle")
        if evidence["exit_code"] != 0:
            raise RuntimeError("Fresh compiler failed")
        evidence["captured"] = pair(args.profile / "published")
        evidence["fresh"] = pair(output / "published")
        log = "body.stderr.log" if arguments["scenario"] == "daemon-body" else "compiler.stderr.log"
        evidence["captured_diagnostics"] = diagnostics(args.profile / log)
        evidence["fresh_diagnostics"] = diagnostics(output / "stderr.log")
        evidence["bytes_equal"] = evidence["captured"] == evidence["fresh"]
        evidence["diagnostics_equal"] = evidence["captured_diagnostics"] == evidence["fresh_diagnostics"]
        require_pinned_sources(mirror, snapshot)
        require_pinned_tools(receipt)
        if snapshot_path.read_bytes() != snapshot_bytes:
            raise ValueError("Capture-time source snapshot changed during comparison")
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
