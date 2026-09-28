#!/usr/bin/env python3
"""DECLARE_INTERACTIONS shadowing lint (doc/rewrite/interactions.md sec 5a).

DECLARE_INTERACTIONS(T, ...) generates T/get_interactions(), which REPLACES every
ancestor's specs: a subtype that declares its own silently loses its parent's
interactions (a headset lost the radio's Use this way). EXTEND_INTERACTIONS adds to
them instead. This fails on any DECLARE_INTERACTIONS (or hand-written
get_interactions() override) on a type whose ancestor also declares, unless the site
carries `// ALLOW(interactions): <reason>` (tools/ci/allow_annotations.py): the
replacement is deliberate (the subtype's Use replaces the parent's Use).

Ancestry is by type path (parent_type overrides are not followed).

    python tools/ci/interactions_lint.py
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from allow_annotations import allowed  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
DECLARE = re.compile(r"^\s*DECLARE_INTERACTIONS\(\s*(/[\w/]+)")
GETTER = re.compile(r"^(/[\w/]+)/get_interactions\(\)")


def scan():
    sites = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True)):
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        with open(path, encoding="utf-8", errors="replace") as handle:
            raw = handle.read().split("\n")
        for number, line in enumerate(raw, 1):
            m = DECLARE.match(line) or GETTER.match(line)
            if m:
                sites[m.group(1)] = (rel, number, allowed(raw, number, "interactions"))
    return sites


def main():
    sites = scan()
    bad = []
    for path, (rel, number, ok) in sorted(sites.items()):
        parts = path.split("/")
        for cut in range(len(parts) - 1, 1, -1):
            ancestor = "/".join(parts[:cut])
            if ancestor in sites:
                if not ok:
                    arel, anum, _ = sites[ancestor]
                    bad.append("%s:%d: DECLARE_INTERACTIONS(%s) discards %s's specs (%s:%d): "
                               "use EXTEND_INTERACTIONS, or annotate `// ALLOW(interactions): reason`"
                               % (rel, number, path, ancestor, arel, anum))
                break
    for line in bad:
        print(line)
    print("interactions_lint: %d declaring types, %d unannotated shadowing sites" % (len(sites), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
