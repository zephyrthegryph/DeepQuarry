#!/usr/bin/env python3
r"""`new /T(loc, a, b)` -> `make(/T, at = loc, v1 = a, v2 = b)` for every type that declares param(nameof(v), pos = N)
(doc/rewrite/final_api.html section 6 "Lifecycle forms", form 2; code/engine/lifeforms/params.dm).

    python tools/codemods/make_calls.py [--apply] [--sites] [--others] [--paths prefix ...]

The positional arguments a type's params take (param(..., pos = N) in its CAPABILITIES block, or an ancestor's) are read from source. A call
site whose type is written literally (`new /obj/effect/foo(T, x)`, `new /obj/effect/foo/bar(T, x)` for a subtype) and passes positional
arguments is rewritten to make() with the names; a call with a variable type, a named argument, or more arguments than the type has
positions is left alone (the param(pos =) mapping in /atom/New() still serves it). Idempotent.
"""
import argparse
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dmlib import File, ROOT, dm_files, split_args, strip_code  # noqa: E402

PARAM = re.compile(r"\bparam\(\s*nameof\((\w+)\)[^)]*?\bpos\s*=\s*(\d+)")
NEW = re.compile(r"(?<![\w.])new\s*(/[\w/]+)\s*\(")


def positions():
    """type -> {pos: var} from every CAPABILITIES block."""
    out = collections.defaultdict(dict)
    head = re.compile(r"^CAPABILITIES\((/[\w/]+)\)")
    for root, _, fs in os.walk(os.path.join(ROOT, "code")):
        for fn in fs:
            if not fn.endswith(".dm"):
                continue
            with open(os.path.join(root, fn), encoding="utf-8", errors="surrogateescape") as fh:
                cur = None
                for line in fh:
                    m = head.match(line)
                    if m:
                        cur = m.group(1)
                        continue
                    if cur and line[:1] not in ("\t", " ") and line.strip():
                        cur = None
                    if cur:
                        for pm in PARAM.finditer(line):
                            out[cur][int(pm.group(2))] = pm.group(1)
    return out


def lineage(t):
    parts = t.split("/")
    return ["/".join(parts[:k]) for k in range(len(parts), 1, -1)]


def pos_of(table, t):
    merged = {}
    for anc in reversed(lineage(t)):
        merged.update(table.get(anc, {}))
    return merged


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--sites", action="store_true")
    ap.add_argument("--others", action="store_true")
    ap.add_argument("--paths", nargs="*", default=["code/", "maps/"])
    a = ap.parse_args()
    table = positions()
    counts = collections.Counter()
    for rel in dm_files(a.paths, others=a.others):
        if rel.startswith(("code/engine/", "code/__defines/")):
            continue
        f = File(rel)
        if "new" not in "\n".join(f.lines):
            continue
        for k, line in enumerate(f.lines):
            code = strip_code(line)
            if "new" not in code:
                continue
            for m in reversed(list(NEW.finditer(code))):
                t = m.group(1)
                pmap = pos_of(table, t)
                if not pmap:
                    continue
                o = m.end() - 1
                depth, j = 0, o
                while j < len(code):
                    if code[j] == "(":
                        depth += 1
                    elif code[j] == ")":
                        depth -= 1
                        if depth == 0:
                            break
                    j += 1
                if j >= len(code):
                    counts["skip:spans_lines"] += 1
                    continue
                args = [x.strip() for x in split_args(line[o + 1:j])]
                args = [x for x in args if x]
                if len(args) < 2:
                    continue
                if any(re.match(r"^\w+\s*=[^=]", x) for x in args):
                    counts["skip:named"] += 1
                    continue
                if any(i not in pmap for i in range(1, len(args))):
                    counts["skip:unmapped"] += 1
                    continue
                parts = ["at = %s" % args[0]] + ["%s = %s" % (pmap[i], args[i]) for i in range(1, len(args))]
                new = "make(%s, %s)" % (t, ", ".join(parts))
                counts["rewritten"] += 1
                if a.sites:
                    print("%s:%d\t%s -> %s" % (rel, k + 1, line[m.start():j + 1].strip(), new))
                if a.apply:
                    line = line[:m.start()] + new + line[j + 1:]
                    f.lines[k] = line
                    f.dirty = True
        if a.apply:
            f.save()
    print("make_calls: %s" % dict(counts.most_common()))


if __name__ == "__main__":
    main()
