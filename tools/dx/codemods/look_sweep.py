#!/usr/bin/env python3
r"""The draw sweep: legacy appearance -> draw(look) over tracked state (doc/rewrite/codemod_rules.md, "The draw sweep").

    python tools/dx/codemods/look_sweep.py dead [--apply] [--sites] [--paths prefix ...]

dead
    Removes the `update_icon()` calls that do nothing. The base /atom/update_icon() only re-applies a legacy appearance
    declaration (decl_appearance_apply()), so a call whose receiver is a type with no drawing declaration (APPEARANCE_TEMPLATE,
    _LEVEL, _EMISSIVE, _SLOT, DECLARE_APPEARANCE, DECLARE_APPEARANCE_PROC) and no update_icon() override anywhere in its
    chain (its ancestors, itself and every subtype, following parent_type) is a no-op: a draw(look) type is redrawn by its
    tracked state and drawn at init by its first refresh. The receiver is the proc's own type for `update_icon()` /
    `src.update_icon()`, or the declared type of a typed local or parameter for `X.update_icon()` / `X?.update_icon()`.

    Statement forms removed: the call alone on its line, and `if(cond) update_icon()` when cond is side-effect free and no
    `else` follows. A block left empty by the removal goes too when its opener is side-effect free (`if(...)` with no `else`
    after it, `else`, a `for(var/x in ...)` loop); otherwise the call stays (residue `empty_block`).
    Unit tests and the engine are not edited. Idempotent. Report: removed calls by folder, residue by code.
"""
import argparse
import collections
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "codemods"))
sys.path.insert(0, HERE)
from dmlib import File, strip_code  # noqa: E402

DRAW_DECL = re.compile(r"^(APPEARANCE_TEMPLATE|APPEARANCE_LEVEL|APPEARANCE_EMISSIVE|APPEARANCE_SLOT|DECLARE_APPEARANCE|DECLARE_APPEARANCE_PROC)\((/[\w/]+)")
UI_DEF = re.compile(r"^(/[\w/]+?)/(?:proc/)?update_icon\(")
HDR = re.compile(r"^(/[\w/]+?)/(?:proc/|verb/)?(\w+)\(")
PARENT_TYPE = re.compile(r"^\s+parent_type\s*=\s*(/[\w/]+)")
CALL_ALONE = re.compile(r"^(?:(?:src|([A-Za-z_]\w*))\s*\??\.\s*)?update_icon\(\s*\)$")
IF_CALL = re.compile(r"^if\s*\((.*)\)\s*(?:(?:src|([A-Za-z_]\w*))\s*\??\.\s*)?update_icon\(\s*\)$")
ATOM_ROOTS = ("/atom", "/obj", "/mob", "/turf", "/area")
NO_EDIT = ("code/modules/unit_tests/", "code/tests/", "code/engine/", "code/__defines/", "code/_generated/", "code/modules/benchmarks/")
PURE_CALLS = {
    "istype", "isnull", "length", "LAZYLEN", "LAZYACCESS", "ismob", "isobj", "isturf", "isarea", "isliving", "iscarbon", "ishuman",
    "isrobot", "issilicon", "isitem", "ismachinery", "isAI", "QDELETED", "QDELING", "isnum", "istext", "islist", "ispath", "isatom",
    "ismovable", "isclient", "get_turf", "isspace", "initial", "round", "max", "min", "abs", "HAS_TRAIT", "isopenturf",
}


def code_files():
    out = []
    for base, _dirs, names in os.walk(os.path.join(ROOT, "code")):
        for n in names:
            if n.endswith(".dm"):
                out.append(os.path.relpath(os.path.join(base, n), ROOT).replace("\\", "/"))
    return sorted(out)


def ancestors(t, parent_override):
    out = []
    seen = set()
    while t and t not in seen:
        seen.add(t)
        out.append(t)
        if t in parent_override:
            t = parent_override[t]
        elif t.count("/") > 1:
            t = t.rsplit("/", 1)[0]
        else:
            t = None
    return out


class Chains:
    """Which types draw through a legacy declaration or an update_icon() override somewhere in their chain."""

    def __init__(self, files):
        self.drawing = set()
        self.parent_override = {}
        for f in files.values():
            cur = None
            for line in f.lines:
                m = DRAW_DECL.match(line)
                if m:
                    self.drawing.add(m.group(2))
                m = UI_DEF.match(line)
                if m:
                    self.drawing.add(m.group(1))
                if line and line[0] not in " \t":
                    hm = re.match(r"^(/[\w/]+)\s*(//.*)?$", line)
                    cur = hm.group(1) if hm else None
                elif cur:
                    pm = PARENT_TYPE.match(line)
                    if pm:
                        self.parent_override[cur] = pm.group(1)
        self.above_drawing = set()
        for d in self.drawing:
            self.above_drawing.update(ancestors(d, self.parent_override))
        self.cache = {}

    def live(self, t):
        """TRUE when update_icon() on a T (or any subtype) can draw something."""
        if t not in self.cache:
            self.cache[t] = t in self.above_drawing or any(a in self.drawing for a in ancestors(t, self.parent_override))
        return self.cache[t]


def pure(cond):
    c = re.sub(r'"(?:[^"\\]|\\.)*"', '""', cond)
    if re.search(r"(?<![=!<>])=(?!=)|\+\+|--", c):
        return False
    for name in re.findall(r"([A-Za-z_][\w]*)\s*\(", c):
        if name not in PURE_CALLS:
            return False
    return True


def indent_of(line):
    return len(line) - len(line.lstrip(" \t"))


def typed_names(header, body_codes):
    """name -> declared type of the proc's parameters and locals (`obj/item/I`, `var/obj/item/I`)."""
    names = {}
    i = header.find("(")
    if i >= 0:
        for pm in re.finditer(r"(?:var/)?((?:[a-z_]\w*/)+)([A-Za-z_]\w*)\s*(?=[,)=]|\s+as\b)", header[i:]):
            names[pm.group(2)] = "/" + pm.group(1).rstrip("/")
    for code in body_codes:
        for vm in re.finditer(r"\bvar/((?:[a-z_]\w*/)+)([A-Za-z_]\w*)", code):
            names[vm.group(2)] = "/" + vm.group(1).rstrip("/")
    return names


def walk_calls(args, files, decide, removed, residue, sites):
    """Visits every update_icon() statement of the editable files. decide(rel, ptype, pname, recv, t) returns "delete",
    ("replace", text for the call), ("after", statement to add after it) or None. Deleting a call deletes a block it leaves
    empty when the block's opener is side-effect free."""
    for rel, f in files.items():
        if rel.startswith(NO_EDIT) or not any(rel.startswith(p) for p in (args.paths or ["code/"])):
            continue
        lines = f.lines
        n = len(lines)
        i = 0
        while i < n:
            m = HDR.match(lines[i]) if lines[i] and lines[i][0] not in " \t" else None
            if not m or "=" in strip_code(lines[i]).split("(")[0]:
                i += 1
                continue
            ptype, pname = m.group(1), m.group(2)
            j = i + 1
            while j < n and (lines[j].strip() == "" or lines[j][0] in " \t"):
                j += 1
            body = list(range(i + 1, j))
            codes = {k: strip_code(lines[k]).strip() for k in body}
            names = typed_names(strip_code(lines[i]), codes.values())
            drop = set()
            inserts = {}
            for k in body:
                code = codes[k]
                if "update_icon" not in code:
                    continue
                ma = CALL_ALONE.match(code)
                mi = None if ma else IF_CALL.match(code)
                if not ma and not mi:
                    if re.search(r"(?<![\w.])update_icon\(\s*\)", code) or re.search(r"\.\s*update_icon\(\s*\)", code):
                        residue["other_form"] += 1
                    continue
                recv = (ma or mi).group(2 if mi else 1)
                if recv is None:
                    t = None if ptype.startswith("/proc") else ptype
                else:
                    t = names.get(recv)
                if not t or not t.startswith(ATOM_ROOTS):
                    continue
                action = decide(rel, ptype, pname, recv, t, strip_code(lines[i]))
                if action is None:
                    continue
                folder = "/".join(rel.split("/")[:3])
                if isinstance(action, tuple) and action[0] == "replace":
                    raw = lines[k]
                    lines[k] = re.sub(r"(?:(?:src|[A-Za-z_]\w*)\s*\??\.\s*)?update_icon\(\s*\)", action[1], raw, count=1)
                    f.dirty = True
                    removed[folder] += 1
                    sites.append("%s:%d %s -> %s" % (rel, k + 1, code, action[1]))
                    continue
                if isinstance(action, tuple) and action[0] == "after":
                    if not ma:
                        residue["after_needs_block"] += 1
                        continue
                    nxt = next((x for x in range(k + 1, j) if codes[x]), None)
                    if nxt is not None and codes[nxt] == action[1]:
                        continue
                    inserts[k] = re.match(r"^[ \t]*", lines[k]).group(0) + action[1]
                    removed[folder] += 1
                    sites.append("%s:%d %s + %s" % (rel, k + 1, code, action[1]))
                    continue
                if mi:
                    if not pure(mi.group(1)):
                        residue["impure_condition"] += 1
                        continue
                    nxt = next((x for x in range(k + 1, j) if codes[x]), None)
                    if nxt is not None and indent_of(lines[nxt]) == indent_of(lines[k]) and re.match(r"^else\b", codes[nxt]):
                        residue["else_follows"] += 1
                        continue
                # the call (and any block it leaves empty) goes
                plan = {k}
                ok = True
                cur = k
                while True:
                    ind = indent_of(lines[cur])
                    prev = next((x for x in range(cur - 1, i, -1) if codes[x] and x not in plan and x not in drop), None)
                    nxt = next((x for x in range(cur + 1, j) if codes[x] and x not in plan and x not in drop), None)
                    opener = prev is not None and indent_of(lines[prev]) < ind
                    sibling_after = nxt is not None and indent_of(lines[nxt]) >= ind
                    sibling_before = prev is not None and indent_of(lines[prev]) >= ind
                    if sibling_before or sibling_after or prev is None:
                        break  # the block keeps a statement (or this is the proc body)
                    if not opener:
                        break
                    oc = codes[prev]
                    after_opener = nxt is not None and indent_of(lines[nxt]) == indent_of(lines[prev]) and re.match(r"^else\b", codes[nxt])
                    mo = re.match(r"^(if|else if)\s*\((.*)\)$", oc)
                    if mo and pure(mo.group(2)) and not after_opener:
                        plan.add(prev)
                        cur = prev
                        continue
                    if oc == "else":
                        plan.add(prev)
                        cur = prev
                        continue
                    if re.match(r"^for\s*\(\s*var/[\w/]+\s+in\s+.*\)$", oc) and pure(oc[3:]):
                        plan.add(prev)
                        cur = prev
                        continue
                    ok = False
                    break
                if not ok:
                    residue["empty_block"] += 1
                    continue
                drop |= plan
                removed[folder] += 1
                sites.append("%s:%d %s" % (rel, k + 1, code))
            if drop or inserts:
                for k in sorted(set(drop) | set(inserts), reverse=True):
                    if k in drop:
                        del lines[k]
                    else:
                        lines.insert(k + 1, inserts[k])
                f.dirty = True
                n = len(lines)
                j += len(inserts) - len(drop)
            i = j
        if f.dirty and args.apply:
            f.save()


def report(label, args, removed, residue, sites):
    total = sum(removed.values())
    print("look_sweep %s: %d update_icon() calls %s; residue %s" % (label, total, "rewritten" if args.apply else "found", dict(residue)))
    for folder, c in removed.most_common():
        print("    %4d %s" % (c, folder))
    if args.sites:
        for s in sites:
            print("    " + s)


def run_dead(args):
    files = {rel: File(rel) for rel in code_files()}
    chains = Chains(files)
    removed, residue, sites = collections.Counter(), collections.Counter(), []
    walk_calls(args, files, lambda rel, ptype, pname, recv, t, header: None if chains.live(t) else "delete", removed, residue, sites)
    report("dead", args, removed, residue, sites)
    return 0


def run_calls(args):
    """After `convert --apply --report R`: the update_icon() calls on the converted components' types (see look_convert)."""
    import json
    rep = json.load(open(args.report)) if args.report else {"converted": []}
    files = {rel: File(rel) for rel in code_files()}
    chains = Chains(files)
    ix = None
    if args.all:
        import look_convert
        ix = look_convert.Index(ROOT, list(files))
    member_of = {}
    for c in rep["converted"]:
        for t in c["types"]:
            member_of[t] = c
    po = chains.parent_override
    removed, residue, sites = collections.Counter(), collections.Counter(), []

    def comp_of(t):
        for a in ancestors(t, po):
            if a in member_of:
                return member_of[a]
        return None

    def below(t):
        """The converted components with a member under t."""
        out = []
        for m, c in member_of.items():
            if m != t and t in ancestors(m, po) and c not in out:
                out.append(c)
        return out

    def decide(rel, ptype, pname, recv, t, header):
        call = "changed(src)" if recv in (None, "src") else "changed(%s)" % recv
        # an op effect, a timer or a hook handler (it takes a datum/act): its dispatcher redraws the holder after it
        dispatched = recv in (None, "src") and re.search(r"\bdatum/act\b", header[header.find("("):] if "(" in header else "")
        c = comp_of(t)
        if c is not None:
            if chains.live(t):
                return None  # another legacy declaration still draws through it
            if pname == "Initialize" and recv in (None, "src"):
                return "delete"  # the first refresh draws every atom after its init
            if c["covered"] or dispatched:
                return "delete"
            return ("replace", call)
        if args.all and not chains.live(t):
            # no legacy declaration draws through it: the call is a redraw request on whatever draw() the chain has
            has, covered, _untracked = look_convert.draw_coverage(ix, t)
            if not has or covered or dispatched or (pname == "Initialize" and recv in (None, "src")):
                return "delete"
            return ("replace", call)
        if args.with_ancestors and t.count("/") > 2:
            if any(not c["covered"] for c in below(t)):
                return ("after", call)
        return None

    walk_calls(args, files, decide, removed, residue, sites)
    report("calls", args, removed, residue, sites)
    return 0


def run_audit(args):
    """The draw() procs that read state nothing publishes (untracked vars, reads through other objects, procs that do):
    each chain once, with what it reads. A redraw request (changed()) is still needed where such state changes."""
    import look_convert
    files = {rel: File(rel) for rel in code_files()}
    ix = look_convert.Index(ROOT, list(files))
    seen = set()
    n = 0
    rows = []
    for t in sorted(ix.draws):
        if not t.startswith(ATOM_ROOTS):
            continue
        has, covered, untracked = look_convert.draw_coverage(ix, t)
        key = tuple(untracked)
        if covered or (t, key) in seen:
            continue
        seen.add((t, key))
        n += 1
        rows.append("%s: %s" % (t, ", ".join(untracked)))
    print("look_sweep audit: %d draw() types read untracked state" % n)
    if args.sites:
        for r in rows:
            print("    " + r)
    return 0


def run_prune(args):
    """The changed() redraw requests this branch added (since --base) whose receiver's draws now read only tracked state:
    tracked writes redraw by themselves, so the request goes."""
    import subprocess
    import look_convert
    added = collections.defaultdict(set)
    diff = subprocess.check_output(["git", "diff", "-U0", args.base, "--", "code"]).decode("utf-8", "surrogateescape")
    rel = None
    for line in diff.split("\n"):
        if line.startswith("+++ b/"):
            rel = line[6:]
            continue
        m = re.match(r"^@@ -\S+ \+(\d+)(?:,(\d+))? @@", line)
        if m and rel:
            start = int(m.group(1))
            count = int(m.group(2)) if m.group(2) is not None else 1
            for k in range(start, start + count):
                added[rel].add(k - 1)
    files = {rel: File(rel) for rel in code_files()}
    ix = look_convert.Index(ROOT, list(files))
    removed, residue, sites = collections.Counter(), collections.Counter(), []
    for rel, f in files.items():
        if rel not in added or rel.startswith(NO_EDIT):
            continue
        L = f.lines
        ptype = None
        params = ""
        names = {}
        drop = []
        for i, l in enumerate(L):
            if l and l[0] not in " \t":
                hm = HDR.match(l)
                ptype = hm.group(1) if hm else None
                names = typed_names(strip_code(l), []) if hm else {}
                continue
            if i not in added[rel]:
                continue
            code = strip_code(l)
            if code.rstrip() != l.rstrip():
                continue  # a commented request stays (someone explained why it is there)
            m = re.match(r"^\s*changed\((src|[A-Za-z_]\w*)\)\s*$", code)
            if not m:
                continue
            for vm in re.finditer(r"\bvar/((?:[a-z_]\w*/)+)([A-Za-z_]\w*)", "\n".join(strip_code(x) for x in L[max(0, i - 60):i])):
                names[vm.group(2)] = "/" + vm.group(1).rstrip("/")
            t = ptype if m.group(1) == "src" else names.get(m.group(1))
            if not t or not t.startswith(ATOM_ROOTS) or t.startswith("/proc"):
                continue
            has, covered, _u = look_convert.draw_coverage(ix, t)
            if has and covered:
                prev = next((x for x in range(i - 1, -1, -1) if strip_code(L[x]).strip()), None)
                nxt = next((x for x in range(i + 1, len(L)) if strip_code(L[x]).strip()), None)
                ind = len(l) - len(l.lstrip())
                lone = prev is not None and (len(L[prev]) - len(L[prev].lstrip())) < ind and (nxt is None or (len(L[nxt]) - len(L[nxt].lstrip())) < ind)
                if lone:
                    residue["only_statement"] += 1
                    continue
                drop.append(i)
                removed["/".join(rel.split("/")[:3])] += 1
                sites.append("%s:%d %s" % (rel, i + 1, code.strip()))
        if drop and args.apply:
            for i in reversed(drop):
                del L[i]
            f.dirty = True
            f.save()
    report("prune", args, removed, residue, sites)
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["dead", "convert", "calls", "audit", "track", "prune"])
    ap.add_argument("--owned-ok", action="store_true", help="track: also rewrite writes in the folders other sessions own")
    ap.add_argument("--vars", nargs="*", help="track: only these vars")
    ap.add_argument("--base", default="origin/master", help="prune: the changed() calls added since this ref are the ones considered")
    ap.add_argument("--all", action="store_true", help="calls: every call whose receiver's chain has no legacy declaration, by the coverage of the chain's draw() procs")
    ap.add_argument("--with-ancestors", action="store_true", help="calls: also add changed() beside the calls of ancestor procs that reach an uncovered component")
    ap.add_argument("--types", nargs="*", help="convert: only the components holding these types (or their subtypes)")
    ap.add_argument("--report", help="convert: write the components (converted, covered, untracked reads, residue) as JSON")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--show", action="store_true", help="convert: print the generated draws")
    ap.add_argument("--sites", action="store_true")
    ap.add_argument("--paths", nargs="*", default=None)
    args = ap.parse_args()
    os.chdir(ROOT)
    if args.mode == "dead":
        return run_dead(args)
    if args.mode == "calls":
        return run_calls(args)
    if args.mode == "audit":
        return run_audit(args)
    if args.mode == "track":
        import look_track
        look_track.run(args, ROOT, code_files())
        return 0
    if args.mode == "prune":
        return run_prune(args)
    if args.mode == "convert":
        import look_convert
        look_convert.run(args, ROOT, code_files(), None)
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
