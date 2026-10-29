"""Exact independent comparison of base_vars/records_data_only Site rows.

This runs no builds. The reference executes the unchanged legacy lint. The
native fixture receives resolved prefixes from this Python TOML host and checks
that its captured config bytes equal that envelope. This proves one named rule
on an explicit-DME fixture, not full Analyze/config-parser/workspace parity.
"""
import argparse
from collections import Counter
from itertools import zip_longest
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tomllib

from fixture_observations import fixture_inputs, observation_digest, require_unchanged

FIELDS = frozenset(("rule", "rel", "line", "msg", "key", "ident"))


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
            if not isinstance(row, dict) or row.keys() != FIELDS:
                raise ValueError("unexpected/missing Site fields")
            if row["rule"] != "records_data_only":
                raise ValueError("foreign rule cannot certify this named-rule fixture")
            if any(not isinstance(row[key], str) for key in ("rel", "msg", "key", "ident")) or not row["rel"]:
                raise ValueError("Site text fields must be strings, with a nonempty path")
            if type(row["line"]) is not int or row["line"] < 1:
                raise ValueError("line must be a positive integer")
            result.append(row)
        except (ValueError, TypeError) as error:
            raise ValueError(f"{label}:{number}: {error}") from error
    return result


def compare(reference, native, *, allow_empty_reference=False):
    if not reference and not allow_empty_reference:
        raise ValueError("empty reference cannot certify a seeded named-rule fixture")
    key = lambda row: json.dumps(row, sort_keys=True, separators=(",", ":"))
    left, right = Counter(map(key, reference)), Counter(map(key, native))
    differences = [{"site": json.loads(site), "reference_count": left[site], "native_count": right[site]}
                   for site in sorted(left.keys() | right.keys()) if left[site] != right[site]]
    order = [{"index": index, "reference": old, "native": new}
             for index, (old, new) in enumerate(zip_longest(reference, native)) if old != new]
    return {"scope": "base_vars/records_data_only/explicit-dme-fixture", "full_analysis_parity": False,
            "full_config_parser_parity": False, "matched": not differences and not order,
            "reference_sites": len(reference), "native_sites": len(native), "differences": differences,
            "order_difference_count": len(order), "first_order_differences": order[:16]}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def configuration(fixture):
    path = fixture / "tools/ci/lint_scopes.toml"
    raw = path.read_bytes().decode("utf-8")
    value = tomllib.loads(raw)
    # Exact Scopes::strings behavior: absent/non-array => empty; ignore nontext
    # array members. Other scope fields remain the old engine's responsibility.
    section = value.get("lint", {}).get("base_vars", {})
    setting = section.get("lists", {}).get("record_accessor_prefixes", [])
    prefixes = [item for item in setting if isinstance(item, str)] if isinstance(setting, list) else []
    return {"raw": raw, "accessor_prefixes": prefixes}


def observe(executable, captured, fixture, timeout, label):
    if captured is not None:
        return rows(captured.read_text(encoding="utf-8-sig"), label), {"jsonl": str(captured.resolve()), "sha256": digest(captured)}
    if fixture is None or not (fixture / "deepquarry.dme").is_file():
        raise ValueError("executable observations require an explicit-DME --fixture")
    executable = executable.resolve()
    arguments = [str(executable), str(fixture.resolve())]
    if label == "native":
        arguments.append(json.dumps(configuration(fixture), separators=(",", ":")))
    before = digest(executable)
    result = subprocess.run(arguments, capture_output=True, encoding="utf-8", timeout=timeout, check=False)
    if result.returncode or digest(executable) != before:
        raise ValueError(f"{label} observation failed/changed executable: exit {result.returncode}\n{result.stderr}")
    return rows(result.stdout, label), {"executable": str(executable), "sha256": before}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    reference = parser.add_mutually_exclusive_group(required=True)
    reference.add_argument("--reference", type=Path)
    reference.add_argument("--reference-jsonl", type=Path)
    native = parser.add_mutually_exclusive_group(required=True)
    native.add_argument("--native", type=Path)
    native.add_argument("--native-jsonl", type=Path)
    parser.add_argument("--fixture", type=Path)
    parser.add_argument("--timeout", type=int, default=60)
    parser.add_argument("--allow-empty-reference", action="store_true")
    args = parser.parse_args(argv)
    if not 1 <= args.timeout <= 300:
        parser.error("--timeout must be between 1 and 300 seconds")
    try:
        inputs = fixture_inputs(args.fixture) if args.fixture is not None else None
        old, old_source = observe(args.reference, args.reference_jsonl, args.fixture, args.timeout, "reference")
        new, new_source = observe(args.native, args.native_jsonl, args.fixture, args.timeout, "native")
        if inputs is not None:
            require_unchanged(inputs, fixture_inputs(args.fixture))
        report = compare(old, new, allow_empty_reference=args.allow_empty_reference)
        report.update(reference_source=old_source, native_source=new_source)
        if inputs is not None:
            report.update(fixture=str(args.fixture.resolve()), fixture_inputs_sha256=observation_digest(inputs), fixture_input_files=len(inputs))
        print(json.dumps(report, indent=2, ensure_ascii=False))
        return 0 if report["matched"] else 1
    except (OSError, ValueError, AttributeError, subprocess.TimeoutExpired) as error:
        print(f"records_data_only comparison failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
