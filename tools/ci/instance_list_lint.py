#!/usr/bin/env python3
"""Flags type-level list vars that allocate a list for every instance.

In DM, `var/list/foo = list()` (or `new/list`, `new()`, `list/foo[4]`) on a type
body runs once per instance at creation, so every instance gets its own list even
if it never uses it. AGENTS.md section 3a has the alternatives: a static var or a
getter for constant tables, a lazy (null) list for per-instance data that is
usually empty, and a shared copy-on-write list for data that is rarely written.

Singletons are exempt without an annotation, detected structurally: a type
under /datum/world_service or /datum/controller, or the exact type a
GLOBAL_DATUM_INIT(name, /type, new...) creates. One instance means one list.
Unit tests, benchmarks and the vendored TGS DMAPI are exempt by path
(allow_annotations.exempt_path()).

Declarations that really are per-instance and non-empty carry
`// ALLOW(instance_list): <reason>` on the declaration line or the comment line
above it (tools/ci/allow_annotations.py). Legacy declarations nobody has
reasoned about yet live in tools/ci/instance_list_baseline.txt (file + line
text), which only shrinks. The lint fails on any other declaration.

Usage: python3 tools/ci/instance_list_lint.py [--list | --update | --seed]
  --list    print every unannotated, non-singleton declaration and exit 0.
  --update  drop fixed declarations from the baseline (never adds).
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from allow_annotations import allowed, check_sites, exempt_path, write_sites  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SCAN_DIRS = ["code"]
BASELINE = os.path.join(ROOT, "tools", "ci", "instance_list_baseline.txt")
SINGLETON_ROOTS = ("/datum/world_service", "/datum/controller")
GLOBAL_DATUM = re.compile(r"GLOBAL_DATUM_INIT\(\s*\w+\s*,\s*(/[\w/]+)\s*,\s*new")

# var/[mods/]list/[typed/path/]name = list(...) | new/list(...) | new(...) | new
INIT_RE = re.compile(
    r"^(?:var/)?(?P<mods>(?:\w+/)*?)list/(?:\w+/)*?(?P<name>\w+)\s*"
    r"(?:=\s*(?:list\s*\(|alist\s*\(|new\s*/list|new\s*\(|new\s*$)|\[\s*\w+\s*\])"
)
SHARED_MODS = ("static", "global", "const")
LINT = "instance_list"


def indent_of(line):
    return len(line) - len(line.lstrip("\t"))


def strip_comment(text):
    # Good enough for declarations: cut a // that is not inside a string.
    in_str = None
    for i, ch in enumerate(text):
        if in_str:
            if ch == in_str and text[i - 1] != "\\":
                in_str = None
        elif ch in "\"'":
            in_str = ch
        elif text.startswith("//", i):
            return text[:i].rstrip()
    return text.rstrip()


def scan_file(path):
    """Yields (type_path, var_name, line_number, lines) for per-instance list declarations. The
    caller applies the singleton exemption and then asks allowed(): an annotation only counts as
    used when the declaration would otherwise be flagged."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().split("\n")
    type_path = None
    in_proc = False
    proc_indent = 0
    var_block = None  # (indent, modifiers) of an open `var` block
    in_comment = False
    for number, raw in enumerate(lines, 1):
        line = raw.rstrip("\r")
        stripped = line.strip()
        if in_comment:
            if "*/" in stripped:
                in_comment = False
            continue
        if stripped.startswith("/*") and "*/" not in stripped:
            in_comment = True
            continue
        if not stripped or stripped.startswith("//") or stripped.startswith("#"):
            continue
        depth = indent_of(line)
        body = strip_comment(stripped)
        if depth == 0:
            var_block = None
            in_proc = False
            type_path = None
            if "(" in body:
                in_proc = True  # a top-level proc definition
                continue
            if not body.startswith("/"):
                continue
            match = re.match(r"^(/[\w/]+?)/var/(.*)$", body)
            if match:
                decl = INIT_RE.match("var/" + match.group(2))
                if decl and not any(m in decl.group("mods") for m in SHARED_MODS):
                    yield match.group(1), decl.group("name"), number, lines
                continue
            type_path = body.rstrip("{").strip()
            continue
        if type_path is None:
            continue
        if in_proc:
            if depth > proc_indent:
                continue
            in_proc = False
        if var_block is not None and depth <= var_block[0]:
            var_block = None
        if var_block is None and re.match(r"^(?:(?:proc|verb)/)?\w+\(.*\)\s*$", body):
            in_proc = True
            proc_indent = depth
            continue
        if var_block is None and re.match(r"^var(?:/(?:static|global|tmp|const))*$", body):
            var_block = (depth, body[3:].strip("/"))
            continue
        if body.startswith("var/"):
            candidate = body
        elif var_block is not None:
            candidate = "var/" + (var_block[1] + "/" if var_block[1] else "") + body
        else:
            continue
        decl = INIT_RE.match(candidate)
        if decl and not any(m in decl.group("mods").split("/") for m in SHARED_MODS):
            yield type_path, decl.group("name"), number, lines


def singleton_types():
    """Exact types some GLOBAL_DATUM_INIT(name, /type, new...) creates (bare /datum excluded)."""
    types = set()
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "code")):
        for name in files:
            if name.endswith(".dm"):
                with open(os.path.join(dirpath, name), encoding="utf-8", errors="replace") as handle:
                    text = handle.read()
                if "GLOBAL_DATUM_INIT" in text:
                    types.update(m.group(1) for m in GLOBAL_DATUM.finditer(text))
    types.discard("/datum")
    return types


def is_singleton(type_path, globals_):
    return type_path in globals_ or any(type_path == r or type_path.startswith(r + "/") for r in SINGLETON_ROOTS)


def scan():
    found = {}
    globals_ = singleton_types()
    for top in SCAN_DIRS:
        base = os.path.join(ROOT, top)
        if not os.path.isdir(base):
            continue
        for dirpath, _dirs, files in os.walk(base):
            for name in files:
                if not name.endswith(".dm"):
                    continue
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
                if exempt_path(rel):
                    continue
                for type_path, var_name, number, lines in scan_file(path):
                    if is_singleton(type_path, globals_) or allowed(lines, number, LINT):
                        continue
                    found.setdefault(f"{type_path}/{var_name}", f"{rel}:{number}")
    return found


def main():
    found = scan()
    if "--list" in sys.argv:
        for key in sorted(found):
            print(f"{key} # {found[key]}")
        return 0
    sites = {"instance_list": []}
    for where in sorted(found.values()):
        rel, number = where.rsplit(":", 1)
        sites["instance_list"].append((rel, int(number)))
    if "--update" in sys.argv or "--seed" in sys.argv:
        rows = write_sites(BASELINE, [
            "Per-instance list declarations not yet reasoned about (tools/ci/instance_list_lint.py).",
            "rule<TAB>file<TAB>normalized line. Shrink-only: convert (AGENTS.md 3a) or give a real",
            "`// ALLOW(instance_list): <reason>`, then `python tools/ci/instance_list_lint.py --update`.",
        ], sites, shrink_only="--seed" not in sys.argv)
        print(f"instance_list_lint: baseline {rows} declarations")
        return 0
    failed = check_sites("instance_list", sites, BASELINE,
                         "allocates a list per instance: use a static var or getter (constant table), a lazy "
                         "list (usually empty) or a shared copy-on-write list (AGENTS.md 3a); if it really is "
                         "per-instance and always filled, mark it `// ALLOW(instance_list): <reason>`")
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main())
