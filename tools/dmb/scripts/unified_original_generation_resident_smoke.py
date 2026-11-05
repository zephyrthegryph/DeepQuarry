#!/usr/bin/env python3
"""All-thirteen Original generator proof through public resident IPC.

Use the existing unified_derived_resident_transport Rust wrapper so the
scratch root and compiler binary are issued by the normal test harness.
No original artifacts are supplied to native generation.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time



def verbatim(path):
    path = path.resolve(strict=True)
    if os.name != "nt" or str(path).startswith("\\\\?\\"):
        return path
    spelling = str(path)
    if spelling.startswith("\\\\"):
        return Path("\\\\?\\UNC\\" + spelling[2:])
    return Path("\\\\?\\" + spelling)


def expected_paths():
    outputs = {
        name: f"code/engine/_generated/{name}.dm" for name in (
            "actions", "auto_tracked", "declare", "deps", "plans", "reads",
            "sparse_slots", "stats", "system_accessors", "tracked_lists",
        )
    }
    outputs["declare_ids"] = "code/engine/_generated/ids.dm"
    outputs["derived_reads"] = "code/_generated/reads.dm"
    return outputs


def inventory(root):
    return {
        path.relative_to(root).as_posix():
            (path.read_bytes(), path.stat().st_mtime_ns) if path.is_file() else None
        for path in root.rglob("*")
    }


def document(result, strict_json):
    assert result.returncode in (0, 1), (result.returncode, result.stderr, result.stdout)
    lines = result.stdout.splitlines()
    assert len(lines) == 2, result.stdout
    header, report = map(strict_json, lines)
    assert header == {
        "schema": "native-generation-batch-v1", "row": "generation_batch",
        "status": "completed", "clean": report["clean"], "committed": report["committed"],
        "cleanup_warnings": len(report["cleanup"]),
    }, header
    assert report["schema"] == "native-generation-v1", report
    assert report["clean"] == (result.returncode == 0), report
    return report


def compare_receipts(original_log, current, old):
    contents = original_log.read_text(encoding="utf8")
    settled = [old.strict_json(line.split("=", 1)[1]) for line in contents.splitlines()
               if line.startswith("OLD_GENERATION_FIXEDPOINT_SETTLED=")]
    assert len(settled) == 4, "four independent old fixed-point completions required"
    for receipt in settled:
        assert set(receipt) == {"schema", "settled", "passes", "stage_zero", "stage_one", "generators"}
        assert receipt["schema"] == "original-generation-fixedpoint-v1" and receipt["settled"] is True
        assert type(receipt["passes"]) is int and 1 <= receipt["passes"] <= 5
        assert receipt["stage_zero"] == 8 and receipt["stage_one"] == 5
        assert len(receipt["generators"]) == 13 and set(receipt["generators"]) == old.NAMES
    original = old.rows(contents, "OLD_ORIGINAL_GENERATION_FULL=")
    for key, value in current.items():
        assert original[key] == value, f"complete native artifacts or ordered diagnostics differ for {key}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("binary", "analyze", "scratch-root", "repository", "fixtures"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--case", action="append", choices=("real", "absent", "noninclude", "invalid_utf8"))
    parser.add_argument("--original", type=Path, help="combined stdout from the four independent old oracle runs")
    args = parser.parse_args()
    sys.path.insert(0, str(args.repository / "tools/dmb/scripts"))
    import compare_original_generation as old
    from unified_daemon_smoke import Smoke
    from unified_derived_resident_transport_smoke import live, report_request

    cases = args.case or ["real", "absent", "noninclude", "invalid_utf8"]
    assert len(set(cases)) == len(cases)
    smoke = Smoke(args.binary, args.scratch_root, args.repository)
    cache = smoke.root / "cache"
    cache.mkdir()
    expected = expected_paths()
    assert set(expected) == old.NAMES - {"ui_types"}
    observations = {}
    pid = None

    def request(root, case, label, check):
        build = report_request(smoke, root)["build"]
        build["policy_inputs"]["workspace_generators"] = sorted(old.NAMES)
        build["policy_inputs"]["workspace_auxiliary"] = []
        path = smoke.root / f"{case}-{label}.json"
        path.write_text(json.dumps({"build": build, "check": check}), encoding="utf8", newline="\n")
        return path

    try:
        for case in cases:
            physical = smoke.root / case
            shutil.copytree(args.fixtures / case, physical)
            root = verbatim(physical)
            before = inventory(root)
            if case == "real":
                cold_check = smoke.run(
                    ["generate", str(request(root, case, "cold-check", True)), "--jsonl"],
                    success=False,
                )
                assert cold_check.returncode == 2 and not cold_check.stdout, cold_check
                assert inventory(root) == before
            cold = document(smoke.run(
                ["generate", str(request(root, case, "cold-write", False)), "--jsonl"], success=False
            ), old.strict_json)
            observed = live(smoke)
            if pid is None:
                pid = observed
            assert observed == pid
            assert cold["committed"] and not cold["cleanup"], cold
            assert len(cold["changed"]) == len(expected), cold
            def relative(name):
                return Path(name).relative_to(root).as_posix()
            assert {relative(name) for name in cold["changed"]} == set(expected.values()), cold
            assert len(cold["rows"]) == len(expected)
            assert {row["generator"]: relative(row["path"]) for row in cold["rows"]} == expected, cold
            assert all(row["state"] == "written" for row in cold["rows"]), cold
            assert "TRACKED(/datum/probe, charge)" in (
                root / expected["auto_tracked"]
            ).read_bytes().decode("utf8")
            assert not (root / "__dmb_original_analysis_subject__").exists()
            after = inventory(root)
            assert set(after) - set(before) >= set(expected.values())
            assert all(after[path] == value for path, value in before.items() if value is not None)
            assert not any(path.endswith((".dmb", ".rsc")) for path in after)
            for name in sorted(old.NAMES):
                row = {
                    "case": case, "generator": name,
                    "files": [
                        [relative(output["path"]), Path(output["path"]).read_bytes().decode("utf8")]
                        for output in cold["rows"] if output["generator"] == name
                    ],
                    "diagnostics": [
                        [diag["relative"], diag["line"], diag["message"]]
                        for diag in cold["diagnostics"] if diag["generator"] == name
                    ],
                }
                observations[(case, name)] = row
                print("NATIVE_ORIGINAL_GENERATION_FULL=" + json.dumps(row, ensure_ascii=False))
            warm_path = request(root, case, "warm-write", False)
            flags = subprocess.CREATE_NO_WINDOW | subprocess.BELOW_NORMAL_PRIORITY_CLASS if os.name == "nt" else 0
            warm = document(subprocess.run(
                [str(args.analyze), "native-gen", "--dmbc", str(smoke.binary), str(warm_path), "--jsonl"],
                cwd=smoke.root, env=smoke.env, capture_output=True, text=True, encoding="utf8",
                timeout=min(90, max(1, smoke.deadline - time.monotonic())), creationflags=flags,
            ), old.strict_json)
            checked = document(smoke.run(
                ["generate", str(request(root, case, "settled-check", True)), "--jsonl"], success=False
            ), old.strict_json)
            assert warm == checked, (warm, checked)
            assert not warm["committed"] and not warm["changed"] and not warm["cleanup"], warm
            assert all(row["state"] == "fresh" for row in warm["rows"]), warm
            assert warm["diagnostics"] == cold["diagnostics"], (warm, cold)
            assert {row["generator"]: relative(row["path"]) for row in warm["rows"]} == expected
            assert inventory(root) == after
            assert live(smoke) == pid
        if args.original:
            compare_receipts(args.original, observations, old)
        print("NATIVE_ORIGINAL_GENERATION_RESIDENT=" + json.dumps({
            "cases": cases, "generators": sorted(old.NAMES), "same_daemon_pid": pid,
            "complete_artifact_rows": len(observations), "independent_original_compared": bool(args.original),
            "cold_write": True, "warm_write_unchanged": True, "settled_check_unchanged": True,
            "cold_real_check_refused_without_changes": "real" in cases,
        }))
    finally:
        smoke.retire()


if __name__ == "__main__":
    main()
