#!/usr/bin/env python3
"""Flags type-level list vars that allocate a list for every instance.

In DM, `var/list/foo = list()` (or `new/list`, `new()`, `list/foo[4]`) on a type
body runs once per instance at creation, so every instance gets its own list even
if it never uses it. AGENTS.md section 3a has the alternatives: a static var or a
getter for constant tables, a lazy (null) list for per-instance data that is
usually empty, and a shared copy-on-write list for data that is rarely written.

Declarations that really are per-instance and non-empty carry
`// ALLOW(instance_list): <reason>` on the declaration line or the comment line
above it (tools/ci/allow_annotations.py). The lint fails on any other.

Usage: python3 tools/ci/instance_list_lint.py [--list]
  --list  print every unannotated declaration and exit 0.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from allow_annotations import allowed  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SCAN_DIRS = ["code", "modular_chomp"]

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
    """Yields (type_path, var_name, line_number) for per-instance list declarations."""
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
                if decl and not any(m in decl.group("mods") for m in SHARED_MODS) and not allowed(lines, number, LINT):
                    yield match.group(1), decl.group("name"), number
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
        if decl and not any(m in decl.group("mods").split("/") for m in SHARED_MODS) and not allowed(lines, number, LINT):
            yield type_path, decl.group("name"), number


def scan():
    found = {}
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
                for type_path, var_name, number in scan_file(path):
                    found.setdefault(f"{type_path}/{var_name}", f"{rel}:{number}")
    return found


def main():
    found = scan()
    if "--list" in sys.argv:
        for key in sorted(found):
            print(f"{key} # {found[key]}")
        return 0
    problems = [
        f"{found[key]}: {key} allocates a list for every instance. Use a static var or getter "
        "(constant table), a lazy list (usually empty), or a shared copy-on-write list "
        "(AGENTS.md 3a); if it really is per-instance and always filled, mark the declaration "
        "`// ALLOW(instance_list): <reason>`."
        for key in sorted(found)
    ]
    for problem in problems:
        print(problem)
    print(f"instance_list_lint: {len(found)} unannotated per-instance list declarations, {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
