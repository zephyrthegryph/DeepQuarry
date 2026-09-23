"""Registry lint (roadmap L3, doc/rewrite/state.md sections 7 and 10).

No new ad-hoc global lists of instances; use a registry. An object that adds
itself to a global list (GLOB.x += src, |= src, .Add(src), .Insert(..., src))
or declares GLOBAL_LIST_BOILERPLATE() must be on tools/ci/registry_allowlist.txt.
New kinds of instance sets declare REGISTRY_MEMBERSHIP() instead
(code/__defines/registries.dm). Entries that no longer match anything fail too,
so the allowlist only shrinks.

Usage:
    python tools/ci/registry_lint.py
"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
ALLOWLIST = os.path.join(ROOT, "tools", "ci", "registry_allowlist.txt")

SELF_ADD = re.compile(
    r"\bGLOB\.(\w+)\s*(?:\+=|\|=)\s*src\b"
    r"|\bGLOB\.(\w+)\.(?:Add|Insert)\((?:[^()]*,\s*)?src\)")
BOILERPLATE = re.compile(r"^\s*GLOBAL_LIST_BOILERPLATE\(\s*(\w+)\s*,")


def allowlist():
    names = set()
    with open(ALLOWLIST, encoding="utf-8") as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if line:
                names.add(line)
    return names


def main():
    allowed = allowlist()
    seen, failures = set(), []
    for base, dirs, files in os.walk(os.path.join(ROOT, "code")):
        for name in files:
            if not name.endswith(".dm"):
                continue
            path = os.path.join(base, name)
            rel = os.path.relpath(path, ROOT)
            if rel.replace("\\", "/").startswith("code/__defines/"):
                continue  # the boilerplate macro's own definition
            with open(path, encoding="utf-8", errors="replace") as f:
                for number, line in enumerate(f, 1):
                    code = line.split("//", 1)[0]
                    hits = [m.group(1) or m.group(2) for m in SELF_ADD.finditer(code)]
                    m = BOILERPLATE.match(code)
                    if m:
                        hits.append(m.group(1))
                    for hit in hits:
                        seen.add(hit)
                        if hit not in allowed:
                            failures.append(f"{rel}:{number}: objects add themselves to GLOB.{hit}; "
                                            "declare REGISTRY_MEMBERSHIP() instead (code/__defines/registries.dm)")
    for stale in sorted(allowed - seen):
        failures.append(f"registry_allowlist.txt: {stale} no longer matches anything; remove it")
    print(f"registry lint: {len(allowed)} allowlisted lists, {len(failures)} problems")
    for f in failures:
        print(f)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
