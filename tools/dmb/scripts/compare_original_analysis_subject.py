#!/usr/bin/env python3
"""Compare complete independently issued old/native full semantic subjects."""
import argparse
import json
import re
from pathlib import Path

CASES = {"real", "absent", "noninclude", "invalid_utf8"}
SELECTOR = "actual_full_original_analyze_subject_matches_real_or_synthetic_code_and_warms_same_bodies"

def records(text, prefix):
    found = {}
    for line in text.splitlines():
        if not line.startswith(prefix):
            continue
        row = json.loads(line[len(prefix):])
        if set(row) != {"schema", "case", "types"} or row["schema"] != "original-analysis-whole-subject-v1":
            raise ValueError("foreign or incomplete subject record")
        case = row["case"]
        if case not in CASES or case in found:
            raise ValueError("duplicate or unknown subject case")
        types = row["types"]
        if not isinstance(types, list) or not types:
            raise ValueError("subject has no complete type roster")
        names = []
        for item in types:
            if not isinstance(item, list) or len(item) != 2:
                raise ValueError("invalid actual type/parent row")
            name, parent = item
            if not isinstance(name, str) or not name.startswith("/") or (parent is not None and (not isinstance(parent, str) or not parent.startswith("/"))):
                raise ValueError("invalid actual type/parent spelling")
            names.append(name)
        if names != sorted(set(names)) or "/" not in names:
            raise ValueError("subject roster is not complete sorted unique source data")
        found[case] = row
    if set(found) != CASES:
        raise ValueError("all four whole subject cases are required")
    return found

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    args = parser.parse_args()
    original = args.original.read_text(encoding="utf-8")
    native = args.native.read_text(encoding="utf-8")
    summaries = re.findall(r"^test result: (\w+)\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured;", native, re.M)
    statuses = re.findall(r"^test ([^\r\n ]+) \.\.\. (\w+)$", native, re.M)
    if summaries != [("ok", "1", "0", "0", "0")] or len(statuses) != 1 or statuses[0][0].split("::")[-1] != SELECTOR or statuses[0][1] != "ok":
        raise ValueError("native proof must be exactly the complete successful subject test")
    old = records(original, "OLD_ANALYSIS_SUBJECT=")
    new = records(native, "NATIVE_ANALYSIS_SUBJECT=")
    if old != new:
        for case in sorted(CASES):
            if old[case] != new[case]:
                raise ValueError(f"whole actual original/native subject differs: {case}")
    print("PASS: all four complete actual original/native type and parent rosters")

if __name__ == "__main__":
    main()
