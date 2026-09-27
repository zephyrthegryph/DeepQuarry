"""Base-type proc count ratchet (doc/rewrite/init_and_turfs.md section 0.5).

BYOND keeps a table entry for every proc every type has, inherited ones
included: ~23.5 bytes per (type, proc) pair. A proc declared on a base type is
paid once per subtype, so each proc on /datum costs ~1 MB of world-load
memory, on /atom ~0.5 MB and on /obj or /obj/item ~0.2-0.45 MB.

This lint counts the procs and verbs *declared* (proc/name, verb/name, not
overrides) on the base types below, across the files deepquarry.dme includes,
and fails if a type's count rises above its ceiling in
tools/ci/base_proc_allowlist.txt. Rarely used procs (debug, admin, vv, legacy
shims) belong in global procs or helper datums instead.

Usage:
    python tools/ci/base_proc_lint.py            # the CI check
    python tools/ci/base_proc_lint.py --report   # per-type counts and names
    python tools/ci/base_proc_lint.py --update   # lower the ceilings to today's counts
"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
DME = os.path.join(ROOT, "deepquarry.dme")
ALLOWLIST = os.path.join(ROOT, "tools", "ci", "base_proc_allowlist.txt")
BASE_TYPES = ["/datum", "/atom", "/atom/movable", "/obj", "/obj/item", "/mob"]

INCLUDE = re.compile(r'^#include "(.+\.dm)"')
PATH_LINE = re.compile(r"^(/?[A-Za-z_][\w/]*)\s*(\(|$)")


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


def declared(path):
    """'/datum/proc/foo' -> ('/datum', 'foo'); None if not a proc declaration."""
    parts = [p for p in path.split("/") if p]
    for kw in ("proc", "verb"):
        if kw in parts:
            i = parts.index(kw)
            if i + 1 < len(parts):
                return "/" + "/".join(parts[:i]), parts[i + 1]
    return None


def scan():
    found = {t: set() for t in BASE_TYPES}
    for fn in dme_files():
        if not os.path.exists(fn):
            continue
        with open(fn, encoding="utf-8", errors="replace") as f:
            lines = strip_comments(f.read())
        stack = []  # (indent, path)
        for line in lines:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            ind = indent_of(line)
            while stack and stack[-1][0] >= ind:
                stack.pop()
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
            if seg.split("/")[0] in ("var", "return", "if", "for", "while", "else", "switch", "do", "spawn", "set", "del"):
                continue
            d = declared(full)
            if d:
                if d[0] in found:
                    found[d[0]].add(d[1])
                continue  # proc body follows, never a nested path
            if m.group(2) == "":
                stack.append((ind, full))
    return found


def read_ceilings():
    ceil = {}
    with open(ALLOWLIST, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                t, n = line.split()
                ceil[t] = int(n)
    return ceil


def main():
    found = scan()
    if "--report" in sys.argv:
        for t in BASE_TYPES:
            print(f"{t} {len(found[t])}")
            for name in sorted(found[t]):
                print(f"    {name}")
        return 0
    if "--update" in sys.argv:
        with open(ALLOWLIST, "w", encoding="utf-8", newline="\n") as f:
            f.write("# Ceilings for tools/ci/base_proc_lint.py: procs and verbs declared on each\n")
            f.write("# base type (doc/rewrite/init_and_turfs.md section 0.5). Only ever lower these.\n")
            for t in BASE_TYPES:
                f.write(f"{t} {len(found[t])}\n")
        print("Updated", ALLOWLIST)
        return 0
    ceil = read_ceilings()
    bad = False
    for t in BASE_TYPES:
        n, c = len(found[t]), ceil.get(t, 0)
        status = "over" if n > c else "ok"
        print(f"{t}: {n} procs (ceiling {c}) {status}")
        if n > c:
            bad = True
        elif n < c:
            print(f"  {t} is below its ceiling; run with --update to lower it.")
    if bad:
        print("Base-type proc count rose. Move the new proc to a global proc or helper datum.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
