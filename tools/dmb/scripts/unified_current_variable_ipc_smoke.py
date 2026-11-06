#!/usr/bin/env python3
"""Observe an unchanged Super caller across two source revisions on one host."""
import argparse
import json
import os
from pathlib import Path

from unified_daemon_smoke import Smoke, assert_reply, json_rows


BODY = "    return ..().field"
SOURCE = (
    "/datum/result_a\n/datum/result_b\n"
    "/datum/base_a/proc/probe()\n"
    "    set SpacemanDMM_return_type=/datum/result_a\n    return null\n"
    "/datum/base_b/proc/probe()\n"
    "    set SpacemanDMM_return_type=/datum/result_b\n    return null\n"
    "/datum/child\n    parent_type = /datum/base_a\n"
    "/datum/child/probe()\n" + BODY + "\n"
)
CHANGED = SOURCE.replace("parent_type = /datum/base_a", "parent_type = /datum/base_b")
CONTEXT = "original_checker0290"


def create_project(root, source):
    (root / "code").mkdir(parents=True)
    project = root / "deepquarry.dme"
    project.write_text('#include "code/probe.dm"\n', encoding="utf-8", newline="\n")
    write_source(project, source)
    return project


def write_source(project, source):
    (project.parent / "code/probe.dm").write_text(source, encoding="utf-8", newline="\n")


def environment_path(project):
    if os.name == "nt":
        # Match the actual Windows acquisition path in the source capture.
        import nt
        return nt._getfinalpathname(str(project))
    return str(project)


def prepare(smoke, project):
    intent = {
        "analysis_context": CONTEXT,
        "files": [
            {"path": str(Path(environment_path(project)).with_name("SpacemanDMM.toml")),
             "role": "configuration", "required": False},
            {"path": environment_path(project), "role": "dm_source", "required": True},
        ],
    }
    result = smoke.run([
        "prepare-query", str(project), "--workers", "1", "--exact-inputs",
        "--request-timeout-seconds", "45", "--policy-inputs-json", json.dumps(intent),
    ])
    rows = [row for row in json_rows(result.stdout) if row.get("row") == "query_prepared"]
    assert len(rows) == 1 and rows[0]["retained"] is True, result.stdout
    return rows[0]


def query(smoke, project, revisions, *, success=True, context=CONTEXT):
    request = {
        "timeout_seconds": 30, "project": str(project),
        "defines": {}, "bootstrap_catalog": False, "queries": [],
        "expected_revision": revisions["semantic_revision"],
        "expected_source_revision": revisions["source_revision"],
        "expected_policy_revision": revisions["policy_revision"],
        "source_queries": [{"NativeConfiguredChecker": {
            "ordinal": 2,  # Two authored parent bodies precede the child override.
            "family": "current_undefined_variable",
            "environment": environment_path(project),
            "configuration": None,
        }}],
    }
    if context is not None:
        request["analysis_context"] = context
    path = smoke.root / f"query-{len(smoke.calls)}.json"
    path.write_text(json.dumps(request), encoding="utf-8")
    result = smoke.run(["query", str(path)], success=success)
    if not success:
        return result
    reply = json.loads(result.stdout)
    assert reply["publication_pair"] is None, reply
    [row] = assert_reply(reply, revisions)
    assert row["family"] == "current_undefined_variable", row
    assert row["full_checker_parity"] is False and row["disposition"] == "evaluated", row
    assert row["configuration_present"] is False, row
    [diagnostic] = row["diagnostics"]
    assert diagnostic["family"] == "undefined_variable", diagnostic
    assert diagnostic["severity"] == "error" and diagnostic["notes"] == [], diagnostic
    assert Path(diagnostic["file"]).name == "probe.dm", diagnostic
    assert diagnostic["line"] == SOURCE.splitlines().index(BODY) + 1, diagnostic
    assert diagnostic["column"] == BODY.index(".field") + 1, diagnostic
    start, end = diagnostic["expanded_span"]
    assert end == start + 1, diagnostic
    return diagnostic


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--scratch-root", type=Path, required=True)
    parser.add_argument("--repository", type=Path, required=True)
    args = parser.parse_args()
    smoke = Smoke(args.binary, args.scratch_root, args.repository)
    try:
        project = create_project(smoke.root / "retained", SOURCE)
        a = prepare(smoke, project)
        before = query(smoke, project, a)
        assert before["message"] == 'undefined field: "field" on /datum/result_a', before
        rejected = query(smoke, project, a, success=False, context=None)
        assert "explicit Original checker source query" in rejected.stderr, rejected.stderr

        write_source(project, CHANGED)
        assert query(smoke, project, a) == before, "query mixed edited disk with prepared source"
        b = prepare(smoke, project)
        assert a["source_revision"] != b["source_revision"], (a, b)
        after = query(smoke, project, b)
        assert after["message"] == 'undefined field: "field" on /datum/result_b', after
        assert after["expanded_span"] == before["expanded_span"], (before, after)
        rejected = query(smoke, project, a, success=False)
        assert "revision is stale" in rejected.stderr, rejected.stderr

        fresh = create_project(smoke.root / "fresh", CHANGED)
        fresh_row = query(smoke, fresh, prepare(smoke, fresh))
        # Source path is expected to differ across actual workspace owners.
        assert {k: v for k, v in after.items() if k != "file"} == {
            k: v for k, v in fresh_row.items() if k != "file"
        }, (after, fresh_row)
        print(json.dumps({
            "test": "original_current_variable_ipc_parent_switch",
            "before": before["message"], "after": after["message"],
            "fresh_workspace_match": True,
            "full_checker_parity": False,
        }))
    finally:
        smoke.retire()


if __name__ == "__main__":
    main()
