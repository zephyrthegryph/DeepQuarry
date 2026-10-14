"""Owned, bounded children and checked archive paths for history replay."""
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bench"))
from upgrade_owned_job import OwnedJob


def safe(path, root):
    path = Path(os.path.abspath(path))
    path.relative_to(root)
    for item in (path, *path.parents):
        if item.exists() and (item.is_symlink() or getattr(item.lstat(), "st_file_attributes", 0) & 0x400):
            raise ValueError(f"linked/reparse path rejected: {item}")
    return path


def archive_relative(name):
    relative = PurePosixPath(name)
    if relative.is_absolute() or not relative.parts or any(p in ("..", ".") or ":" in p for p in relative.parts) or "\\" in name:
        raise ValueError("unsafe archive member")
    return relative


def run_owned(command, cwd, environment, output, seconds, memory_bytes,
              job_factory=OwnedJob, popen=subprocess.Popen, combine_stderr=False):
    started = time.monotonic()
    job, child = job_factory(memory_bytes), None
    result = {"command": command, "exit_code": None, "failure": None}
    try:
        child = popen(command, cwd=cwd, env=environment, stdout=output,
                      stderr=subprocess.STDOUT if combine_stderr else subprocess.PIPE, creationflags=0x08000000 | 0x4)
        job.add(child)
        job.resume(child)
        try:
            _, stderr = child.communicate(timeout=seconds)
            result["exit_code"] = child.returncode
            result["stderr"] = stderr.decode(errors="replace") if stderr is not None else "in output log"
        except subprocess.TimeoutExpired:
            result["failure"] = "owned child watchdog"
    except Exception as error:
        result["failure"] = str(error)
    finally:
        result["cleanup"] = job.close()
        if child is not None:
            try:
                child.wait(timeout=5)
            except Exception as error:
                result["cleanup"]["reaped"] = False
                result["cleanup"]["wait_error"] = str(error)
            if child.stderr is not None:
                child.stderr.close()
        result["seconds"] = time.monotonic() - started
    return result


def succeeded(result):
    return result["exit_code"] == 0 and result["failure"] is None and result["cleanup"].get("reaped")
