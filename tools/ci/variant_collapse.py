#!/usr/bin/env python3
"""Collapse the data-only leaf types under one parent into rows of a variant table (code/content/variants/README.md).

  python3 tools/ci/variant_collapse.py PARENT TABLE            # report what would move
  python3 tools/ci/variant_collapse.py PARENT TABLE --apply    # write the table, register it, delete the leaf blocks

PARENT is the type path the leaves sit directly under (a family in doc/rewrite/variant_census.md). TABLE is the slug of the table:
`GLOBAL_LIST_INIT(dq_variants_<TABLE>, ...)` in code/content/variants/<TABLE>.dm, registered in code/content/variants/variant_tables.dm.
A row's key is the last segment of the old path, so the old path (parent + "/" + key) still resolves through variant_alias_of()
(code/content/variants/variant_alias.dm) for maps and saves.

A falsey value (0, null, "", FALSE) moves with the row: variant_apply() sets it, and a list value is copied per instance.
A leaf moves only when its definition is top-level blocks (one or several in a file, merged) of plain `var = value` lines that a row can hold. It stays a type, and is listed
in the report, when:
  - a value reads src or calls a proc (a row holds constants);
  - the type is defined in more than one file, or not as a top-level block.
The parent still needs `var/variant`, `variants(nameof(variant), PROC_REF(variant_table))` and a `variant_table()` returning
`dq_variant_table(type)`; add them by hand (this tool does not edit the parent).
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import variant_census as vc  # noqa: E402

# a falsey scalar is carried and a list is copied per instance (variant_apply() sets it)
ASSIGN = re.compile(r"^([A-Za-z_]\w*)\s*=\s*(.*?)\s*(//.*)?$")


def strip_comment(s):
    """The line without a trailing // comment (outside strings)."""
    in_s = False
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and in_s:
            i += 2
            continue
        if c == '"':
            in_s = not in_s
        elif not in_s and s[i:i + 2] == "//":
            return s[:i].rstrip()
        i += 1
    return s.rstrip()


def find_block(lines, path):
    """Line index ranges (start, end exclusive) of top-level `path` blocks in a file."""
    found = []
    for i, ln in enumerate(lines):
        if strip_comment(ln).rstrip() == path:
            j = i + 1
            last = i
            while j < len(lines):
                l2 = lines[j]
                if l2.strip() == "":
                    j += 1
                    continue
                if l2[0] in "\t ":
                    last = j
                    j += 1
                    continue
                break
            found.append((i, last + 1))
    return found


def parse_body(lines):
    """[(var, value text)] or None when a line is not a plain assignment."""
    out = []
    buf = None
    for ln in lines:
        s = ln.strip()
        if buf is None:
            if not s or s.startswith("//"):
                continue
            buf = s
        else:
            buf += " " + s
        code = strip_comment(buf)
        depth = sum(code.count(c) for c in "([{") - sum(code.count(c) for c in ")]}")
        if depth > 0:
            continue
        m = ASSIGN.match(code)
        buf = None
        if not m:
            return None
        out.append((m.group(1), m.group(2)))
    if buf is not None:
        return None
    return out


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 2:
        print(__doc__)
        return 2
    parent, table = args
    apply = "--apply" in argv
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    _, _, fam = vc.census(root)
    leaves = sorted(fam.get(parent, []), key=lambda t: t.path)
    if not leaves:
        print("no data-only leaves directly under", parent)
        return 1
    rows = []
    kept = []
    edits = {}  # file -> [(start, end)]
    for t in leaves:
        key = t.path.rsplit("/", 1)[1]
        if len(t.files) != 1:
            kept.append((t.path, "defined in %d files" % len(t.files)))
            continue
        rel = next(iter(t.files))
        full = os.path.join(root, rel)
        if full not in edits:
            edits[full] = [open(full, encoding="utf-8", newline="").read().split("\n"), []]
        lines = edits[full][0]
        blocks = find_block([l.rstrip("\r") for l in lines], t.path)
        if not blocks:
            kept.append((t.path, "no top-level block"))
            continue
        # A type written as several blocks in one file is one row: the later block's value of a var wins, as the compiler reads them.
        merged = {}
        plain = True
        for s, e in blocks:
            part = parse_body([l.rstrip("\r") for l in lines[s + 1:e]])
            if part is None:
                plain = False
                break
            for var, val in part:
                merged[var] = val
        body = list(merged.items()) if plain else None
        if not body:
            kept.append((t.path, "body is not plain assignments"))
            continue
        bad = [v for v, x in body if re.search(r"\bsrc\b", x)]
        if bad:
            kept.append((t.path, "row cannot hold: %s" % ", ".join(bad)))
            continue
        if any(v in ("variant", "type", "parent_type") for v, _ in body):
            kept.append((t.path, "sets variant/type"))
            continue
        rows.append((key, body))
        edits[full][1].extend(blocks)
    print("%s: %d leaves, %d move, %d stay" % (parent, len(leaves), len(rows), len(kept)))
    for p, why in kept:
        print("  stays:", p, "-", why)
    if not apply or not rows:
        return 0
    # the table
    out = ["// Variants of %s: one row per type that only set data (doc/rewrite/variant_census.md). The old path, parent + \"/\" + key, still resolves" % parent,
           "// for maps and saves (variant_alias_of()). Started by tools/ci/variant_collapse.py.", "",
           "GLOBAL_LIST_INIT(dq_variants_%s, list(" % table]
    for key, body in rows:
        out.append('\t"%s" = list(%s),' % (key, ", ".join('"%s" = %s' % (v, x) for v, x in body)))
    out.append("))")
    tpath = os.path.join(root, "code", "content", "variants", table + ".dm")
    with open(tpath, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(out) + "\n")
    # the registry
    reg = os.path.join(root, "code", "content", "variants", "variant_tables.dm")
    text = open(reg, encoding="utf-8").read()
    line = "\t%s = \"dq_variants_%s\",\n" % (parent, table)
    marker = "))\n\n/// The variant table for"
    assert marker in text, "variant_tables.dm changed shape"
    head, tail = text.split(marker, 1)
    open(reg, "w", encoding="utf-8", newline="\n").write(head + line + marker + tail)
    # remove the leaf blocks
    for full, (lines, spans) in edits.items():
        if not spans:
            continue
        drop = set()
        for s, e in spans:
            drop.update(range(s, e))
            # one blank line after the block goes with it
            if e < len(lines) and lines[e].strip() == "":
                drop.add(e)
        kept_lines = [l for i, l in enumerate(lines) if i not in drop]
        body = "\n".join(kept_lines)
        if not body.strip():
            os.remove(full)
            print("deleted", os.path.relpath(full, root))
        else:
            open(full, "w", encoding="utf-8", newline="").write(body)
    print("wrote", os.path.relpath(tpath, root))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
