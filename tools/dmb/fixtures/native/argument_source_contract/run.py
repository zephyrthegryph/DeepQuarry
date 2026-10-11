"""Paired owning-frame observations plus authentic argument-source helper tables.

Direct calls may not execute allowed-values helpers; helper call count is observed,
not presumed. This fixture does not simulate a client or assert prompt behavior.
"""
import argparse
import ast
from collections import Counter
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
import time

HERE = Path(__file__).resolve().parent
BENCH = HERE.parents[2] / "bench"
EXPECTED_BINDINGS = {
    "earlier": (1,), "argument_count": (1,), "argument_first": (1,),
    "first_source": (0,), "third_source": (1, 2),
}


def load(file, name):
    spec = importlib.util.spec_from_file_location(name, file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def observations(file):
    raw = file.read_bytes()
    if len(raw) > 1024 * 1024:
        raise ValueError("tiny runtime log exceeds 1MiB")
    text = raw.decode("utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig")
    markers = []
    errors = Counter()
    for line in text.splitlines():
        if "DQ_ARGFRAME " in line:
            markers.append(line[line.index("DQ_ARGFRAME "):])
        match = re.search(r"runtime error:\s*(.*)", line, re.IGNORECASE)
        if match:
            errors[match[1]] += 1
    if not markers or markers[-1] != "DQ_ARGFRAME finished":
        raise ValueError("fixture did not finish")
    for prefix in ("earlier", "count", "first", "first_source", "third_source", "calls"):
        if sum(line.startswith("DQ_ARGFRAME " + prefix + " ") for line in markers) != 1:
            raise ValueError("missing/duplicate owning frame observation")
    return {"markers": markers, "runtimes": dict(sorted(errors.items()))}


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--inspector", required=True, type=Path)
    parser.add_argument("--inspector-sha256", required=True)
    args, remaining = parser.parse_known_args()
    if os.name != "nt":
        raise ValueError("pinned Windows fixture requires Windows")
    inspector = args.inspector.resolve(strict=True)
    sys.path.insert(0, str(BENCH))
    from upgrade_owned_job import OwnedJob
    common = load(HERE.parent / "power_retirement_runtime" / "run.py", "frame_runtime")
    deadline = time.monotonic() + 300
    job = OwnedJob(4_000_000_000)
    h = None
    evidence_root = None
    original_load = common.load
    old_argv = sys.argv

    def common_load(name, file):
        nonlocal h
        module = original_load(name, file)
        if file.name == "native-iteration.py":
            h = module
            h.regular(inspector)
            if not re.fullmatch(r"[0-9a-f]{64}", args.inspector_sha256) or h.sha(inspector) != args.inspector_sha256:
                raise ValueError("inspector pin mismatch")
            h._owned_job = job
            original_child = h.run_child
            def bounded_child(executable, arguments, directory, child_deadline, **kwargs):
                nonlocal evidence_root
                if evidence_root is None:
                    evidence_root = directory.parent
                return original_child(executable, arguments, directory, min(deadline, child_deadline), **kwargs)
            h.run_child = bounded_child
        return module

    def capture(dmb, backend, receipt):
        root = Path(receipt["root"])
        receipt.setdefault("pinned_inputs", {})["inspector"] = {
            "path": str(inspector), "sha256": args.inspector_sha256}
        before = h.sha(dmb)
        evidence = receipt.setdefault("helper_metadata", {})[backend] = {"dmb_sha256": before, "helpers": []}
        def inspect(arguments, label):
            directory = root / (backend + "-metadata") / label
            result = h.run_child(inspector, arguments, directory, min(deadline, time.monotonic() + 30))
            stdout = (directory / "stdout.log").read_bytes()
            stderr = (directory / "stderr.log").read_bytes()
            if result["exit"] != 0 or len(stdout) + len(stderr) > 1024 * 1024:
                raise ValueError("bounded metadata extraction failed: " + label)
            evidence.setdefault("children", []).append(result)
            return stdout.decode("utf-8-sig", errors="replace")
        audit = inspect(["argument-source-audit", str(dmb)], "references")
        count = re.search(r"^proc_references=(\d+)$", audit, re.MULTILINE)
        if not count or not sum(map(len, EXPECTED_BINDINGS.values())) <= int(count[1]) <= 8:
            raise ValueError("helper reference inventory not fully exposed by bounded inspector")
        references = re.findall(r"^reference\[(\d+)\]=(\d+) path=(.*)$", audit, re.MULTILINE)
        if len(references) != int(count[1]):
            raise ValueError("incomplete helper inventory")
        bindings = {}
        for owner in EXPECTED_BINDINGS:
            locator = inspect(["proc-code", str(dmb), "/proc/" + owner], "owner-code-" + owner)
            match = re.search(r"^proc#(\d+) /proc/" + owner + r"$", locator, re.MULTILINE)
            if not match:
                raise ValueError("owning procedure identity unavailable")
            record = inspect(["proc", str(dmb), match[1]], "owner-record-" + owner)
            formal_list = re.search(r"code_locals_args: \[\d+, \d+, (\d+)\]", record)
            if not formal_list:
                raise ValueError("owning formal list unavailable")
            formals = ast.literal_eval(inspect(["list", str(dmb), formal_list[1]], "owner-args-" + owner).strip())
            if not isinstance(formals, list) or len(formals) % 4 or not all(type(word) is int and 0 <= word <= 0xffffffff for word in formals):
                raise ValueError("invalid owning formal rows")
            for argument in range(len(formals) // 4):
                source = formals[argument * 4 + 1]
                if source & 255 == 64:
                    bindings.setdefault(source >> 8, []).append((owner, argument))
        actual_bindings = {tuple(binding) for bindings_for_reference in bindings.values()
                           for binding in bindings_for_reference}
        expected_bindings = {(owner, argument) for owner, arguments in EXPECTED_BINDINGS.items()
                             for argument in arguments}
        if actual_bindings != expected_bindings:
            raise ValueError("actual owning selectors differ from authored helper roster")
        evidence["owning_bindings"] = bindings
        for ordinal, proc_id, path in references:
            text = inspect(["proc", str(dmb), proc_id], "proc-" + ordinal)
            match = re.search(r"code_locals_args: \[\d+, \d+, (\d+)\]", text)
            if not match:
                raise ValueError("helper formal list was not issued")
            list_id = int(match[1])
            words = [] if list_id == 65535 else ast.literal_eval(inspect(["list", str(dmb), str(list_id)], "args-" + ordinal).strip())
            if not isinstance(words, list) or len(words) % 4 or not all(type(word) is int and 0 <= word <= 0xffffffff for word in words):
                raise ValueError("invalid helper formal rows")
            rows = []
            for offset in range(0, len(words), 4):
                type_flags, source, variable, reserved = words[offset:offset + 4]
                variable_text = inspect(["variable", str(dmb), str(variable)], f"name-{ordinal}-{offset}")
                name = re.search(r" name=(.*)$", variable_text.strip())
                if not name:
                    raise ValueError("helper formal name unavailable")
                rows.append({"name": name[1], "type_flags": type_flags, "value_source": source, "reserved": reserved})
            evidence["helpers"].append({"reference": int(ordinal), "proc_id": int(proc_id), "path": path,
                                         "list_id": list_id, "raw_formals": words, "formals": rows,
                                         "owning_parameters": bindings.get(int(ordinal), [])})
        if h.sha(dmb) != before or h.sha(inspector) != args.inspector_sha256:
            raise ValueError("metadata input/tool changed")
        # Metadata differences are retained independently of runtime equivalence.
        receipt["helper_metadata_equal"] = None
        if "byond" in receipt["helper_metadata"] and "native" in receipt["helper_metadata"]:
            normalize = lambda rows: sorted((tuple(owner), row["formals"])
                for row in rows["helpers"] for owner in row["owning_parameters"])
            receipt["helper_metadata_equal"] = normalize(receipt["helper_metadata"]["byond"]) == normalize(evidence)
        return []

    try:
        common.load = common_load
        sys.argv = [sys.argv[0], *remaining]
        with common.hidden_error_mode():
            return common.main(fixture_directory=HERE, observation_reader=observations,
                               prepare_runtime=capture, scope=__doc__)
    finally:
        sys.argv = old_argv
        common.load = original_load
        if h is not None:
            h._owned_job = None
        cleanup = job.close()
        if evidence_root is not None:
            (evidence_root / "owned-job.json").write_text(json.dumps(cleanup, indent=2), encoding="utf-8")
        if not cleanup.get("reaped"):
            raise RuntimeError("owned fixture children were not reaped")


if __name__ == "__main__":
    raise SystemExit(main())
