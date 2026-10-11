"""Pinned compile-only diagnostic stability observations; no runtime or parity claim."""
import argparse
import ctypes
import hashlib
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
CASES = ("baseline", "global_proc", "two_fields", "empty_fields", "valid_type")
ENV_KEYS = ("BYOND_USER", "BYOND_CONFIG", "LANG", "LC_ALL", "TZ", "TEMP", "TMP",
            "DMB_CACHE_DIR", "DMB_DAEMON_NAMESPACE", "DMB_DAEMON_AUTOSTART")


def diagnostics(text):
    return [{"file": m[1], "line": int(m[2]), "severity": m[3], "message": m[4]}
            for line in text.splitlines()
            if (m := re.match(r"^(.*\.dme?):(\d+):(error|warning|note):\s*(.*)$", line))]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dm", required=True, type=Path)
    parser.add_argument("--dm-sha256", required=True)
    parser.add_argument("--output-root", type=Path,
                        default=Path("E:/dq-cache/dmb-modified-initializer-diagnostic-repeat"))
    args = parser.parse_args()
    if os.name != "nt":
        parser.error("requires pinned Windows compiler")
    sys.path.insert(0, str(BENCH))
    spec = importlib.util.spec_from_file_location("repeat_iteration", BENCH / "native-iteration.py")
    h = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(h)
    from upgrade_owned_job import OwnedJob
    args.dm = args.dm.resolve(strict=True)
    h.regular(args.dm)
    if args.dm_sha256 != DM_SHA or h.sha(args.dm) != DM_SHA:
        raise ValueError("requires authenticated BYOND516.1687 compiler")
    h.safe_e(args.output_root)
    args.output_root.mkdir(parents=True, exist_ok=True)
    root = args.output_root.resolve() / uuid.uuid4().hex
    root.mkdir()
    original_cwd = Path.cwd()
    original_job = h._owned_job
    job = None
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.SetErrorMode.argtypes = [ctypes.c_uint]
    kernel.SetErrorMode.restype = ctypes.c_uint
    old_mode = kernel.SetErrorMode(3)
    receipt = {"schema": "modified-initializer-repeat-v1", "complete": False,
               "runtime": "not run", "scope": "observed baseline stability; no assumed cascades",
               "compiler": {"path": str(args.dm), "sha256": DM_SHA},
               "child_seconds": 30, "overall_seconds": 240, "job_memory_bytes": 4_000_000_000,
               "environment": {key: os.environ.get(key) for key in ENV_KEYS},
               "path_environment_sha256": hashlib.sha256(os.environ.get("PATH", "").encode()).hexdigest(),
               "rows": []}
    deadline = time.monotonic() + 240
    try:
        hashes = {case: h.sha(HERE / (case + ".dm")) for case in CASES}
        receipt["source_sha256"] = hashes
        job = OwnedJob(4_000_000_000)
        h._owned_job = job
        for index, case in enumerate(("baseline",) * 3 + CASES[1:]):
            directory = root / f"{index:02d}-{case}"
            directory.mkdir()
            source = directory / "probe.dm"
            shutil.copyfile(HERE / (case + ".dm"), source)
            manifest = directory / "probe.dme"
            manifest.write_bytes(b'#include "probe.dm"\n')
            if h.sha(source) != hashes[case]:
                raise ValueError("copied source does not match authored pin")
            os.chdir(directory)
            row = {"case": case, "cwd": str(Path.cwd()), "source_sha256": h.sha(source),
                   "manifest_sha256": h.sha(manifest)}
            receipt["rows"].append(row)
            row["child"] = h.run_child(args.dm, [str(manifest)], directory / "child",
                                       min(deadline, time.monotonic() + 30))
            logs = []
            for name in ("stdout.log", "stderr.log"):
                path = directory / "child" / name
                if path.stat().st_size > 1024 * 1024:
                    raise ValueError("tiny compiler log exceeds1MiB")
                row[name] = {"path": str(path), "sha256": h.sha(path)}
                logs.append(path.read_text(encoding="utf-8-sig", errors="replace"))
            row["acceptance"] = row["child"].get("exit") == 0
            row["diagnostics"] = diagnostics("\n".join(logs))
            # run_child returns a compact exit/timing DTO; its persisted child
            # receipt carries lifecycle status. Negative compiler exits are
            # normal completed observations, never a timeout classification.
            child_status = json.loads((directory / "child" / "child.json").read_text(encoding="utf-8"))
            if child_status.get("status") != "completed":
                raise ValueError("compiler child did not complete")
            if "DM compiler version 516.1687" not in logs[0]:
                raise ValueError("compiler banner does not match admitted pin")
            if h.sha(source) != hashes[case] or h.sha(manifest) != row["manifest_sha256"]:
                raise ValueError("captured inputs changed during child")
        receipt["baseline_stable"] = all(
            row["diagnostics"] == receipt["rows"][0]["diagnostics"]
            and row["acceptance"] == receipt["rows"][0]["acceptance"]
            for row in receipt["rows"][:3])
        if h.sha(args.dm) != DM_SHA or any(h.sha(HERE / (c + ".dm")) != hashes[c] for c in CASES):
            raise ValueError("authored source/compiler changed during observations")
        receipt["complete"] = True
    except Exception as error:
        receipt["error"] = str(error)
    finally:
        os.chdir(original_cwd)
        h._owned_job = original_job
        kernel.SetErrorMode(old_mode)
        if job is not None:
            receipt["owned_job_cleanup"] = job.close()
            if not receipt["owned_job_cleanup"].get("reaped"):
                receipt["complete"] = False
        (root / "receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
        print(root / "receipt.json")
    return 0 if receipt["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
