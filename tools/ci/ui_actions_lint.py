#!/usr/bin/env python3
"""TSX act() calls against ui_<action> procs (doc/rewrite/dx_conventions.md §5).

For every DM type that sets `tgui_id = "Interface"` and defines `ui_<action>(mob/user, ...)` procs,
every `act('action', {k: ...})` in tgui/packages/tgui/interfaces/Interface(.tsx | /**) must:
  - name an action that has a ui_<action> proc on that type (or a parent), and
  - pass only keys that proc declares as arguments.
An argument name the proc doesn't declare is a runtime at dispatch; this catches it in CI.
Hosts still on the old declared model (no ui_ procs) are skipped until they migrate.

Two more rules (design review C1, C2), on every ui_<action> proc of a migrated host:
  C1 ui_unsent_param       every parameter except `user` is sent by some TSX act('<action>', {..})
                           of an interface that reaches the proc (the nearest tgui_id at or above
                           its type, and every host below it). A parameter no client sends is an
                           internal flag a client could still set by naming it: move it to an
                           internal proc.
  C2 ui_unvalidated_param  the first use of each parameter validates it: it is the first argument of
                           ui_number/ui_text/ui_choice/ui_ref/ui_bool(...), or `!!param`,
                           `switch(param)`, or `param ==/!= <constant>` ("text", a number, TRUE/FALSE/
                           null, an ALL_CAPS define). Skipped on the way: an assignment target
                           (`p = ui_number(p)`), a named-argument key, a bare truthiness test (`!p`,
                           `isnull(p)`). A parameter handed to a helper proc (on the host's type
                           chain, or global) passes when the helper's matching parameter passes the
                           same check (up to 3 levels). A parameter never used is fine.
Both are ratchets on a fingerprint baseline (tools/ci/ui_actions_baseline.txt), target 0; a
justified keep is `// ALLOW(ui_actions): <reason>` on the proc head (C1) or on the use (C2).

    python tools/ci/ui_actions_lint.py            # check, exit 1 on a mismatch
    python tools/ci/ui_actions_lint.py --selftest
    python tools/ci/ui_actions_lint.py --report   # every C1/C2 site
    python tools/ci/ui_actions_lint.py --seed     # (re)create the C1/C2 baseline
    python tools/ci/ui_actions_lint.py --update   # drop fixed sites from the baseline (never adds)
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "sys_rules"))
import _dx_dm as dm  # noqa: E402
from allow_annotations import allowed, check_sites, write_sites  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASELINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ui_actions_baseline.txt")
RULES = {
    "ui_unsent_param": "every ui_ parameter must be sent by some TSX act(); move internal flags to an internal proc (design review C1)",
    "ui_unvalidated_param": "validate the parameter first: ui_number/ui_text/ui_choice/ui_ref/ui_bool(param), or compare it to a constant (design review C2)",
}
VALIDATORS = ("ui_number", "ui_text", "ui_choice", "ui_ref", "ui_bool")
CONSTANT = r'(?:"[^"\n]*"|-?\d+(?:\.\d+)?|TRUE|FALSE|null|[A-Z][A-Z0-9_]+)\b'

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



def interface_of(ids, path):
    """The tgui_id at or nearest above path, or None."""
    by_type = {t: i for i, ts in ids.items() for t in ts}
    for anc in reversed(dm.ancestors(path)):
        if anc in by_type:
            return by_type[anc]
    return None


def served_interfaces(ids, path):
    """Interfaces whose windows can reach a ui_ proc defined on path."""
    out = set()
    top = interface_of(ids, path)
    if top:
        out.add(top)
    for interface, types in ids.items():
        for t in types:
            if t.startswith(path + "/"):
                out.add(interface)
    return out


def migrated_hosts(procs, ids):
    legacy = procs.get("__legacy__", {})
    out = []
    for interface, types in ids.items():
        for path in types:
            if any(path == t or path.startswith(t + "/") for t in legacy):
                continue
            if len(actions_of(procs, path)) == len(BUILTIN):
                continue
            out.append(path)
    return out


def ui_proc_defs(all_procs, procs, ids):
    """The ui_<action> Proc objects of migrated hosts (defined on a host, its ancestor or subtype)."""
    hosts = migrated_hosts(procs, ids)
    out = []
    for proc in all_procs:
        if not proc.name.startswith("ui_") or proc.name[3:] in HOOKS or proc.path in ("/datum", "/atom", "/"):
            continue
        if any(h == proc.path or h.startswith(proc.path + "/") or proc.path.startswith(h + "/") for h in hosts):
            out.append(proc)
    return out


def unsent_params(ui_procs, ids, acts_for=tsx_acts):
    """C1: [(proc, param)] for each parameter no act() of a reaching interface sends."""
    cache = {}
    out = []
    for proc in ui_procs:
        action = proc.name[3:]
        sent = set()
        for interface in served_interfaces(ids, proc.path):
            if interface not in cache:
                cache[interface] = list(acts_for(interface))
            for _rel, act, keys in cache[interface]:
                if act == action:
                    sent |= keys
        for param in proc.params:
            if param != "user" and param not in sent:
                out.append((proc, param))
    return out


def _uses(proc, param):
    """(line number, text, column) for each occurrence of param in the body, in order."""
    # Not a member (x.param), a path segment (/obj/param, var/obj/param/x) or a type::param.
    pattern = re.compile(r"(?<![\w./:])" + re.escape(param) + r"\b")
    for number, text in proc.lines():
        for m in pattern.finditer(text):
            yield number, text, m.start()


def first_bad_use(proc, param, find_proc, depth=0):
    """None when param's first real use validates it, else the offending line number."""
    for number, text, col in _uses(proc, param):
        before, after = text[:col], text[col + len(param):]
        if re.match(r"\s*=(?!=)", after):
            continue  # an assignment target or a named-argument key
        if re.search(r"(?<!!)!\s*$", before) and not re.match(r"\s*(?:==|!=|in\b)", after):
            continue  # a bare truthiness test
        if re.search(r"\bisnull\(\s*$", before):
            continue
        if re.search(r"!!\s*$", before):
            return None
        if re.search(r"\bswitch\s*\(\s*$", before) and re.match(r"\s*\)", after):
            return None
        if re.match(r"\s*(?:==|!=)\s*" + CONSTANT, after) or re.search(CONSTANT + r"\s*(?:==|!=)\s*$", before):
            return None
        call = dm.enclosing_call(text, col)
        if call and re.match(r"\s*[,)]", after):
            name, index, key = call
            if name in VALIDATORS and index == 0 and not key:
                return None
            helper = find_proc(proc.path, name)
            if helper and depth < 3:
                target = key if key else (helper.params[index] if index < len(helper.params) else None)
                if target and target in helper.params and first_bad_use(helper, target, find_proc, depth + 1) is None:
                    return None
        return number
    return None


def proc_finder(all_procs):
    table = {}
    for proc in all_procs:
        table.setdefault(proc.name, []).append(proc)

    def find(path, name):
        best = None
        for proc in table.get(name, ()):
            if proc.path == "/" or path == proc.path or path.startswith(proc.path + "/"):
                if best is None or len(proc.path) > len(best.path):
                    best = proc
        return best
    return find


def unvalidated_params(ui_procs, all_procs):
    """C2: [(proc, param, line)]."""
    find = proc_finder(all_procs)
    out = []
    for proc in ui_procs:
        for param in proc.params:
            if param == "user":
                continue
            bad = first_bad_use(proc, param, find)
            if bad:
                out.append((proc, param, bad))
    return out


def dx_sites(files, procs, ids, acts_for=tsx_acts):
    """{rule: [(rel, line)]} for C1/C2, ALLOW(ui_actions) honoured."""
    cleaned = {rel: dm.sanitize(lines) for rel, lines in files}
    raw = dict(files)
    all_procs = dm.procs(files, cleaned)
    ui_procs = ui_proc_defs(all_procs, procs, ids)
    sites = {rule: [] for rule in RULES}
    for proc, _param in unsent_params(ui_procs, ids, acts_for):
        if not allowed(raw[proc.rel], proc.line, "ui_actions"):
            sites["ui_unsent_param"].append((proc.rel, proc.line))
    for proc, _param, line in unvalidated_params(ui_procs, all_procs):
        if not allowed(raw[proc.rel], line, "ui_actions"):
            sites["ui_unvalidated_param"].append((proc.rel, line))
    return sites


DX_FIXTURE = """/obj/thing
	tgui_id = "Thing"
/obj/thing/proc/ui_go(mob/user, speed, force)
	speed = ui_number(speed, 0, 10)
	if(!speed)
		return
/obj/thing/proc/ui_pick(mob/user, mode, ref, flag)
	var/datum/D = find_ref(user, ref)
	if(!!flag)
		return
	switch(mode)
		if("a")
			return
/obj/thing/proc/find_ref(mob/user, ref)
	return ui_ref(ref, null, /datum)
/obj/thing/proc/ui_raw(mob/user, amount, name, kind, when)
	if(!amount)
		return
	var/x = amount + 1
	to_chat(user, name)
	if(kind == MODE_FAST)
		return
	helper(when)
/obj/thing/proc/helper(value)
	world << value
/obj/thing/subtype/proc/ui_sub(mob/user, level)
	var/obj/level/marker = null
	level = ui_bool(level)
"""


def dx_selftest():
    lines = DX_FIXTURE.split("\n")
    procs, ids = dm_tables(["\n".join(lines)])
    acts = {"Thing": [("x.tsx", "go", {"speed"}), ("x.tsx", "pick", {"mode", "ref", "flag"}),
                      ("x.tsx", "raw", {"amount", "name", "kind", "when"}), ("x.tsx", "sub", {"level"})]}
    sites = dx_sites([("x.dm", lines)], procs, ids, lambda i: acts.get(i, []))

    def at(snippet):
        return [k + 1 for k, line in enumerate(lines) if snippet in line][0]
    # C1: `force` on ui_go is sent by no act().
    assert sites["ui_unsent_param"] == [("x.dm", at("ui_go("))], sites
    # C2: ui_raw's amount (after the skipped !amount), name (raw to to_chat) and when (the helper
    # doesn't validate); kind compares to a define. ui_go/ui_pick/ui_sub are clean (ui_number after
    # the assignment target, a helper that ui_refs, !!flag, switch(mode), ui_bool after a path
    # segment that merely spells the name).
    got = sorted(n for _r, n in sites["ui_unvalidated_param"])
    assert got == sorted([at("var/x = amount + 1"), at("to_chat(user, name)"), at("helper(when)")]), got


def selftest():
    fixture = ["/obj/thing\n\ttgui_id = \"Thing\"\n/obj/thing/proc/ui_go(mob/user, speed)\n\treturn\n"]
    procs, ids = dm_tables(fixture)
    fake = lambda interface: [("x.tsx", "go", {"speed"}), ("x.tsx", "go", {"speed", "bogus"}), ("x.tsx", "stop", set())]
    problems = check(procs, ids, fake)
    assert len(problems) == 2, problems
    assert "bogus" in problems[0] and "stop" in problems[1], problems
    dx_selftest()
    print("ui_actions_lint selftest ok")
    return 0


def main(argv):
    if "--selftest" in argv:
        return selftest()
    files = []
    for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        with open(path, encoding="utf-8", errors="replace") as handle:
            files.append((rel, handle.read().split("\n")))
    procs, ids = dm_tables(["\n".join(lines) for _rel, lines in files])
    sites = dx_sites(files, procs, ids)
    header = ["ui_actions_lint C1/C2 baseline (design review C1, C2); shrink-only, target 0"]
    if "--report" in argv:
        for rule, found in sites.items():
            for rel, number in found:
                print("%s:%d: %s" % (rel, number, rule))
        return 0
    if "--seed" in argv or "--update" in argv:
        write_sites(BASELINE, header, sites, rules=list(RULES), shrink_only="--update" in argv)
        return 0
    problems = check(procs, ids)
    for p in problems:
        print(p)
    print("ui_actions_lint: %d problem(s)" % len(problems))
    failed = check_sites("ui_actions", sites, BASELINE, RULES)
    return 1 if problems or failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
