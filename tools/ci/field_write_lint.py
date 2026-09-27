"""Declared-field write lint (doc/rewrite/object_model_core.md sec 5.1).

A declared field (a decl's `fields = list("name" = CHANNEL)`, code/datums/om/fields.dm) is
written only through om_set() or its OM_SETTER() setter, which raise its channel. This finds
direct writes (`name = x`, `src.name = x`, `thing.name = x`, `name |= x`, `name++`, ...) to a
declared field in a proc of a related type (the declaring type, a subtype, or an ancestor an
instance of it can run), outside Initialize()/New() and the setter itself. `thing` counts when
its declared type in the proc (a typed var or argument) is related. It also checks every
OM_SETTER(type, field) names a declared field.

Used by tools/ci/api_lints.py (count `field_write`); run alone for a report:
    python tools/ci/field_write_lint.py
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import code_only  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

DECL_RE = re.compile(r"^(/datum/om/decl/[\w/]+)\s*$")
OF_RE = re.compile(r"^\s+of\s*=\s*(.+)$")
FIELD_ROW_RE = re.compile(r'"(\w+)"\s*=\s*([\w|() <>]+)')
SETTER_RE = re.compile(r"OM_SETTER\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\)")
PROC_DEF_RE = re.compile(r"^(/[\w/]+?)/(?:(?:proc|verb)/)?(\w+)\((.*)$")
TYPE_DEF_RE = re.compile(r"^(/[\w/]+)\s*$")
TYPED_NAME_RE = re.compile(r"(?:var/)?((?:/?\w+)(?:/\w+)+)/(\w+)\b")
EXEMPT_PROCS = {"Initialize", "New"}
WRITE_OPS = r"(?:=(?!=)|\+=|-=|\|=|&=|\^=|\*=|/=|\+\+|--)"


def dm_files():
    for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        yield rel, path


def related(a, b):
    """True when type path a is b, a subtype of b, or an ancestor of b."""
    return a == b or a.startswith(b + "/") or b.startswith(a + "/")


def declared_fields():
    """(field -> list of declaring types), setters as (rel, line, type, field)."""
    fields, setters = {}, []
    for rel, path in dm_files():
        with open(path, encoding="utf-8", errors="replace") as handle:
            raw = handle.read()
        lines = raw.split("\n")
        i = 0
        while i < len(lines):
            m = DECL_RE.match(lines[i])
            if not m:
                i += 1
                continue
            j, of, body = i + 1, [], []
            while j < len(lines) and (lines[j].startswith(("\t", " ")) or not lines[j].strip()):
                body.append(lines[j])
                j += 1
            text = "\n".join(body)
            for b in body:
                om = OF_RE.match(b)
                if om:
                    of = re.findall(r"/[\w/]+", om.group(1))
            fm = re.search(r"\bfields\s*=\s*list\((.*?)\)\s*(?:\n\s*\w+\s*=|\Z)", text, re.S)
            if fm and of:
                for name, _ in FIELD_ROW_RE.findall(fm.group(1)):
                    for t in of:
                        fields.setdefault(name, []).append(t)
            i = j
        for no, line in enumerate(lines, 1):
            for sm in SETTER_RE.finditer(line):
                if not line.lstrip().startswith("#define"):
                    setters.append((rel, no, sm.group(1), sm.group(2)))
    return fields, setters


def norm(path):
    return path if path.startswith("/") else "/" + path


def violations(fields, rel, text):
    """(line, field, how) for every direct write to a declared field in this file."""
    if rel == "code/datums/om/fields.dm":
        return
    names = "|".join(sorted(fields, key=len, reverse=True))
    if not names:
        return
    bare = re.compile(r"(?<![\w./])(?:src\.)?(" + names + r")\s*" + WRITE_OPS)
    dotted = re.compile(r"(?<![\w.])(\w+)(?:\?)?\.(" + names + r")\s*" + WRITE_OPS)
    owner, proc, locals_ = None, None, {}
    for no, line in enumerate(text.split("\n"), 1):
        if line and not line[0].isspace():
            m = PROC_DEF_RE.match(line)
            if m and not line.startswith("#"):
                owner, proc = norm(m.group(1)), m.group(2)
                locals_ = {}
                for tm in TYPED_NAME_RE.finditer(m.group(3)):
                    locals_[tm.group(2)] = norm(tm.group(1))
                continue
            owner, proc = None, None
            continue
        if owner is None:
            continue
        for tm in TYPED_NAME_RE.finditer(line):
            if "var/" in line[max(0, tm.start() - 4):tm.start() + 4] or line[tm.start():].startswith("var/"):
                locals_[tm.group(2)] = norm(tm.group(1))
        if proc in EXEMPT_PROCS:
            continue
        for m in bare.finditer(line):
            field = m.group(1)
            if proc == "set_" + field:
                continue
            if line[:m.start()].rstrip().endswith("var") or re.search(r"var/(?:[\w/]+/)?$", line[:m.start()]):
                continue
            if field in locals_:
                continue  # a local of the same name shadows the field
            if any(related(owner, t) for t in fields[field]):
                yield no, field, "%s/%s" % (owner, proc)
        for m in dotted.finditer(line):
            recv, field = m.group(1), m.group(2)
            if recv == "src":
                continue
            rtype = locals_.get(recv)
            if rtype and any(related(rtype, t) for t in fields[field]):
                yield no, field, "%s.%s in %s/%s" % (recv, field, owner, proc)


_CACHE = {}


def index():
    if "fields" not in _CACHE:
        _CACHE["fields"], _CACHE["setters"] = declared_fields()
    return _CACHE["fields"], _CACHE["setters"]


def check(rel, text):
    """api_lints.py check: one line number per direct write (and per bad setter)."""
    fields, setters = index()
    for no, _, _ in violations(fields, rel, text):
        yield no
    for srel, no, t, f in setters:
        if srel == rel and not any(t == d or t.startswith(d + "/") for d in fields.get(f, [])):
            yield no


def main():
    fields, setters = index()
    total = 0
    for rel, path in dm_files():
        if "/unit_tests/" in rel:
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = code_only(handle.read())
        for no, field, where in violations(fields, rel, text):
            print("%s:%d: direct write to declared field %s (%s): use its setter" % (rel, no, field, where))
            total += 1
    for rel, no, t, f in setters:
        if not any(t == d or t.startswith(d + "/") for d in fields.get(f, [])):
            print("%s:%d: OM_SETTER(%s, %s) names no declared field" % (rel, no, t, f))
            total += 1
    print("declared fields: %d; direct writes: %d" % (len(fields), total))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
