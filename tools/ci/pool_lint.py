#!/usr/bin/env python3
"""Pool take/release lint (code/datums/lifecycle/pool.dm).

A pooled type (a subtype of /datum/pooled, or declared with POOL_DECLARE) is taken with take(type) and
given back with .release(), never built with `new`. Fails when:
  - `new` builds a pooled type outside pool.dm, unit tests, or the type's own New chain;
  - a file calls take() / pool_take() but never releases anything (a leak by construction).

A justified keep is an inline `// ALLOW(pool): <reason>`.

    python tools/ci/pool_lint.py
    python tools/ci/pool_lint.py --selftest
"""
import glob
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
TYPE_LINE = re.compile(r"^(/datum/[A-Za-z0-9_/]+)\s*$")
PARENT = re.compile(r"^\s+parent_type\s*=\s*(/datum/pooled\b[A-Za-z0-9_/]*|/datum/[A-Za-z0-9_/]+)")
DECLARE = re.compile(r"POOL_DECLARE\((/datum/[A-Za-z0-9_/]+)\)")
NEW = re.compile(r"\bnew\s+(/datum/[A-Za-z0-9_/]+)")
TAKE = re.compile(r"\b(?:pool_take|take)\((/datum/[A-Za-z0-9_/]+)")
RELEASE = re.compile(r"\.release\(\)|\bpool_release\(|\brelease\(\)")
EXEMPT_PREFIX = ("code/modules/unit_tests/", "code/datums/lifecycle/pool.dm")


def strip(line):
    return re.sub(r'"[^"]*"', '""', line.split("//", 1)[0])


def check(files):
    pooled = set()
    for rel, text in files:
        current = None
        for line in text.split("\n"):
            m = TYPE_LINE.match(line)
            if m:
                current = m.group(1)
            m = PARENT.match(line)
            if m and current and m.group(1).startswith("/datum/pooled"):
                pooled.add(current)
            for d in DECLARE.findall(line):
                pooled.add(d)
    problems = []
    for rel, text in files:
        exempt = rel.startswith(EXEMPT_PREFIX)
        takes = []
        releases = False
        for number, raw in enumerate(text.split("\n"), 1):
            if "ALLOW(pool)" in raw:
                continue
            line = strip(raw)
            if RELEASE.search(line):
                releases = True
            for t in TAKE.findall(line):
                takes.append((number, t))
            if exempt:
                continue
            for t in NEW.findall(line):
                if any(t == p or t.startswith(p + "/") for p in pooled):
                    problems.append("%s:%d: new %s: a pooled type is taken with take(), not built" % (rel, number, t))
        if takes and not releases and not exempt:
            number, t = takes[0]
            problems.append("%s:%d: take(%s) but the file never releases: give it back with .release()" % (rel, number, t))
    return problems


def selftest():
    good = [("a.dm", "/datum/foo\n\tparent_type = /datum/pooled\n\n/proc/f()\n\tvar/datum/foo/F = take(/datum/foo)\n\tF.release()\n")]
    bad_new = good + [("b.dm", "/proc/g()\n\tvar/datum/foo/F = new /datum/foo\n")]
    bad_leak = [("a.dm", "/datum/foo\n\tparent_type = /datum/pooled\n"), ("c.dm", "/proc/h()\n\treturn take(/datum/foo)\n")]
    if check(good):
        print("selftest: clean input flagged: %s" % check(good))
        return 1
    if not check(bad_new) or not check(bad_leak):
        print("selftest: a violation went unflagged")
        return 1
    print("pool_lint selftest ok")
    return 0


def main(argv):
    if "--selftest" in argv:
        return selftest()
    files = []
    for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        with open(path, encoding="utf-8", errors="replace") as handle:
            files.append((rel, handle.read()))
    problems = check(files)
    for p in problems:
        print(p)
    print("pool_lint: %d problem(s)" % len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
