"""Long-lived JSON-lines bridge to the shared Rust mapcore."""

import atexit
import json
import shutil
import subprocess
import tempfile
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "tools/mapcore/Cargo.toml"
BINARY = ROOT / "tools/mapcore/target/debug/mapcore.exe"
_lock = threading.RLock()
_process = None
_binary_dir = None


def _stop():
    global _process
    if _process and _process.poll() is None:
        _process.terminate()
        try:
            _process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            _process.kill()
            _process.wait()
    _process = None


def _start():
    global _process, _binary_dir
    if _process and _process.poll() is None:
        return _process
    build = subprocess.run(["cargo", "build", "--quiet", "--manifest-path", str(MANIFEST)],
                           cwd=ROOT, capture_output=True, text=True, timeout=180)
    if build.returncode:
        raise RuntimeError("Rust mapcore build failed: " + build.stderr[-2000:])
    # Windows cannot replace a running executable. Give each service process its
    # own copy so Cargo can rebuild the canonical binary during development.
    if _binary_dir:
        _binary_dir.cleanup()
    _binary_dir = tempfile.TemporaryDirectory(prefix="dq-mapcore-")
    atexit.register(_stop)
    running_binary = Path(_binary_dir.name) / BINARY.name
    shutil.copy2(BINARY, running_binary)
    _process = subprocess.Popen([str(running_binary), "serve"], cwd=ROOT,
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, text=True, encoding="utf-8", bufsize=1)
    return _process


def call(method, args):
    with _lock:
        process = _start()
        process.stdin.write(json.dumps({"method": method, "args": args}, separators=(",", ":")) + "\n")
        process.stdin.flush()
        response = process.stdout.readline()
        if not response:
            raise RuntimeError("Rust mapcore stopped while processing the request")
        result = json.loads(response)
        if "error" in result:
            raise ValueError(result["error"])
        return result
