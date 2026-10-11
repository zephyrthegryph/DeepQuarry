"""Separate-process disk replay with the existing compiler/OwnedJob launcher; no DD."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
import time
import uuid

HERE = Path(__file__).resolve().parent
BENCH = HERE.parents[2] / "bench"

def revisions(source):
    def replace(text, before, after):
        if text.count(before) != 1:
            raise ValueError("one exact fixture edit required")
        return text.replace(before, after, 1)
    changed = replace(source, "return 2", "return 3")
    shifted = "\n\n" + changed
    nested = replace(shifted, "amount=7", "amount=9")
    removed = replace(nested, "/obj/inner\n    var/amount\n", "")
    return [("cold", source, False, True),
            ("unrelated_body", changed, True, True),
            ("shifted_origins", shifted, True, True),
            ("nested_value", nested, False, True),
            ("removed_nested_type", removed, False, False)]

def bounded_json(path):
    if path.stat().st_size > 1024 * 1024:
        raise ValueError("tiny compiler evidence exceeds 1 MiB")
    return json.loads(path.read_text(encoding="utf-8"))

def disk_evidence(stats):
    memo = stats.get("memo") or {}
    hits = memo.get("disk_hits")
    if type(hits) is not int or hits < 0:
        raise ValueError("missing exact current-request disk hit telemetry")
    if memo.get("resident_hits") != 0:
        raise ValueError("separate-process fixture cannot claim resident memo reuse")
    explanations = stats.get("explanations")
    if not isinstance(explanations, list):
        raise ValueError("missing per-procedure replay evidence")
    selected = [entry for entry in explanations if entry.get("path") == "/proc/modified_value"
                and entry.get("occurrence") == 0]
    if len(selected) != 1:
        raise ValueError("modified procedure needs one exact replay explanation")
    return {"disk_hits": hits, "compact_disk_hits": memo.get("compact_disk_hits"),
            "resident_hits": 0, "session_hit": stats.get("session_hit"),
            "modified_procedure": selected[0]}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("native", "template"):
        parser.add_argument("--" + name, type=Path, required=True)
        parser.add_argument("--" + name + "-sha256", required=True)
    parser.add_argument("--output-root", type=Path,
                        default=Path("E:/dq-cache/dmb-modified-procedure-disk-contract"))
    args = parser.parse_args()
    if os.name != "nt":
        raise ValueError("owned Windows process fixture required")
    sys.path.insert(0, str(BENCH))
    spec = importlib.util.spec_from_file_location("modified_disk_iteration", BENCH / "native-iteration.py")
    h = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(h)
    from upgrade_owned_job import OwnedJob
    diagnostic_path = HERE.parent / "safe_receiver_catch_diagnostics" / "run.py"
    spec = importlib.util.spec_from_file_location("modified_disk_diagnostics", diagnostic_path)
    d = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(d)
    parent = h.safe_e(args.output_root)
    parent.mkdir(parents=True, exist_ok=True)
    root = parent / uuid.uuid4().hex
    root.mkdir()
    receipt = {"schema": 1, "complete": False, "scope": "separate compiler processes, persisted modified procedure replay and exact fresh output; no runtime or performance claim",
               "root": str(root), "pins": {}, "revisions": [], "child_watchdog_seconds": 30,
               "overall_watchdog_seconds": 300, "job_memory_bytes": 4 * 1024 ** 3}
    job = None
    previous = h._owned_job
    deadline = time.monotonic() + 300
    try:
        for name in ("native", "template"):
            path = getattr(args, name).resolve(strict=True)
            h.regular(path)
            expected = getattr(args, name + "_sha256")
            if not re.fullmatch(r"[0-9a-f]{64}", expected) or h.sha(path) != expected:
                raise ValueError("pinned input mismatch: " + name)
            setattr(args, name, path)
            receipt["pins"][name] = {"path": str(path), "sha256": expected}
        receipt["fixture_sha256"] = {name: h.sha(HERE / name) for name in ("probe.dm", "probe.dme", "run.py")}
        source = root / "source"
        source.mkdir()
        (source / "probe.dme").write_bytes((HERE / "probe.dme").read_bytes())
        project = source / "probe.dme"
        cache = root / "shared-disk-cache"
        job = OwnedJob(4 * 1024 ** 3)
        h._owned_job = job
        for name, text, require_hit, accepted in revisions((HERE / "probe.dm").read_text()):
            (source / "probe.dm").write_text(text, encoding="utf-8")
            source_pin = h.sha(source / "probe.dm")
            row = {"name": name, "source_sha256": source_pin, "expected_acceptance": accepted}
            receipt["revisions"].append(row)
            for mode in ("persisted", "fresh"):
                output = root / name / mode
                arguments = ["compile", str(project), "--workers", "1", "--no-daemon",
                    "--exact-inputs", "--bootstrap-catalog", "--engine-template", str(args.template),
                    "--artifact-directory", str(output / "artifacts"),
                    "--output-store", str(output / "store"), "--compile-result-file", str(output / "result.json")]
                if mode == "fresh":
                    arguments.append("--no-cache")
                child = h.run_child(args.native, arguments, output / "logs",
                                    min(deadline, time.monotonic() + 30), False, cache)
                child_record = bounded_json(output / "logs" / "child.json")
                pid = child_record.get("pid")
                # Every launcher call starts and reaps a new Popen; operating
                # systems may recycle PIDs after exit, so PID uniqueness is not authority.
                if type(pid) is not int or child_record.get("status") != "completed":
                    raise ValueError("compiler request lacks completed process evidence")
                diagnostic = d.diagnostics(d.bounded_log(output / "logs"))
                current = {"child": child, "pid": pid, "diagnostics": diagnostic}
                row[mode] = current
                if child["exit"] != (0 if accepted else 2):
                    raise ValueError("unexpected compile classification: " + name + "/" + mode)
                if accepted:
                    stats = bounded_json(source / ".dmbc/probe.stats.json")
                    (output / "stats.json").write_text(json.dumps(stats, indent=2), encoding="utf-8")
                    current["memo"] = disk_evidence(stats)
                    current["outputs"] = {ext: h.sha(output / "artifacts" / ("probe." + ext)) for ext in ("dmb", "rsc")}
                elif not any(item["severity"] == "error" for item in diagnostic):
                    raise ValueError("rejection lacks source diagnostics")
                if h.sha(source / "probe.dm") != source_pin:
                    raise ValueError("source mutated during request")
                for pin_name in ("native", "template"):
                    if h.sha(getattr(args, pin_name)) != receipt["pins"][pin_name]["sha256"]:
                        raise ValueError("pinned input mutated during request: " + pin_name)
            if row["persisted"]["diagnostics"] != row["fresh"]["diagnostics"]:
                raise ValueError("current source diagnostics differ from fresh")
            if accepted and row["persisted"]["outputs"] != row["fresh"]["outputs"]:
                raise ValueError("persisted/fresh binary mismatch")
            if require_hit and (row["persisted"]["memo"]["disk_hits"] < 1
                    or row["persisted"]["memo"]["modified_procedure"]["outcome"] != "DiskHit"):
                raise ValueError("unchanged modified procedure did not replay from disk")
            if accepted and row["fresh"]["memo"]["modified_procedure"]["outcome"] != "Recomputed":
                raise ValueError("fresh oracle unexpectedly reused the modified procedure")
            row["fresh_oracle_passed"] = True
        receipt["complete"] = True
    except Exception as error:
        receipt["error"] = str(error)
    finally:
        if job is not None:
            receipt["owned_job_cleanup"] = job.close()
            if not receipt["owned_job_cleanup"].get("reaped"):
                receipt.update(complete=False, error="owned compiler descendants not reaped")
        h._owned_job = previous
        (root / "receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
        print(root / "receipt.json")
    return 0 if receipt["complete"] else 1

if __name__ == "__main__":
    raise SystemExit(main())
