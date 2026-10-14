"""Bounded NEW compile-only BYOND/native baseline capture. No runtime or parity claim."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

from recover_iteration_source import absolute_nonreparse, regular, sha
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "bench"))
import semantic_configuration
from iteration_structural import authenticate_source_snapshot
from watchdog import terminate_owned

BYOND_SHA = "8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0"
DEFINES = ["CIBUILDING", "CITESTING", "DM_VERSION=516", "DM_BUILD=1687"]


def file_version(executable):
    from ctypes import wintypes
    api = ctypes.WinDLL("version", use_last_error=True)
    api.GetFileVersionInfoSizeW.argtypes = [wintypes.LPCWSTR, ctypes.POINTER(wintypes.DWORD)]
    api.GetFileVersionInfoSizeW.restype = wintypes.DWORD
    api.GetFileVersionInfoW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p]
    api.VerQueryValueW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR, ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(wintypes.UINT)]
    handle = wintypes.DWORD()
    size = api.GetFileVersionInfoSizeW(str(executable), ctypes.byref(handle))
    if not size:
        raise ctypes.WinError(ctypes.get_last_error())
    data = ctypes.create_string_buffer(size)
    if not api.GetFileVersionInfoW(str(executable), 0, size, data):
        raise ctypes.WinError(ctypes.get_last_error())
    pointer, length = ctypes.c_void_p(), wintypes.UINT()
    if not api.VerQueryValueW(data, "\\", ctypes.byref(pointer), ctypes.byref(length)) or length.value < 52:
        raise ValueError("missing fixed binary version metadata")
    fields = ctypes.cast(pointer, ctypes.POINTER(wintypes.DWORD * 13)).contents
    if fields[0] != 0xFEEF04BD:
        raise ValueError("invalid fixed version signature")
    return '.'.join(map(str, (fields[2] >> 16, fields[2] & 65535, fields[3] >> 16, fields[3] & 65535)))


def write(path, value):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")


def verify_source(source, files, deadline):
    actual = set()
    for current, directories, names in os.walk(source, followlinks=False):
        directory = absolute_nonreparse(Path(current))
        directories[:] = [name for name in directories if name != ".dmbc"]
        for name in directories:
            absolute_nonreparse(directory / name)
        for name in names:
            path = directory / name
            regular(path)
            key = path.relative_to(source).as_posix()
            actual.add(key)
            if key not in files or sha(path, deadline) != files[key]:
                raise ValueError(f"source closure differs: {key}")
    if actual != set(files):
        raise ValueError("source closure has missing files")


def run(command, cwd, log, deadline, limit=300):
    timeout = min(limit, deadline - time.monotonic())
    if timeout <= 0:
        raise TimeoutError("aggregate recapture deadline")
    started = time.monotonic()
    with log.open("xb") as stream:
        child = subprocess.Popen(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT,
                                 creationflags=subprocess.CREATE_NO_WINDOW)
        cleanup = None
        try:
            code = child.wait(timeout=timeout)
            timed_out = False
        except subprocess.TimeoutExpired:
            cleanup = terminate_owned(child)
            code, timed_out = child.returncode, True
    return {"command": command, "exit_code": code, "timeout": timed_out,
            "seconds": time.monotonic() - started, "log": str(log), "cleanup": cleanup}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepared-root", type=Path, required=True)
    parser.add_argument("--capture-name", default="recapture")
    parser.add_argument("--byond", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--native-sha256", required=True)
    parser.add_argument("--engine-template", type=Path, required=True)
    args = parser.parse_args()
    if os.name != "nt":
        raise ValueError("Windows binary metadata required")
    deadline = time.monotonic() + 600
    root = absolute_nonreparse(args.prepared_root)
    if not root.is_relative_to(Path("E:/dq-cache")):
        raise ValueError("prepared root must be E:/dq-cache")
    source = root / "source"
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", args.capture_name):
        raise ValueError("capture-name must be a contained simple basename")
    capture = root / args.capture_name
    byond, native, template = (absolute_nonreparse(path) for path in
                               (args.byond, args.native, args.engine_template))
    identities = {"byond": sha(byond, deadline), "native": sha(native, deadline),
                  "template": sha(template, deadline)}
    if identities["byond"] != BYOND_SHA or identities["native"] != args.native_sha256:
        raise ValueError("compiler identity differs from supplied frozen pins")
    version = file_version(byond)
    if version != "5.0.516.1687":
        raise ValueError(f"wrong binary version: {version}")
    closure = root / "input-closure.json"
    snapshot = root / "source-snapshot.json"
    closure_sha, snapshot_sha = sha(closure, deadline), sha(snapshot, deadline)
    files = json.loads(snapshot.read_text())["files"]
    if any(Path(key).parts[0] == ".dmbc" for key in files):
        raise ValueError("snapshot includes compiler output domain; explicitly reissue filtered roster first")
    entries = json.loads(closure.read_text())
    if {row["path"]: row["sha256"] for row in entries if row["tree"] == "source"} != files:
        raise ValueError("snapshot and closure disagree")
    capture.mkdir()
    report = {"schema": 1, "status": "running", "compiler_sha256": identities,
              "source_closure_sha256": closure_sha, "runtime": "not run", "parity": "not asserted",
              "recovery_receipt_sha256": sha(root / "recovery.json", deadline),
              "historical_snapshot_equivalence": "not asserted"}
    try:
        verify_source(source, files, deadline)
        banner = run([str(byond)], source, capture / "version.log", deadline, 30)
        if banner["timeout"] or not re.search(r"DM compiler version 516\.1687\b", (capture / "version.log").read_text()):
            raise ValueError("BYOND version banner not authenticated")
        version_path = capture / "byond-version.json"
        write(version_path, {"file_version": version, "compiler_sha256": identities["byond"], "banner": banner})
        flags = [f"-D{value}" for value in DEFINES]
        byond_result = run([str(byond), *flags, "comparison.dme"], source, capture / "byond.log", deadline)
        report["byond"] = byond_result
        if byond_result["timeout"] or byond_result["exit_code"] != 0:
            raise ValueError("BYOND baseline compilation failed")
        pairs = capture / "byond"
        pairs.mkdir()
        for suffix in (".dmb", ".rsc"):
            output = source / ("comparison" + suffix)
            regular(output)
            byond_result[suffix + "_sha256"] = sha(output, deadline)
            output.rename(pairs / ("world" + suffix))
        byond_result.update(producer="byond", compiler_sha256=identities["byond"])
        verify_source(source, files, deadline)
        native_arguments = ["--no-daemon", "--no-cache", "--workers", "2", "--engine-template", str(template),
                            "--bootstrap-catalog", "--exact-inputs", "--output-store", str(capture / "native-store"),
                            "--artifact-directory", str(capture / "native"), *flags]
        native_result = run([str(native), "compile", "comparison.dme", *native_arguments],
                            source, capture / "native.log", deadline)
        report["native"] = native_result
        if native_result["timeout"] or native_result["exit_code"] != 0:
            raise ValueError("native configuration capture compilation failed")
        for suffix in (".dmb", ".rsc"):
            output = capture / "native" / ("comparison" + suffix)
            regular(output)
            native_result[suffix + "_sha256"] = sha(output, deadline)
        native_result.update(producer="native", compiler_sha256=identities["native"])
        verify_source(source, files, deadline)
        if (sha(closure, deadline) != closure_sha or sha(snapshot, deadline) != snapshot_sha or
            identities != {"byond": sha(byond, deadline), "native": sha(native, deadline), "template": sha(template, deadline)}):
            raise ValueError("capture authority changed")
        evidence = capture / "configuration-evidence.json"
        write(evidence, [byond_result, native_result])
        configuration, _ = semantic_configuration.command_configuration("comparison.dme", native_arguments, sha)
        pin = {"schema": 1, "snapshot_id": snapshot_sha, "dmb_sha256": byond_result[".dmb_sha256"],
               "rsc_sha256": byond_result[".rsc_sha256"], "source_closure_manifest_sha256": closure_sha,
               "semantic_configuration": configuration,
               "configuration_evidence": [{"path": str(evidence), "sha256": sha(evidence)}],
               "byond_version_evidence": {"path": str(version_path), "sha256": sha(version_path)}}
        semantic_configuration.authenticate_pin(pin, configuration, sha)
        authenticate_source_snapshot(json.loads(snapshot.read_text()), closure, pin, sha)
        write(root / "byond-structural-pin.json", pin)
        write(root / "scenarios.json", [{"name": "cold", "project": "comparison.dme",
              "arguments": ["--bootstrap-catalog", "--engine-template", str(template), *flags]}])
        report["status"] = "passed"
    except Exception as error:
        report.update(status="failed", error=str(error))
    finally:
        write(capture / "recapture.json", report)
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
