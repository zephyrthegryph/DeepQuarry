#!/usr/bin/env python3
"""Prepare, authenticate and record a bounded cached cohort; never execute it."""
import argparse
import copy
import hashlib
import importlib.util
import json
import sys
from pathlib import Path
from types import SimpleNamespace


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build_record", type=Path)
    parser.add_argument("--parent-cohort", type=Path, default=Path("E:/dq-cache/dmb-native-v2/r6-pool-cohort-20261008-193650.json"))
    parser.add_argument("--variant", type=Path, default=Path("E:/dmb-native-v2-phase0/body-edit-variant-20261008-a/variant.json"))
    parser.add_argument("--edited-pin", type=Path, default=Path("E:/dmb-native-v2-phase0/body-edit-byond-baseline-20261008-a/byond-structural-pin.json"))
    parser.add_argument("--edited-dmb", type=Path, default=Path("E:/dmb-native-v2-phase0/body-edit-byond-baseline-20261008-a/source/comparison.dmb"))
    parser.add_argument("--prepare-directory", type=Path, required=True)
    args = parser.parse_args()
    record = json.loads(args.build_record.read_bytes())
    if record.get("build_exit_code") != 0 or sha(record["frozen_compiler"]) != record["compiler_sha256"]:
        raise ValueError("build record does not authenticate a successfully frozen compiler")
    command = list(json.loads(args.parent_cohort.read_bytes())["command"])
    def value(flag):
        return command[command.index(flag) + 1]
    bench = Path(command[1]).parent
    sys.path.insert(0, str(bench))
    scenario_tool = load_module("cached_scenario_generator", bench / "cached-scenarios.py")
    edit_tool = load_module("cached_edited_authentication", bench / "edited_snapshot.py")
    parent = json.loads(Path(value("--scenarios")).read_bytes())
    if len(parent) != 1 or parent[0]["name"] != "cold":
        raise ValueError("parent cohort must pin exactly one captured cold scenario")
    variant = json.loads(args.variant.read_bytes())
    pin = json.loads(args.edited_pin.read_bytes())
    edited = copy.deepcopy(parent[0])
    edited.update(name="cold-body-edit", input_journal=variant["snapshot"],
                  variant_receipt=str(args.variant.resolve()), variant_receipt_sha256=sha(args.variant),
                  byond_snapshot=str(args.edited_pin.resolve()), byond_dmb=str(args.edited_dmb.resolve()))
    edit_tool.authenticate(SimpleNamespace(sha=sha), edited, value("--input-journal"), pin)
    if sha(args.edited_dmb) != pin["dmb_sha256"]:
        raise ValueError("edited BYOND output hash mismatch")
    plan = scenario_tool.sequence(parent[0], edited)
    directory = args.prepare_directory.absolute()
    if directory.drive.lower() != "e:" or directory.exists():
        raise ValueError("preparation must use a new E: directory")
    directory.mkdir(parents=True, exist_ok=False)
    scenarios = directory / "scenarios.json"
    scenarios.write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
    def set_value(flag, replacement):
        if flag in command:
            command[command.index(flag) + 1] = str(replacement)
        else:
            command.extend([flag, str(replacement)])
    set_value("--compiler", record["frozen_compiler"])
    set_value("--profile-metadata", record["frozen_metadata"])
    set_value("--scenarios", scenarios)
    set_value("--output", directory / "cohort")
    set_value("--cache", directory / "cache")
    set_value("--results", directory / "results.jsonl")
    set_value("--watchdog", 600)
    set_value("--worker-counts", 8)
    receipt = {"schema": 1, "status": "prepared_not_executed", "command": command,
               "build_record": str(args.build_record.resolve()), "build_record_sha256": sha(args.build_record),
               "scenarios_sha256": sha(scenarios), "derivative_pin_sha256": sha(args.edited_pin),
               "variant_receipt_sha256": sha(args.variant), "per_compile_timeout_s": 600, "workers": 8,
               "runtime_launched": False, "performance_admission": "diagnostic_only",
               "overall_deadline_note": "48 measured/oracle compiler children; each has a 600-second watchdog"}
    (directory / "preparation.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
