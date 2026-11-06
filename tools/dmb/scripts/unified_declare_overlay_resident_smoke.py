#!/usr/bin/env python3
"""Small fixed-DME Declare overlay control through the existing public IPC."""
import argparse
import json
from pathlib import Path

from compare_original_generation import strict_json
from unified_daemon_smoke import Smoke
from unified_derived_resident_transport_smoke import live, report_request
from unified_original_generation_resident_smoke import document, inventory, verbatim


MANIFEST = """#define CAPABILITIES(T) ##T/__capabilities()
#include "code/engine/overlay_forms.dm"
#include "code/probe.dm"
#include "code/engine/_generated/declare.dm"
"""
SOURCE = """/datum/overlay_base
    var/datum/target
/datum/overlay_child
    parent_type = /datum/overlay_base
CAPABILITIES(/datum/overlay_child)
    ref_one(nameof(target))
"""
OUTPUT = "code/engine/_generated/declare.dm"
ROW = '\t.["/datum/overlay_child|target"] = /datum\n'


def request(smoke, root, label, *, check, overlay, roles=("declare",), progress=False):
    build = report_request(smoke, root)["build"]
    build["progress_enabled"] = progress
    build["policy_inputs"]["workspace_auxiliary"] = []
    build["policy_inputs"]["workspace_generators"] = list(roles)
    body = {"build": build, "check": check}
    if overlay:
        body["bootstrap"] = "declare_overlay"
    path = smoke.root / f"{label}.json"
    path.write_text(json.dumps(body), encoding="utf8", newline="\n")
    return smoke.run(["generate", str(path), "--jsonl"], success=False)


def query(smoke, root, label):
    path = smoke.root / f"{label}.json"
    path.write_text(json.dumps({
        "analysis_context": "original_analyze0290",
        "timeout_seconds": 30,
        "project": str(root / "deepquarry.dme"),
        "defines": {},
        "engine_template": None,
        "bootstrap_catalog": False,
        "queries": [],
        "source_queries": [],
    }), encoding="utf8", newline="\n")
    return smoke.run(["query", str(path)], success=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("binary", "scratch-root", "repository"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    smoke = Smoke(args.binary, args.scratch_root, args.repository)
    (smoke.root / "cache").mkdir()
    try:
        physical = smoke.root / "workspace"
        (physical / "code/engine").mkdir(parents=True)
        (physical / "tools/ci").mkdir(parents=True)
        (physical / "tools/ci/lint_scopes.toml").write_text("", encoding="utf8")
        (physical / "deepquarry.dme").write_text(MANIFEST, encoding="utf8", newline="\n")
        (physical / "code/probe.dm").write_text(SOURCE, encoding="utf8", newline="\n")
        (physical / "code/engine/overlay_forms.dm").write_text(
            "/proc/ref_one(name)\n    return null\n", encoding="utf8", newline="\n"
        )
        root = verbatim(physical)
        target = root / OUTPUT
        before = inventory(root)

        ordinary = request(smoke, root, "ordinary-cold", check=True, overlay=False)
        assert ordinary.returncode == 2 and not ordinary.stdout.strip(), ordinary
        wrong = request(smoke, root, "unrelated-role", check=False, overlay=True, roles=("deps",))
        assert wrong.returncode == 2 and not wrong.stdout.strip(), wrong
        assert "Declare-only Original Analyze" in wrong.stderr, wrong
        assert inventory(root) == before

        cold = request(smoke, root, "overlay-check", check=True, overlay=True, progress=True)
        check = document(cold, strict_json)
        completed = [line for line in cold.stderr.splitlines()
                     if line.startswith("frontend DeclarationParsing Completed:")]
        # The fixture emits a real typed row, so there must be both named-byte
        # parses. Check performs no final installed-source preparation.
        assert len(completed) == 2, (completed, cold.stderr)
        assert check["rows"] == [{"generator": "declare", "path": str(target), "state": "stale"}], check
        assert not check["committed"] and not check["changed"] and not check["cleanup"], check
        assert inventory(root) == before and not target.exists()
        pid = live(smoke)
        no_snapshot = query(smoke, root, "cold-snapshot")
        assert no_snapshot.returncode != 0 and not no_snapshot.stdout.strip(), no_snapshot

        write = document(request(smoke, root, "overlay-write", check=False, overlay=True), strict_json)
        assert write["rows"] == [{"generator": "declare", "path": str(target), "state": "written"}], write
        assert write["committed"] and write["changed"] == [str(target)] and not write["cleanup"], write
        installed = target.read_bytes()
        assert installed.count(ROW.encode("utf8")) == 1, installed
        assert b'/proc/declared_rel_var_types()\n\t. = list()\n' in installed, installed
        after = inventory(root)
        assert all(after[path] == value for path, value in before.items())
        # Installed-source preparation takes the existing build lock in this
        # directory. The lock itself has been released before the reply.
        assert set(after) - set(before) == {".dmbc", "code/engine/_generated", OUTPUT}, after
        assert not list((root / ".dmbc").iterdir())
        snapshot = query(smoke, root, "installed-snapshot")
        assert snapshot.returncode == 0, snapshot
        assert len(strict_json(snapshot.stdout)["revision"]) == 32, snapshot

        warm = document(request(smoke, root, "ordinary-warm", check=True, overlay=False), strict_json)
        assert warm["rows"] == [{"generator": "declare", "path": str(target), "state": "fresh"}], warm
        assert not warm["committed"] and not warm["changed"] and not warm["cleanup"], warm
        assert warm["diagnostics"] == write["diagnostics"], (warm, write)
        assert target.read_bytes() == installed and inventory(root) == after
        assert live(smoke) == pid
        print("NATIVE_DECLARE_OVERLAY_RESIDENT=stale/installed/fresh")
    finally:
        smoke.retire()


if __name__ == "__main__":
    main()
