#!/usr/bin/env python3
"""Cold, warm, and edited selected reports through one private resident dmbc."""
import argparse
import copy
import hashlib
import json
import os
import re
import subprocess
import time
from pathlib import Path

from unified_daemon_smoke import Smoke
from unified_derived_resident_transport_smoke import live, report_request

NOTICE = "actual_selected_report_prepare_notice"
POLICIES = ["allow_annotations", "cooldown", "notice_publisher", "report_in_catch", "scheduler", "silicon_entry"]
SOURCE = """#define isAI(A) istype(A, /mob/living/silicon/ai)
/datum/act
    var/actor
/datum/act/op
/mob/living/silicon/ai
/obj/machinery
"""


def call(smoke, request, name, clean):
    path = smoke.root / (name + ".json")
    path.write_text(json.dumps(request), encoding="utf8")
    result = smoke.run(["analyze-exclusions", str(path), "--report-batch"], success=clean)
    assert result.returncode == (0 if clean else 1), (result.returncode, result.stderr)
    header, body = result.stdout.split("\n", 1)
    header = json.loads(header)
    assert header["schema"] == "native-analyze-exclusions-batch-v1" and header["roster"] == "with_silicon", header
    assert header["clean"] is clean, header
    assert len(body.encode("utf8")) == header["report"]["length"], header
    assert re.fullmatch(r"[0-9a-f]{32}", header["report"]["hash"]), header
    assert all(re.fullmatch(r"[0-9a-f]{32}", header["frame"][key]) for key in
               ("semantic_revision", "source_revision", "policy_revision")), header
    assert result.stderr.count(NOTICE) == 1 and NOTICE not in body, (header, result.stderr)
    assert header["diagnostics"]["length"] > 0, header
    return header, body, result.stderr


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("binary", "scratch-root", "repository", "configuration", "registry", "analyze"):
        parser.add_argument(f"--{name}", required=True, type=Path)
    args = parser.parse_args()
    smoke = Smoke(args.binary, args.scratch_root, args.repository)
    smoke.env.update(DMB_DAEMON_MAX_WORKERS="1", LOCALAPPDATA=str(smoke.root / "local"))
    image = hashlib.sha256(smoke.binary.read_bytes()).hexdigest()
    try:
        root = smoke.root / "fixture"
        (root / "code").mkdir(parents=True)
        (root / "maps").mkdir()
        (root / "tools/ci").mkdir(parents=True)
        (smoke.root / "cache").mkdir()
        config = root / "tools/ci/lint_scopes.toml"
        config.write_bytes(args.configuration.read_bytes())
        manifest = root / "deepquarry.dme"
        manifest.write_text(f'#warn {NOTICE}\n#include "code/probe.dm"\n#include "maps/.actor.dm"\n#include "maps/allowed.dm"\n', encoding="utf8", newline="\n")
        source = root / "code/probe.dm"
        source.write_text(SOURCE + "    var/is_ai_remote_interface = 1\n/proc/probe()\n" + "    sleep(2)\n" * 150,
                          encoding="utf8", newline="\n")
        hidden = root / "maps/.actor.dm"
        hidden.write_text("/obj/machinery/proc/hidden_actor(datum/act/op/A)\n    return isAI(A.actor)\n", encoding="utf8", newline="\n")
        (root / "maps/allowed.dm").write_text(
            "/obj/machinery/proc/allowed_actor(datum/act/op/A)\n"
            "    return isAI(A.actor) // ALLOW(silicon_entry): this fixture exercises actual map actor use\n"
            "/datum/map_only\n    var/is_ai_remote_interface = 1\n", encoding="utf8", newline="\n")
        build = report_request(smoke, root)["build"]
        build["policy_inputs"]["workspace_auxiliary"] = []
        build["policy_inputs"]["workspace"]["recursive_roots"].append(str(root / "maps"))
        all_policies = json.loads(args.registry.read_text(encoding="utf8"))
        assert set(POLICIES).issubset(all_policies)
        request = {"build": build, "exclusions": ["-" + name for name in all_policies if name not in POLICIES]}
        cold = call(smoke, request, "cold", clean=False)
        assert len(cold[1].encode("utf8")) > 8192, "real report must require more than one fragment"
        assert "maps/.actor.dm:2: [silicon_entry/handler_actor_check]" in cold[1]
        assert "code/probe.dm:7: [silicon_entry/shortcut]" in cold[1]
        assert "maps/allowed.dm:" not in cold[1] and "allow annotations: 0 unused" in cold[1]
        pid = live(smoke)
        assert call(smoke, request, "warm", clean=False) == cold and live(smoke) == pid
        source.write_text(SOURCE, encoding="utf8", newline="\n")
        hidden.write_text("/obj/machinery/proc/hidden_actor(datum/act/op/A)\n    return 0\n", encoding="utf8", newline="\n")
        edited = call(smoke, request, "edited", clean=True)
        assert edited[0]["frame"]["source_revision"] != cold[0]["frame"]["source_revision"] and live(smoke) == pid
        assert "[silicon_entry/" not in edited[1] and "[scheduler/" not in edited[1]
        analyze = args.analyze.resolve(strict=True)
        scratch = smoke.root / "thin-client"
        scratch.mkdir()
        request_path = smoke.root / "edited.json"
        flags = subprocess.CREATE_NO_WINDOW | subprocess.BELOW_NORMAL_PRIORITY_CLASS if os.name == "nt" else 0

        def thin(roster):
            return subprocess.run([str(analyze), "native-exclusions", "--dmbc", str(smoke.binary),
                                   "--scratch", str(scratch), "--roster", roster, str(request_path)],
                                  cwd=smoke.root, env=smoke.env, capture_output=True, text=True,
                                  encoding="utf8", timeout=min(90, max(1, smoke.deadline - time.monotonic())),
                                  creationflags=flags)

        valid = thin("with-silicon")
        assert valid.returncode == 0, (valid.returncode, valid.stderr)
        header, body = valid.stdout.split("\n", 1)
        assert (json.loads(header), body, valid.stderr) == edited and live(smoke) == pid
        foreign = thin("base")
        assert foreign.returncode == 2 and not foreign.stdout and NOTICE not in foreign.stderr
        assert not list(scratch.iterdir()), "verified transport scratch should close and disappear"
        denied = copy.deepcopy(request)
        denied["exclusions"].remove("-image_dir_after_build")
        inexact = copy.deepcopy(request)
        inexact["build"]["exact_inputs"] = False
        unbounded = copy.deepcopy(request)
        unbounded["build"]["timeout_seconds"] = None
        for name, data in [("unsupported", denied), ("inexact", inexact),
                           ("unbounded", unbounded), ("missing-config", request)]:
            if name == "missing-config":
                config.unlink()
            path = smoke.root / (name + ".json")
            path.write_text(json.dumps(data), encoding="utf8")
            result = smoke.run(["analyze-exclusions", str(path), "--report-batch"], success=False)
            assert result.returncode == 2 and not result.stdout and NOTICE not in result.stderr, result
        assert not manifest.with_suffix(".dmb").exists() and hashlib.sha256(smoke.binary.read_bytes()).hexdigest() == image
        print(json.dumps({"test": "selected_exclusions_resident", "passed": True, "same_daemon_pid": pid,
                          "report_bytes": cold[0]["report"]["length"], "calls": smoke.calls}))
    finally:
        smoke.retire()


if __name__ == "__main__":
    main()
