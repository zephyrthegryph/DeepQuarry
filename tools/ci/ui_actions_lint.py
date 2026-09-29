#!/usr/bin/env python3
"""TSX act() calls against act_<action> procs (doc/rewrite/dx_conventions.md §5).

For every DM type that sets `tgui_id = "Interface"` and answers actions with `act_<action>(mob/user,
...)` procs (legacy: `ui_<action>`), every `act('action', {k: ...})` in
tgui/packages/tgui/interfaces/Interface(.tsx | /**) must:
  - name an action the host answers: an act_<action> proc on that type (or a parent), or on a
    capability its capabilities() adds (directly, or through a bundle proc such as door()), and
  - pass only keys that proc declares as arguments.
Action names and keys are normalised as ui_action_key() does ("bolt-toggle", "boltToggle" and
"bolt_toggle" are one action). An argument name the proc doesn't declare is a runtime at dispatch;
this catches it in CI. Hosts that answer no actions this way yet are skipped until they migrate.

    python tools/ci/ui_actions_lint.py            # check, exit 1 on a mismatch
    python tools/ci/ui_actions_lint.py --selftest
"""
import glob
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
ACTION_PROC = re.compile(r"^(/[\w/]+?)/(?:proc/)?(ui|act)_(\w+)\(([^)]*)\)")
TGUI_ID = re.compile(r"^\s*tgui_id\s*=\s*\"(\w+)\"")
TYPE_HEAD = re.compile(r"^(/[\w/]+)\s*$")
GLOBAL_PROC = re.compile(r"^/proc/(\w+)\(")
CAPS_PROC = re.compile(r"^(/[\w/]+)/capabilities\(\)")
NEW_CAP = re.compile(r"\bvar(/datum/capability/[\w/]+?)/\w+\s*=\s*new\b|\bnew\s+(/datum/capability/[\w/]+)")
CALL = re.compile(r"\b([A-Za-z_]\w*)\(")
ACT = re.compile(r"act\(\s*'([\w-]+)'\s*(?:,\s*\{([^}]*)\})?")
KEY = re.compile(r"(?:^|,)\s*([A-Za-z_]\w*)\s*(?::|,|$)")
CAMEL = re.compile(r"([a-z0-9])([A-Z])")
# Actions every datum answers (code/modules/tgui/modal.dm).
BUILTIN = {"modal_open": {"id", "arguments"}, "modal_answer": {"id", "answer", "arguments"}, "modal_close": {"id"}}
# ui_* procs that are framework hooks, not actions.
HOOKS = {"allowed", "logged", "redirect", "prepare", "interface", "title", "window", "opening", "opened",
	"act_allowed", "nested_allowed", "nested_done", "slot_fragment", "modal_opened", "modal_answered",
	"types", "data", "status", "host", "close", "static_data"}
# Arguments the dispatcher supplies (code/datums/capabilities/ui_actions.dm ui_reserved_arg_names).
RESERVED = {"user", "holder", "src", "usr", "ui", "state"}
LEGACY = re.compile(r"^\s*DECLARE_UI\w*\(\s*(/[\w/]+)")


def action_key(raw):
    """ui_action_key(): camelCase boundaries and hyphens become underscores, lowercased."""
    return CAMEL.sub(r"\1_\2", raw).replace("-", "_").lower()


def dm_tables(files):
    procs = {}   # type -> action -> set(args); "__legacy__" -> DECLARE_UI types
    ids = {}     # interface -> [types]
    ctors = {}   # global proc -> capability type it builds
    calls = {}   # global proc -> names it calls
    caps = {}    # type -> names its capabilities() calls
    for text in files:
        current = None
        body = None  # the call set of the proc body being read
        for line in text.split("\n"):
            if body is not None and line[:1].isspace():
                body[1].update(CALL.findall(line))
                built = NEW_CAP.search(line)
                if built and body[0] is not None:
                    ctors.setdefault(body[0], built.group(1) or built.group(2))
                continue
            body = None
            head = TYPE_HEAD.match(line)
            if head:
                current = head.group(1)
                continue
            legacy = LEGACY.match(line)
            if legacy:
                procs.setdefault("__legacy__", {})[legacy.group(1)] = True
            g = GLOBAL_PROC.match(line)
            if g:
                body = (g.group(1), calls.setdefault(g.group(1), set()))
                current = None
                continue
            c = CAPS_PROC.match(line)
            if c:
                body = (None, caps.setdefault(c.group(1), set()))
                current = None
                continue
            m = ACTION_PROC.match(line)
            if m and not (m.group(2) == "ui" and m.group(3) in HOOKS) and m.group(1) not in ("/datum", "/atom"):
                args = set()
                for part in m.group(4).split(","):
                    name = part.strip().split("=")[0].strip().split("/")[-1]
                    if name and name not in RESERVED:
                        args.add(action_key(name))
                procs.setdefault(m.group(1), {})[action_key(m.group(3))] = args
                current = None
                continue
            if line and not line[0].isspace():
                current = None
            t = TGUI_ID.match(line)
            if t and current:
                ids.setdefault(t.group(1), []).append(current)
    return procs, ids, ctors, calls, caps


def actions_on(procs, path):
    out = {}
    parts = path.split("/")
    for i in range(2, len(parts) + 1):
        out.update(procs.get("/".join(parts[:i]), {}))
    return out


def capability_types(path, ctors, calls, caps):
    """The capability types path's capabilities() (and its parents') add, through bundles too."""
    names = set()
    parts = path.split("/")
    for i in range(2, len(parts) + 1):
        names |= caps.get("/".join(parts[:i]), set())
    seen = set()
    todo = list(names)
    found = set()
    while todo:
        name = todo.pop()
        if name in seen:
            continue
        seen.add(name)
        if name in ctors:
            found.add(ctors[name])
        elif name in calls:
            todo.extend(calls[name])
    return found


def actions_of(procs, path, ctors=None, calls=None, caps=None):
    out = dict(BUILTIN)
    for cap_type in sorted(capability_types(path, ctors or {}, calls or {}, caps or {})):
        out.update(actions_on(procs, cap_type))
    out.update(actions_on(procs, path))  # the host's own act_ wins, as at dispatch
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


def check(tables, acts_for=tsx_acts):
    procs, ids, ctors, calls, caps = tables
    problems = []
    for interface, types in ids.items():
        for path in types:
            if any(path == t or path.startswith(t + "/") for t in procs.get("__legacy__", {})):
                continue  # still on DECLARE_UI rows
            own = actions_of(procs, path, ctors, calls, caps)
            if len(own) == len(BUILTIN):
                continue  # not migrated: no act_ procs yet
            for rel, action, keys in acts_for(interface):
                key = action_key(action)
                if key not in own:
                    problems.append("%s: act('%s') has no act_%s on %s or its capabilities" % (rel, action, key, path))
                    continue
                extra = {action_key(k) for k in keys} - own[key]
                if extra:
                    problems.append("%s: act('%s') passes %s, which act_%s on %s doesn't declare" % (rel, action, ", ".join(sorted(extra)), key, path))
    return problems


def selftest():
    dm = ["/obj/thing\n\ttgui_id = \"Thing\"\n/obj/thing/proc/act_go(mob/user, speed)\n\treturn\n"
		"/obj/thing/capabilities()\n\t. = ..()\n\t. += bundle()\n"
		"/proc/bundle()\n\t. = list(cap_stopper())\n"
		"/proc/cap_stopper()\n\tvar/datum/capability/stopper/C = new\n\treturn C\n"
		"/datum/capability/stopper/proc/act_full_stop(mob/user, atom/holder, hard)\n\treturn\n"]
    tables = dm_tables(dm)
    fake = lambda interface: [("x.tsx", "go", {"speed"}), ("x.tsx", "go", {"speed", "bogus"}), ("x.tsx", "stop", set()),
		("x.tsx", "full-stop", {"hard"}), ("x.tsx", "fullStop", {"holder"})]
    problems = check(tables, fake)
    assert len(problems) == 3, problems
    assert "bogus" in problems[0] and "stop" in problems[1] and "holder" in problems[2], problems
    print("ui_actions_lint selftest ok")
    return 0


def main(argv):
    if "--selftest" in argv:
        return selftest()
    files = []
    for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
        with open(path, encoding="utf-8", errors="replace") as handle:
            files.append(handle.read())
    problems = check(dm_tables(files))
    for p in problems:
        print(p)
    print("ui_actions_lint: %d problem(s)" % len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
