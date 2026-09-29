"""Registry lint (roadmap L3, doc/rewrite/state.md sections 7 and 10).

No new ad-hoc global lists of instances; use a registry. An object that adds
itself to a global list (GLOB.x += src, |= src, .Add(src), .Insert(..., src), GLOB.x[key] = src)
or declares GLOBAL_LIST_BOILERPLATE() fails unless the site carries
`// ALLOW(registry): <reason>` (tools/ci/allow_annotations.py): an object pool,
or a list of non-datums such as clients. New kinds of instance sets declare
REGISTRY_MEMBERSHIP() instead (code/__defines/registries.dm).

Usage:
    python tools/ci/registry_lint.py
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from allow_annotations import allowed  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

SELF_ADD = re.compile(
    r"\bGLOB\.(\w+)\s*(?:\+=|\|=)\s*src\b"
    r"|\bGLOB\.(\w+)\.(?:Add|Insert)\((?:[^()]*,\s*)?src\)"
    r"|\bGLOB\.(\w+)\[[^\]]*\]\s*=\s*src\b")
BOILERPLATE = re.compile(r"^\s*GLOBAL_LIST_BOILERPLATE\(\s*(\w+)\s*,")


def main():
    kept, failures = 0, []
    for base, dirs, files in os.walk(os.path.join(ROOT, "code")):
        for name in files:
            if not name.endswith(".dm"):
                continue
            path = os.path.join(base, name)
            rel = os.path.relpath(path, ROOT)
            if rel.replace("\\", "/").startswith("code/__defines/"):
                continue  # the boilerplate macro's own definition
            with open(path, encoding="utf-8", errors="replace") as f:
                lines = f.read().split("\n")
            for number, line in enumerate(lines, 1):
                code = line.split("//", 1)[0]
                hits = [m.group(1) or m.group(2) or m.group(3) for m in SELF_ADD.finditer(code)]
                m = BOILERPLATE.match(code)
                if m:
                    hits.append(m.group(1))
                if hits and allowed(lines, number, "registry"):
                    kept += len(hits)
                    continue
                for hit in hits:
                    failures.append(f"{rel}:{number}: objects add themselves to GLOB.{hit}; "
                                    "declare REGISTRY_MEMBERSHIP() instead (code/__defines/registries.dm)")
    print(f"registry lint: {kept} kept sites (ALLOW(registry)), {len(failures)} problems")
    for f in failures:
        print(f)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
