#!/usr/bin/env python3
"""Mechanical conversion: starting reagents in Initialize() -> DECLARE_REAGENTS
(doc/rewrite/declarative_lifecycle.md, "Starting reagents").

Rewrites

    /obj/item/reagent_containers/pill/tox/Initialize(mapload)
        . = ..()
        reagents.add_reagent(REAGENT_ID_TOXIN, 50)
        color = reagents.get_color()

into

    DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/tox, null, list(REAGENT_ID_TOXIN = 50))

Only the leading run of `reagents.add_reagent(ID, <number>)` lines right after `. = ..()` moves
(a data argument, a computed amount or anything in between stops the run). A directly following
`color = reagents.get_color()` becomes the TINTED form when nothing else is left in the body.
The override is deleted when its body is left as only `. = ..()`.

A type is converted only when its holder comes from a declaration: it must lie under one of
ROOTS (types whose holder is DECLARE_REAGENTS-declared), and neither it nor an ancestor may call
create_reagents() / clear_reagents() / assign `reagents` in its own Initialize() (that would run
after the root and wipe the declared contents).

    python tools/ci/decl_convert_reagents.py [--dry-run] [path-prefix ...]

Prefixes limit the files touched (e.g. code/modules/food). Prints one line per conversion.
"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
# Types whose reagent holder is declared (DECLARE_REAGENTS with a volume).
ROOTS = ("/obj/item/reagent_containers", "/obj/structure/reagent_dispensers")

HEADER = re.compile(r"^(/[\w/]+)/Initialize\s*\(\s*(mapload)?\s*\)\s*(//.*)?$")
PARENT = re.compile(r"^\.\s*=\s*\.\.\(\)\s*(//.*)?$")
ADD = re.compile(r"^(?:src\.)?reagents\.add_reagent\(\s*(REAGENT_ID_\w+|\"[^\"]+\")\s*,\s*(\d+(?:\.\d+)?)\s*\)\s*(//.*)?$")
TINT = re.compile(r"^color\s*=\s*reagents\.get_color\(\)\s*(//.*)?$")
RESETS = re.compile(r"\bcreate_reagents\s*\(|\bclear_reagents\s*\(|^\s*(?:src\.)?reagents\s*=")


def under(path, roots):
    return any(path == r or path.startswith(r + "/") for r in roots)


def dm_files(prefixes):
    for base, _dirs, files in os.walk(os.path.join(ROOT, "code")):
        for name in files:
            if name.endswith(".dm"):
                full = os.path.join(base, name)
                rel = os.path.relpath(full, ROOT).replace("\\", "/")
                if rel.startswith("code/modules/unit_tests/"):
                    continue
                if not prefixes or rel.startswith(tuple(prefixes)):
                    yield full, rel


def overrides(lines):
    """(header index, type, body start, body end) per Initialize override."""
    i = 0
    while i < len(lines):
        m = HEADER.match(lines[i])
        if not m:
            i += 1
            continue
        j = i + 1
        while j < len(lines) and (not lines[j].strip() or lines[j][0].isspace()):
            j += 1
        # trailing blank lines belong to the gap, not the body
        end = j
        while end > i + 1 and not lines[end - 1].strip():
            end -= 1
        yield i, m.group(1), i + 1, end
        i = j


def reset_types(all_files):
    found = set()
    for full, _rel in all_files:
        lines = open(full, encoding="utf-8", errors="replace").read().replace("\r", "").split("\n")
        for _h, path, start, end in overrides(lines):
            if any(RESETS.search(l.split("//", 1)[0]) for l in lines[start:end]):
                found.add(path)
    return found


def main(argv):
    dry = "--dry-run" in argv
    prefixes = [a for a in argv if not a.startswith("--")]
    resets = reset_types(list(dm_files([])))
    total = 0
    for full, rel in dm_files(prefixes):
        raw = open(full, encoding="utf-8", errors="replace").read()
        crlf = "\r\n" in raw
        lines = raw.replace("\r", "").split("\n")
        edits = []
        for h, path, start, end in overrides(lines):
            if not under(path, ROOTS):
                continue
            parts = path.split("/")
            if any("/".join(parts[:k]) in resets for k in range(2, len(parts) + 1)):
                continue
            body = [l.strip() for l in lines[start:end]]
            idx = [k for k, l in enumerate(body) if l]
            if not idx or not PARENT.match(body[idx[0]]):
                continue
            pairs = []
            k = 1
            while k < len(idx) and ADD.match(body[idx[k]]):
                m = ADD.match(body[idx[k]])
                pairs.append((m.group(1), m.group(2)))
                k += 1
            if not pairs:
                continue
            tint = False
            rest = idx[k:]
            if len(rest) == 1 and TINT.match(body[rest[0]]):
                tint = True
                rest = []
            merged = {}
            for rid, amount in pairs:
                merged[rid] = merged.get(rid, 0) + float(amount)
            contents = ", ".join("%s = %s" % (rid, ("%g" % amt)) for rid, amt in merged.items())
            macro = "DECLARE_REAGENTS_TINTED" if tint else "DECLARE_REAGENTS"
            decl = "%s(%s, null, list(%s))" % (macro, path, contents)
            if rest:
                # header, `. = ..()`, then everything from the first unmoved line on
                replacement = [decl, "", lines[h], lines[start + idx[0]]] + lines[start + idx[k]:end]
            else:
                replacement = [decl]
            edits.append((h, end, replacement))
            print("%s:%d: %s%s" % (rel, h + 1, path, " (override kept)" if rest else ""))
        if not edits:
            continue
        total += len(edits)
        for h, end, replacement in reversed(edits):
            lines[h:end] = replacement
        if not dry:
            text = "\n".join(lines)
            if crlf:
                text = text.replace("\n", "\r\n")
            with open(full, "w", encoding="utf-8", newline="") as f:
                f.write(text)
    print("decl_convert_reagents: %d conversions%s" % (total, " (dry run)" if dry else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
