#!/usr/bin/env python3
"""K4: subsystems with a fire() only on the core allowlist (doc/rewrite/completion_plan.md sec 3.6).

The MC is a thin kernel; the OM scheduler (SSbehaviours) is the only runtime scheduler for
gameplay. Periodic gameplay work is a lane on the OM global owner (code/datums/om/world_lanes.dm,
feature_lanes.dm) or a behaviour on an entity, never a new subsystem fire() loop. This lint fails
on any `/datum/controller/subsystem/<name>[/...]/fire(` definition whose <name> is not in CORE
below, unless the site carries `// ALLOW(subsystem_fire): <reason>` on its line or the comment
line above it (tools/ci/allow_annotations.py).

    python tools/ci/subsystem_fire_lint.py            # the CI check
    python tools/ci/subsystem_fire_lint.py --report   # every fire() and whether it is allowed
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from allow_annotations import allowed  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

# The kernel and the engines that own their own frame (sec 3.6, "Core subsystems that stay").
CORE = {
    "air",            # drives the Rust world step
    "asset_loading",
    "behaviours",     # the OM scheduler
    "chat",
    "dbcore",
    "garbage",
    "input",
    "ping",
    "profiler",
    "runechat",
    "server_maint",
    "statpanels",
    "tgui",
    "ticker",
    "time_track",
    "verb_manager",   # and its speech_controller subtype
    "vg",
    "vis_overlays",
}

FIRE = re.compile(r"^/datum/controller/subsystem/(\w+)(?:/\w+)*/fire\(")


def main(argv):
    report = "--report" in argv
    bad = []
    for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        with open(path, encoding="utf-8", errors="replace") as handle:
            raw = handle.read().split("\n")
        for number, line in enumerate(raw, 1):
            m = FIRE.match(line)
            if not m:
                continue
            name = m.group(1)
            if name == "proc":  # the base proc on /datum/controller/subsystem
                continue
            ok = name in CORE or allowed(raw, number, "subsystem_fire")
            if report:
                print("%s:%d  %s  %s" % (rel, number, name, "ok" if ok else "NOT ALLOWED"))
            if not ok:
                bad.append("%s:%d: SS%s has a fire() outside the core allowlist" % (rel, number, name))
    for problem in bad:
        print(problem)
    if bad:
        print("subsystem_fire_lint: move the periodic work onto an OM lane (world service or feature "
              "lane, code/datums/om/world_lanes.dm) or, for a kernel engine, add it to CORE here; a "
              "temporary keep takes `// ALLOW(subsystem_fire): <reason>`.")
        return 1
    print("subsystem_fire_lint: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
