#!/usr/bin/env python3
"""Observe an unchanged Super caller across two source revisions on one host."""
import argparse
import json
import os
from pathlib import Path
import subprocess

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


def query(smoke, project, revisions, *, success=True, context=CONTEXT, source_name="probe.dm", source_line_offset=0):
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
    assert Path(diagnostic["file"]).name == source_name, diagnostic
    assert diagnostic["line"] == SOURCE.splitlines().index(BODY) + 1 + source_line_offset, diagnostic
    assert diagnostic["column"] == BODY.index(".field") + 1, diagnostic
    start, end = diagnostic["expanded_span"]
    assert end == start + 1, diagnostic
    return diagnostic


def ordered_query(smoke, project, revisions):
    environment = environment_path(project)

    def read(*, context=CONTEXT, config=None, success=True):
        request = {
            "timeout_seconds": 45, "project": str(project),
            "defines": {}, "bootstrap_catalog": False, "queries": [],
            "expected_revision": revisions["semantic_revision"],
            "expected_source_revision": revisions["source_revision"],
            "expected_policy_revision": revisions["policy_revision"],
            "source_queries": [{"NativeOriginalOrderedChecker": {
                "environment": environment, "configuration": config,
            }}],
        }
        if context is not None:
            request["analysis_context"] = context
        path = smoke.root / f"ordered-query-{len(smoke.calls)}.json"
        path.write_text(json.dumps(request), encoding="utf-8")
        result = smoke.run(["query", str(path)], success=success)
        if success:
            [row] = assert_reply(json.loads(result.stdout), revisions)
            return row
        assert result.returncode != 0 and not result.stdout.strip(), result
        return result.stderr

    return read


def ordered_control(smoke):
    fixture = (smoke.repository /
               "tools/dmb/fixtures/unified_checks/final_graph_kwargs_before_graph/project.dme")
    project = create_project(smoke.root / "ordered", fixture.read_text(encoding="utf-8"))
    read = ordered_query(smoke, project, prepare(smoke, project))
    environment = environment_path(project)
    row = read()
    assert row["row"] == "source_native_original_ordered_checker", row
    assert row["full_checker_parity"] is False, row
    assert row["coverage"] == "selected_original_checker_phases", row
    diagnostics = row["diagnostics"]
    # These coordinates, severities and messages also occur in the pinned
    # Original result for this fixture. Their source lines are deliberately
    # not monotone because the reader orders phases, not source locations.
    assert [(d["phase"], d["severity"], d["line"], d["column"], d["message"])
            for d in diagnostics] == [
        ("settings_prelude", "warning", 8, 5, 'unknown setting "mystery_probe"'),
        ("body", "error", 11, 5, 'undefined var: "missing_probe"'),
        ("keyword_overrides", "error", 2, 22, "an override of /datum/base/proc/work is missing keyword args"),
        ("sleep_graph", "error", 7, 12, "/proc/probe sets SpacemanDMM_should_not_sleep but calls blocking proc /datum/base/proc/work"),
        ("purity_graph", "error", 7, 12, "/proc/probe sets SpacemanDMM_should_be_pure but calls a /datum/base/proc/work that does impure operations"),
    ], diagnostics
    assert [d["registration_tag"] for d in diagnostics] == [
        None, None, "override_missing_keyword_arg", "must_not_sleep", "must_be_pure",
    ], diagnostics
    assert [len(d["notes"]) for d in diagnostics] == [0, 0, 2, 3, 3], diagnostics
    assert all(Path(d["file"]).name == "probe.dm" for d in diagnostics), diagnostics
    assert read() == row, "same retained report changed"
    assert "explicit Original checker source query" in read(context=None, success=False)
    assert "configuration" in read(config=str(Path(environment).with_name("foreign.toml")), success=False)
    configuration = project.with_name("SpacemanDMM.toml")
    for severity, expected in (
        ("warning", [*diagnostics[:2], {**diagnostics[2], "severity": "warning"}, *diagnostics[3:]]),
        ("off", diagnostics[:2] + diagnostics[3:]),
    ):
        configuration.write_text(
            f'[diagnostics]\noverride_missing_keyword_arg = "{severity}"\n',
            encoding="utf-8", newline="\n",
        )
        configured = ordered_query(smoke, project, prepare(smoke, project))()
        assert configured["configuration_present"] is True, configured
        assert configured["diagnostics"] == expected, configured

    print(json.dumps({"test": "original_ordered_checker_ipc", "diagnostics": len(diagnostics),
                      "keyword_configuration": ["warning", "off"], "full_checker_parity": False}))


def root_increment_control(smoke):
    fixture = (smoke.repository /
               "tools/dmb/fixtures/unified_checks/root_increment_no_overload/project.dme")
    project = create_project(smoke.root / "root-increment", fixture.read_text(encoding="utf-8"))
    read = ordered_query(smoke, project, prepare(smoke, project))
    row = read()
    diagnostics = row["diagnostics"]
    assert [(d["line"], d["column"], d["message"]) for d in diagnostics] == [
        (2, 11, "Attempting operator++ on a (global) which does not overload operator++"),
        (3, 5, "Attempting operator-- on a (global) which does not overload operator--"),
        (4, 10, "Attempting operator++ on a /datum which does not overload operator++"),
        (5, 5, "Attempting operator-- on a /datum which does not overload operator--"),
    ], diagnostics
    assert all(
        d["phase"] == "body" and d["family"] == "operator_overload" and d["severity"] == "error"
        and d["registration_tag"] is None and not d["notes"]
        for d in diagnostics
    ), diagnostics
    assert read() == row
    print(json.dumps({"test": "original_ordered_checker_ipc_root_increment", "diagnostics": len(diagnostics)}))


def implicit_new_or_hint_control(smoke):
    fixture = (smoke.repository /
               "tools/dmb/fixtures/unified_checks/implicit_new_or_hint/project.dme")
    source = fixture.read_text(encoding="utf-8")
    project = create_project(smoke.root / "implicit-new-or-hint", source)
    read = ordered_query(smoke, project, prepare(smoke, project))
    row = read()
    diagnostics = row["diagnostics"]
    assert row["full_checker_parity"] is False, row
    source_lines = source.splitlines()
    expected = [
        ("undefined_proc", None, 5, source_lines[4].index("missing_argument") + 1,
         'undefined proc: "missing_argument" on (global)'),
        ("no_typehint_implicit_new", "no_typehint_implicit_new", 7,
         source_lines[6].index("new") + 1, "no type hint available on implicit new()"),
        ("no_typehint_implicit_new", "no_typehint_implicit_new", 8,
         source_lines[7].index("new") + 1, "no type hint available on implicit new()"),
    ]
    assert [(d["family"], d["registration_tag"], d["line"], d["column"], d["message"])
            for d in diagnostics] == expected, diagnostics
    assert all(d["phase"] == "body" and d["severity"] == "error" and not d["notes"]
               for d in diagnostics), diagnostics
    assert read() == row, "same retained report changed"
    print(json.dumps({"test": "original_ordered_checker_ipc_implicit_new_or_hint",
                      "diagnostics": len(diagnostics)}))


def sealed_parent_control(smoke, original_probe):
    fixture = (
        "/world\n    var/unified_parent_marker\n"
        "/savefile\n    parent_type = /world\n"
        "/datum/z_bad\n    parent_type = /datum/absent_parent_probe\n"
        "/datum\n    parent_type = /world\n"
        "/alist\n    parent_type = /world\n"
        "/list\n    parent_type = /world\n"
        "/proc/ancestry_probe(world/target, alist/alist_subject,"
        " datum/datum_subject, list/list_subject, savefile/savefile_subject)\n"
        "    var/observed_target = target.unified_parent_marker\n"
        "    var/observed_alist = alist_subject.unified_parent_marker\n"
        "    var/observed_datum = datum_subject.unified_parent_marker\n"
        "    var/observed_list = list_subject.unified_parent_marker\n"
        "    var/observed_savefile = savefile_subject.unified_parent_marker\n"
    )
    project = create_project(smoke.root / "sealed-parent", fixture)
    flags = subprocess.BELOW_NORMAL_PRIORITY_CLASS if os.name == "nt" else 0
    original = subprocess.run(
        [str(original_probe.resolve(strict=True)), str(project)],
        cwd=project.parent, capture_output=True, text=True, encoding="utf-8",
        timeout=25, creationflags=flags, check=True,
    )
    (smoke.root / "sealed-parent-original.json").write_text(original.stdout, encoding="utf-8")
    old = json.loads(original.stdout)
    sealed = ("alist", "datum", "list", "savefile")
    assert old["ancestry"] == {
        **{"/" + owner: {"parent": "/", "has_marker": False} for owner in sealed},
        "/world": {"parent": "/", "has_marker": True},
    }, old
    read = ordered_query(smoke, project, prepare(smoke, project))
    native = read()
    assert native["row"] == "source_native_original_ordered_checker", native
    assert native["full_checker_parity"] is False, native
    assert native["coverage"] == "selected_original_checker_phases", native
    rows = native["diagnostics"]

    def file_key(path):
        path = Path(path)
        if not path.is_absolute():
            path = project.parent / path
        resolved = path.resolve(strict=True)
        assert resolved == (project.parent / "code/probe.dm").resolve(strict=True), resolved
        return str(resolved)

    def reader_row(file, line, column, severity, tag, message, notes):
        # This cohort has no notes. Compare that requirement without erasing
        # extra rows or note locations from either real producer.
        assert not notes, (file, line, column, notes)
        return (file_key(file), line, column, severity, tag, message)

    native_reader = [reader_row(d["file"], d["line"], d["column"], d["severity"],
                                d["registration_tag"], d["message"], d["notes"])
                     for d in rows if d["phase"] == "reader_declarations"]
    old_reader = [reader_row(d["location"]["file"], d["location"]["line"],
                             d["location"]["column"], d["severity"],
                             d["registration_tag"], d["message"], d["notes"])
                  for d in old["diagnostics"]]
    assert native_reader == old_reader, (native_reader, old_reader)
    assert [r[-1] for r in old_reader] == [
        "not allowed to change /alist/parent_type",
        "not allowed to change /datum/parent_type",
        "bad parent type for /datum/z_bad: /datum/absent_parent_probe",
        "not allowed to change /list/parent_type",
        "not allowed to change /savefile/parent_type",
        "undefined var 'parent_type' on type '/datum/z_bad'",
    ], old_reader

    # The diagnostic-only snapshot refuses generic ancestry/model queries.
    # The ordered checker therefore supplies an actual descendant lookup
    # witness for each independently verified old root and its positive parent.
    expected_body = []
    for owner in sealed:
        assert not old["ancestry"]["/" + owner]["has_marker"]
        fragment = " " + owner + "_subject.unified_parent_marker"
        [(line, column)] = [(i, text.index(".unified_parent_marker") + 1)
                            for i, text in enumerate(fixture.splitlines(), 1) if fragment in text]
        expected_body.append((line, column, "error", None,
                              f'undefined field: "unified_parent_marker" on /{owner}'))
    actual_body = []
    for d in rows[len(old_reader):]:
        assert d["phase"] == "body" and not d["notes"], d
        file_key(d["file"])
        actual_body.append((d["line"], d["column"], d["severity"], d["registration_tag"], d["message"]))
    assert actual_body == expected_body, (actual_body, expected_body)
    assert read() == native, "warm ordered checker changed the source report"
    print(json.dumps({"test": "original_sealed_parent_ipc", "reader_rows": len(old_reader),
                      "ancestry_witnesses": len(actual_body), "full_checker_parity": False}))



def nested_source_control(smoke):
    root = smoke.root / "nested"
    project = create_project(root, '#include "leaf.dm"\n')
    leaf = root / "code/leaf.dm"
    # This leaf is reached only by the actual Original include walk. The
    # eager Native scan visits the direct include, and never captures this.
    leaf.write_bytes(b"\xef\xbb\xbf// raw \r\n" + SOURCE.replace("\n", "\r\n").encode("utf-8"))
    original = prepare(smoke, project)
    before = query(smoke, project, original, source_name=leaf.name, source_line_offset=1)
    assert before["message"] == 'undefined field: "field" on /datum/result_a', before

    leaf.write_bytes(b"\xef\xbb\xbf// raw \r\n" + CHANGED.replace("\n", "\r\n").encode("utf-8"))
    current = prepare(smoke, project)
    assert current["source_revision"] != original["source_revision"]
    assert "stale" in query(smoke, project, original, success=False).stderr
    after = query(smoke, project, current, source_name=leaf.name, source_line_offset=1)
    assert after["message"] == 'undefined field: "field" on /datum/result_b', after
    print("Standalone Original Checker used current nested raw-only source with a UTF-8 BOM and CRLF.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", choices=("parent-switch", "ordered", "root-increment", "implicit-new-or-hint", "sealed-parent", "nested-source"), default="parent-switch")
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--scratch-root", type=Path, required=True)
    parser.add_argument("--repository", type=Path, required=True)
    args = parser.parse_args()
    original_probe = os.environ.get("DQ_ORIGINAL_PARENT_ORACLE")
    if args.case == "sealed-parent" and not original_probe:
        parser.error("sealed-parent requires the pinned library example via DQ_ORIGINAL_PARENT_ORACLE")
    smoke = Smoke(args.binary, args.scratch_root, args.repository)
    try:
        if args.case == "nested-source":
            nested_source_control(smoke)
            return
        if args.case == "sealed-parent":
            sealed_parent_control(smoke, Path(original_probe))
            return
        if args.case == "ordered":
            ordered_control(smoke)
            return
        if args.case == "root-increment":
            root_increment_control(smoke)
            return
        if args.case == "implicit-new-or-hint":
            implicit_new_or_hint_control(smoke)
            return
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
