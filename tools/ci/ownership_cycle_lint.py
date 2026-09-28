"""Ownership-cycle lint (doc/rewrite/object_model_core.md, lifecycle section).

Ownership must be a tree. REF_OWNED / REF_OWNED_LIST / REF_OWNED_VALUES say
"deleting me deletes this child"; if a child's type in turn owns something of
the owner's type, the two can each qdel the other (an overmap mob and its
marker did exactly that: a double-qdel CRASH, swallowed, a hung test batch).

This reads every REF_OWNED* declaration, looks up the declared type of each
named var (on the declaring type or an ancestor), and builds a graph
owner type -> child var type. A cycle is reported when following owned edges
from type A reaches a var typed as A or an ancestor of A.
Edges whose var type is a broad root (/datum, /atom, /obj/item, /mob/living,
untyped, ...) or the owner's own kind are skipped: they say nothing about which type is owned.

The runtime check (dq_lifecycle_link_table(), links.dm) catches the instance
cases this can't see (untyped vars, declarations written as procs).

One side of a mutual pair should own; the other side holds a plain reference
that it nulls in Destroy(), or a handle. Escape hatch for a cycle that can't
actually form (or a test fixture): `// ALLOW(ownership_cycle): reason` on the
REF_OWNED* line or the line above it.

Usage:
    python tools/ci/ownership_cycle_lint.py
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import state_schema_lint as schema  # noqa: E402
from allow_annotations import names_on  # noqa: E402

ROOT = schema.ROOT
DECL = re.compile(r"^REF_OWNED(?:_LIST|_VALUES)?\(\s*(/[\w/]+)\s*,\s*(.*)\)\s*(//.*)?$")
VAGUE = {"", "/datum", "/atom", "/atom/movable", "/obj", "/mob", "/turf", "/area",
         "/obj/item", "/obj/effect", "/obj/machinery", "/obj/structure", "/mob/living",
         "/datum/component", "/datum/element"}


def ancestors_inclusive(path):
    segs = path.strip("/").split("/")
    return ["/" + "/".join(segs[:i]) for i in range(len(segs), 0, -1)]


def related(a, b):
    return a == b or a.startswith(b + "/") or b.startswith(a + "/")


def main():
    files = schema.dm_files()
    decls, _, _ = schema.parse(files)
    var_types = {}
    for owner, vs in decls.items():
        for v in vs:
            var_types[(owner, v.name)] = v.vtype
    edges = {}  # owner type -> [(child type, var, where)]
    for path in files:
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        with open(path, encoding="utf-8", errors="ignore") as f:
            prev = ""
            for no, line in enumerate(f, 1):
                m = DECL.match(line.strip())
                allowed = "ownership_cycle" in names_on(line) or (prev.lstrip().startswith("//") and "ownership_cycle" in names_on(prev))
                prev = line
                if not m or allowed:
                    continue
                owner = m.group(1).rstrip("/")
                for name in re.findall(r'"(\w+)"', m.group(2)):
                    vtype = None
                    for anc in ancestors_inclusive(owner):
                        if (anc, name) in var_types:
                            vtype = var_types[(anc, name)]
                            break
                    if vtype is None or vtype in VAGUE:
                        continue
                    # A var typed as the owner's own kind (a gift holding an item,
                    # shoes holding shoes) is a container, not a mutual pair.
                    if owner == vtype or owner.startswith(vtype + "/"):
                        continue
                    edges.setdefault(owner, []).append((vtype, name, f"{rel}:{no}"))

    owners = list(edges)

    def out_edges(t):
        # What an instance whose declared type is `t` owns: declarations on t
        # and its ancestors (inherited).
        for o in owners:
            if t == o or t.startswith(o + "/"):
                yield from ((o,) + e for e in edges[o])

    problems = set()
    for start in owners:
        for (vtype, name, where) in edges[start]:
            # DFS from the child type looking for a way back to `start`.
            stack = [(vtype, [f"{start}.{name} ({where})"])]
            seen = set()
            while stack:
                t, trail = stack.pop()
                if t in seen:
                    continue
                seen.add(t)
                for (o, child, cname, cwhere) in out_edges(t):
                    step = trail + [f"{o}.{cname} ({cwhere})"]
                    if start == child or start.startswith(child + "/"):
                        problems.add(" -> ".join(step) + f" -> back to {start}")
                        continue
                    if len(step) < 6:
                        stack.append((child, step))
    for p in sorted(problems):
        print(f"ownership cycle: {p}")
    if problems:
        print(f"ownership_cycle_lint: {len(problems)} cycle(s). One side owns; the other "
              "holds a plain ref nulled in Destroy() or a handle.")
        return 1
    print(f"ownership_cycle_lint: {sum(len(v) for v in edges.values())} typed owned edges, no cycles.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
