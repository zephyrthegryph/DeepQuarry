"""Compare captured compiler, runtime and unit-test results without running DM.

Runtime identities ignore timestamps and line relocation, retain procedure/source
identities and exact messages, and report counts separately. Whole-run captures do
not establish per-test attribution or execution equivalence. Large runtime logs
are streamed; no complete log or call-stack collection is retained in memory.
"""
import argparse
import io
import json
import re
from collections import Counter
from pathlib import Path


def lines(path):
    with Path(path).open("rb") as raw:
        prefix = raw.read(4)
        raw.seek(0)
        encoding = "utf-16" if prefix.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig"
        with io.TextIOWrapper(raw, encoding=encoding, errors="replace") as text:
            yield from text


def source_path(value):
    value = value.replace("\\", "/")
    for root in ("code/", "maps/", "interface/", "fixtures/"):
        at = value.find(root)
        if at >= 0:
            return value[at:]
    return value


def runtime_errors(path):
    records = {}
    pending = None

    def flush():
        if pending is None:
            return
        identity = pending.get("procedure") or pending.get("source") or "<unlocated>"
        key = (identity, pending["message"])
        item = records.setdefault(key, {"identity": identity, "message": pending["message"],
                                       "count": 0, "sources": set(), "lines": set()})
        item["count"] += 1
        if pending.get("source"):
            item["sources"].add(pending["source"])
        if pending.get("line") is not None:
            item["lines"].add(pending["line"])

    for text in lines(path):
        inline = re.search(r"Runtime in (.+?\.dm),(\d+): (.*)", text)
        header = re.match(r"^\s*\d{2}:\d{2}:\d{2}(?:\.\d+)?\s+(.*)", text)
        if inline or header:
            flush()
            if inline:
                source, line, message = inline.groups()
                pending = {"source": source_path(source), "line": int(line), "message": message.rstrip()}
            else:
                tail = header[1].strip()
                located = re.match(r"(.+?\.dm)[,:](\d+)\s*:?\s*(.*)", tail)
                if located:
                    source, line, message = located.groups()
                    pending = {"source": source_path(source), "line": int(line), "message": message.rstrip()}
                else:
                    pending = {"message": tail.removeprefix(":").strip()}
        elif pending is not None:
            proc = re.match(r"\s*proc name: .*\((/[^)]+)\)\s*$", text)
            source = re.match(r"\s*source file: (.+?\.dm),(\d+)\s*$", text)
            if proc:
                pending["procedure"] = proc[1]
            elif source:
                pending.update(source=source_path(source[1]), line=int(source[2]))
    flush()
    for item in records.values():
        item["sources"] = sorted(item["sources"])
        item["lines"] = sorted(item["lines"])
    return records


def compiler_errors(path):
    records = {}
    for text in lines(path):
        rust = re.match(r"(?:dm-compile|dm-compiled):\s*(.*)", text.strip())
        diagnostic = rust[1] if rust else text.strip()
        native = re.match(r"(.+?\.(?:dm|dme)):(\d+):error(?:\s*\(([^)]+)\))?:\s*(.*)", diagnostic)
        entries = []
        if native:
            source, line, code, message = native.groups()
            entries.append({"source": source_path(source), "line": int(line), "code": code or "", "message": message})
        elif rust:
            # These prefixes are fatal CLI errors, never timing traces or success.
            entries.append({"source": "", "line": None, "code": "", "message": rust[1]})
        elif text.lstrip().startswith("{"):
            try:
                data = json.loads(text)
                for diagnostic in data.get("diagnostics", []):
                    if diagnostic.get("severity") == "error":
                        entries.append({"source": source_path(diagnostic.get("source", "")),
                                        "line": diagnostic.get("line"), "code": diagnostic.get("code", ""),
                                        "message": diagnostic["message"]})
            except (ValueError, TypeError, KeyError, AttributeError):
                pass
        for entry in entries:
            key = (entry["source"], entry["code"], entry["message"])
            item = records.setdefault(key, {**entry, "count": 0, "lines": set()})
            item["count"] += 1
            if entry["line"] is not None:
                item["lines"].add(entry["line"])
    for entry in records.values():
        entry.pop("line")
        entry["lines"] = sorted(entry["lines"])
    return records


def compare_records(expected, actual):
    shared = expected.keys() & actual.keys()
    return {"expected_only": [expected[key] for key in sorted(expected.keys() - actual.keys())],
            "actual_only": [actual[key] for key in sorted(actual.keys() - expected.keys())],
            "shared": [{"expected": expected[key], "actual": actual[key],
                        "count_delta": actual[key]["count"] - expected[key]["count"]} for key in sorted(shared)],
            "expected_count": sum(item["count"] for item in expected.values()),
            "actual_count": sum(item["count"] for item in actual.values())}


def compare_runtime(expected, actual):
    """Never infer a source/procedure from an unlocated message-only capture."""
    expected_located = {key: item for key, item in expected.items() if key[0] != "<unlocated>"}
    actual_located = {key: item for key, item in actual.items() if key[0] != "<unlocated>"}
    result = compare_records(expected_located, actual_located)
    result["unattributed_expected"] = [item for key, item in sorted(expected.items()) if key[0] == "<unlocated>"]
    result["unattributed_actual"] = [item for key, item in sorted(actual.items()) if key[0] == "<unlocated>"]
    result["attribution_complete"] = not (result["unattributed_expected"] or result["unattributed_actual"])
    # A missing location can correspond to any procedure with this message. Keep
    # ambiguous candidates out of proven new procedure/source signatures.
    baseline_unknown = {item["message"] for item in result["unattributed_expected"]}
    result["ambiguous_actual"] = [item for item in result["actual_only"] if item["message"] in baseline_unknown]
    result["actual_only"] = [item for item in result["actual_only"] if item["message"] not in baseline_unknown]
    left, right = Counter(), Counter()
    for item in expected.values(): left[item["message"]] += item["count"]
    for item in actual.values(): right[item["message"]] += item["count"]
    result["new_messages"] = [message for message in sorted(right.keys() - left.keys())]
    result["message_totals"] = [{"message": message, "expected": left[message], "actual": right[message]}
                                for message in sorted(left.keys() | right.keys())]
    result["expected_count"] = sum(left.values())
    result["actual_count"] = sum(right.values())
    result["attribution"] = "whole-run capture; per-test attribution requires the separate result JSON"
    return result


def test_results(path):
    result = json.loads("".join(lines(path)))
    if not isinstance(result, dict) or not result:
        raise ValueError(f"No completed test results in {path}")
    for name, item in result.items():
        if not isinstance(item, dict) or item.get("status") not in (0, 1, 2):
            raise ValueError(f"Unknown status for {name}")
    return result


def compare_tests(expected, actual):
    shared = expected.keys() & actual.keys()
    changes = [{"test": name, "expected": expected[name], "actual": actual[name]} for name in sorted(shared)
               if expected[name]["status"] != actual[name]["status"]]
    regressions = [item for item in changes if item["actual"]["status"] == 1 and item["expected"]["status"] != 1]
    return {"expected_statuses": dict(Counter(item["status"] for item in expected.values())),
            "actual_statuses": dict(Counter(item["status"] for item in actual.values())),
            "missing": sorted(expected.keys() - actual.keys()), "extra": sorted(actual.keys() - expected.keys()),
            "status_changes": changes, "new_failures": regressions,
            "shared_failures": [name for name in sorted(shared) if expected[name]["status"] == actual[name]["status"] == 1],
            "runtime_count_changes": [{"test": name, "expected": expected[name].get("runtimes", 0),
                                       "actual": actual[name].get("runtimes", 0)} for name in sorted(shared)
                                      if expected[name].get("runtimes", 0) != actual[name].get("runtimes", 0)]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for kind in ("compile", "runtime", "tests"):
        parser.add_argument(f"--expected-{kind}")
        parser.add_argument(f"--actual-{kind}")
    parser.add_argument("--expected-compile-exit", type=int)
    parser.add_argument("--actual-compile-exit", type=int)
    parser.add_argument("--fail-on-count-increase", action="store_true")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    report = {"schema": 1, "execution_equivalence_verified": False, "passed": True}
    selected = 0
    for kind, loader in (("compile", compiler_errors), ("runtime", runtime_errors), ("tests", test_results)):
        a, b = getattr(args, f"expected_{kind}"), getattr(args, f"actual_{kind}")
        if bool(a) != bool(b):
            parser.error(f"Both --expected-{kind} and --actual-{kind} are required")
        if not a:
            continue
        selected += 1
        if kind == "compile" and (args.expected_compile_exit is None or args.actual_compile_exit is None):
            parser.error("Compile gates require both captured process exit codes")
        left, right = loader(a), loader(b)
        result = compare_tests(left, right) if kind == "tests" else compare_runtime(left, right) if kind == "runtime" else compare_records(left, right)
        if kind == "compile":
            result.update(expected_exit=args.expected_compile_exit, actual_exit=args.actual_compile_exit)
            failed = bool(result["actual_only"] or args.actual_compile_exit != args.expected_compile_exit)
            result["both_clean"] = args.expected_compile_exit == args.actual_compile_exit == 0 and not result["expected_count"] and not result["actual_count"]
        elif kind == "runtime":
            failed = bool(result["actual_only"] or result["new_messages"] or args.fail_on_count_increase and
                          any(item["actual"] > item["expected"] for item in result["message_totals"]))
        else:
            failed = bool(result["missing"] or result["extra"] or result["new_failures"])
            if args.fail_on_count_increase:
                failed |= any(item["actual"] > item["expected"] for item in result["runtime_count_changes"])
        result["regression"] = failed
        report[kind] = result
        report["passed"] &= not failed and result.get("attribution_complete", True)
    if not selected:
        parser.error("At least one captured result pair is required")
    Path(args.output).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "sections": selected, "report": args.output}))
    return not report["passed"]


if __name__ == "__main__":
    raise SystemExit(main())
