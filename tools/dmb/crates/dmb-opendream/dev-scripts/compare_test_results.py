"""Compare fresh native and Rust test JSON, including partitioned suite runs.

No log inference: missing entries remain unrun. Original result objects and all
duplicate observations are preserved in the JSON report.
"""
import argparse
import csv
import json
import re
from collections import Counter
from pathlib import Path

STATUS = {0: "pass", 1: "fail", 2: "skip"}


def names(path):
    return set(Path(path).read_text(encoding="utf-8-sig").split()) if path else set()


def load(paths):
    observations = {}
    for supplied in paths:
        path = Path(supplied).resolve()
        files = sorted(path.rglob("unit_tests.json")) if path.is_dir() else [path]
        if not files:
            raise ValueError(f"No result files found: {path}")
        for file in files:
            document = json.loads(file.read_text(encoding="utf-8-sig"))
            if not isinstance(document, dict):
                raise ValueError(f"Expected test-path object: {file}")
            for name, result in document.items():
                if not isinstance(result, dict) or type(result.get("status")) is not int or result["status"] not in STATUS:
                    raise ValueError(f"Invalid status: {file}: {name}")
                observations.setdefault(name, []).append({"source": str(file), "result": result})
    return observations


def summarize(observations):
    if not observations:
        return {"status": "unrun", "runtimes": None, "message": "", "failure_kind": "none"}
    statuses = {item["result"]["status"] for item in observations}
    status = STATUS[next(iter(statuses))] if len(statuses) == 1 else "conflict"
    messages = list(dict.fromkeys(str(item["result"].get("message", "")) for item in observations))
    message = "\n--- duplicate observation ---\n".join(messages)
    failure_kind = "none"
    if status in ("fail", "conflict"):
        runtime = bool(re.search(r"runtime error|unhandled exception|runtime encountered", message, re.I))
        assertion = bool(re.search(r"assertion failed|expected .+ to ", message, re.I))
        failure_kind = "mixed" if runtime and assertion else "runtime" if runtime else "timeout" if "timed out" in message.lower() else "assertion" if assertion else "other"
    return {"status": status, "runtimes": sum(item["result"].get("runtimes", 0) or 0 for item in observations),
            "message": message, "failure_kind": failure_kind, "observations": observations}


def compare(native, rust, expected, abstract):
    rows = []
    for name in sorted(set(native) | set(rust) | expected | abstract):
        left, right = summarize(native.get(name)), summarize(rust.get(name))
        a, b = left["status"], right["status"]
        if "conflict" in (a, b):
            category = "duplicate_status_conflict"
        elif "unrun" in (a, b):
            category = "intentional_exclusion" if name in abstract and a == b == "unrun" else "unrun"
        elif a == b:
            category = "both_" + a
        elif b == "fail":
            category = "rust_only_fail"
        elif a == "fail":
            category = "native_only_fail"
        else:
            category = "skip_difference"
        rows.append({"test": name, "category": category, "intentional_exclusion": name in abstract,
                     "same_message": left["message"] == right["message"], "native": left, "rust": right})
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", nargs="+", required=True, help="Fresh result JSON files or a dedicated run directory")
    parser.add_argument("--rust", nargs="+", required=True)
    parser.add_argument("--expected", help="One expected test type per line")
    parser.add_argument("--abstract", "--exclusions", dest="abstract", help="Explicitly identified abstract/focus-only excluded test types, one per line")
    parser.add_argument("--output", required=True, help="Output filename prefix")
    args = parser.parse_args()
    expected, abstract = names(args.expected), names(args.abstract)
    rows = compare(load(args.native), load(args.rust), expected, abstract)
    counts = Counter(row["category"] for row in rows)
    sides = {side: dict(Counter(row[side]["status"] for row in rows)) for side in ("native", "rust")}
    runtime_counts = {side: {"errors": sum(row[side]["runtimes"] or 0 for row in rows),
                             "tests_with_errors": sum(bool(row[side]["runtimes"]) for row in rows),
                             "passing_tests_with_errors": sum(row[side]["status"] == "pass" and bool(row[side]["runtimes"]) for row in rows)}
                      for side in ("native", "rust")}
    complete = bool(expected) and not counts["unrun"] and not counts["duplicate_status_conflict"]
    report = {"inputs": vars(args), "coverage_complete": complete, "expected_types": len(expected),
              "counts": dict(counts), "statuses": sides, "runtime_counts": runtime_counts, "tests": rows}
    output = Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.with_suffix(".json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    with output.with_suffix(".csv").open("w", newline="", encoding="utf-8-sig") as stream:
        fields = ["test", "category", "native_status", "rust_status", "same_message", "native_failure_kind", "rust_failure_kind", "native_runtimes", "rust_runtimes", "native_message", "rust_message"]
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            item = {key: row[key] for key in ("test", "category", "same_message")}
            for side in ("native", "rust"):
                item.update({f"{side}_{key}": row[side][key] for key in ("status", "failure_kind", "runtimes", "message")})
            writer.writerow(item)
    lines = ["# Full suite compiler comparison", "", f"Coverage complete: **{complete}**. Expected types: {len(expected)}.", "",
             "| Result | BYOND | Rust |", "|---|---:|---:|"]
    for status in ("pass", "fail", "skip", "unrun", "conflict"):
        lines.append(f"| {status} | {sides['native'].get(status, 0)} | {sides['rust'].get(status, 0)} |")
    lines += ["", "| Comparison | Count |", "|---|---:|"]
    for category, count in sorted(counts.items()):
        lines.append(f"| {category} | {count} |")
    lines += ["", "| Runtime errors | BYOND | Rust |", "|---|---:|---:|"]
    for metric in ("errors", "tests_with_errors", "passing_tests_with_errors"):
        lines.append(f"| {metric} | {runtime_counts['native'][metric]} | {runtime_counts['rust'][metric]} |")
    lines += ["", "Runtime counts are reported independently of assertion status. A passing assertion with runtime errors is not a clean runtime pass.",
              "Missing JSON entries are unrun unless explicitly listed as intentional exclusions. Batched runs preserve each batch's game state and are not equivalent to one continuous suite run.",
              "Failure classification is a message heuristic; exact original messages and result objects are preserved in JSON/CSV.", "", "## Failure differences", ""]
    for row in rows:
        if row["category"] in ("rust_only_fail", "native_only_fail", "duplicate_status_conflict") or (row["category"] == "both_fail" and not row["same_message"]):
            lines.append(f"- `{row['test']}`: {row['category']}; exact messages in CSV/JSON.")
    output.with_suffix(".md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"report": str(output.with_suffix('.md')), "counts": dict(counts), "statuses": sides, "coverage_complete": complete}))


if __name__ == "__main__":
    main()
