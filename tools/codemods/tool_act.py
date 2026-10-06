#!/usr/bin/env python3
r"""Legacy tool procs (screwdriver_act, crowbar_act, wrench_act, wirecutter_act, multitool_act, welder_act) -> tool ops.

    python tools/codemods/tool_act.py [--check] [--sites] [--dirs code/game/objects/items ...]

The unit is a lineage: every override of `<q>_act` on a type and its subtypes (by path), across the whole tree. A lineage
converts only when every member does; then

    /T/<q>_act(mob/user, obj/item/tool)          ->   CAPABILITIES(T)
        body                                              op("use_<q>", tool(TOOL_Q), wait(0), then(PROC_REF(<q>_used)))
                                                      /T/proc/<q>_used(datum/act/op/A)
                                                          var/mob/user = A.actor
                                                          var/obj/item/tool = A.held
                                                          body

The op goes on the lineage's root only; a subtype's override becomes an override of the handler (`/T/sub/<q>_used(...)`),
so `..()` and virtual dispatch keep working. wait(0) keeps the legacy instant use (the tool profile would add 2-5 s);
the welder also says costs(RES_FUEL, 0) (the legacy procs spent their own fuel).

Returns (the legacy caller's reading of ITEM_INTERACT_*):
    ITEM_INTERACT_SUCCESS, TRUE, 1            -> OP_OK       (handled)
    ITEM_INTERACT_BLOCKING / _FAILURE         -> OP_OK       (handled, the click used up, no attack; nothing more said)
    ITEM_INTERACT_SKIP_TO_ATTACK, NONE, FALSE, 0, null, bare return, falling off the end
                                              -> OP_DECLINE  (the click goes on to the legacy attackby, as before)
    return ..()                               kept (a subtype calling its parent's handler)

Residue codes: banned_dir (another agent's area), external_call (something calls the proc), root_super (the root calls ..():
the base dispatcher), dot_used (`.`), return_expr (a return the table does not name), sleeps (do_after, sleep, spawn, input,
alert, tgui_*), local_A (a name `A` already used), key_taken (the op key exists on the type tree), parent_type (a type in
the lineage sets parent_type), nested (a def that is not a column-0 full path).
"""
import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _excl import excluded  # noqa: E402

EXCLUDED = excluded("tool_act")

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
QUALITIES = {
    "screwdriver": "TOOL_SCREWDRIVER",
    "crowbar": "TOOL_CROWBAR",
    "wrench": "TOOL_WRENCH",
    "wirecutter": "TOOL_WIRECUTTER",
    "multitool": "TOOL_MULTITOOL",
    "welder": "TOOL_WELDER",
}
BANNED = (
    "code/modules/organs/", "code/modules/body/", "code/modules/medical/", "code/datums/om/",
    "code/modules/atmospherics/", "code/ATMOSPHERICS/", "code/__defines/", "code/modules/unit_tests/", "code/tests/",
    "code/engine/", "code/_onclick/",
)
DEF_RE = re.compile(r"^(/[\w/]+?)/(" + "|".join(QUALITIES) + r")_act\((.*)\)\s*(//.*)?$")
SLEEPS = re.compile(r"\b(do_after|do_mob|sleep|spawn|input|alert|tgui_alert|tgui_input_\w+|tgui_input_list)\s*\(")
RET_RE = re.compile(r"^(\s*)return\b\s*(.*?)\s*(//.*)?$")
OK_VALUES = {"ITEM_INTERACT_SUCCESS", "TRUE", "1", "ITEM_INTERACT_BLOCKING", "ITEM_INTERACT_FAILURE",
             "ITEM_INTERACT_SUCCESS | ITEM_INTERACT_BLOCKING", "(ITEM_INTERACT_SUCCESS | ITEM_INTERACT_BLOCKING)"}
DECLINE_VALUES = {"", "ITEM_INTERACT_SKIP_TO_ATTACK", "NONE", "FALSE", "0", "null"}


def rel(p):
    return os.path.relpath(p, ROOT).replace("\\", "/")


def dm_files():
    for base, _dirs, files in os.walk(os.path.join(ROOT, "code")):
        _dirs[:] = [d for d in _dirs if d != "_generated"]  # build output (analyze gen), not source
        for f in files:
            if f.endswith(".dm"):
                yield os.path.join(base, f)


def read(p):
    with open(p, "r", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        return fh.read()


def write(p, text):
    with open(p, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        fh.write(text)


def nl_of(text):
    return "\r\n" if "\r\n" in text else "\n"


class Def:
    def __init__(self, path, line, typ, q, params):
        self.path, self.line, self.type, self.q, self.params = path, line, typ, q, params
        self.body = []  # (index, text)
        self.problems = []


def body_end(lines, i):
    """Index after the last line of the proc that starts at i (indented lines and blank lines; trailing blanks excluded)."""
    j = i + 1
    last = i
    while j < len(lines):
        l = lines[j]
        if l.strip() == "":
            j += 1
            continue
        if l[0] in "\t ":
            last = j
            j += 1
            continue
        break
    return last + 1


def strip_strings(l):
    """A string literal's text goes; its embedded expressions ("[user]") stay, as code."""
    return re.sub(r'"(?:[^"\\]|\\.)*"', lambda m: '"' + " ".join(re.findall(r"\[([^\]]*)\]", m.group(0))) + '"', l)


def parse_params(params):
    out = []
    for p in [x.strip() for x in params.split(",") if x.strip()]:
        p = p.split("=")[0].strip()
        parts = p.split("/")
        name = parts[-1]
        typ = "/".join(parts[:-1])
        out.append((name, typ))
    return out


def collect(files_text):
    defs = []
    callers = defaultdict(list)  # q -> (path, line, text, receiver type or None)
    for p, text in files_text.items():
        lines = text.splitlines()
        cur_type = None
        for i, l in enumerate(lines):
            m = DEF_RE.match(l)
            if m:
                d = Def(p, i, m.group(1), m.group(2), m.group(3))
                end = body_end(lines, i)
                d.body = list(range(i + 1, end))
                defs.append(d)
                cur_type = m.group(1)
                continue
            h = re.match(r"^(/[\w/]+?)(?:/proc|/verb)?/\w+\(", l)
            if h:
                cur_type = h.group(1)
            s = strip_strings(l)
            if s.lstrip().startswith("//"):
                continue
            for cm in re.finditer(r"(?:(\w+)\s*\.\s*)?\b(" + "|".join(QUALITIES) + r")_act\b", s):
                recv, q = cm.group(1), cm.group(2)
                rtype = cur_type
                if recv:
                    rtype = None
                    for k in range(i, max(-1, i - 200), -1):
                        vm = re.search(r"(?:var/|[(,]\s*)([\w/]+)/" + re.escape(recv) + r"\b", lines[k])
                        if vm:
                            rtype = "/" + vm.group(1).lstrip("/")
                            break
                    if rtype is None:
                        rtype = "@" + recv  # resolved tree-wide in main()
                callers[q].append((p, i, l, rtype))
    return defs, callers


def is_ancestor(a, b):
    return b != a and b.startswith(a + "/")


def main(argv):
    check = "--check" in argv
    sites = "--sites" in argv
    dirs = []
    if "--dirs" in argv:
        dirs = [d.rstrip("/") + "/" for d in argv[argv.index("--dirs") + 1:] if not d.startswith("--")]
    # --prefix /type: only lineages rooted at that type or below it (a wave over one family in shared directories)
    prefix = argv[argv.index("--prefix") + 1] if "--prefix" in argv else None
    files_text = {}
    for p in dm_files():
        t = read(p)
        if "_act" in t or "CAPABILITIES(" in t or "parent_type" in t:
            files_text[p] = t
    defs, callers = collect(files_text)
    by_q = defaultdict(list)
    for d in defs:
        by_q[d.q].append(d)

    # parent_type users
    parent_typed = set()
    for p, t in files_text.items():
        cur = None
        for l in t.splitlines():
            m = re.match(r"^(/[\w/]+)\s*$", l)
            if m:
                cur = m.group(1)
            if cur and re.match(r"^\s+parent_type\s*=", l):
                parent_typed.add(cur)

    # existing op keys, by the type whose CAPABILITIES block declares them: a key must be unique in a type tree
    key_sites = defaultdict(set)  # key -> owner types
    for p, t in files_text.items():
        owner = None
        for l in t.splitlines():
            cm = re.match(r"^CAPABILITIES\((/[\w/]+)\)", l)
            if cm:
                owner = cm.group(1)
                continue
            if l and l[0] not in "\t ":
                owner = None
            if owner:
                for m in re.finditer(r'op\("(use_\w+)"', l):
                    key_sites[m.group(1)].add(owner)

    # a receiver not declared near its call: a member var declared once in the tree
    var_types = defaultdict(set)
    var_decl_files = defaultdict(list)
    for p, t in files_text.items():
        # member declarations only (one tab in a type block)
        for m in re.finditer(r"^\tvar/(?:global/|static/|tmp/)?((?:obj|mob|atom|turf|area|datum)(?:/\w+)*)/(\w+)\b", t, re.M):
            var_types[m.group(2)].add("/" + m.group(1))
            var_decl_files[m.group(2)].append(("/" + m.group(1), p))
    for q in callers:
        fixed = []
        for p, i, l, rtype in callers[q]:
            if rtype and rtype.startswith("@"):
                ts = var_types.get(rtype[1:], set())
                if len(ts) > 1:  # several types declare it: the one declared beside the caller
                    near = {t for t, f in var_decl_files[rtype[1:]] if os.path.dirname(f) == os.path.dirname(p)}
                    ts = near or ts
                rtype = next(iter(ts)) if len(ts) == 1 else None
            fixed.append((p, i, l, rtype))
        callers[q] = fixed
    lineages = []
    for q, ds in by_q.items():
        types = {d.type for d in ds}
        roots = [d for d in ds if not any(is_ancestor(o, d.type) for o in types)]
        for r in roots:
            members = [d for d in ds if d.type == r.type or is_ancestor(r.type, d.type)]
            lineages.append((q, r, members))

    # base-dispatcher lines that are allowed to mention the procs
    def allowed_call(p, l):
        rp = rel(p)
        return rp == "code/_onclick/item_attack.dm"

    results = []
    test_callers = []
    ext_sites = []
    for q, root, members in lineages:
        problems = []
        if dirs and not any(rel(root.path).startswith(d) for d in dirs):
            continue
        if prefix and not (root.type == prefix or root.type.startswith(prefix + "/")):
            continue
        member_lines = {(m.path, m.line) for m in members}
        for m in members:
            rp = rel(m.path)
            if rp.startswith(BANNED):
                problems.append("banned_dir")
            if m.type in parent_typed:
                problems.append("parent_type")
            lines = files_text[m.path].splitlines()
            body = [lines[i] for i in m.body]
            code = [strip_strings(l) for l in body]
            joined = "\n".join(code)
            if re.search(r"(^|[^\w.])\.\s*(=|\||&|\+|-)|\breturn\s+\.\s*$|[(,]\s*\.\s*[),]", joined, re.M):
                problems.append("dot_used")
            if SLEEPS.search(joined):
                problems.append("sleeps")
            if re.search(r"\bA\b", joined) or any(n == "A" for n, _ in parse_params(m.params)):
                problems.append("local_A")
            # the root's `return ..()` reached the base proc, which only runs the legacy tool interactions: a decline reaches the same
            # path (the click goes on to the legacy handling); any other use of ..() at the root is residue
            if m is root and re.search(r"\.\.\(\)", re.sub(r"^\s*return \.\.\(\)\s*$", "", joined, flags=re.M)):
                problems.append("root_super")
            for l in code:
                rm = RET_RE.match(l)
                if rm:
                    val = rm.group(2)
                    if val in OK_VALUES or val in DECLINE_VALUES or val == "..()":
                        continue
                    problems.append("return_expr")
                elif "..()" in l and m is not root and not re.match(r"^\s*\.\.\(\)\s*$", l):
                    problems.append("return_expr")
        # callers: attributed by the receiver's type (the enclosing type for an unqualified call)
        for p, i, l, rtype in callers[q]:
            if (p, i) in member_lines or allowed_call(p, l):
                continue
            if rtype and not (rtype == root.type or is_ancestor(root.type, rtype) or is_ancestor(rtype, root.type)):
                continue
            if rel(p).startswith(("code/modules/unit_tests/", "code/tests/")) and rtype:
                test_callers.append((root.type, q, rel(p), i + 1))
                continue
            problems.append("external_call")
            ext_sites.append(f"{root.type}/{q}_act <- {rel(p)}:{i+1}")
        if f"{root.type}/{q}" in EXCLUDED:
            problems.append("excluded")
        key = f"use_{q}"
        if any(u == root.type or is_ancestor(u, root.type) or is_ancestor(root.type, u) for u in key_sites.get(key, ())):
            problems.append("key_taken")
        results.append((q, root, members, sorted(set(problems))))

    conv = [r for r in results if not r[3]]
    resid = [r for r in results if r[3]]
    print(f"tool_act: {len(conv)} lineages convert ({sum(len(r[2]) for r in conv)} procs){' (check)' if check else ''}; residue {len(resid)} lineages ({sum(len(r[2]) for r in resid)} procs)")
    codes = defaultdict(list)
    for q, root, members, probs in resid:
        for c in probs:
            codes[c].append(f"{root.type}/{q}_act  ({rel(root.path)})")
    for c, items in sorted(codes.items(), key=lambda kv: -len(kv[1])):
        print(f"    {c:<16} {len(items)}")
        if sites:
            for it in items:
                print(f"        {it}")
    if sites:
        for e in ext_sites:
            print(f"    external: {e}")
    conv_roots = {(r[1].type, r[0]) for r in conv}
    for t, q, p, ln in test_callers:
        if (t, q) in conv_roots:
            print(f"    test caller to rewrite: {t}/{q}_act <- {p}:{ln}")
    if check:
        return 0
    apply(files_text, conv)
    return 0


def handler_lines(m, root, lines, nl):
    """New text lines for one member."""
    params = parse_params(m.params)
    header = f"{m.type}/proc/{m.q}_used(datum/act/op/A)" if m is root else f"{m.type}/{m.q}_used(datum/act/op/A)"
    body = [lines[i] for i in m.body]
    code = "\n".join(strip_strings(l) for l in body)
    pre = []
    for idx, (name, typ) in enumerate(params[:2]):
        if not re.search(r"\b" + re.escape(name) + r"\b", code):
            continue
        src = "A.actor" if idx == 0 else "A.held"
        t = typ or ("mob" if idx == 0 else "obj/item")
        pre.append(f"\tvar/{t}/{name} = {src}")
    out = [header] + pre
    for l in body:
        rm = RET_RE.match(strip_strings(l))
        if rm and RET_RE.match(l):
            orig = RET_RE.match(l)
            val = rm.group(2)
            comment = (" " + orig.group(3)) if orig.group(3) else ""
            if val in OK_VALUES:
                l = f"{orig.group(1)}return OP_OK{comment}"
            elif val in DECLINE_VALUES or (val == "..()" and m is root):
                l = f"{orig.group(1)}return OP_DECLINE{comment}"
        out.append(l)
    # falling off the end answered NONE: the click went on to attackby
    last = [l for l in body if l.strip() and not l.strip().startswith("//")]
    if not last or not re.match(r"^\treturn\b", last[-1]):
        out.append("\treturn OP_DECLINE")
    return out


def op_entry(q):
    extra = ", costs(RES_FUEL, 0)" if q == "welder" else ""
    return f'\top("use_{q}", tool({QUALITIES[q]}), wait(0){extra}, then(PROC_REF({q}_used)))'


def find_block(lines, typ):
    for i, l in enumerate(lines):
        if l.rstrip() == f"CAPABILITIES({typ})":
            j = i + 1
            while j < len(lines) and (lines[j].strip() == "" or lines[j][0] in "\t "):
                j += 1
            k = j
            while k - 1 > i and lines[k - 1].strip() == "":
                k -= 1
            return i, k
    return None


def apply(files_text, conv):
    edits = defaultdict(list)  # path -> list of (start, end, newlines)
    inserts = defaultdict(list)  # path -> list of (index, newlines) inserted before index
    blocks_wanted = defaultdict(list)  # root type -> entries
    root_site = {}
    for q, root, members, _ in conv:
        for m in members:
            lines = files_text[m.path].splitlines()
            new = handler_lines(m, root, lines, None)
            edits[m.path].append((m.line, m.body[-1] + 1 if m.body else m.line + 1, new))
        blocks_wanted[root.type].append(op_entry(q))
        root_site.setdefault(root.type, (root.path, root.line))
    # existing blocks anywhere
    for typ, entries in blocks_wanted.items():
        placed = False
        for p, t in files_text.items():
            lines = t.splitlines()
            b = find_block(lines, typ)
            if b:
                inserts[p].append((b[1], entries))
                placed = True
                break
        if not placed:
            p, line = root_site[typ]
            inserts[p].append((line, [f"CAPABILITIES({typ})"] + entries + [""]))
    for p in set(edits) | set(inserts):
        text = files_text[p]
        nl = nl_of(text)
        trailing = text.endswith(("\n", "\r\n"))
        lines = text.splitlines()
        ops = [(s, e, n, 1) for s, e, n in edits[p]] + [(i, i, n, 0) for i, n in inserts[p]]
        # apply bottom-up; at equal index the insert goes before the edit
        for s, e, n, _kind in sorted(ops, key=lambda o: (o[0], o[3]), reverse=True):
            lines[s:e] = n
        out = nl.join(lines) + (nl if trailing else "")
        write(p, out)
        print(f"    wrote {rel(p)}")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
