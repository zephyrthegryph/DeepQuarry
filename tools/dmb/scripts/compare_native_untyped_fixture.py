"""Compare native untyped findings with the independent legacy Analyze oracle.

Both executables must already be built through the machine's cargo slot. This
script only compares observations, never serializes or imports either model.
The legacy executable is tools/analyze/examples/unified_legacy_untyped.rs; the
native executable is dm-analysis/examples/native_untyped.rs. JSONL captured from
those programs can be supplied instead. A match covers this fixture and these
five finding fields, not full Analyze, configuration, suppression or cache parity.
"""

import argparse
from collections import Counter
from dataclasses import asdict, dataclass
import hashlib
from itertools import zip_longest
import json
from pathlib import Path
import subprocess
import sys
from fixture_observations import fixture_inputs, require_unchanged, observation_digest


FIELDS = frozenset(("rule", "file", "line", "message", "identity"))


@dataclass(frozen=True, order=True)
class Finding:
    file: str
    line: int
    rule: str
    message: str
    identity: str


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON field {key!r}")
        result[key] = value
    return result


def rows(text, label):
    """Strict JSONL observations; log noise cannot become an empty success."""
    findings = []
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        try:
            row = json.loads(line, object_pairs_hook=unique_object)
            if not isinstance(row, dict) or row.keys() != FIELDS:
                raise ValueError(f"expected exactly {sorted(FIELDS)}")
            if any(not isinstance(row[key], str) or not row[key]
                   for key in FIELDS - {"line"}):
                raise ValueError("finding text fields must be nonempty strings")
            if type(row["line"]) is not int or row["line"] < 1:
                raise ValueError("finding line must be a positive integer")
            if row["rule"] not in ("typed", "call", "schema"):
                raise ValueError(f"unknown untyped rule {row['rule']!r}")
            findings.append(Finding(**row))
        except (ValueError, TypeError) as error:
            raise ValueError(f"{label}:{number}: {error}") from error
    return findings


def compare(reference, native, *, allow_empty_reference=False):
    """Compare every field, multiplicity and the legacy policy's row order."""
    if not reference and not allow_empty_reference:
        raise ValueError("empty reference observations cannot prove a seeded fixture")
    expected = Counter(reference)
    observed = Counter(native)
    differences = []
    for finding in sorted(expected.keys() | observed.keys()):
        if expected[finding] != observed[finding]:
            differences.append({
                "finding": asdict(finding),
                "reference_count": expected[finding],
                "native_count": observed[finding],
            })
    order_differences = []
    for position, (left, right) in enumerate(zip_longest(reference, native), 1):
        if left != right:
            order_differences.append({
                "position": position,
                "reference": asdict(left) if left is not None else None,
                "native": asdict(right) if right is not None else None,
            })
    return {
        "scope": "untyped-fixture/finding-fields",
        "full_analysis_parity": False,
        "reference_findings": len(reference),
        "native_findings": len(native),
        "matched": not differences and not order_differences,
        "differences": differences,
        "order_difference_count": len(order_differences),
        "first_order_differences": order_differences[:16],
    }


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def observe(executable, jsonl, fixture, timeout, label):
    if jsonl is not None:
        text = jsonl.read_text(encoding="utf-8-sig")
        source = {"jsonl": str(jsonl.resolve()), "sha256": digest(jsonl)}
    else:
        if fixture is None or not fixture.is_dir():
            raise ValueError("--fixture must name a directory when running executables")
        executable = executable.resolve()
        command = [str(executable), str(fixture.resolve())]
        executable_before = digest(executable)
        result = subprocess.run(command, capture_output=True, text=True,
                                encoding="utf-8", timeout=timeout, check=False)
        if result.returncode:
            raise ValueError(
                f"{label} exited {result.returncode}; no comparison made\n{result.stderr}")
        if digest(executable) != executable_before:
            raise ValueError(f"{label} executable changed during observation")
        text = result.stdout
        source = {"executable": str(executable), "sha256": executable_before}
    return rows(text, label), source


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    reference = parser.add_mutually_exclusive_group(required=True)
    reference.add_argument("--reference", type=Path, help="built legacy oracle executable")
    reference.add_argument("--reference-jsonl", type=Path)
    native = parser.add_mutually_exclusive_group(required=True)
    native.add_argument("--native", type=Path, help="built native fixture executable")
    native.add_argument("--native-jsonl", type=Path)
    parser.add_argument("--fixture", type=Path)
    parser.add_argument("--timeout", type=int, default=60,
                        help="per executable limit in seconds (no builds are run)")
    parser.add_argument("--allow-empty-reference", action="store_true",
                        help="only for a deliberately clean fixture")
    args = parser.parse_args(argv)
    if args.timeout < 1 or args.timeout > 300:
        parser.error("--timeout must be between 1 and 300 seconds")
    try:
        inputs = fixture_inputs(args.fixture) if args.fixture is not None else None
        expected, reference_source = observe(args.reference, args.reference_jsonl,
                                              args.fixture, args.timeout, "reference")
        actual, native_source = observe(args.native, args.native_jsonl,
                                        args.fixture, args.timeout, "native")
        if inputs is not None:
            require_unchanged(inputs, fixture_inputs(args.fixture))
        report = compare(expected, actual, allow_empty_reference=args.allow_empty_reference)
        report.update(reference_source=reference_source, native_source=native_source)
        if args.fixture is not None:
            report["fixture"] = str(args.fixture.resolve())
            report["fixture_inputs_sha256"] = observation_digest(inputs)
            report["fixture_input_files"] = len(inputs)
        print(json.dumps(report, indent=2, ensure_ascii=False))
        return 0 if report["matched"] else 1
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"untyped fixture comparison failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
