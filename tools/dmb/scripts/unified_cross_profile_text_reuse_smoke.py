#!/usr/bin/env python3
"""Real Original Prepare to Native Compile storage and output-equivalence control."""
import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path

from unified_daemon_smoke import Smoke, json_rows

TRACE = "native source backing observation: "
SOURCE = """/proc/common_probe()
    return 37
#ifdef SPACEMAN_DMM
/proc/profile_marker()
    return 1666
#else
/proc/profile_marker()
    return 1687
#endif
"""


def prepare(smoke, project):
    root = project.parent
    configuration = root / "tools/ci/lint_scopes.toml"
    result = smoke.run([
        "prepare-query", str(project), "--workers", "2", "--exact-inputs",
        "--request-timeout-seconds", "45", "--policy-inputs-json",
        json.dumps({"analysis_context": "original_analyze0290", "workspace": {
            "root": str(root), "recursive_roots": [str(root / "code"), str(root / "maps")],
            "configuration": str(configuration),
        }}),
    ])
    [row] = [row for row in json_rows(result.stdout) if row["row"] == "query_prepared"]
    assert row["retained"] is True, row


def compile_project(smoke, project):
    out = smoke.root / "artifacts"
    result = smoke.run([
        "compile", str(project), "--workers", "2", "--exact-inputs", "--request-timeout-seconds", "45",
        "--output-store", str(smoke.root / "pairs"), "--artifact-directory", str(out),
    ])
    traces = [json.loads(line.split(TRACE, 1)[1]) for line in result.stderr.splitlines() if TRACE in line]
    pair = out / "deepquarry.dmb", out / "deepquarry.rsc"
    assert all(path.is_file() for path in pair), result.stderr
    return pair, traces


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for arg in ("binary", "equiv", "scratch-root", "cold-scratch", "changed-scratch", "repository"):
        parser.add_argument("--" + arg, required=True, type=Path)
    args = parser.parse_args()
    warm, cold, changed = (
        Smoke(args.binary, path, args.repository)
        for path in (args.scratch_root, args.cold_scratch, args.changed_scratch)
    )
    try:
        for smoke in (warm, cold, changed):
            smoke.env["DMB_UNIFIED_TEST_OWNER_TRACE"] = "1"
        root = warm.root / "fixture"
        (root / "code").mkdir(parents=True)
        config = root / "tools/ci/lint_scopes.toml"
        config.parent.mkdir(parents=True)
        shutil.copyfile(args.repository / "tools/ci/lint_scopes.toml", config)
        project = root / "deepquarry.dme"
        # The eager literal pre-scan reaches code/bridge.dm but not its nested include.
        # common.dm is acquired by each profile's real directive walk.
        project.write_text('#include "code/bridge.dm"\n', encoding="utf-8", newline="\n")
        (root / "code/bridge.dm").write_text('#include "common.dm"\n', encoding="utf-8", newline="\n")
        source = root / "code/common.dm"
        source.write_text(SOURCE, encoding="utf-8", newline="\n")
        prepare(warm, project)
        pair, traces = compile_project(warm, project)
        assert any(Path(row["path"]).name == source.name and
                   row["edge"] == "original_decoded_text_to_native" for row in traces), traces
        warm.retire()
        reference, cold_traces = compile_project(cold, project)
        cold.retire()
        assert not cold_traces, cold_traces
        options = {}
        if os.name == "nt":
            options["creationflags"] = subprocess.CREATE_NO_WINDOW | subprocess.BELOW_NORMAL_PRIORITY_CLASS
        subprocess.run(
            [str(args.equiv.resolve()), str(pair[0]), str(reference[0]), "--rsc", str(pair[1]),
             str(reference[1]), "--all", "--strict-order"],
            check=True, timeout=30, **options,
        )
        marker = subprocess.run(
            [str(args.equiv.resolve()), "dump-proc", str(pair[0]), "profile_marker"],
            capture_output=True, text=True, check=True, timeout=15, **options,
        ).stdout
        assert "PushVal 1687" in marker and "PushVal 1666" not in marker, marker

        prepare(changed, project)
        source.write_text(SOURCE.replace("37", "42"), encoding="utf-8", newline="\n")
        updated, changed_traces = compile_project(changed, project)
        assert all(Path(row["path"]).name != source.name for row in changed_traces), changed_traces
        updated_code = subprocess.run(
            [str(args.equiv.resolve()), "dump-proc", str(updated[0]), "common_probe"],
            capture_output=True, text=True, check=True, timeout=15, **options,
        ).stdout
        assert "PushVal 42" in updated_code and "PushVal 37" not in updated_code, updated_code
        print("Original decoded text reused after a real Native read. Native output matched fresh compile.")
    finally:
        for smoke in (changed, cold, warm):
            smoke.retire()


if __name__ == "__main__":
    main()
