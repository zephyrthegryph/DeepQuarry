"""Pinned BYOND compile-only icon grammar capture; never starts DreamDaemon.

Raw list words are evidence. proc-code is used only to locate the procedure ID;
its decode result may fail and does not license any operand grammar.
"""
import argparse
import ast
import ctypes
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import sys
import time
import uuid

HERE = Path(__file__).resolve().parent
BENCH = HERE.parents[2] / "bench"
DM_SHA = "8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0"
PROCEDURES = ("/proc/insert_receiver", "/proc/map_colors_receiver")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("dm", "inspector"):
        parser.add_argument("--" + name, required=True, type=Path)
        parser.add_argument("--" + name + "-sha256", required=True)
    parser.add_argument("--output-root", type=Path,
                        default=Path("E:/dq-cache/dmb-icon-receiver-grammar"))
    args = parser.parse_args()
    if os.name != "nt":
        parser.error("requires pinned Windows tools")
    sys.path.insert(0, str(BENCH))
    spec = importlib.util.spec_from_file_location("icon_iteration", BENCH / "native-iteration.py")
    h = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(h)
    from upgrade_owned_job import OwnedJob
    h.safe_e(args.output_root)
    args.output_root.mkdir(parents=True, exist_ok=True)
    root = args.output_root / uuid.uuid4().hex
    root.mkdir()
    receipt = {"schema": "icon-receiver-grammar-v1", "complete": False,
               "scope": "BYOND compile-only raw words; grammar not inferred",
               "runtime": "not run", "child_watchdog_seconds": 30,
               "overall_watchdog_seconds": 180, "job_memory_bytes": 4_000_000_000,
               "pins": {}, "procedures": {}}
    deadline = time.monotonic() + 180
    job = None
    old_job = h._owned_job
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.SetErrorMode.argtypes = [ctypes.c_uint]
    kernel.SetErrorMode.restype = ctypes.c_uint
    old_mode = kernel.SetErrorMode(3)

    def run(exe, arguments, name, accept_failure=False):
        row = h.run_child(exe, arguments, root / name,
                          min(deadline, time.monotonic() + 30), cache_directory=root / "cache")
        stdout = (root / name / "stdout.log").read_bytes()
        stderr = (root / name / "stderr.log").read_bytes()
        if len(stdout) + len(stderr) > 1024 * 1024:
            raise ValueError("tiny capture exceeded 1MiB output limit")
        if row["exit"] != 0 and not accept_failure:
            raise ValueError("capture child failed: " + name)
        return row, stdout.decode("utf-8-sig", errors="replace")

    try:
        for name in ("dm", "inspector"):
            path = getattr(args, name).resolve(strict=True)
            h.regular(path)
            digest = getattr(args, name + "_sha256")
            if not re.fullmatch(r"[0-9a-f]{64}", digest) or h.sha(path) != digest:
                raise ValueError("tool pin mismatch: " + name)
            if name == "dm" and digest != DM_SHA:
                raise ValueError("requires admitted BYOND 516.1687 compiler")
            setattr(args, name, path)
            receipt["pins"][name] = {"path": str(path), "sha256": digest}
        hashes = {name: h.sha(HERE / name) for name in ("probe.dm", "probe.dme")}
        receipt["source_sha256"] = hashes
        for name in hashes:
            shutil.copyfile(HERE / name, root / name)
        job = OwnedJob(4_000_000_000)
        h._owned_job = job
        receipt["compile"], text = run(args.dm, [str(root / "probe.dme")], "compile")
        if not re.search(r"\b516\.1687\b", text):
            raise ValueError("successful compiler banner does not match pin")
        dmb = root / "probe.dmb"
        h.regular(dmb)
        receipt["output"] = {"path": str(dmb), "bytes": dmb.stat().st_size, "sha256": h.sha(dmb)}
        for index, path in enumerate(PROCEDURES):
            row = receipt["procedures"][path] = {}
            row["locator"], text = run(args.inspector, ["proc-code", str(dmb), path],
                                        f"locate-{index}", accept_failure=True)
            match = re.search(r"^proc#(\d+) " + re.escape(path) + r"$", text, re.MULTILINE)
            if not match:
                raise ValueError("inspector did not issue exact procedure locator")
            proc_id = int(match[1])
            row["record"], text = run(args.inspector, ["proc", str(dmb), str(proc_id)], f"record-{index}")
            match = re.search(r"code_locals_args: \[(\d+),", text)
            if not match:
                raise ValueError("missing raw code-list identity")
            list_id = int(match[1])
            row["raw_capture"], text = run(args.inspector, ["list", str(dmb), str(list_id)], f"raw-{index}")
            words = ast.literal_eval(text.strip())
            if not isinstance(words, list) or not all(type(word) is int and 0 <= word <= 0xffffffff for word in words):
                raise ValueError("invalid raw word list")
            row.update(proc_id=proc_id, list_id=list_id, raw_words=words)
        for name, digest in hashes.items():
            if h.sha(HERE / name) != digest or h.sha(root / name) != digest:
                raise ValueError("source changed during capture")
        if h.sha(dmb) != receipt["output"]["sha256"]:
            raise ValueError("compiled output changed during inspection")
        for name, pin in receipt["pins"].items():
            if h.sha(getattr(args, name)) != pin["sha256"]:
                raise ValueError("tool changed during capture")
        receipt["complete"] = True
    except Exception as error:
        receipt["error"] = str(error)
    finally:
        if job is not None:
            receipt["cleanup"] = job.close()
            if not receipt["cleanup"].get("reaped"):
                receipt["complete"] = False
        h._owned_job = old_job
        kernel.SetErrorMode(old_mode)
        (root / "receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
        print(root / "receipt.json")
    return 0 if receipt["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
