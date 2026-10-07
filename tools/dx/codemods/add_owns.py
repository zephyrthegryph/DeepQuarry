#!/usr/bin/env python3
"""Adds owns_one / owns_many entries to a type's CAPABILITIES block (made after the type's var block when there is none).

    python tools/dx/codemods/add_owns.py <file> <type> <entry> [<entry> ...]      entries as written: "owns_one(nameof(v), /datum/x)"

The block is the type's one composition root: when the type already has a CAPABILITIES header (in any file) the entries go under it.
"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import pathlib
import re
import sys


def find_header(type_path):
    pat = re.compile(r"^CAPABILITIES\(" + re.escape(type_path) + r"\)\s*$", re.M)
    for p in pathlib.Path("code").rglob("*.dm"):
        text = p.read_text(encoding="utf-8", errors="replace")
        m = pat.search(text.replace("\r\n", "\n"))
        if m:
            return p
    return None


def add(file, type_path, entries):
    host = find_header(type_path)
    if host:
        file = str(host)
    p = pathlib.Path(file)
    raw = p.read_bytes().decode("utf-8")
    crlf = "\r\n" in raw
    text = raw.replace("\r\n", "\n")
    header = f"CAPABILITIES({type_path})\n"
    block = "".join(f"\t{e}\n" for e in entries)
    if host:
        i = text.index(header) + len(header)
        # skip entries already there
        existing = text[i:text.find("\n\n", i)]
        block = "".join(f"\t{e}\n" for e in entries if e not in existing)
        text = text[:i] + block + text[i:]
    else:
        # before the first proc of the type, else before the first top-level definition after the type's own
        m = re.search(r"^" + re.escape(type_path) + r"/[A-Za-z_]", text, re.M)
        decl = re.search(r"^" + re.escape(type_path) + r"\s*$", text, re.M)
        if not decl:
            raise SystemExit(f"{file}: no `{type_path}` definition")
        if m and m.start() > decl.start():
            i = m.start()
        else:
            nxt = re.search(r"^/[A-Za-z_]", text[decl.end():], re.M)
            i = decl.end() + nxt.start() if nxt else len(text)
        text = text[:i] + header + block + "\n" + text[i:]
    p.write_bytes((text.replace("\n", "\r\n") if crlf else text).encode("utf-8"))
    print(f"{type_path}: {len(entries)} entr(y/ies) -> {file}")


if __name__ == "__main__":
    add(sys.argv[1], sys.argv[2], sys.argv[3:])
