"""Independent, pinned differential oracle for the first migrated checker family.

This compares observations, not models. The native executable must have been
built separately through the machine's cargo slot. It cannot certify other
families, macro columns, pragma/config behavior or whole-project parity.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from fixture_observations import fixture_inputs, require_unchanged, observation_digest

PINNED_CHECKER_SHA256 = "bafd54168a539e61d8c3f71d9778e92de76d7ffbf11c693541e10be10c9633ba"
LOCATION = re.compile(r"^(.+), line (\d+), column (\d+):$")
MESSAGE = re.compile(r"^(warning|error|hint|info): (.+)$")


def reference_rows(text, fixture):
    rows, pending = [], None
    for line in text.splitlines():
        location = LOCATION.match(line)
        if location:
            pending = {"file": str((fixture.parent / location[1]).resolve()),
                       "line": int(location[2]), "column": int(location[3]), "notes": []}
        elif pending is not None and (message := MESSAGE.match(line)):
            pending.update(severity=message[1], message=message[2])
            rows.append(pending)
        elif pending is not None and line.startswith("- "):
            pending["notes"].append(line[2:])
        elif not line:
            pending = None
    return rows


def native_rows(text, family="ambiguous_not_bitwise"):
    rows = []
    for line in text.splitlines():
        row = json.loads(line)
        accepted = {"control_condition_static", "unreachable_code", "loop_condition_determinate", "if_condition_determinate", "set_has_no_effect"} if family == "control_policies" else {family}
        if row.pop("family") not in accepted:
            raise ValueError("fixture includes an unported diagnostic family")
        row["file"] = str(Path(row["file"]).resolve())
        row["column"] = row.pop("expanded_column")
        rows.append(row)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--family", choices=("ambiguous_not_bitwise", "ambiguous_in_lhs", "invalid_set_value", "control_condition_static", "unreachable_code", "loop_condition_determinate", "if_condition_determinate", "set_has_no_effect", "control_policies", "proc_has_no_parent", "undefined_proc"), default="ambiguous_not_bitwise")
    parser.add_argument("fixture", type=Path)
    args = parser.parse_args()
    if hashlib.sha256(args.reference.read_bytes()).hexdigest() != PINNED_CHECKER_SHA256:
        parser.error("reference executable does not match pinned suite-1.11")
    inputs = fixture_inputs(args.fixture.resolve().parent)
    native_before = hashlib.sha256(args.native.read_bytes()).hexdigest()
    reference = subprocess.run([str(args.reference), "-e", str(args.fixture)], capture_output=True, text=True, timeout=60)
    native = subprocess.run([str(args.native), str(args.fixture), args.family], capture_output=True, text=True, timeout=60)
    if reference.returncode not in (0, 1) or native.returncode:
        raise RuntimeError(f"oracle execution failed: reference={reference.returncode}, native={native.returncode}\n{reference.stderr}\n{native.stderr}")
    require_unchanged(inputs, fixture_inputs(args.fixture.resolve().parent))
    if hashlib.sha256(args.native.read_bytes()).hexdigest() != native_before or hashlib.sha256(args.reference.read_bytes()).hexdigest() != PINNED_CHECKER_SHA256:
        raise RuntimeError("an oracle executable changed during observation")
    expected = reference_rows(reference.stderr, args.fixture.resolve())
    observed = native_rows(native.stdout, args.family)
    if not expected:
        raise RuntimeError("empty reference observations cannot certify this seeded fixture")
    if observed != expected:
        print(json.dumps({"reference": expected, "native": observed}, indent=2))
        return 1
    print(json.dumps({"scope": args.family + "/unexpanded-fixture", "diagnostics": len(expected), "matched": True, "full_checker_parity": False, "fixture_inputs_sha256": observation_digest(inputs), "fixture_input_files": len(inputs), "native_sha256": native_before, "reference_sha256": PINNED_CHECKER_SHA256}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
