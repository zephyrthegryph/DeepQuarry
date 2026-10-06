#!/usr/bin/env python3
r"""The needs-review half of the Phase C codemods: dump the residue with context, then apply hand decisions.

    python tools/codemods/review.py dump qdel_src|init|usr [--others] [--paths ...] [--context N] > sites.txt
    python tools/codemods/review.py apply decisions.tsv

A decision line is `file:line<TAB>action<TAB>argument` (the line is the site's 1-based line when the dump was made; decisions are
applied bottom-up per file, so earlier ones do not shift later ones):

    allow      `// ALLOW(<argument>` above the site line, at its indent (argument: `lifecycle): reason` or `init/CODE): reason`)
    sub        replace text on that line: argument `old|||new`
    del        delete that line
    hint       `qdel(src)` + the bare `return` after it -> `return INITIALIZE_HINT_QDEL`
"""
import argparse
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dmlib import File, dm_files, procs_in, strip_code  # noqa: E402

QDEL_SRC = re.compile(r"(?<![\w.])qdel\s*\(\s*src\s*[,)]")
USR = re.compile(r"(?<![\w.])usr(?!\w)")
INIT_HEAD = re.compile(r"^(/[\w/]+)/Initialize\s*\(")


def kept(lines, k, name):
    return ("ALLOW(" + name) in lines[k] or (k and lines[k - 1].lstrip().startswith("//") and ("ALLOW(" + name) in lines[k - 1])


def dump(kind, files, context):
    n = 0
    for r in files:
        f = File(r)
        text = "\n".join(f.lines)
        if kind == "qdel_src" and "qdel" not in text:
            continue
        if kind == "init" and "Initialize" not in text:
            continue
        if kind == "usr" and "usr" not in text:
            continue
        for p in procs_in(f):
            hits = []
            if kind == "init":
                if p.name == "Initialize" and p.kind is None and not kept(f.lines, p.start, "init"):
                    hits = [p.start]
            else:
                for k in range(p.start + 1, p.end):
                    code = strip_code(f.lines[k])
                    if kind == "qdel_src" and QDEL_SRC.search(code) and not kept(f.lines, k, "lifecycle"):
                        hits.append(k)
                    if kind == "usr" and USR.search(code):
                        hits.append(k)
            if not hits:
                continue
            if kind == "init":
                print("@@ %s:%d %s" % (r, p.start + 1, p.type))
                for k in range(p.start, p.end):
                    print("%5d| %s" % (k + 1, f.lines[k]))
                n += 1
                continue
            print("@@ %s:%d %s" % (r, p.start + 1, f.lines[p.start].strip()))
            shown = set()
            for k in hits:
                lo = max(p.start + 1, k - context)
                hi = min(p.end, k + 3)
                if shown and min(shown) <= lo <= max(shown) + 1:
                    pass
                elif shown:
                    print("   ...")
                for j in range(lo, hi):
                    if j in shown:
                        continue
                    shown.add(j)
                    print("%s%5d| %s" % (">" if j in hits else " ", j + 1, f.lines[j]))
                n += 1
    print("# %d sites" % n, file=sys.stderr)


def apply(path):
    by_file = collections.defaultdict(list)
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line.strip() or line.startswith("#"):
            continue
        loc, action, *rest = line.split("\t")
        arg = rest[0] if rest else ""
        r, ln = loc.rsplit(":", 1)
        by_file[r].append((int(ln) - 1, action, arg))
    done = 0
    for r, items in by_file.items():
        f = File(r)
        for k, action, arg in sorted(items, key=lambda x: -x[0]):
            line = f.lines[k]
            ind = line[: len(line) - len(line.lstrip())]
            if action == "allow":
                f.lines.insert(k, ind + "// ALLOW(" + arg)
            elif action == "sub":
                old, new = arg.split("|||")
                if old not in line:
                    print("NOT FOUND %s:%d %r" % (r, k + 1, old))
                    continue
                f.lines[k] = line.replace(old, new, 1)
            elif action == "del":
                del f.lines[k]
            elif action == "hint":
                assert "qdel(src)" in line, (r, k + 1)
                f.lines[k] = line.replace("qdel(src)", "return INITIALIZE_HINT_QDEL", 1)
                assert re.fullmatch(r"\s*return\s*\.?\s*", f.lines[k + 1]), (r, k + 2)
                del f.lines[k + 1]
            else:
                raise SystemExit("unknown action %s" % action)
            done += 1
        f.dirty = True
        f.save()
    print("applied %d decisions in %d files" % (done, len(by_file)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd")
    ap.add_argument("what")
    ap.add_argument("--others", action="store_true")
    ap.add_argument("--paths", nargs="*", default=["code/"])
    ap.add_argument("--context", type=int, default=6)
    a = ap.parse_args()
    if a.cmd == "dump":
        dump(a.what, dm_files(a.paths, others=a.others), a.context)
    elif a.cmd == "apply":
        apply(a.what)


if __name__ == "__main__":
    main()
