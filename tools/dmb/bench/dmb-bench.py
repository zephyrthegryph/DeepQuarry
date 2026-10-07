#!/usr/bin/env python3
"""Revision-5 benchmark driver. Runs only its compiler children, never a world."""
import argparse
import csv
import io
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import signal
import statistics
import subprocess
import time

SCHEMA = 1
TARGETS = {"cold": (15.0, 40.0, 400_000_000, 600_000_000),
           "body-edit": (1.5, None, 50_000_000, 120_000_000),
           "unchanged": (0.25, None, 5_000_000, 1_000_000)}
STAGE_BUDGETS = {"input": (0.5, 1.0), "frontend": (3.0, 12.0),
                 "tree": (1.0, 2.0), "resources_maps": (2.0, 6.0),
                 "abi_initializers": (1.5, 4.0), "lowering": (3.0, 16.0),
                 "link": (1.0, 2.0), "composition_publication": (1.5, 3.0)}


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_path(root, relative):
    path = (root / relative).resolve()
    if not path.is_relative_to(root):
        raise ValueError("source path escapes frozen project: " + relative)
    return path


def check_snapshot(root, expected):
    for relative, digest in expected.items():
        if sha(source_path(root, relative)) != digest.lower():
            raise ValueError("frozen input changed: " + relative)


def process_context():
    """Observation only; no process is suspended or stopped."""
    try:
        if os.name == "nt":
            result = subprocess.run(["tasklist", "/FO", "CSV", "/NH"], capture_output=True,
                                    text=True, timeout=5, creationflags=subprocess.CREATE_NO_WINDOW)
            if result.returncode:
                return None
            rows = list(csv.reader(io.StringIO(result.stdout)))
            names = [row[0].lower() for row in rows if len(row) > 1 and row[1] != str(os.getpid())]
        else:
            names = []
            for directory in Path("/proc").iterdir():
                if directory.name.isdigit() and directory.name != str(os.getpid()):
                    try:
                        names.append((directory / "comm").read_text().strip().lower())
                    except OSError:
                        pass
        return {"scope": "visible_processes_excluding_harness", "total": len(names),
                "cargo_rustc": sum(n in ("cargo", "rustc", "cargo.exe", "rustc.exe") for n in names),
                "dreamdaemon": sum(n in ("dreamdaemon", "dreamdaemon.exe") for n in names)}
    except (OSError, subprocess.TimeoutExpired):
        return None


def append(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(value, separators=(",", ":"), allow_nan=False) + "\n")


def run(command, cwd, prefix, deadline, env):
    start = time.monotonic()
    kwargs = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {"start_new_session": True}
    with prefix.with_suffix(".stdout.log").open("wb") as out, prefix.with_suffix(".stderr.log").open("wb") as err:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=out, stderr=err, **kwargs)
        try:
            code = process.wait(timeout=deadline)
            return code, time.monotonic() - start, False
        except subprocess.TimeoutExpired:
            # Kill only this measurement's process tree. No unrelated process is stopped.
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10, **kwargs)
            else:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            return process.returncode, time.monotonic() - start, True


def profile(path):
    if not path.exists():
        return {"profile_error": "profile report missing"}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError) as error:
        return {"profile_error": "profile report unreadable: " + str(error)}
    if not isinstance(value, dict) or value.get("schema") != 1:
        return {"profile_error": "unsupported profile report schema"}
    if not isinstance(value.get("stages"), list) or any(not isinstance(s, dict) for s in value["stages"]):
        return {"profile_error": "invalid profile stage roster"}
    # JSONL remains strict. The original raw report retains invalid values;
    # unusable numeric measurements become unknown with an explicit error.
    invalid = False
    def clean(item):
        nonlocal invalid
        if isinstance(item, float) and not math.isfinite(item):
            invalid = True
            return None
        if isinstance(item, dict):
            return {k: clean(v) for k, v in item.items()}
        if isinstance(item, list):
            return [clean(v) for v in item]
        return item
    value = clean(value)
    if invalid:
        value["profile_error"] = "nonfinite profile measurements"
    return value


# Measurement-quality tolerance, not an allowance above an acceptance budget.
CPU_CROSSCHECK_TOLERANCE = 0.05


def metric(value, positive=False):
    return (type(value) in (int, float) and math.isfinite(value)
            and (value > 0 if positive else value >= 0))


def cpu_quality(row):
    errors = []
    if row.get("profile_error"):
        errors.append(row["profile_error"])
    for name in ("critical_path_cpu_s", "total_cpu_s", "covered_thread_cpu_s"):
        if not metric(row.get(name), positive=True):
            errors.append("missing/invalid " + name)
    calibration = row.get("calibration")
    if not isinstance(calibration, dict):
        calibration = {}
    method = calibration.get("method")
    if method == "QueryThreadCycleTime":
        for name in ("cycles_per_cpu_second", "calibration_cpu_s", "calibration_wall_s"):
            if not metric(calibration.get(name), positive=True):
                errors.append("invalid Windows calibration " + name)
    elif method != "CLOCK_THREAD_CPUTIME_ID":
        errors.append("unknown/missing thread CPU clock calibration")
    if not metric(calibration.get("calibration_wall_s")):
        errors.append("invalid calibration wall duration")
    ratio = row.get("cpu_crosscheck_ratio")
    if not metric(ratio, positive=True):
        errors.append("missing/invalid process CPU crosscheck")
    elif abs(ratio - 1.0) > CPU_CROSSCHECK_TOLERANCE:
        errors.append("covered/process CPU differ by more than 5%")
    total, covered = row.get("total_cpu_s"), row.get("covered_thread_cpu_s")
    if metric(total, True) and metric(covered, True) and metric(ratio, True):
        if not math.isclose(ratio, covered / total, rel_tol=1e-6, abs_tol=1e-9):
            errors.append("CPU crosscheck does not match recorded totals")
        critical = row.get("critical_path_cpu_s")
        if metric(critical) and critical > total * (1 + CPU_CROSSCHECK_TOLERANCE):
            errors.append("critical-path CPU exceeds total process CPU")
    stages = row.get("stages", [])
    if any(not isinstance(stage.get("name"), str) or not stage["name"] for stage in stages):
        return errors + ["invalid profile stage name"]
    if not stages or len({stage.get("name") for stage in stages}) != len(stages):
        errors.append("missing/duplicate profile stages")
    by_name = {stage.get("name"): stage for stage in stages}
    exclusive = []
    for stage in stages:
        for key in ("cpu_s", "max_thread_cpu_s", "exclusive_cpu_s", "wall_s"):
            if not metric(stage.get(key)):
                errors.append("missing/invalid stage metric " + str(stage.get("name")) + ":" + key)
        for name in ("allocations", "allocated_bytes", "peak_live_bytes"):
            if type(stage.get(name)) is not int or stage[name] < 0:
                errors.append("missing/invalid stage allocation count: " + name)
        if type(stage.get("calls")) is not int or stage["calls"] <= 0:
            errors.append("missing/invalid stage call count")
        if metric(stage.get("cpu_s")):
            if metric(stage.get("max_thread_cpu_s")) and stage["max_thread_cpu_s"] > stage["cpu_s"] + 1e-9:
                errors.append("stage max CPU exceeds summed CPU")
            if metric(stage.get("exclusive_cpu_s")) and stage["exclusive_cpu_s"] > stage["cpu_s"] + 1e-9:
                errors.append("stage exclusive CPU exceeds inclusive CPU")
        if metric(stage.get("exclusive_cpu_s")):
            exclusive.append(stage["exclusive_cpu_s"])
    if row.get("allocation_counting") is True and not any(
            metric(stage.get("allocations"), True) and metric(stage.get("allocated_bytes"), True) for stage in stages):
        errors.append("allocation feature enabled without observed counting allocations")
    if metric(covered) and len(exclusive) == len(stages) and not math.isclose(sum(exclusive), covered, rel_tol=1e-6, abs_tol=1e-9):
        errors.append("covered CPU does not match exclusive stage sum")
    sequence = row.get("critical_path_stages")
    if not isinstance(sequence, list) or not sequence or any(not isinstance(n, str) for n in sequence) or len(sequence) != len(set(sequence)):
        errors.append("missing/invalid sequential critical-path stage declaration")
    elif any(name not in by_name or not metric(by_name[name].get("max_thread_cpu_s")) for name in sequence):
        errors.append("critical path references an unmeasured stage")
    elif metric(row.get("critical_path_cpu_s")) and not math.isclose(
            sum(by_name[name]["max_thread_cpu_s"] for name in sequence), row["critical_path_cpu_s"],
            rel_tol=1e-6, abs_tol=1e-9):
        errors.append("critical path does not match declared stage maxima")
    return errors


def medians(rows):
    result = {}
    for key in ("wall_s", "critical_path_cpu_s", "total_cpu_s", "read_bytes", "write_bytes", "peak_private_bytes"):
        values = [row.get(key) for row in rows]
        valid = all(metric(v) for v in values)
        if key in ("read_bytes", "write_bytes", "peak_private_bytes"):
            valid = valid and all(type(v) is int for v in values)
        result[key] = statistics.median(values) if valid else None
    return result


def gate(scenario, rows, history, stage_map):
    if len(rows) != 3 or any(row["status"] != "verified" for row in rows):
        return "incomplete", ["three successful oracle-verified runs required"]
    quality = [reason for row in rows for reason in cpu_quality(row)]
    if quality:
        return "not_evaluable", sorted(set(quality))
    summary = medians(rows)
    required = ("critical_path_cpu_s", "total_cpu_s", "peak_private_bytes")
    missing = [name for name in required if summary[name] is None]
    if not all(row.get("allocation_counting") is True for row in rows):
        missing.append("allocation counting")
    if missing:
        return "not_evaluable", missing
    failures = []
    target = TARGETS.get(scenario)
    if target:
        for name, maximum in zip(("critical_path_cpu_s", "total_cpu_s"), target[:2]):
            if maximum is not None and summary[name] > maximum:
                failures.append(name + " exceeds scenario budget")
    if summary["peak_private_bytes"] > 1_500_000_000:
        failures.append("private memory exceeds 1.5 GB")
    # Cold stage budgets apply to rerun whole-program stages as well. A profile
    # stage name must be explicitly mapped; no substring matching or wall substitution.
    if not stage_map:
        return "not_evaluable", ["explicit profile stage mapping required"]
    if not isinstance(stage_map, dict) or set(stage_map) != set(STAGE_BUDGETS):
        return "not_evaluable", ["all eight budget domains must be mapped"]
    if any(not isinstance(names, list) or not names or any(not isinstance(name, str) for name in names) for names in stage_map.values()):
        return "not_evaluable", ["each budget domain needs a nonempty stage list"]
    mapped_names = [n for names in stage_map.values() for n in names]
    if any(set(mapped_names) != set(row["critical_path_stages"]) for row in rows):
        return "not_evaluable", ["budget mapping must cover exactly declared critical-path stages"]
    if len(mapped_names) != len(set(mapped_names)):
        return "not_evaluable", ["overlapping stage mappings"]
    for domain, names in stage_map.items():
        costs = []
        for row in rows:
            by_name = {s["name"]: s for s in row.get("stages", [])}
            if any(name not in by_name for name in names):
                return "not_evaluable", ["missing mapped profile stage: " + domain]
            if any(by_name[n].get("max_thread_cpu_s") is None or by_name[n].get("cpu_s") is None for n in names):
                return "not_evaluable", ["missing mapped stage CPU: " + domain]
            costs.append((sum(by_name[n]["max_thread_cpu_s"] for n in names),
                          sum(by_name[n]["cpu_s"] for n in names)))
        if domain in STAGE_BUDGETS:
            limit = STAGE_BUDGETS[domain]
            if statistics.median(c[0] for c in costs) > limit[0] or statistics.median(c[1] for c in costs) > limit[1]:
                failures.append(domain + " exceeds cold CPU stage budget")
    prior = [r for r in history if r.get("kind") == "median" and r.get("scenario") == scenario
             and r.get("workers") == 8 and r.get("acceptance") in ("passed", "failed")]
    for field in ("critical_path_cpu_s", "total_cpu_s"):
        values = [r[field] for r in prior[-3:] if metric(r.get(field))]
        if values and summary[field] > statistics.median(values) * 1.2:
            failures.append(field + " regresses >20% from trailing median")
    return ("failed" if failures else "passed"), failures


def io_gate(scenario, rows):
    if len(rows) != 3 or any(row.get("status") != "verified" for row in rows):
        return "incomplete", ["three successful oracle-verified runs required"]
    summary = medians(rows)
    if summary["read_bytes"] is None or summary["write_bytes"] is None:
        return "not_evaluable", ["I/O byte counts unavailable"]
    target = TARGETS.get(scenario)
    failures = []
    if target:
        for key, limit in zip(("read_bytes", "write_bytes"), target[2:]):
            if summary[key] > limit:
                failures.append(key + " exceeds I/O budget")
    if failures:
        return "failed", failures
    if any(row.get("io_coverage") != "complete" or not row.get("stages") or any(not metric(stage.get("io_blocked_s")) for stage in row["stages"]) for row in rows):
        return "not_evaluable", ["blocked I/O time unavailable; process-window bytes are not additive"]
    return "passed", []


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--snapshot", type=Path, required=True, help="JSON {commit,files:{relative:sha256}}")
    parser.add_argument("--scenarios", type=Path, required=True, help="ordered scenario JSON; edits must be private copies")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--results", type=Path, default=Path(__file__).with_name("results.jsonl"))
    parser.add_argument("--cache", type=Path, default=Path(os.environ.get("DMB_CACHE_DIR", "E:/.dmbd/cache")))
    parser.add_argument("--watchdog", type=int, default=285)
    parser.add_argument("--min-free-bytes", type=int, default=4 * 1024**3)
    parser.add_argument("--stage-map", type=Path)
    args = parser.parse_args()
    if not 1 <= args.watchdog <= 285:
        parser.error("watchdog must be 1..285 seconds")
    root, compiler = args.project_root.resolve(), args.compiler.resolve()
    compiler_identity = sha(compiler)
    snapshot = json.loads(args.snapshot.read_text(encoding="utf-8"))
    scenarios = json.loads(args.scenarios.read_text(encoding="utf-8"))
    if not scenarios or len({s["name"] for s in scenarios}) != len(scenarios):
        parser.error("scenario names must be unique and nonempty")
    for scenario in scenarios:
        if scenario["name"] not in TARGETS:
            parser.error("scenario must be cold, body-edit or unchanged")
        forbidden = {"--workers", "--trace", "--verify", "--record-inputs", "--replay-inputs", "--artifact-directory", "--no-cache"}
        if any(arg in forbidden for arg in scenario["arguments"]):
            parser.error("scenario arguments may not override harness-owned options")
    stage_map = json.loads(args.stage_map.read_text()) if args.stage_map else {}
    expected = dict(snapshot["files"])
    check_snapshot(root, expected)
    args.cache.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(args.cache).free < args.min_free_bytes:
        parser.error("cache drive free space below requested population floor")
    args.output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, DMB_CACHE_DIR=str(args.cache.resolve()), DMBD_VERIFY="1")
    history = [json.loads(line) for line in args.results.read_text().splitlines()] if args.results.exists() else []
    original = {}
    for scenario in scenarios:
        for edit in scenario.get("edits", []):
            path = source_path(root, edit["path"])
            if path.is_symlink() or path.stat().st_nlink > 1:
                parser.error("edited source must be a private file, not a link: " + edit["path"])
            if edit["path"] not in expected:
                parser.error("edit omitted from frozen snapshot")
            original[path] = path.read_bytes()
    failed = False
    try:
        for workers in (8, 2):
            collected = {s["name"]: [] for s in scenarios}
            for repeat in range(3):
                for path, value in original.items():
                    path.write_bytes(value)
                current = dict(expected)
                for scenario in scenarios:
                    for edit in scenario.get("edits", []):
                        path = source_path(root, edit["path"])
                        before, after = edit["before"].encode(), edit["after"].encode()
                        data = path.read_bytes()
                        if data.count(before) != 1:
                            raise ValueError("edit must match exactly once: " + edit["path"])
                        path.write_bytes(data.replace(before, after))
                        current[edit["path"]] = sha(path)
                    check_snapshot(root, current)
                    name = scenario["name"]
                    prefix = args.output / (str(workers) + "-" + str(repeat + 1) + "-" + name)
                    trace = prefix.with_suffix(".trace.json")
                    command = [str(compiler), "compile", scenario["project"], *scenario["arguments"], "--workers", str(workers)]
                    if sha(compiler) != compiler_identity:
                        raise ValueError("frozen compiler changed")
                    measured_command = command + ["--trace", str(trace.resolve())]
                    if scenario.get("no_cache"):
                        measured_command.append("--no-cache")
                    competing_start = process_context()
                    code, wall, timeout = run(measured_command, root, prefix, args.watchdog, env)
                    competing_end = process_context()
                    check_snapshot(root, current)
                    if sha(compiler) != compiler_identity:
                        raise ValueError("frozen compiler changed")
                    report_path = trace.with_suffix(".report.json")
                    report = profile(report_path)
                    manifest = source_path(root, scenario["project"])
                    pair_hashes = {ext: sha(manifest.with_suffix(ext)) for ext in (".dmb", ".rsc")} if code == 0 and not timeout else {}
                    # Verification is deliberately outside the measured build and uses
                    # a fresh captured snapshot. Source hashes must still match both sides.
                    verified = False
                    if code == 0 and not timeout:
                        vcode, _, vtimeout = run(command + ["--verify"], root,
                                                Path(str(prefix) + "-oracle"), args.watchdog, env)
                        check_snapshot(root, current)
                        verified = vcode == 0 and not vtimeout
                        if verified:
                            verified = all(sha(manifest.with_suffix(ext)) == digest for ext, digest in pair_hashes.items())
                    row = {"schema": SCHEMA, "kind": "run", "commit": snapshot["commit"],
                           "compiler_sha256": compiler_identity, "scenario": name, "workers": workers,
                           "repeat": repeat + 1, "wall_s": wall, "status": "watchdog" if timeout else ("verified" if verified else "failed"),
                           "exit_code": code, "oracle": "passed" if verified else "not_passed",
                           "trace": str(trace), "profile_report": str(report_path),
                           "profile_report_sha256": sha(report_path) if report_path.exists() else None,
                           "profile_error": report.get("profile_error"),
                           "command": measured_command, "cache": str(args.cache),
                           "pair_sha256": pair_hashes, "competing_processes_start": competing_start, "competing_processes_end": competing_end,
                           "stages": report.get("stages", []), "critical_path_cpu_s": report.get("critical_path_cpu_s"),
                           "total_cpu_s": report.get("total_cpu_s"), "covered_thread_cpu_s": report.get("covered_thread_cpu_s"),
                           "critical_path_stages": report.get("critical_path_stages"), "calibration": report.get("calibration"),
                           "cpu_crosscheck_ratio": report.get("cpu_crosscheck_ratio"), "coverage_notes": report.get("coverage_notes"),
                           "io_coverage": report.get("io_coverage"), "process_io_scope": "whole_measured_process",
                           "attributed_io": [{"stage": stage.get("name"), "read_bytes": stage.get("attributed_read_bytes"),
                                              "write_bytes": stage.get("attributed_write_bytes"), "blocked_s": stage.get("io_blocked_s"),
                                              "coverage": "explicit_operations_only"} for stage in report.get("stages", [])],
                           "read_bytes": report.get("read_bytes"),
                           "write_bytes": report.get("write_bytes"), "peak_private_bytes": report.get("peak_private_bytes"),
                           "allocation_counting": report.get("allocation_counting", False)}
                    append(args.results, row)
                    collected[name].append(row)
                    if not verified:
                        failed = True
            for name, rows in collected.items():
                acceptance, reasons = gate(name, rows, history, stage_map) if workers == 8 else ("regression_only", [])
                io_acceptance, io_reasons = io_gate(name, rows)
                row = {"schema": SCHEMA, "kind": "median", "commit": snapshot["commit"], "scenario": name,
                       "workers": workers, "runs": len(rows), "acceptance": acceptance, "cpu_acceptance": acceptance,
                       "reasons": reasons, "io_acceptance": io_acceptance, "io_reasons": io_reasons, **medians(rows)}
                append(args.results, row)
                if workers == 8 and acceptance != "passed":
                    failed = True
    finally:
        for path, value in original.items():
            path.write_bytes(value)
        check_snapshot(root, expected)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
