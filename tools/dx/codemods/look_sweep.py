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


def run_dead(args):
    files = {rel: File(rel) for rel in code_files()}
    chains = Chains(files)
    removed = collections.Counter()
    residue = collections.Counter()
    sites = []
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
            ptype = m.group(1)
            j = i + 1
            while j < n and (lines[j].strip() == "" or lines[j][0] in " \t"):
                j += 1
            body = list(range(i + 1, j))
            codes = {k: strip_code(lines[k]).strip() for k in body}
            names = typed_names(strip_code(lines[i]), codes.values())
            drop = set()
            for k in body:
                code = codes[k]
                if "update_icon" not in code:
                    continue
                ma = CALL_ALONE.match(code)
                mi = None if ma else IF_CALL.match(code)
                if not ma and not mi:
                    continue
                recv = (ma or mi).group(2 if mi else 1)
                if recv is None:
                    t = None if ptype.startswith("/proc") else ptype
                else:
                    t = names.get(recv)
                if not t or not t.startswith(ATOM_ROOTS):
                    continue
                if chains.live(t):
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
                if len(plan) > 1 and k in plan and any(indent_of(lines[x]) == 0 for x in plan):
                    residue["empty_block"] += 1
                    continue
                drop |= plan
                folder = "/".join(rel.split("/")[:3])
                removed[folder] += 1
                sites.append("%s:%d %s" % (rel, k + 1, code))
            if drop:
                for k in sorted(drop, reverse=True):
                    # a comment-only line right above a dropped line, with nothing else under it, stays (it may describe more)
                    del lines[k]
                f.dirty = True
                n = len(lines)
                j -= len(drop)
            i = j
        if f.dirty and args.apply:
            f.save()
    total = sum(removed.values())
    print("look_sweep dead: %d no-op update_icon() calls %s; residue %s" % (total, "removed" if args.apply else "found", dict(residue)))
    for folder, c in removed.most_common():
        print("    %4d %s" % (c, folder))
    if args.sites:
        for s in sites:
            print("    " + s)
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["dead", "convert"])
    ap.add_argument("--types", nargs="*", help="convert: only the components holding these types (or their subtypes)")
    ap.add_argument("--report", help="convert: write the components (converted, covered, untracked reads, residue) as JSON")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--sites", action="store_true")
    ap.add_argument("--paths", nargs="*", default=None)
    args = ap.parse_args()
    os.chdir(ROOT)
    if args.mode == "dead":
        return run_dead(args)
    if args.mode == "convert":
        import look_convert
        look_convert.run(args, ROOT, code_files(), None)
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
