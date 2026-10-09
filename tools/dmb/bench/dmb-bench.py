#!/usr/bin/env python3
"""Revision-6 alternating benchmark driver. Runs only its compiler children, never a world."""
import argparse
import csv
import concurrent.futures
from collections import deque
import io
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import time

_domain_spec = importlib.util.spec_from_file_location(
    "dmb_bench_domain_adoption", Path(__file__).with_name("domain_adoption.py"))
_domain_module = importlib.util.module_from_spec(_domain_spec)
_domain_spec.loader.exec_module(_domain_module)
DOMAIN_BOUND_METHOD = _domain_module.METHOD

def domain_bound_adoption(row, stage_map):
    return _domain_module.evaluate(row, stage_map, selected_stages)


_watchdog_spec = importlib.util.spec_from_file_location(
    "dmb_bench_owned_watchdog", Path(__file__).with_name("watchdog.py"))
if _watchdog_spec is None or _watchdog_spec.loader is None:
    raise ImportError("cannot load benchmark sibling watchdog")
_watchdog_module = importlib.util.module_from_spec(_watchdog_spec)
_watchdog_spec.loader.exec_module(_watchdog_module)
terminate_owned = _watchdog_module.terminate_owned

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
            receipt = terminate_owned(process)
            prefix.with_suffix(".watchdog.json").write_text(
                json.dumps(receipt, indent=2, allow_nan=False), encoding="utf-8")
            if not receipt["reaped"]:
                raise RuntimeError(f"owned benchmark process did not exit; see {prefix.with_suffix('.watchdog.json')}")
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
    if calibration.get("method") not in ("QueryThreadCycleTime", "GetThreadTimes", "CLOCK_THREAD_CPUTIME_ID"):
        errors.append("unknown/missing thread CPU clock calibration")
    quantum = row.get("cpu_bounds_quantum_s")
    expected = 0.03125 if calibration.get("method") in ("QueryThreadCycleTime", "GetThreadTimes") else 0.0
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
    stages = [stage for stage in stages if stage.get("cpu_measurement") != "wall_allocations_only"]
    if not stages:
        return errors + ["missing CPU-measured profile stages"]
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
    by_name = selected_stages(row)
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


def selected_stages(row):
    stages = {stage.get("name"): stage for stage in row.get("stages", [])}
    for name in row.get("critical_path_stages", []):
        if isinstance(name, str) and name.startswith("exclusive:"):
            original = stages.get(name[len("exclusive:"):])
            if original is not None:
                stages[name] = {**original, "name": name,
                                "max_thread_cpu_s": original.get("max_thread_exclusive_cpu_s"),
                                "max_thread_cpu_bounds_s": original.get("max_thread_exclusive_cpu_bounds_s"),
                                "cpu_s": original.get("exclusive_cpu_s"),
                                "cpu_bounds_s": original.get("exclusive_cpu_bounds_s")}
    return stages


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
    if method == "GetThreadTimes":
        if thread_calibrations not in (None, []):
            errors.append("direct thread CPU report unexpectedly contains cycle calibrations")
    elif thread_calibrations is not None:
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
        if method not in ("QueryThreadCycleTime", "GetThreadTimes", "CLOCK_THREAD_CPUTIME_ID"):
            errors.append("unknown/missing thread CPU clock calibration")
    elif method == "QueryThreadCycleTime":
        for name in ("cycles_per_cpu_second", "calibration_cpu_s", "calibration_wall_s"):
            if not metric(calibration.get(name), positive=True):
                errors.append("invalid Windows calibration " + name)
        if metric(calibration.get("calibration_cpu_s")) and calibration["calibration_cpu_s"] < 0.5:
            errors.append("Windows calibration has less than 500 ms thread CPU")
    elif method != "CLOCK_THREAD_CPUTIME_ID":
        errors.append("unknown/missing thread CPU clock calibration")
    if method != "GetThreadTimes" and not metric(calibration.get("calibration_wall_s")):
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
    stages = [stage for stage in row.get("stages", [])
              if stage.get("cpu_measurement") != "wall_allocations_only"]
    if any(not isinstance(stage.get("name"), str) or not stage["name"] for stage in stages):
        return errors + ["invalid profile stage name"]
    if not stages or len({stage.get("name") for stage in stages}) != len(stages):
        errors.append("missing/duplicate profile stages")
    by_name = selected_stages(row)
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
    for key in ("wall_s", "child_wall_s", "profile_wall_s", "critical_path_cpu_s", "total_cpu_s", "read_bytes", "write_bytes", "peak_private_bytes"):
        values = [row.get(key) for row in rows]
        valid = bool(values) and all(metric(v) for v in values)
        if key in ("read_bytes", "write_bytes", "peak_private_bytes"):
            valid = valid and all(type(v) is int for v in values)
        result[key] = statistics.median(values) if valid else None
    scopes = {row.get("wall_scope") for row in rows}
    result["wall_scope"] = next(iter(scopes)) if len(scopes) == 1 else "mixed_or_unspecified"
    result["child_wall_scope"] = "harness_child_launch_to_reap" if result["child_wall_s"] is not None else "unavailable_legacy_or_missing_measurement"
    profile_scopes = {row.get("profile_wall_scope") for row in rows}
    result["profile_wall_scope"] = next(iter(profile_scopes)) if len(profile_scopes) == 1 else "mixed_or_unspecified"
    # Existing rows keep their recorded wall metric/scope. Missing child wall
    # cannot be reconstructed from profiler wall and must remain unavailable.
    upper = [cpu_upper(row, "critical_path_cpu_s", "critical_path_cpu_bounds_s") for row in rows]
    result["critical_path_cpu_budget_upper_s"] = statistics.median(upper) if upper and all(metric(v) for v in upper) else None
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
    if all(row.get("measurement_revision") == 6 for row in rows):
        if any(row.get("binary_mode") != "acceptance" or row.get("allocation_counting") is not False for row in rows):
            missing.append("non-counting revision6 acceptance binary")
    elif not all(row.get("allocation_counting") is True for row in rows):
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
    adopted_rows = []
    for row in rows:
        # Short unchanged sequence has its own existing measurement contract.
        proof_row = row if scenario != "unchanged" else {
            key: value for key, value in row.items()
            if key not in ("domain_cpu_bounds", "domain_cpu_selectors")}
        adopted, _, proof_errors = domain_bound_adoption(proof_row, active_map)
        if proof_errors:
            return "not_evaluable", proof_errors
        adopted_rows.append(adopted)
    for domain, names in active_map.items():
        costs = [adopted[domain] for adopted in adopted_rows]
        if any(not metric(value) for pair in costs for value in pair):
            return "not_evaluable", ["missing mapped stage CPU: " + domain]
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
    parser.add_argument("--previous-compiler", type=Path)
    parser.add_argument("--self-comparison", action="store_true", help="ABABAB current binary noise floor")
    parser.add_argument("--profile-metadata", type=Path, required=True)
    parser.add_argument("--previous-profile-metadata", type=Path)
    parser.add_argument("--binary-mode", choices=("acceptance", "counting"), default="acceptance")
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--snapshot", type=Path, required=True, help="JSON {commit,files:{relative:sha256}}")
    parser.add_argument("--input-journal", type=Path, help="Pinned captured replay journal; never copied per repetition")
    parser.add_argument("--scenarios", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--results", type=Path, default=Path(__file__).with_name("results.jsonl"))
    parser.add_argument("--cache", type=Path, default=Path(os.environ.get("DMB_CACHE_DIR", "E:/dq-cache/dmb/bench")))
    parser.add_argument("--watchdog", type=int, default=600)
    parser.add_argument("--min-free-bytes", type=int, default=25 * 1024**3)
    parser.add_argument("--worker-counts", type=int, nargs="+", default=[8])
    parser.add_argument("--stage-map", type=Path)
    parser.add_argument("--previous-stage-map", type=Path, help="Explicit CPU domain map for the previous compiler; defaults to --stage-map")
    parser.add_argument("--inspector", type=Path, required=True)
    parser.add_argument("--byond-dmb", type=Path, required=True)
    parser.add_argument("--byond-snapshot", type=Path, required=True,
                        help="JSON {snapshot_id,dmb_sha256} pins BYOND to this exact input snapshot")
    parser.add_argument("--native-baseline", type=Path, help="JSON {snapshot_id,pair_sha256:{.dmb:sha256,.rsc:sha256}} pins byte-identical native reference")
    parser.add_argument("--structural-baseline", type=Path, help="Pinned complete structural report with exact category case signatures")
    parser.add_argument("--establish-structural-baseline", action="store_true", help="Record complete existing divergences, without claiming zero parity")
    args = parser.parse_args()
    if args.establish_structural_baseline and not args.self_comparison:
        parser.error("establish a structural baseline with --self-comparison")
    if not 1 <= args.watchdog <= 600:
        parser.error("watchdog must be 1..600 seconds")
    if args.min_free_bytes < 25 * 1024**3:
        parser.error("free-space floor must be at least 25 GiB")
    if any(workers not in (1, 2, 8) for workers in args.worker_counts):
        parser.error("worker counts must be 1, 2, or 8")
    if len(set(args.worker_counts)) != len(args.worker_counts):
        parser.error("worker counts must be unique")
    spec = importlib.util.spec_from_file_location("dmb_bench_protocol", Path(__file__).with_name("protocol.py"))
    if spec is None or spec.loader is None:
        raise ImportError("cannot load revision6 benchmark protocol")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    from types import SimpleNamespace
    return module.execute(SimpleNamespace(**globals()), args)


if __name__ == "__main__":
    raise SystemExit(main())
