"""Exact independent comparison of base-vars semantic supplement observations.

Build the old example with dq-analyze --features unified-oracle, and separately
build dm-analysis's native_base_vars example. This tool runs no builds. A match
covers ordered declaration/record rows only, not final lint admission or parity.
"""
import argparse
from collections import Counter
from itertools import zip_longest
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from fixture_observations import fixture_inputs, require_unchanged, observation_digest

FIELDS = {
    "base_var_declaration": frozenset(("row", "rel", "line", "owner", "name", "vtype", "base", "list_init")),
    "record_proc": frozenset(("row", "rel", "line", "name")),
}

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key {key!r}")
        result[key] = value
    return result

def rows(text, label):
    result = []
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        try:
            row = json.loads(line, object_pairs_hook=unique_object)
            if not isinstance(row, dict) or row.get("row") not in FIELDS or row.keys() != FIELDS[row["row"]]:
                raise ValueError("unknown row type or unexpected/missing supplement fields")
            if any(not isinstance(row[key], str) or not row[key] for key in ("rel", "name")):
                raise ValueError("path/name must be nonempty strings")
            if type(row["line"]) is not int or row["line"] < 1:
                raise ValueError("line must be a positive integer")
            if row["row"] == "base_var_declaration":
                if not isinstance(row["owner"], str) or not row["owner"].startswith("/") or not isinstance(row["vtype"], str):
                    raise ValueError("invalid owner/type text")
                if type(row["base"]) is not bool or type(row["list_init"]) is not bool:
                    raise ValueError("base/list_init must be booleans")
            result.append(row)
        except (ValueError, TypeError) as error:
            raise ValueError(f"{label}:{number}: {error}") from error
    return result

def compare(reference, native, *, allow_empty_reference=False):
    if not reference and not allow_empty_reference:
        raise ValueError("empty reference cannot certify a seeded supplement fixture")
    key = lambda row: json.dumps(row, sort_keys=True, separators=(",", ":"))
    left, right = Counter(map(key, reference)), Counter(map(key, native))
    differences = [{"row":json.loads(row), "reference_count":left[row], "native_count":right[row]}
                   for row in sorted(left.keys() | right.keys()) if left[row] != right[row]]
    order = [{"index":index, "reference":old, "native":new}
             for index, (old, new) in enumerate(zip_longest(reference, native)) if old != new]
    return {"scope":"base-vars-semantic-supplement/explicit-dme-fixture", "full_analysis_parity":False,
            "matched":not differences and not order, "reference_rows":len(reference), "native_rows":len(native),
            "differences":differences, "order_difference_count":len(order), "first_order_differences":order[:16]}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def observe(executable, captured, fixture, timeout, label):
    if captured is not None:
        return rows(captured.read_text(encoding="utf-8-sig"), label), {"jsonl":str(captured.resolve()), "sha256":digest(captured)}
    if fixture is None or not (fixture / "deepquarry.dme").is_file():
        raise ValueError("executable observations require --fixture with explicit deepquarry.dme")
    executable = executable.resolve()
    before = digest(executable)
    result = subprocess.run([str(executable), str(fixture.resolve())], capture_output=True, encoding="utf-8", timeout=timeout, check=False)
    if result.returncode or digest(executable) != before:
        raise ValueError(f"{label} observation failed/changed executable: exit {result.returncode}\n{result.stderr}")
    return rows(result.stdout, label), {"executable":str(executable), "sha256":before}

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    ref = parser.add_mutually_exclusive_group(required=True)
    ref.add_argument("--reference", type=Path)
    ref.add_argument("--reference-jsonl", type=Path)
    new = parser.add_mutually_exclusive_group(required=True)
    new.add_argument("--native", type=Path)
    new.add_argument("--native-jsonl", type=Path)
    parser.add_argument("--fixture", type=Path)
    parser.add_argument("--timeout", type=int, default=60)
    parser.add_argument("--allow-empty-reference", action="store_true")
    args = parser.parse_args(argv)
    if not 1 <= args.timeout <= 300:
        parser.error("--timeout must be between 1 and 300 seconds")
    try:
        inputs = fixture_inputs(args.fixture) if args.fixture is not None else None
        reference, old_source = observe(args.reference, args.reference_jsonl, args.fixture, args.timeout, "reference")
        native, new_source = observe(args.native, args.native_jsonl, args.fixture, args.timeout, "native")
        if inputs is not None:
            require_unchanged(inputs, fixture_inputs(args.fixture))
        report = compare(reference, native, allow_empty_reference=args.allow_empty_reference)
        report.update(reference_source=old_source, native_source=new_source)
        if inputs is not None:
            report.update(fixture=str(args.fixture.resolve()), fixture_inputs_sha256=observation_digest(inputs), fixture_input_files=len(inputs))
        print(json.dumps(report, indent=2, ensure_ascii=False))
        return 0 if report["matched"] else 1
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"base-vars supplement comparison failed: {error}", file=sys.stderr)
        return 2

if __name__ == "__main__":
    raise SystemExit(main())
