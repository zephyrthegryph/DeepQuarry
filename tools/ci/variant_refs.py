#!/usr/bin/env python3
"""Turn the references to a collapsed family's old types into VARIANT() references (code/content/variants/README.md).

  python3 tools/ci/variant_refs.py PARENT            # report the references that would change and the ones that need a hand
  python3 tools/ci/variant_refs.py PARENT --apply    # rewrite them

Run it after tools/ci/variant_collapse.py has moved the leaves into the table. A reference is `PARENT/key` (a row of the table, no further
path segment) in a .dm file under code/ outside code/tests/: `trash = /obj/item/trash/popcorn` becomes `trash = VARIANT(/obj/item/trash, "popcorn")`,
a loot table key `/obj/item/trash/popcorn = 3` becomes `VARIANT(/obj/item/trash, "popcorn") = 3`.

It lists, and leaves alone, a reference that a list cannot stand in for: inside `istype(`/`ispath(`/`typesof(`/`subtypesof(`/`is_type_in_list(`
and similar, in a string or a comment, or as a type definition (`/obj/item/trash/popcorn` at the start of a line). Those are fixed by hand: a check against
the family is `istype(x, PARENT)` plus a test of the variant, and a definition is a row.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_variants as cv  # noqa: E402

ROOT = cv.ROOT
TYPE_CTX = re.compile(r"\b(istype|ispath|typesof|subtypesof|is_type_in_list|is_path_in_list|text2path|type2parent|initial|cache_type|locate_on|turf_contents_of_type|get_type|GET_DECL|LAZYLEN)\s*\([^()]*$")


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 1:
        print(__doc__)
        return 2
    parent = args[0]
    apply = "--apply" in argv
    parents = cv.load_registry()
    if parent not in parents:
        print("%s is not in the variant registry; run tools/ci/variant_collapse.py first" % parent)
        return 1
    files = list(cv.dm_files())
    rows = cv.load_tables([f for f in files if "dq_variants_" in open(f, encoding="utf-8", errors="replace").read()])
    keys = rows[parents[parent]]
    pat = re.compile(re.escape(parent) + r"/(\w+)(?![\w/])")
    changed = 0
    manual = []
    for full in files:
        rel = os.path.relpath(full, ROOT).replace("\\", "/")
        if rel.startswith("code/tests/") or "/variants/" in rel and os.path.basename(full).startswith("variant"):
            continue
        text = open(full, encoding="utf-8", errors="replace", newline="").read()
        if parent + "/" not in text:
            continue
        out = []
        dirty = False
        for n, line in enumerate(text.split("\n"), 1):
            def sub(m):
                nonlocal dirty, changed
                key = m.group(1)
                if key not in keys:
                    return m.group(0)
                before = line[:m.start()]
                if before.count('"') % 2 == 1 or "//" in before:
                    manual.append("%s:%d: in a string or comment: %s" % (rel, n, line.strip()[:110]))
                    return m.group(0)
                if before == "":
                    manual.append("%s:%d: a definition: %s" % (rel, n, line.strip()[:110]))
                    return m.group(0)
                if TYPE_CTX.search(before):
                    manual.append("%s:%d: a type check or lookup: %s" % (rel, n, line.strip()[:110]))
                    return m.group(0)
                dirty = True
                changed += 1
                return 'VARIANT(%s, "%s")' % (parent, key)
            out.append(pat.sub(sub, line))
        if dirty and apply:
            open(full, "w", encoding="utf-8", newline="").write("\n".join(out))
    print("%s: %d reference(s) %s, %d need a hand" % (parent, changed, "rewritten" if apply else "to rewrite", len(manual)))
    for m in manual:
        print("  manual:", m)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
