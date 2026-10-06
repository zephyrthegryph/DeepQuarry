#!/usr/bin/env python3
r"""qdel(src) -> the lifecycle verbs (Phase C; doc/rewrite/final_api.html section 6 "Lifecycle", doc/rewrite/lifecycle.md section 5,
code/datums/lifecycle/verbs.dm; the qdel_src lint in tools/analyze/src/lints/qdel_src.rs).

    python tools/codemods/qdel_src.py [--apply] [--class C ...] [--sites] [--others] [--paths prefix ...]

Each `qdel(src)` statement not kept by `// ALLOW(lifecycle)` is classified:

  safe-auto
    replace     the statement before it (same block) is an unassigned `new /T(where, args...)` with `where` the thing's own place
                (loc, src.loc, get_turf(src), drop_location()), in a proc of an /obj or /mob type:
                `replace_with(src, /T, args...)` (the successor takes the original's place, its slot included).
    init_hint   in Initialize(), `qdel(src)` followed by a bare `return` at the same depth: `return INITIALIZE_HINT_QDEL`.
    expire      a proc whose whole body is `qdel(src)`, on an /obj or /mob type, named only by `after(src, D, PROC_REF(x))` calls
                (each one alone on its line): each call becomes `expire(D)` and the proc goes.
  needs-review  everything else (by code; --sites lists them): a real destroy-now keeps qdel(src) with `// ALLOW(lifecycle): <reason>`.
"""
import argparse
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dmlib import File, ROOT, dm_files, procs_in, statements, strip_code  # noqa: E402

QDEL_SRC = re.compile(r"(?<![\w.])qdel\s*\(\s*src\s*\)")
QDEL_STMT = re.compile(r"^qdel\(\s*src\s*\)$")
NEW = re.compile(r"^new\s*(/[\w/]+)\s*\((.*)\)$")
WHERE = {"loc", "src.loc", "get_turf(src)", "get_turf(loc)", "get_turf(src.loc)", "drop_location()", "src.drop_location()", "get_turf(src.loc)"}
MOVABLE_ROOTS = ("/obj/",)  # a mob successor would take over its handles (replace_with forwards them): by hand


def split_args(s):
    out, depth, cur, q = [], 0, [], None
    for c in s:
        if q:
            cur.append(c)
            if c == q:
                q = None
            continue
        if c in "\"'":
            q = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            out.append("".join(cur).strip())
            cur = []
            continue
        cur.append(c)
    if "".join(cur).strip():
        out.append("".join(cur).strip())
    return out


def is_movable(t):
    return (t + "/").startswith(MOVABLE_ROOTS)


def sites(f, others_ok=True):
    """(proc, stmt index list, stmt) for every qdel(src) statement of every proc in f."""
    for p in procs_in(f):
        st = None
        for k in range(p.start + 1, p.end):
            if QDEL_SRC.search(strip_code(f.lines[k])):
                if st is None:
                    st = statements(f, p.start + 1, p.end)
                for i, s in enumerate(st):
                    if s.first == k:
                        yield p, st, i
                        break
                else:
                    yield p, st, -1


def kept(f, k):
    return "ALLOW(lifecycle" in f.lines[k] or (k and f.lines[k - 1].lstrip().startswith("//") and "ALLOW(lifecycle" in f.lines[k - 1])


def classify(f, p, st, i):
    if i < 0:
        return "review", "inline", None
    s = st[i]
    if kept(f, s.first):
        return "kept", None, None
    if not QDEL_STMT.match(s.code):
        return "review", "not_a_statement", None
    prev = st[i - 1] if i > 0 else None
    nxt = st[i + 1] if i + 1 < len(st) else None
    if p.name == "Initialize" and p.kind is None and nxt and nxt.indent == s.indent and re.fullmatch(r"return\s*\.?", nxt.code):
        return "init_hint", None, nxt
    if prev and prev.indent == s.indent and prev.last == s.first - 1 or (prev and prev.indent == s.indent and all(not strip_code(f.lines[k]).strip() for k in range(prev.last + 1, s.first))):
        m = NEW.match(prev.code) if prev else None
        if m and is_movable(p.type):
            args = split_args(m.group(2))
            if args and args[0].replace(" ", "") in WHERE:
                return "replace", None, (prev, m.group(1), args[1:])
            return "review", "new_elsewhere", None
    if p.name not in ("Initialize",) and len(st) == 1 and is_movable(p.type) and p.kind == "proc" or (len(st) == 1 and p.kind is None and is_movable(p.type)):
        return "expire_candidate", None, None
    return "review", "destroy_now", None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--class", dest="classes", nargs="*", default=["replace", "init_hint", "expire"])
    ap.add_argument("--sites", action="store_true")
    ap.add_argument("--others", action="store_true")
    ap.add_argument("--paths", nargs="*", default=["code/"])
    a = ap.parse_args()

    counts = collections.Counter()
    residue = collections.Counter()
    expire_procs = []
    files = {}
    for relpath in dm_files(a.paths, others=a.others):
        f = File(relpath)
        if "qdel" not in "\n".join(f.lines):
            continue
        edits = []
        for p, st, i in sites(f):
            cls, code, extra = classify(f, p, st, i)
            if cls == "kept":
                continue
            if cls == "expire_candidate":
                expire_procs.append((relpath, p))
                continue
            if cls == "review":
                residue[code] += 1
                if a.sites:
                    print("review\t%s\t%s/%s\t%s:%d" % (code, p.type, p.name, relpath, (st[i].first if i >= 0 else p.start) + 1))
                continue
            counts[cls] += 1
            if a.sites:
                print("%s\t%s/%s\t%s:%d" % (cls, p.type, p.name, relpath, st[i].first + 1))
            if a.apply and cls in a.classes:
                edits.append((cls, st[i], extra))
        for cls, s, extra in sorted(edits, key=lambda e: -e[1].first):
            indent = f.lines[s.first][: len(f.lines[s.first]) - len(f.lines[s.first].lstrip())]
            tail = f.lines[s.first].lstrip()[len("qdel(src)"):] if f.lines[s.first].lstrip().startswith("qdel(src)") else ""
            if cls == "init_hint":
                nxt = extra
                f.lines[s.first] = indent + "return INITIALIZE_HINT_QDEL" + tail
                del f.lines[nxt.first : nxt.last + 1]
            elif cls == "replace":
                prev, path, args = extra
                pind = f.lines[prev.first][: len(f.lines[prev.first]) - len(f.lines[prev.first].lstrip())]
                ptail = ""
                if prev.first == prev.last:
                    raw = f.lines[prev.first]
                    c = strip_code(raw).rstrip()
                    ptail = raw[len(c):].rstrip() if raw.startswith(c) else ""
                call = "replace_with(src, %s)" % ", ".join([path] + args)
                comment = tail.strip()
                if ptail.strip():
                    comment = (ptail.strip() + " " + comment).strip() if comment else ptail.strip()
                f.lines[s.first] = pind + call + ((" " + comment) if comment else "")
                del f.lines[prev.first : prev.last + 1]
            f.dirty = True
        if f.dirty:
            files[relpath] = f

    # expire: a qdel-only proc named only by after(src, D, PROC_REF(x)) lines.
    for relpath, p in expire_procs:
        refs = []
        name = p.name
        for root, _, fs in os.walk(os.path.join(ROOT, "code")):
            for fn in fs:
                if fn.endswith(".dm"):
                    path = os.path.join(root, fn)
                    with open(path, encoding="utf-8", errors="surrogateescape") as fh:
                        text = fh.read()
                    if name in text:
                        r = os.path.relpath(path, ROOT).replace("\\", "/")
                        for k, line in enumerate(text.split("\n")):
                            if re.search(r"(?<!\w)" + re.escape(name) + r"(?!\w)", line):
                                refs.append((r, k, line))
        defs = [x for x in refs if re.match(r"^/[\w/]+/(proc/)?" + re.escape(name) + r"\s*\(", x[2])]
        calls = [x for x in refs if x not in defs]
        timer = re.compile(r"^(\s*)after\(\s*src\s*,\s*(.+?)\s*,\s*PROC_REF\(" + re.escape(name) + r"\)\s*\)\s*(//.*)?$")
        ok = len(defs) == 1 and calls and all(timer.match(c[2].rstrip("\r")) for c in calls)
        if not ok:
            residue["destroy_now"] += 1
            if a.sites:
                print("review\tdestroy_now\t%s/%s\t%s:%d" % (p.type, p.name, relpath, p.start + 1))
            continue
        counts["expire"] += 1
        if a.sites:
            print("expire\t%s/%s\t%s:%d (%d calls)" % (p.type, p.name, relpath, p.start + 1, len(calls)))
        if a.apply and "expire" in a.classes:
            for r, k, line in calls:
                g = files.get(r) or File(r)
                files[r] = g
                m = timer.match(g.lines[k])
                g.lines[k] = "%sexpire(%s)%s" % (m.group(1), m.group(2), (" " + m.group(3)) if m.group(3) else "")
                g.dirty = True
            g = files.get(relpath) or File(relpath)
            files[relpath] = g
            for k, line in enumerate(g.lines):
                if re.match(r"^/[\w/]+/(proc/)?" + re.escape(name) + r"\s*\(", line):
                    end = k + 1
                    while end < len(g.lines) and (not g.lines[end].strip() or g.lines[end][0] in " \t"):
                        end += 1
                    start = k
                    while start > 0 and g.lines[start - 1].startswith("///"):
                        start -= 1
                    del g.lines[start:end]
                    g.dirty = True
                    break
    if a.apply:
        for g in files.values():
            g.save()
    print("qdel_src: safe-auto %s; needs-review %d %s" % (dict(counts), sum(residue.values()), dict(residue.most_common())))


if __name__ == "__main__":
    main()
