#!/usr/bin/env python3
"""Prepare the authenticated cache/edit sequence; compilation uses dmb-bench.py."""
import argparse
import copy
import json
from pathlib import Path
from cached_scenarios import SEQUENCE


def sequence(parent, edited):
    if parent.get("name") != "cold" or edited.get("name") != "cold-body-edit":
        raise ValueError("inputs must be existing cold and authenticated cold-body-edit scenarios")
    if parent.get("edits") or edited.get("edits"):
        raise ValueError("captured benchmark scenarios cannot contain live edits")
    for key in ("input_journal", "variant_receipt", "variant_receipt_sha256", "byond_snapshot", "byond_dmb"):
        if not edited.get(key):
            raise ValueError("derivative requires independent pinned " + key)
    result = []
    for index, name in enumerate(SEQUENCE):
        scenario = copy.deepcopy(parent if index < 2 else edited)
        scenario["name"] = name
        scenario["no_cache"] = name == "cold-after-edit"
        result.append(scenario)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--parent-scenario", type=Path, required=True)
    parser.add_argument("--edited-scenario", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    def load(path):
        value = json.loads(path.read_bytes())
        if isinstance(value, list):
            if len(value) != 1:
                raise ValueError("scenario input must contain exactly one scenario")
            value = value[0]
        return value
    if args.output.exists():
        raise ValueError("refusing to overwrite an existing scenario plan")
    result = sequence(load(args.parent_scenario), load(args.edited_scenario))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print("Prepared scenario plan only; pins are authenticated by dmb-bench.py before any compile.")


if __name__ == "__main__":
    main()
