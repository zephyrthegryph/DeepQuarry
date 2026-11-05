#!/usr/bin/env python3
"""Exercise a real shared semantic read report through the resident service."""
import argparse
import copy
import difflib
import json
import os
from pathlib import Path
import subprocess
import time

from unified_daemon_smoke import Smoke
from unified_derived_resident_transport_smoke import live, report_request

POLICIES = ["sem/reads", "setter_publishes", "untracked_inputs"]
QUESTIONS = {
    "sem/reads": "sem_reads",
    "setter_publishes": "setter_publishes",
    "untracked_inputs": "untracked_inputs",
}


def fixture(smoke, configuration):
    root = smoke.root / "fixture"
    source = smoke.repository / "tools/analyze/fixtures/native-sem-reads/basic"
    includes = []
    for original in sorted((source / "code").rglob("*.dm")):
        relative = original.relative_to(source)
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        contents = original.read_bytes()
        if target.name == "apc.dm":
            original_read = b"return mode == 2"
            assert contents.count(original_read) == 1
            contents = contents.replace(
                original_read,
                original_read + b" // ALLOW(reads): this fixture samples a mutable field",
            )
        target.write_bytes(contents)
        includes.append(relative.as_posix())
    (root / "code/setter.dm").write_text(
        "/datum/setter_probe\n    var/charge\nSETTER(/datum/setter_probe, charge)\n"
        "/datum/setter_probe/proc/set_charge(value)\n    charge=value\n",
        encoding="utf8",
        newline="\n",
    )
    includes.append("code/setter.dm")
    (root / "deepquarry.dme").write_text(
        "".join(f'#include "{relative}"\n' for relative in includes),
        encoding="utf8",
        newline="\n",
    )
    (root / "maps").mkdir()
    (root / "tools/ci").mkdir(parents=True)
    (root / "tools/ci/lint_scopes.toml").write_bytes(configuration.read_bytes())
    return root


def policy_request(smoke, root, selected):
    request = report_request(smoke, root)
    request["lints"] = selected
    request["ci"] = True
    policy = request["build"]["policy_inputs"]
    policy["workspace_auxiliary"] = [QUESTIONS[name] for name in selected]
    policy["workspace"]["recursive_roots"].append(str(root / "maps"))
    return request


def read_result(result, selected):
    assert result.returncode in (0, 1), (result.returncode, result.stderr)
    document = json.loads(result.stdout)
    assert document["schema"] == "native-analyze-report-v1", document
    assert document["complete"] and not document["baseline"], document
    assert document["clean"] == (result.returncode == 0), document
    assert document["lints"] == selected, document
    return document


def section(document, name):
    prefix = f"::group::{name}\n"
    assert document["text"].count(prefix) == 1, document["text"]
    _, _, text = document["text"].partition(prefix)
    group, end, _ = text.partition("::endgroup::\n")
    assert end, text
    return group


def compare_legacy(smoke, root, combined, flags):
    executable = os.environ.get("DQ_UNIFIED_ANALYZE_ORIGINAL")
    if not executable:
        return None
    allow_path = smoke.root / "legacy-allow-usage.tsv"
    env = dict(smoke.env, DQ_ALLOW_USAGE=str(allow_path))
    original = subprocess.run(
        [executable, "check", "--no-selftest", "--no-cache", "--ci", "--raw",
         "--lint", ",".join(POLICIES), "--root", str(root)],
        cwd=smoke.root, env=env, capture_output=True, text=True, encoding="utf8",
        timeout=min(90, max(1, smoke.deadline - time.monotonic())), creationflags=flags,
    )
    assert original.returncode == int(not combined["clean"]), original.stderr
    expected = original.stdout
    actual = combined["text"]
    assert expected == actual, "".join(difflib.unified_diff(
        expected.splitlines(keepends=True), actual.splitlines(keepends=True),
        fromfile="legacy Analyze", tofile="native cohort",
    ))
    rows = set()
    for line in allow_path.read_text(encoding="utf8").splitlines():
        name, digest, number = line.split("\t")
        rows.add((name, digest, int(number)))
    assert rows == set(map(tuple, combined["allow_usage"]))
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("binary", "analyze", "scratch-root", "repository", "configuration"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    smoke = Smoke(args.binary, args.scratch_root, args.repository)

    def write_request(label, request):
        path = smoke.root / f"{label}.json"
        path.write_text(json.dumps(request), encoding="utf8", newline="\n")
        return path

    try:
        root = fixture(smoke, args.configuration)
        selected = list(reversed(POLICIES))
        request = policy_request(smoke, root, selected)
        path = write_request("cohort", request)
        combined = read_result(
            smoke.run(["analyze-check", str(path), "--jsonl"], success=False), selected
        )
        pid = live(smoke)
        assert not combined["clean"] and combined["allow_usage"], combined
        assert [line for line in combined["text"].splitlines() if line.startswith("::group::")] == [
            f"::group::{policy}" for policy in POLICIES
        ]
        flags = subprocess.CREATE_NO_WINDOW | subprocess.BELOW_NORMAL_PRIORITY_CLASS if os.name == "nt" else 0
        warm = subprocess.run(
            [str(args.analyze), "native-check", "--dmbc", str(smoke.binary), str(path), "--jsonl"],
            cwd=smoke.root, env=smoke.env, capture_output=True, text=True, encoding="utf8",
            timeout=min(90, max(1, smoke.deadline - time.monotonic())), creationflags=flags,
        )
        assert read_result(warm, selected) == combined and live(smoke) == pid
        usage = smoke.root / "workspace-allow.tsv"
        workspace_env = {**smoke.env, "DQ_ALLOW_USAGE": str(usage), "DMB_CACHE_DIR": str(smoke.root / "cache")}
        workspace_args = [
            str(args.analyze), "check", "--native-dmbc", str(smoke.binary),
            "--root", str(root), "--no-selftest", "--ci", "--raw",
            "--lint", *selected,
        ]
        workspace = subprocess.run(
            workspace_args, cwd=smoke.root, env=workspace_env, capture_output=True,
            timeout=min(90, max(1, smoke.deadline - time.monotonic())), creationflags=flags,
        )
        assert workspace.returncode == 1, (workspace.returncode, workspace.stderr)
        assert workspace.stdout == combined["text"].encode("utf8"), workspace.stdout
        assert sorted(usage.read_text(encoding="utf8").splitlines()) == sorted(
            "\t".join(map(str, row)) for row in combined["allow_usage"]
        )
        assert live(smoke) == pid
        refused = subprocess.run(
            workspace_args + ["--changed-only"], cwd=smoke.root, env=workspace_env,
            capture_output=True, timeout=min(15, max(1, smoke.deadline - time.monotonic())),
            creationflags=flags,
        )
        assert refused.returncode == 2 and not refused.stdout, refused
        assert b"native workspace check supports only" in refused.stderr
        separate_usage = set()
        for name in POLICIES:
            single_path = write_request(QUESTIONS[name], policy_request(smoke, root, [name]))
            single = read_result(
                smoke.run(["analyze-check", str(single_path), "--jsonl"], success=False), [name]
            )
            assert not single["clean"], (name, single)
            assert section(single, name) == section(combined, name), name
            separate_usage.update(tuple(row) for row in single["allow_usage"])
            assert live(smoke) == pid
        assert set(map(tuple, combined["allow_usage"])) == separate_usage
        legacy_matches = compare_legacy(smoke, root, combined, flags)
        # Edit one setter while keeping this workspace and daemon resident.
        # Its old findings must disappear without changing the read reports.
        setter = root / "code/setter.dm"
        with setter.open("a", encoding="utf8", newline="\n") as output:
            output.write('    tracked_changed(src, "charge")\n')
        updated = read_result(
            smoke.run(["analyze-check", str(path), "--jsonl"], success=False), selected
        )
        assert live(smoke) == pid and not updated["clean"]
        assert updated["source_revision"] != combined["source_revision"]
        assert updated["policy_revision"] != combined["policy_revision"]
        assert "setter_publishes/no_publish" in section(combined, "setter_publishes")
        assert "setter_publishes: no_publish 0 OK" in section(updated, "setter_publishes")
        for name in ("sem/reads", "untracked_inputs"):
            assert section(updated, name) == section(combined, name), name
        assert updated["allow_usage"] == combined["allow_usage"]
        wrong = copy.deepcopy(request)
        wrong["build"]["policy_inputs"]["workspace_auxiliary"].pop()
        rejected = smoke.run(
            ["analyze-check", str(write_request("wrong", wrong)), "--jsonl"], success=False
        )
        assert rejected.returncode == 2 and not rejected.stdout
        assert not (root / "deepquarry.dmb").exists()
        assert not (root / "deepquarry.rsc").exists()
        print(json.dumps({"test": "actual_semantic_read_cohort", "passed": True, "same_daemon_pid": pid,
                          "compared_policies": POLICIES, "thin_client_matches": True,
                          "legacy_matches": legacy_matches, "stale_setter_finding_retracted": True,
                          "workspace_cli_matches": True}))
    finally:
        smoke.retire()


if __name__ == "__main__":
    main()
