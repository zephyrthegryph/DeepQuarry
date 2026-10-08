#!/usr/bin/env python3
"""Revision-5 benchmark driver. Runs only its compiler children, never a world."""
import argparse
import csv
import concurrent.futures
from collections import deque
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
           "body-edit": (1.5, 2.0, 50_000_000, 120_000_000),
           "unchanged": (0.25, 0.2, 5_000_000, 1_000_000)}
STAGE_BUDGETS = {"input": (0.5, 1.0), "frontend": (3.0, 12.0),
                 "tree": (1.0, 2.0), "resources_maps": (2.0, 6.0),
                 "abi_initializers": (1.5, 4.0), "lowering": (3.0, 16.0),
                 "link": (1.0, 2.0), "composition_publication": (1.5, 3.0)}


def sha(path):
    digest = hashlib.sha256()
    buffer = bytearray(1024 * 1024)
    view = memoryview(buffer)
    with path.open("rb") as stream:
        while size := stream.readinto(buffer):
            digest.update(view[:size])
    return digest.hexdigest()


def source_path(root, relative):
    path = (root / relative).resolve()
    if not path.is_relative_to(root):
        raise ValueError("source path escapes frozen project: " + relative)
    return path


def check_snapshot(root, expected):
    # Resolve and hash every input on every check. Only two files are active,
    # with one reusable 1 MiB read buffer each; no stamp-based trust shortcut.
    def check(item):
        relative, digest = item
        if sha(source_path(root, relative)) != digest.lower():
            raise ValueError("frozen input changed: " + relative)

    items = iter(expected.items())
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        pending = deque()
        for _ in range(8):
            item = next(items, None)
            if item is not None:
                pending.append(pool.submit(check, item))
        try:
            while pending:
                # Consume in captured order so the earliest mismatch is stable.
                pending.popleft().result()
                item = next(items, None)
                if item is not None:
                    pending.append(pool.submit(check, item))
        finally:
            for future in pending:
                future.cancel()


def normalized_diagnostics(path, policy):
    """Use the same exact whitelist embedded by the Rust snapshot oracle."""
    lines = path.read_text(encoding="utf-8").splitlines()
    def measurement(line):
        for prefix, names in policy["stage_prefixes"].items():
            if line.startswith(prefix):
                name, separator, _ = line[len(prefix):].partition(":")
                if separator and name in names:
                    return True
        return any(line.startswith(prefix) for prefix in policy["prefixes"])
    return [line for line in lines if not measurement(line)]


def normal_windows_path(path):
    """Compare canonical Windows drive/UNC spellings without the API prefix."""
    value = str(path)
    if os.name == "nt":
        if value.startswith("\\\\?\\UNC\\"):
            value = "\\\\" + value[8:]
        elif value.startswith("\\\\?\\"):
            value = value[4:]
    return Path(value).resolve()


def compare_measured_diagnostics(measured_log, oracle_log, root, policy):
    prefix = "native verification passed: output and diagnostics match; evidence "
    lines = oracle_log.read_text(encoding="utf-8").splitlines()
    evidence = [line[len(prefix):] for line in lines if line.startswith(prefix)]
    if len(evidence) != 1:
        raise ValueError("oracle must report exactly one successful evidence directory")
    directory = normal_windows_path(evidence[0])
    if not directory.is_relative_to(normal_windows_path(root)):
        raise ValueError("oracle evidence escaped private project")
    measured = normalized_diagnostics(measured_log, policy)
    result = {"measured_normalized_sha256": hashlib.sha256(
        json.dumps(measured, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest(),
        "evidence_directory": str(directory), "children": {}}
    matched = True
    for name in ("incremental", "cold"):
        child_path = directory / (name + ".log")
        child = normalized_diagnostics(child_path, policy)
        result["children"][name] = {"log": str(child_path), "raw_sha256": sha(child_path),
            "normalized_sha256": hashlib.sha256(json.dumps(
                child, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()}
        matched = matched and measured == child
    result["matched"] = matched
    return result


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
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)
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


def cpu_bound(value):
    return (isinstance(value, dict) and metric(value.get("lower"))
            and metric(value.get("upper")) and value["lower"] <= value["upper"])


def cpu_upper(record, scalar, bounds):
    # Budget decisions use the worst permitted value, never a midpoint estimate.
    if record.get("cpu_bounds_method") == "paired_thread_cpu_quantization":
        value = record.get(bounds)
        return value["upper"] if cpu_bound(value) else None
    return record.get(scalar)


def bounded_cpu_quality(row):
    errors = [row["profile_error"]] if row.get("profile_error") else []
    total = row.get("total_cpu_s")
    if not metric(total, True):
        errors.append("missing/invalid total_cpu_s")
    calibration = row.get("calibration")
    calibration = calibration if isinstance(calibration, dict) else {}
    if calibration.get("method") not in ("QueryThreadCycleTime", "CLOCK_THREAD_CPUTIME_ID"):
        errors.append("unknown/missing thread CPU clock calibration")
    quantum = row.get("cpu_bounds_quantum_s")
    expected = 0.03125 if calibration.get("method") == "QueryThreadCycleTime" else 0.0
    if not metric(quantum) or quantum != expected:
        errors.append("invalid CPU quantization bound")
    fields = ("critical_path_cpu_bounds_s", "covered_thread_cpu_bounds_s", "cpu_crosscheck_ratio_bounds")
    for field in fields:
        if not cpu_bound(row.get(field)):
            errors.append("missing/invalid " + field)
    covered, ratio = row.get(fields[1]), row.get(fields[2])
    if cpu_bound(covered) and cpu_bound(ratio) and metric(total, True):
        for endpoint in ("lower", "upper"):
            if not math.isclose(ratio[endpoint], covered[endpoint] / total, rel_tol=1e-6, abs_tol=1e-9):
                errors.append("CPU crosscheck bounds do not match recorded totals")
        if ratio["lower"] < 0.95 or ratio["upper"] > 1.05:
            errors.append("covered/process CPU uncertainty is not wholly within 5%")
    stages = row.get("stages")
    if not isinstance(stages, list) or not stages or any(not isinstance(s, dict) for s in stages):
        return errors + ["missing/invalid profile stages"]
    names = [s.get("name") for s in stages]
    if any(not isinstance(n, str) or not n for n in names) or len(names) != len(set(names)):
        return errors + ["missing/duplicate profile stages"]
    for stage in stages:
        for field in ("cpu_bounds_s", "max_thread_cpu_bounds_s", "exclusive_cpu_bounds_s"):
            if not cpu_bound(stage.get(field)):
                errors.append("missing/invalid stage bound " + stage["name"] + ":" + field)
        inclusive, maximum, exclusive = (stage.get("cpu_bounds_s"),
                                         stage.get("max_thread_cpu_bounds_s"),
                                         stage.get("exclusive_cpu_bounds_s"))
        if cpu_bound(inclusive) and cpu_bound(maximum) and maximum["upper"] > inclusive["upper"] + 1e-9:
            errors.append("stage maximum bound exceeds total bound")
        if cpu_bound(inclusive) and cpu_bound(exclusive) and exclusive["lower"] > inclusive["upper"] + 1e-9:
            errors.append("stage exclusive bound contradicts inclusive bound")
        if not metric(stage.get("wall_s")):
            errors.append("missing/invalid stage wall duration")
        for field in ("allocations", "allocated_bytes", "peak_live_bytes", "calls"):
            if type(stage.get(field)) is not int or stage[field] < (1 if field == "calls" else 0):
                errors.append("missing/invalid stage count: " + field)
    by_name = dict(zip(names, stages))
    sequence = row.get("critical_path_stages")
    if (not isinstance(sequence, list) or not sequence or any(not isinstance(n, str) for n in sequence)
            or len(sequence) != len(set(sequence)) or any(n not in by_name for n in sequence)):
        errors.append("missing/invalid sequential critical-path stage declaration")
    else:
        critical = row.get(fields[0])
        if cpu_bound(critical) and all(cpu_bound(by_name[n].get("max_thread_cpu_bounds_s")) for n in sequence):
            for endpoint in ("lower", "upper"):
                if not math.isclose(sum(by_name[n]["max_thread_cpu_bounds_s"][endpoint] for n in sequence),
                                    critical[endpoint], rel_tol=1e-6, abs_tol=1e-9):
                    errors.append("critical bounds do not match declared stage maxima")
    if cpu_bound(covered) and all(cpu_bound(s.get("exclusive_cpu_bounds_s")) for s in stages):
        exclusive_sum = {endpoint: sum(s["exclusive_cpu_bounds_s"][endpoint] for s in stages)
                         for endpoint in ("lower", "upper")}
        coverage_method = row.get("covered_cpu_bounds_method")
        if coverage_method == "participating_thread_interval_union":
            # Stage endpoint errors are correlated. Their conservative sum can be
            # wider than the independently merged same-thread coverage interval.
            if (exclusive_sum["lower"] > covered["lower"] + 1e-9 or
                    exclusive_sum["upper"] < covered["upper"] - 1e-9):
                errors.append("covered union bounds contradict exclusive stage sum")
        elif coverage_method is None:
            for endpoint in ("lower", "upper"):
                if not math.isclose(exclusive_sum[endpoint], covered[endpoint],
                                    rel_tol=1e-6, abs_tol=1e-9):
                    errors.append("covered bounds do not match exclusive stage sum")
        else:
            errors.append("unknown covered CPU bounds method")
    if row.get("allocation_counting") is True and not any(
            metric(s.get("allocations"), True) and metric(s.get("allocated_bytes"), True) for s in stages):
        errors.append("allocation feature enabled without observed counting allocations")
    return errors


def cpu_quality(row):
    if row.get("cpu_bounds_method") == "paired_thread_cpu_quantization":
        return bounded_cpu_quality(row)
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
    thread_calibrations = row.get("thread_calibrations")
    if thread_calibrations is not None:
        if row.get("cpu_conversion_complete") is not True:
            errors.append("per-thread CPU conversion is incomplete")
        if not isinstance(thread_calibrations, list) or not thread_calibrations:
            errors.append("missing/invalid per-thread calibrations")
            thread_calibrations = []
        thread_ids = []
        for thread in thread_calibrations:
            if not isinstance(thread, dict):
                errors.append("invalid per-thread calibration record")
                continue
            thread_ids.append(thread.get("thread"))
            if method == "QueryThreadCycleTime":
                if thread.get("status") != "valid_observed_envelope":
                    errors.append("unavailable per-thread cycle calibration")
                if not metric(thread.get("cycles_per_cpu_second"), True):
                    errors.append("invalid per-thread cycle rate")
                if not metric(thread.get("observed_cpu_s")) or thread["observed_cpu_s"] < 1.0:
                    errors.append("per-thread calibration has less than 1 s thread CPU")
                if type(thread.get("checked_subintervals")) is not int or thread["checked_subintervals"] < 2:
                    errors.append("per-thread calibration lacks two stability windows")
                uncertainty = thread.get("envelope_relative_quantization_uncertainty")
                if not metric(uncertainty) or uncertainty > CPU_CROSSCHECK_TOLERANCE:
                    errors.append("per-thread envelope uncertainty exceeds 5%")
                for name in ("max_relative_rate_deviation", "max_relative_quantization_uncertainty"):
                    if not metric(thread.get(name)):
                        errors.append("missing per-thread stability evidence " + name)
                drift, uncertainty = (thread.get("max_relative_rate_deviation"),
                                      thread.get("max_relative_quantization_uncertainty"))
                if (thread.get("status") == "valid_observed_envelope" and metric(drift)
                        and metric(uncertainty) and drift > CPU_CROSSCHECK_TOLERANCE + uncertainty):
                    errors.append("per-thread rate is unstable despite valid status")
            elif method == "CLOCK_THREAD_CPUTIME_ID":
                if thread.get("status") != "native_nanoseconds":
                    errors.append("unavailable native thread CPU clock")
        if any(not isinstance(t, str) or not t for t in thread_ids):
            errors.append("invalid/duplicate calibration thread identity")
        elif len(set(thread_ids)) != len(thread_ids):
            errors.append("invalid/duplicate calibration thread identity")
        if method not in ("QueryThreadCycleTime", "CLOCK_THREAD_CPUTIME_ID"):
            errors.append("unknown/missing thread CPU clock calibration")
    elif method == "QueryThreadCycleTime":
        for name in ("cycles_per_cpu_second", "calibration_cpu_s", "calibration_wall_s"):
            if not metric(calibration.get(name), positive=True):
                errors.append("invalid Windows calibration " + name)
        if metric(calibration.get("calibration_cpu_s")) and calibration["calibration_cpu_s"] < 0.5:
            errors.append("Windows calibration has less than 500 ms thread CPU")
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
    upper = [cpu_upper(row, "critical_path_cpu_s", "critical_path_cpu_bounds_s") for row in rows]
    result["critical_path_cpu_budget_upper_s"] = statistics.median(upper) if all(metric(v) for v in upper) else None
    result["cpu_acceptance_basis"] = ("uncertainty_upper_bound" if any(
        row.get("cpu_bounds_method") == "paired_thread_cpu_quantization" for row in rows) else "calibrated_scalar")
    return result


def gate(scenario, rows, history, stage_map):
    if len(rows) != 3 or any(row["status"] != "verified" for row in rows):
        return "incomplete", ["three successful oracle-verified runs required"]
    quality = [reason for row in rows for reason in cpu_quality(row)]
    if quality:
        return "not_evaluable", sorted(set(quality))
    summary = medians(rows)
    required = ("critical_path_cpu_budget_upper_s", "total_cpu_s", "peak_private_bytes")
    missing = [name for name in required if summary[name] is None]
    if not all(row.get("allocation_counting") is True for row in rows):
        missing.append("allocation counting")
    if missing:
        return "not_evaluable", missing
    failures = []
    target = TARGETS.get(scenario)
    if target:
        for name, maximum in zip(("critical_path_cpu_budget_upper_s", "total_cpu_s"), target[:2]):
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
    if scenario == "unchanged":
        expected_sequence = ["engine_input", "session_validation"]
        if any(row["critical_path_stages"] != expected_sequence for row in rows):
            return "not_evaluable", ["unchanged requires exact authenticated-session short sequence"]
        if any(mapped_names.count(name) != 1 for name in expected_sequence):
            return "not_evaluable", ["short sequence must map uniquely into global budget domains"]
        active_map = {domain: [name for name in names if name in expected_sequence]
                      for domain, names in stage_map.items()}
        active_map = {domain: names for domain, names in active_map.items() if names}
    else:
        if any(set(mapped_names) != set(row["critical_path_stages"]) for row in rows):
            return "not_evaluable", ["budget mapping must cover exactly declared critical-path stages"]
        active_map = stage_map
    if len(mapped_names) != len(set(mapped_names)):
        return "not_evaluable", ["overlapping stage mappings"]
    for domain, names in active_map.items():
        costs = []
        for row in rows:
            by_name = {s["name"]: s for s in row.get("stages", [])}
            if any(name not in by_name for name in names):
                return "not_evaluable", ["missing mapped profile stage: " + domain]
            bounded = row.get("cpu_bounds_method") == "paired_thread_cpu_quantization"
            def cost(stage, scalar, bounds):
                return stage[bounds]["upper"] if bounded and cpu_bound(stage.get(bounds)) else stage.get(scalar)
            if any(cost(by_name[n], "max_thread_cpu_s", "max_thread_cpu_bounds_s") is None
                   or cost(by_name[n], "cpu_s", "cpu_bounds_s") is None for n in names):
                return "not_evaluable", ["missing mapped stage CPU: " + domain]
            costs.append((sum(cost(by_name[n], "max_thread_cpu_s", "max_thread_cpu_bounds_s") for n in names),
                          sum(cost(by_name[n], "cpu_s", "cpu_bounds_s") for n in names)))
        if domain in STAGE_BUDGETS:
            limit = STAGE_BUDGETS[domain]
            if statistics.median(c[0] for c in costs) > limit[0] or statistics.median(c[1] for c in costs) > limit[1]:
                failures.append(domain + " exceeds cold CPU stage budget")
    prior = [r for r in history if r.get("kind") == "median" and r.get("scenario") == scenario
             and r.get("workers") == 8 and r.get("acceptance") in ("passed", "failed")]
    for field in ("critical_path_cpu_s", "total_cpu_s"):
        history_field = "critical_path_cpu_budget_upper_s" if field == "critical_path_cpu_s" else field
        values = [r.get(history_field, r.get(field)) for r in prior[-3:]
                  if metric(r.get(history_field, r.get(field)))]
        current = summary["critical_path_cpu_budget_upper_s"] if field == "critical_path_cpu_s" else summary[field]
        if values and current > statistics.median(values) * 1.2:
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
    parser.add_argument("--cache", type=Path, default=Path(os.environ.get("DMB_CACHE_DIR", "E:/dq-cache/dmb/bench")))
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
    policy_path = Path(__file__).resolve().parent.parent / "diagnostic-measurements.json"
    diagnostic_policy = json.loads(policy_path.read_text(encoding="utf-8"))
    if diagnostic_policy.get("schema") != 1:
        parser.error("unsupported diagnostic measurement policy")
    policy_identity = sha(policy_path)
    expected = dict(snapshot["files"])
    check_snapshot(root, expected)
    args.cache.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(args.cache).free < args.min_free_bytes:
        parser.error("cache drive free space below requested population floor")
    args.output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, DMBD_VERIFY="1")
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
                # A previous repetition's edited variant must not turn the next
                # body-edit measurement into a hit for code already compiled.
                # Cold's separate oracle populates the unedited project in this
                # repetition's new cache before body-edit is measured.
                run_cache = args.cache / args.output.name / (str(workers) + "-" + str(repeat + 1))
                run_cache.mkdir(parents=True, exist_ok=False)
                if shutil.disk_usage(run_cache).free < args.min_free_bytes:
                    raise ValueError("cache drive free space below requested population floor")
                env["DMB_CACHE_DIR"] = str(run_cache.resolve())
                # Authenticated session records live beside the manifest rather
                # than beneath DMB_CACHE_DIR. Preserve prior repetitions' records
                # outside the active project so an old edited session cannot
                # bypass the body-edit pipeline in a later repetition.
                session_directories = sorted({source_path(root, scenario["project"]).parent
                                              / ".dmbc" / "input-sessions"
                                              for scenario in scenarios})
                for index, directory in enumerate(session_directories):
                    if directory.is_symlink() or not directory.resolve().is_relative_to(root):
                        raise ValueError("benchmark session directory must remain inside private project")
                    if directory.exists():
                        archive = run_cache / ("prior-input-sessions-" + str(index))
                        shutil.move(str(directory), str(archive))
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
                    diagnostic_comparison = None
                    diagnostic_error = None
                    if code == 0 and not timeout:
                        vcode, _, vtimeout = run(command + ["--verify"], root,
                                                Path(str(prefix) + "-oracle"), args.watchdog, env)
                        check_snapshot(root, current)
                        verified = vcode == 0 and not vtimeout
                        if verified:
                            verified = all(sha(manifest.with_suffix(ext)) == digest for ext, digest in pair_hashes.items())
                        if verified:
                            try:
                                if sha(policy_path) != policy_identity:
                                    raise ValueError("diagnostic measurement policy changed")
                                diagnostic_comparison = compare_measured_diagnostics(
                                    prefix.with_suffix(".stderr.log"),
                                    Path(str(prefix) + "-oracle").with_suffix(".stderr.log"),
                                    root, diagnostic_policy)
                                verified = diagnostic_comparison["matched"]
                                if not verified:
                                    diagnostic_error = "measured diagnostics differ from verified children"
                            except (OSError, ValueError) as error:
                                diagnostic_error = str(error)
                                verified = False
                    row = {"schema": SCHEMA, "kind": "run", "commit": snapshot["commit"],
                           "compiler_sha256": compiler_identity, "scenario": name, "workers": workers,
                           "repeat": repeat + 1, "wall_s": wall, "status": "watchdog" if timeout else ("verified" if verified else "failed"),
                           "exit_code": code, "oracle": "passed" if verified else "not_passed",
                           "trace": str(trace), "profile_report": str(report_path),
                           "profile_report_sha256": sha(report_path) if report_path.exists() else None,
                           "profile_error": report.get("profile_error"),
                           "command": measured_command, "cache": str(run_cache),
                           "pair_sha256": pair_hashes, "competing_processes_start": competing_start, "competing_processes_end": competing_end,
                           "diagnostic_policy_sha256": policy_identity,
                           "diagnostic_comparison": diagnostic_comparison, "diagnostic_error": diagnostic_error,
                           "stages": report.get("stages", []), "critical_path_cpu_s": report.get("critical_path_cpu_s"),
                           "total_cpu_s": report.get("total_cpu_s"), "covered_thread_cpu_s": report.get("covered_thread_cpu_s"),
                           "critical_path_stages": report.get("critical_path_stages"), "calibration": report.get("calibration"),
                           "cpu_crosscheck_ratio": report.get("cpu_crosscheck_ratio"), "coverage_notes": report.get("coverage_notes"),
                           "cpu_precision_scope": report.get("cpu_precision_scope"),
                           "coarse_covered_thread_cpu_s": report.get("coarse_covered_thread_cpu_s"),
                           "coarse_cpu_crosscheck_ratio": report.get("coarse_cpu_crosscheck_ratio"),
                           "thread_calibrations": report.get("thread_calibrations"),
                           "cpu_conversion_complete": report.get("cpu_conversion_complete"),
                           "cpu_bounds_method": report.get("cpu_bounds_method"),
                           "covered_cpu_bounds_method": report.get("covered_cpu_bounds_method"),
                           "cpu_bounds_quantum_s": report.get("cpu_bounds_quantum_s"),
                           "critical_path_cpu_bounds_s": report.get("critical_path_cpu_bounds_s"),
                           "covered_thread_cpu_bounds_s": report.get("covered_thread_cpu_bounds_s"),
                           "cpu_crosscheck_ratio_bounds": report.get("cpu_crosscheck_ratio_bounds"),
                           "io_coverage": report.get("io_coverage"), "process_io_scope": "whole_measured_process",
                           "attributed_io": [{"stage": stage.get("name"), "read_bytes": stage.get("attributed_read_bytes"),
                                              "write_bytes": stage.get("attributed_write_bytes"), "blocked_s": stage.get("io_blocked_s"),
                                              "call_elapsed_s": stage.get("io_call_elapsed_s"),
                                              "calls": stage.get("io_calls"), "failed_calls": stage.get("io_failed_calls"),
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
