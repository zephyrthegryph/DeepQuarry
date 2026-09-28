"""Base-type proc memory budget (doc/rewrite/init_and_turfs.md section 0.5).

BYOND keeps a proc-table entry for every proc every type has, inherited ones
included: ~23.5 bytes per (type, proc) pair. A proc declared on a base type is
therefore paid once per subtype.

For each base type below this lint estimates

    bytes = procs declared on the type x types at or under it x 23.5

counting procs and verbs *declared* there (proc/name, verb/name, not overrides)
and type paths defined in the files deepquarry.dme includes. It fails when the
total rises above the ceiling in tools/ci/base_proc_budget.txt; the per-type
figures are reported for information. It says nothing about where a proc
lives (global or type): it only watches the memory.

Usage:
    python tools/ci/base_proc_lint.py            # the CI check
    python tools/ci/base_proc_lint.py --report   # per-type figures and proc names
    python tools/ci/base_proc_lint.py --update   # ceiling = today's total + 5%
"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
DME = os.path.join(ROOT, "deepquarry.dme")
BUDGET = os.path.join(ROOT, "tools", "ci", "base_proc_budget.txt")
BASE_TYPES = ["/datum", "/atom", "/atom/movable", "/obj", "/obj/item", "/mob"]
BYTES_PER_PAIR = 23.5
HEADROOM = 1.05

INCLUDE = re.compile(r'^#include "(.+\.dm)"')
PATH_LINE = re.compile(r"^(/?[A-Za-z_][\w/]*)\s*(\(|$)")
KEYWORDS = ("var", "return", "if", "for", "while", "else", "switch", "do", "spawn", "set", "del")
# Built-in roots that are not /datum descendants.
NON_DATUM = ("/client", "/world", "/list")


def dme_files():
    out = []
    with open(DME, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = INCLUDE.match(line.strip())
            if m:
                out.append(os.path.join(ROOT, m.group(1).replace("\\", "/")))
    return out


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    return [re.sub(r"//.*$", "", l).rstrip() for l in text.split("\n")]


def indent_of(line):
    n = 0
    for ch in line:
        if ch == "\t":
            n += 4
        elif ch == " ":
            n += 1
        else:
            break
    return n


def split_path(path):
    """'/obj/foo/proc/bar' -> ('/obj/foo', 'proc', 'bar'); '/obj/foo/var/x' -> ('/obj/foo', 'var', 'x')."""
    parts = [p for p in path.split("/") if p]
    for i, p in enumerate(parts):
        if p in ("proc", "verb", "var"):
            name = parts[i + 1] if i + 1 < len(parts) else None
            return "/" + "/".join(parts[:i]), p, name
    return "/" + "/".join(parts), None, None


def scan():
    procs = {t: set() for t in BASE_TYPES}
    types = set()
    for fn in dme_files():
        if not os.path.exists(fn):
            continue
        with open(fn, encoding="utf-8", errors="replace") as f:
            lines = strip_comments(f.read())
        stack = []  # (indent, path); path None marks a proc body
        for line in lines:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            ind = indent_of(line)
            while stack and stack[-1][0] >= ind:
                stack.pop()
            if stack and stack[-1][1] is None:
                continue  # inside a proc body
            m = PATH_LINE.match(s)
            if not m:
                continue
            seg = m.group(1)
            if ind == 0:
                full = seg if seg.startswith("/") else "/" + seg
            elif stack:
                if seg.startswith("/"):
                    continue
                full = stack[-1][1].rstrip("/") + "/" + seg
            else:
                continue
            if seg.split("/")[0] in KEYWORDS and ind > 0:
                continue
            typ, kind, name = split_path(full)
            if kind is None and m.group(2) == "(":
                # An override (/obj/foo/Destroy()): the type is the path above the proc.
                typ = typ.rsplit("/", 1)[0] or "/"
                kind = "override"
            if typ != "/":
                types.add(typ)
            if kind in ("proc", "verb", "override"):
                if kind != "override" and typ in procs and name:
                    procs[typ].add(name)
                stack.append((ind, None))  # the body follows, never a nested path
                continue
            if kind == "var":
                continue
            if m.group(2) == "":
                stack.append((ind, full))
    # A declared path implies its parents.
    for t in list(types):
        parts = t.strip("/").split("/")
        for i in range(1, len(parts)):
            types.add("/" + "/".join(parts[:i]))
    return procs, types


def under(t, base):
    if base == "/datum":
        return not t.startswith(NON_DATUM)
    if base == "/atom":
        return t.startswith(("/atom", "/area", "/turf", "/obj", "/mob"))
    if base == "/atom/movable":
        return t == "/atom/movable" or t.startswith(("/atom/movable/", "/obj", "/mob"))
    return t == base or t.startswith(base + "/")


def figures():
    procs, types = scan()
    rows = []
    for base in BASE_TYPES:
        n_types = sum(1 for t in types if under(t, base)) or 1
        n_procs = len(procs[base])
        rows.append((base, n_procs, n_types, int(n_procs * n_types * BYTES_PER_PAIR)))
    return procs, rows


def read_ceiling():
    with open(BUDGET, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line.startswith("total "):
                return int(line.split()[1])
    return 0


def fmt(b):
    return f"{b:,} B ({b / 1048576:.1f} MB)"


def main():
    procs, rows = figures()
    total = sum(r[3] for r in rows)
    if "--report" in sys.argv:
        for base, n_procs, n_types, b in rows:
            print(f"{base}: {n_procs} procs x {n_types} types = {fmt(b)}")
            for name in sorted(procs[base]):
                print(f"    {name}")
        print(f"total: {fmt(total)}")
        return 0
    if "--update" in sys.argv:
        ceiling = int(total * HEADROOM)
        with open(BUDGET, "w", encoding="utf-8", newline="\n") as f:
            f.write("# Memory budget for tools/ci/base_proc_lint.py (doc/rewrite/init_and_turfs.md 0.5):\n")
            f.write("# estimated bytes of proc-table entries paid for procs declared on base types\n")
            f.write("# (procs x subtypes x 23.5). Only `total` is enforced; it is today's value + 5%.\n")
            f.write(f"total {ceiling}\n")
            for base, n_procs, n_types, b in rows:
                f.write(f"# {base} {n_procs} procs x {n_types} types = {b}\n")
        print(f"Updated {BUDGET}: total {fmt(total)}, ceiling {fmt(ceiling)}")
        return 0
    ceiling = read_ceiling()
    for base, n_procs, n_types, b in rows:
        print(f"{base}: {n_procs} procs x {n_types} types = {fmt(b)}")
    print(f"total: {fmt(total)} (ceiling {fmt(ceiling)})")
    if total > ceiling:
        print("Base-type proc memory rose above the budget. Trim procs declared on base types, or")
        print("raise the ceiling deliberately with --update.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
