"""Streaming Phase 0 runtime comparison; raw inputs are never modified.

Usage: --run byond:preserved=DIR --run byond:1=DIR ... --run rust:3=DIR
       --output report.json
Only numeric :1/:2/:3 labels participate in repeated-run distributions. Preserved
runs are retained separately. Structured runtime.log.json (JSONL) is authoritative
when present: raw logs are never added to it; an independent raw audit is always retained. Raw logs are fallback only,
with explicitly incomplete procedure/ownership coverage. Normalization is a
heuristic; original messages and test objects remain available in the report.
"""
import argparse
from collections import Counter, defaultdict
from bisect import bisect_right
from datetime import datetime, timedelta
import json
from pathlib import Path
import re

NUMBER = re.compile(r"(?<![A-Za-z_])[-+]?\d+(?:\.\d+)?(?:e[-+]?\d+)?", re.I)
REFERENCE = re.compile(r"\[0x[0-9a-f]+\]|0x[0-9a-f]+", re.I)
PROC = re.compile(r"^proc name:\s*.*?\((/[^\n]+)\)\s*$", re.M)
SOURCE = re.compile(r"^\s*source file:\s*(.*?),(\d+)\s*$", re.M)
RAW = re.compile(r"^(?:\d{2}:\d{2}:\d{2}\s+)?(.*?\.dm):(\d+)\s+(.+)$")
RAW_UNLOCATED = re.compile(r"^(?:\d{2}:\d{2}:\d{2}\s+)?:\s+(.+)$")


def normalize(message):
    # Source location is extracted first and retained independently. Strip the
    # variable-rich call stack, timestamps, reference IDs and numeric values.
    text = message.split("\n", 1)[0].removeprefix("runtime error:").strip()
    text = REFERENCE.sub("<ref>", text)
    text = re.sub(r"\b\d{4}-\d\d-\d\d[ T]\d\d:\d\d:\d\d(?:\.\d+)?", "<time>", text)
    return NUMBER.sub("<number>", text)


def identity(message, source=None, line=None, proc=None):
    match = PROC.search(message)
    location = SOURCE.search(message)
    return (normalize(message), proc or (match.group(1) if match else None),
            source or (location.group(1).replace("\\", "/") if location else None),
            line if line is not None else (int(location.group(2)) if location else None))



TEST_BOUNDARY = re.compile(r"^\[(.+?)\] Running \d+/\d+: (/datum/unit_test/[^\s]+)$")
LOG_TIME = re.compile(r"^\[(.+?)\]")
RAW_TIME = re.compile(r"^(\d{2}:\d{2}:\d{2})(?:\s|$)")
TEST_OWNER = re.compile(r"/datum/unit_test/[A-Za-z0-9_/]+")


def read_test_intervals(directory):
    """Closed log intervals are timing evidence, never event ownership."""
    file = directory / "tests.log"
    intervals, pending = [], None
    if file.exists():
        with file.open(encoding="utf-8-sig", errors="replace") as stream:
            for line in stream:
                boundary = TEST_BOUNDARY.match(line.rstrip())
                closing = LOG_TIME.match(line) if "Unit-test suite finished:" in line else None
                if not boundary and not closing:
                    continue
                try:
                    at = datetime.fromisoformat((boundary or closing).group(1))
                except ValueError:
                    continue
                if at.tzinfo is not None:
                    continue
                if pending and at > pending[0]:
                    intervals.append((pending[0], at, pending[1]))
                pending = (at, boundary.group(2)) if boundary else None
    intervals.sort()
    return intervals, pending


def temporal_candidates(timestamp, intervals):
    """Conservative clock overlap; dates/timezones are never guessed or shifted."""
    starts, entries, dates = intervals
    try:
        if re.fullmatch(r"\d{2}:\d{2}:\d{2}", timestamp):
            clock = datetime.strptime(timestamp, "%H:%M:%S").time()
            windows = [(datetime.combine(day, clock), timedelta(seconds=1)) for day in dates]
        else:
            at = datetime.fromisoformat(timestamp)
            # Logs without a validated timezone conversion cannot be aligned.
            if at.tzinfo is not None:
                return ()
            windows = [(at, timedelta(milliseconds=1))]
    except (ValueError, TypeError):
        return ()
    candidates = set()
    for at, width in windows:
        index = max(0, bisect_right(starts, at) - 1)
        while index < len(entries) and entries[index][0] < at + width:
            start, end, name = entries[index]
            if end > at:
                candidates.add(name)
            index += 1
    return tuple(sorted(candidates))


def event_rows(counts, examples=None):
    return [{"message": key[0], "procedure": key[1], "source": key[2],
             "line": key[3], "count": count,
             "raw_message_examples_first16": sorted((examples or {}).get(key, ()))}
            for key, count in sorted(counts.items(), key=lambda item: str(item[0]))]


def explicit_owner(record):
    supplied = [record[field] for field in ("test", "test_path")
                if record.get(field) is not None]
    if not supplied:
        return None, "no-explicit-owner"
    if any(not isinstance(owner, str) for owner in supplied):
        return None, "invalid-explicit-owner"
    if len(set(supplied)) != 1:
        return None, "conflicting-explicit-owners"
    owner = supplied[0]
    return (owner, None) if TEST_OWNER.fullmatch(owner) else (None, "non-test-explicit-owner")

def read_runtime(directory, raw_only=False, attribution=None):
    structured = directory / "runtime.log.json"
    raw = next((directory/name for name in ("runtime-errors.log", "stderr.log", "stderr", "stdout.log", "stdout") if (directory/name).exists()), directory/"runtime-errors.log")
    counts, variants = Counter(), defaultdict(set)
    owned, unassigned, temporal = defaultdict(Counter), defaultdict(Counter), defaultdict(Counter)
    owned_examples, unassigned_examples = defaultdict(dict), defaultdict(dict)
    closed, pending = read_test_intervals(directory) if attribution is not None else ([], None)
    interval_index = ([row[0] for row in closed], closed,
                      sorted({day for start, end, _ in closed for day in (start.date(), end.date())}))
    coverage = {"structured_events": 0, "raw_events": 0, "unlocated_procedure": 0,
                "unlocated_source": 0, "ownership_unavailable": 0,
                "non_test_owned": 0, "test_owned": 0, "parse_errors": 0,
                "ignored_structured_records": 0}
    chosen = raw if raw_only and raw.exists() else None if raw_only else structured if structured.exists() else raw if raw.exists() else None
    if chosen is None:
        return counts, variants, {**coverage, "mode": "missing", "complete": False}
    mode = "structured" if chosen == structured else "raw"
    with chosen.open(encoding="utf-8-sig", errors="replace") as stream:
        for number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            if mode == "structured":
                try:
                    record = json.loads(line)
                except (ValueError, TypeError):
                    coverage["parse_errors"] += 1
                    continue
                message = record.get("msg", "") if isinstance(record, dict) else ""
                if not isinstance(message, str) or "runtime error:" not in message.lower():
                    coverage["ignored_structured_records"] += 1
                    continue
                key = identity(message)
                coverage["structured_events"] += 1
                # Existing recorder has no reliable per-event current-test field.
                # Never infer ownership from a procedure in the call stack.
                owner, reason = explicit_owner(record)
                if owner is not None:
                    coverage["test_owned"] += 1
                elif reason == "non-test-explicit-owner":
                    coverage["non_test_owned"] += 1
                else:
                    coverage["ownership_unavailable"] += 1
                timestamp = record.get("ts")
            else:
                match = RAW.match(line.rstrip())
                unlocated = RAW_UNLOCATED.match(line.rstrip()) if not match else None
                if not match and not unlocated:
                    coverage["parse_errors"] += 1
                    continue
                if match:
                    source, location, message = match.groups()
                    key = identity(message, source.replace("\\", "/"), int(location))
                else:
                    message = unlocated.group(1)
                    # Blank origins are admitted as errors, never assigned to a
                    # nearby test, a known procedure, or a located raw event.
                    key = identity(message)
                coverage["raw_events"] += 1
                coverage["ownership_unavailable"] += 1
                owner, reason = None, "raw-channel-has-no-explicit-owner"
                stamp = RAW_TIME.match(line)
                timestamp = stamp.group(1) if stamp else None
            if attribution is not None:
                if owner is not None:
                    owned[owner][key] += 1
                    examples = owned_examples[owner].setdefault(key, set())
                else:
                    unassigned[reason][key] += 1
                    examples = unassigned_examples[reason].setdefault(key, set())
                if len(examples) < 16:
                    examples.add(message.split("\n", 1)[0][:4096])
                candidates = temporal_candidates(timestamp, interval_index) if isinstance(timestamp, str) else ()
                if candidates:
                    temporal[candidates][key] += 1
            counts[key] += 1
            # Keep bounded diagnostic examples; full original event text stays
            # in the immutable source log identified in coverage.
            if len(variants[key]) < 16:
                variants[key].add(message.split("\n", 1)[0][:4096])
            coverage["unlocated_procedure"] += key[1] is None
            coverage["unlocated_source"] += key[2] is None or key[3] is None
    coverage.update(mode=mode, source=str(chosen), raw_channel_not_added=mode == "structured",
                    complete=mode == "structured" and not coverage["parse_errors"]
                    and not coverage["unlocated_procedure"] and not coverage["unlocated_source"])
    if attribution is not None:
        attribution.update(
            source_file=str(chosen),
            attributed_tests={test: event_rows(events, owned_examples[test]) for test, events in sorted(owned.items())},
            unassigned={reason: event_rows(events, unassigned_examples[reason]) for reason, events in sorted(unassigned.items())},
            temporal_interval_associations=[{"candidate_tests": list(names), "events": event_rows(events)}
                                           for names, events in sorted(temporal.items())],
            closed_test_intervals=[{"test": name, "start": start.isoformat(), "end": end.isoformat()}
                                   for start, end, name in closed],
            open_interval_test=pending[1] if pending else None,
            temporal_policy="clock overlap only, never ownership; second-resolution raw times may overlap adjacent tests; raw date is unknown; no timezone conversion",
            event_total=sum(counts.values()),
            attributed_total=sum(sum(events.values()) for events in owned.values()),
            unassigned_total=sum(sum(events.values()) for events in unassigned.values()))
    return counts, variants, coverage


def load_run(label, directory):
    directory = Path(directory).resolve()
    file = directory / "unit_tests.json"
    tests = json.loads(file.read_text(encoding="utf-8-sig")) if file.exists() else {}
    if not isinstance(tests, dict):
        raise ValueError(f"Expected test object: {file}")
    for name, result in tests.items():
        if not isinstance(result, dict) or type(result.get("status")) is not int or result.get("status") not in (0, 1, 2):
            raise ValueError(f"Invalid test result: {file}: {name}")
    attribution, raw_attribution = {}, {}
    counts, variants, coverage = read_runtime(directory, attribution=attribution)
    raw_counts, _, raw_coverage = read_runtime(directory, raw_only=True, attribution=raw_attribution)
    # Independent channels are never summed. Historical raw files contain many
    # events missing from structured JSONL, so structured preference is NOT a
    # completeness assertion or evidence that every raw line is a mirror.
    structured_located = Counter()
    for (message, proc, source, line), count in counts.items():
        structured_located[(message, source, line)] += count
    raw_located = Counter()
    for (message, proc, source, line), count in raw_counts.items():
        raw_located[(message, source, line)] += count
    comparable = coverage["mode"] == "structured" and raw_coverage["mode"] != "missing"
    coverage["selected_channel_located_complete"] = coverage["complete"]
    coverage["raw_reconciliation"] = "normalized location/message multiset only" if comparable else "unavailable"
    coverage["raw_normalized_multiset_matches"] = structured_located == raw_located if comparable else None
    coverage["complete"] = False  # no proven cross-channel event identity/complete recorder inventory
    raw_audit = {"coverage":raw_coverage,"event_total":sum(raw_counts.values()),
                 "event_attribution": raw_attribution,
                 "identities":[{"message":key[0],"source":key[2],"line":key[3],"count":count}
                               for key,count in sorted(raw_counts.items(),key=lambda item:str(item[0]))],
                 "unmatched_raw_normalized_count":sum((raw_located-structured_located).values()) if comparable else None,
                 "unmatched_structured_normalized_count":sum((structured_located-raw_located).values()) if comparable else None}
    return {"label": label, "directory": str(directory), "tests": tests,"raw_audit":raw_audit,
            "event_attribution": attribution,
            "test_file_present": file.exists(), "test_runtime_total": sum(
                result.get("runtimes", 0) or 0 for result in tests.values()),
            "coverage": coverage, "counts": counts, "variants": variants}


def compare(runs):
    groups = defaultdict(list)
    for run in runs:
        compiler, separator, repetition = run["label"].rpartition(":")
        if separator and repetition in ("1", "2", "3"):
            groups[compiler].append(run)
    all_keys = set().union(*(run["counts"] for run in runs)) if runs else set()
    ordered = sorted(all_keys, key=lambda key: tuple("" if part is None else str(part) for part in key))
    identities = []
    for key in ordered:
        distributions = {compiler: [run["counts"][key] for run in sorted(group, key=lambda r:r["label"])]
                         for compiler, group in groups.items()}
        complete_repeats = len(groups) >= 2 and all(len(group) == 3 and all(run["coverage"].get("selected_channel_located_complete",False) for run in group) for group in groups.values())
        nondeterministic = any(len(set(values)) > 1 for values in distributions.values())
        distinct = len({tuple(sorted(values)) for values in distributions.values()}) > 1
        identities.append({"message": key[0], "procedure": key[1], "source": key[2], "line": key[3],
                           "counts": {run["label"]:run["counts"][key] for run in runs},
                           "distributions": distributions, "nondeterministic": nondeterministic,
                           "selected_channel_deterministic_difference": complete_repeats and not nondeterministic and distinct,
                           "selected_channel_observed_distribution_difference": complete_repeats and nondeterministic and distinct,
                           "raw_message_examples_first16_per_run": sorted(set().union(*(run["variants"].get(key,set()) for run in runs)))})
    test_names = sorted(set().union(*(run["tests"] for run in runs))) if runs else []
    test_distributions = []
    for name in test_names:
        values = {compiler:[run["tests"].get(name, {}).get("status") for run in sorted(group,key=lambda r:r["label"])] for compiler,group in groups.items()}
        messages = {compiler:[normalize(str(run["tests"].get(name, {}).get("message", ""))) for run in sorted(group,key=lambda r:r["label"])] for compiler,group in groups.items()}
        runtimes = {compiler:[run["tests"].get(name, {}).get("runtimes") for run in sorted(group,key=lambda r:r["label"])] for compiler,group in groups.items()}
        observations = {compiler:list(zip(values[compiler],messages[compiler],runtimes[compiler])) for compiler in groups}
        unstable = any(len(set(value))>1 for value in observations.values())
        missing = any(None in value for value in values.values())
        repeated = len(groups)>=2 and all(len(group)==3 for group in groups.values())
        test_distributions.append({"test":name,"statuses":values,"normalized_messages":messages,
                                   "runtime_counts":runtimes,"nondeterministic":unstable,
                                   "deterministic_difference":repeated and not missing and not unstable and len({tuple(value) for value in observations.values()})>1,
                                   "missing":missing})
    complete = bool(groups) and len(groups)>=2 and all(len(group)==3 for group in groups.values()) and all(run["coverage"]["complete"] and run["test_file_present"] for group in groups.values() for run in group) and not any(row["missing"] for row in test_distributions)
    return {"comparison_coverage_complete":complete,
            "equality_claim":False, # finite observations/heuristic normalization do not establish equivalence
            "normalization_policy":"first runtime message line; references/timestamps/numbers replaced; procedure and source/line retained; bounded original first-line examples; complete raw events preserved in source logs",
            "ownership_policy":"only consistent explicit test/test_path attributes ownership; unassigned events retained; temporal interval overlap is separate and never ownership; recorder totals are not added to event totals",
            "repeat_policy":"exactly :1,:2,:3 per compiler; count/presence variability tracked; 3 observations do not prove statistical distribution equivalence",
            "runs":[{k:v for k,v in run.items() if k not in ("counts","variants")} for run in runs],
            "identities":identities,"test_distributions":test_distributions}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run",action="append",required=True,metavar="LABEL=DIRECTORY")
    parser.add_argument("--output",required=True)
    args=parser.parse_args()
    runs=[]; seen=set()
    for supplied in args.run:
        label, separator, directory=supplied.partition("=")
        if not separator or not label or label in seen:
            parser.error("Each run needs a unique LABEL=DIRECTORY")
        seen.add(label);runs.append(load_run(label,directory))
    output=Path(args.output);output.parent.mkdir(parents=True,exist_ok=True)
    with output.open("w",encoding="utf-8") as stream:
        json.dump(compare(runs),stream,indent=2,ensure_ascii=False);stream.write("\n")


if __name__ == "__main__":
    main()
