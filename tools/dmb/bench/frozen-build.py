"""Build an immutable Git snapshot through a stable, owned source directory.

Unchanged source bytes retain their timestamps so Cargo can reuse artifacts.
This is build preparation, never compiler benchmark time or an acceptance gate.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import stat
import subprocess
import time
import uuid
import zipfile

from upgrade_owned_job import OwnedJob


def safe(path, root):
    path = Path(os.path.abspath(path))
    path.relative_to(root)
    for ancestor in (path, *path.parents):
        if ancestor.exists() and getattr(ancestor.lstat(), "st_file_attributes", 0) & 0x400:
            raise ValueError(f"reparse path rejected: {ancestor}")
    return path



def execute_owned_build(command, cwd, env, log, seconds, memory_bytes,
                        job_factory=OwnedJob, popen=subprocess.Popen):
    """Suspend Cargo before assigning the bounded Job; reap every descendant."""
    try:
        job = job_factory(memory_bytes)
    except Exception as error:
        return 70, {"reaped": True, "child_spawned": False,
                    "job_creation_error": str(error)}, str(error)
    child = None
    code, failure, cleanup = 70, None, None
    try:
        child = popen(command, cwd=cwd, env=env, stdout=log,
                      stderr=subprocess.STDOUT, creationflags=0x08000000 | 0x4)
        job.add(child)
        job.resume(child)
        try:
            code = child.wait(timeout=seconds)
        except subprocess.TimeoutExpired:
            code = 124
            failure = "owned Cargo build exceeded its fixed watchdog"
    except Exception as error:
        failure = str(error)
    finally:
        cleanup = job.close()
        if child is not None:
            try:
                child.wait(timeout=5)
            except Exception as error:
                cleanup = dict(cleanup, reaped=False, child_wait_error=str(error))
        if not cleanup.get("reaped") and code == 0:
            code = 70
            failure = "build exited successfully but owned descendants were not reaped"
    return code, cleanup, failure


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--cache", default="E:/dq-cache/dmb-native-v2/frozen-build")
    parser.add_argument("--seconds", type=int, default=300)
    parser.add_argument("--memory-bytes", type=int, default=4_000_000_000,
                        help="Windows owned Job commit limit; not a private-memory ceiling")
    parser.add_argument("--allocation-counting", action="store_true",
                        help="diagnostic-only requested-byte counters; never acceptance timing")
    parser.add_argument("--dmbc-codegen-units", type=int, choices=(16, 64, 256), default=16,
                        help="prototype-only dmbc LLVM partitioning; dependencies remain unchanged")
    parser.add_argument("--dmbc-opt-level", type=int, choices=(0, 1, 2, 3), default=3,
                        help="prototype-only dmbc optimization level; default 3 preserves release settings")
    parser.add_argument("--tree-opt-level", type=int, choices=(0, 1, 2, 3), default=3,
                        help="prototype-only dm-tree optimization level; included in the receipt")
    parser.add_argument("--dmbc-debug-level", type=int, choices=(0, 1, 2), default=None,
                        help="prototype-only dmbc debug information override; default preserves workspace settings")
    args = parser.parse_args()
    if not 1 <= args.seconds <= 300:
        raise ValueError("build watchdog must be between 1 and 300 seconds")
    if not 1 <= args.memory_bytes <= 32768 * 1024 * 1024:
        raise ValueError("owned Job memory limit must be positive and at most 32 GiB")
    if os.name != "nt":
        raise ValueError("frozen Cargo builds require Windows owned Job containment")
    cache = Path(os.path.abspath(args.cache))
    allowed = Path("E:/dq-cache").resolve()
    safe(cache, allowed)
    if cache == allowed:
        raise ValueError("a dedicated cache subdirectory is required")
    cache.mkdir(parents=True, exist_ok=True)
    # Exclusive ownership spans both source mutation and Cargo execution.
    lock = cache / "owner.lock"
    with lock.open("x") as owner:
        owner.write(str(os.getpid()))
    try:
        commit = subprocess.check_output(
            ["git", "rev-parse", "--verify", args.commit + "^{commit}"], timeout=30
        ).decode().strip()
        archive = subprocess.check_output(
            ["git", "archive", "--format=zip", commit, "tools/dmb"], timeout=60
        )
        source = cache / "source"
        marker = cache / "source-owner.json"
        ownership = {"schema": 1, "tool": "dmb-frozen-build", "source": str(source)}
        if marker.exists():
            if json.loads(marker.read_text()) != ownership:
                raise ValueError("source ownership marker does not match")
        elif source.exists():
            raise ValueError("refusing an existing source directory without ownership evidence")
        else:
            marker.write_text(json.dumps(ownership))
        source.mkdir(exist_ok=True)
        changed = removed = 0
        expected = set()
        with zipfile.ZipFile(io.BytesIO(archive)) as entries:
            for entry in entries.infolist():
                relative = PurePosixPath(entry.filename)
                if relative.is_absolute() or ".." in relative.parts or "\\" in entry.filename:
                    raise ValueError("unsafe archive path")
                if relative.parts[:2] != ("tools", "dmb") and not (
                    entry.is_dir() and relative.parts == ("tools",)
                ):
                    raise ValueError("archive entry outside compiler source")
                mode = entry.external_attr >> 16
                if stat.S_ISLNK(mode):
                    raise ValueError("archive symlink rejected")
                target = safe(source.joinpath(*relative.parts), source)
                if entry.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                    continue
                expected.add(target)
                data = entries.read(entry)
                if target.exists() and (not target.is_file() or target.stat().st_nlink != 1):
                    raise ValueError(f"refusing a nonregular or linked source file: {target}")
                if target.exists() and target.read_bytes() == data:
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                changed += 1
        for current, directories, files in os.walk(source, followlinks=False):
            safe(current, source)
            for directory in directories:
                safe(Path(current) / directory, source)
            for filename in files:
                target = safe(Path(current) / filename, source)
                if target not in expected:
                    if not target.is_file() or target.stat().st_nlink != 1:
                        raise ValueError(f"refusing a nonregular or linked stale file: {target}")
                    target.unlink()
                    removed += 1
        receipt_path = cache / (time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8])
        env = dict(os.environ, CARGO_HOME="E:/cargo",
                   CARGO_TARGET_DIR="E:/dq-cache/dmb-native-v2/cargo-target",
                   CARGO_PROFILE_RELEASE_LTO="false")
        command = ["E:/cargo/bin/cargo.exe", "build", "--release", "--locked",
                   "--offline", "-j1", "-p", "dmbc", "--bin", "dmbc",
                   "--config", f"profile.release.package.dmbc.codegen-units={args.dmbc_codegen_units}"]
        if args.allocation_counting:
            command.extend(["--features", "allocation-counting"])
        # Leave the default command untouched to preserve existing Cargo fingerprints.
        if args.dmbc_opt_level != 3:
            command.extend(["--config", f"profile.release.package.dmbc.opt-level={args.dmbc_opt_level}"])
        if args.tree_opt_level != 3:
            command.extend(["--config", f"profile.release.package.dm-tree.opt-level={args.tree_opt_level}"])
        if args.dmbc_debug_level is not None:
            command.extend(["--config", f"profile.release.package.dmbc.debug={args.dmbc_debug_level}"])
        started = time.monotonic()
        with receipt_path.with_suffix(".log").open("wb") as log:
            code, cleanup, launch_failure = execute_owned_build(
                command, source / "tools/dmb", env, log, args.seconds, args.memory_bytes)
        receipt = dict(commit=commit, archive_sha256=hashlib.sha256(archive).hexdigest(),
                       changed_files=changed, removed_files=removed, exit_code=code,
                       build_seconds=time.monotonic() - started, watchdog_seconds=args.seconds,
                       command=command, acceptance_profile=False, lto=False,
                       dmbc_codegen_units=args.dmbc_codegen_units,
                       dmbc_opt_level=args.dmbc_opt_level,
                       dm_tree_opt_level=args.tree_opt_level,
                       dmbc_debug_level_override=args.dmbc_debug_level,
                       allocation_counting=args.allocation_counting,
                       owned_child_cleanup=cleanup, build_failure=launch_failure,
                       memory_limit_bytes=args.memory_bytes,
                       memory_limit_scope="Windows owned Job aggregate commit; not private bytes or working set")
        if code == 0:
            binary = Path(env["CARGO_TARGET_DIR"]) / "release/dmbc.exe"
            data = binary.read_bytes()
            output = receipt_path.with_suffix(".exe")
            output.write_bytes(data)
            receipt.update(binary=str(output), binary_sha256=hashlib.sha256(data).hexdigest())
        receipt_path.with_suffix(".json").write_text(json.dumps(receipt, indent=2))
        print(json.dumps(receipt))
        return code
    finally:
        # This process created the exclusive lock; never remove another owner's lock.
        lock.unlink()


if __name__ == "__main__":
    raise SystemExit(main())
