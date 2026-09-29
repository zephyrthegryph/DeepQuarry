#!/usr/bin/env python3
"""TSX act() calls against ui_<action> procs (doc/rewrite/dx_conventions.md §5).

For every DM type that sets `tgui_id = "Interface"` and defines `ui_<action>(mob/user, ...)` procs,
every `act('action', {k: ...})` in tgui/packages/tgui/interfaces/Interface(.tsx | /**) must:
  - name an action that has a ui_<action> proc on that type (or a parent), and
  - pass only keys that proc declares as arguments.
An argument name the proc doesn't declare is a runtime at dispatch; this catches it in CI.
Hosts still on the old declared model (no ui_ procs) are skipped until they migrate.

    python tools/ci/ui_actions_lint.py            # check, exit 1 on a mismatch
    python tools/ci/ui_actions_lint.py --selftest
"""
import glob
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
UI_PROC = re.compile(r"^(/[\w/]+?)/(?:proc/)?ui_(\w+)\(([^)]*)\)")
TGUI_ID = re.compile(r"^\s*tgui_id\s*=\s*\"(\w+)\"")
TYPE_HEAD = re.compile(r"^(/[\w/]+)\s*$")
ACT = re.compile(r"act\(\s*'(\w+)'\s*(?:,\s*\{([^}]*)\})?")
KEY = re.compile(r"(?:^|,)\s*([A-Za-z_]\w*)\s*(?::|,|$)")
# Actions every datum answers (code/modules/tgui/modal.dm).
BUILTIN = {"modal_open": {"id", "arguments"}, "modal_answer": {"id", "answer", "arguments"}, "modal_close": {"id"}}
# ui_* procs that are framework hooks, not actions.
HOOKS = {"allowed", "logged", "redirect", "prepare", "interface", "title", "window", "opening", "opened",
	"act_allowed", "nested_allowed", "nested_done", "slot_fragment", "modal_opened", "modal_answered",
	"types", "data", "status", "host", "close", "static_data"}
LEGACY = re.compile(r"^\s*DECLARE_UI\w*\(\s*(/[\w/]+)")


def dm_tables(files):
    procs = {}   # type -> action -> set(args)
    ids = {}     # interface -> [types]
    for text in files:
        current = None
        for line in text.split("\n"):
            head = TYPE_HEAD.match(line)
            if head:
                current = head.group(1)
                continue
            legacy = LEGACY.match(line)
            if legacy:
                procs.setdefault("__legacy__", {})[legacy.group(1)] = True
            m = UI_PROC.match(line)
            if m and m.group(2) not in HOOKS and m.group(1) not in ("/datum", "/atom"):
                args = set()
                for part in m.group(3).split(","):
                    name = part.strip().split("=")[0].strip().split("/")[-1]
                    if name and name != "user":
                        args.add(name)
                procs.setdefault(m.group(1), {})[m.group(2)] = args
                current = None
                continue
            if line and not line[0].isspace():
                current = None
            t = TGUI_ID.match(line)
            if t and current:
                ids.setdefault(t.group(1), []).append(current)
    return procs, ids


def actions_of(procs, path):
    out = dict(BUILTIN)
    parts = path.split("/")
    for i in range(2, len(parts) + 1):
        out.update(procs.get("/".join(parts[:i]), {}))
    return out


def tsx_acts(interface):
    base = os.path.join(ROOT, "tgui", "packages", "tgui", "interfaces")
    paths = glob.glob(os.path.join(base, interface + ".tsx")) + glob.glob(os.path.join(base, interface, "**", "*.tsx"), recursive=True)
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        for m in ACT.finditer(text):
            keys = set(KEY.findall(m.group(2) or ""))
            yield os.path.relpath(path, ROOT), m.group(1), keys


def check(procs, ids, acts_for=tsx_acts):
    problems = []
    for interface, types in ids.items():
        for path in types:
            if any(path == t or path.startswith(t + "/") for t in procs.get("__legacy__", {})):
                continue  # still on DECLARE_UI rows
            own = actions_of(procs, path)
            if len(own) == len(BUILTIN):
                continue  # not migrated: no ui_ procs yet
            for rel, action, keys in acts_for(interface):
                if action not in own:
                    problems.append("%s: act('%s') has no ui_%s on %s" % (rel, action, action, path))
                    continue
                extra = keys - own[action]
                if extra:
                    problems.append("%s: act('%s') passes %s, which ui_%s on %s doesn't declare" % (rel, action, ", ".join(sorted(extra)), action, path))
    return problems


def selftest():
    dm = ["/obj/thing\n\ttgui_id = \"Thing\"\n/obj/thing/proc/ui_go(mob/user, speed)\n\treturn\n"]
    procs, ids = dm_tables(dm)
    fake = lambda interface: [("x.tsx", "go", {"speed"}), ("x.tsx", "go", {"speed", "bogus"}), ("x.tsx", "stop", set())]
    problems = check(procs, ids, fake)
    assert len(problems) == 2, problems
    assert "bogus" in problems[0] and "stop" in problems[1], problems
    print("ui_actions_lint selftest ok")
    return 0


def main(argv):
    if "--selftest" in argv:
        return selftest()
    files = []
    for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
        with open(path, encoding="utf-8", errors="replace") as handle:
            files.append(handle.read())
    procs, ids = dm_tables(files)
    problems = check(procs, ids)
    for p in problems:
        print(p)
    print("ui_actions_lint: %d problem(s)" % len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
