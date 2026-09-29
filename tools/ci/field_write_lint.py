"""Declared-field write lint (doc/rewrite/object_model_core.md sec 5.1).

A declared field is declared once with OM_FIELD(type, name, default, channel) or
OM_FIELD_TYPED(type, vartype, name, default, channel) (code/__defines/om.dm). The macro expands
to the var `name` and its setter `set_name()`, which raises the channel. The only writers allowed
are that generated setter and the initial value (the OM_FIELD default, or a subtype's
`name = x` override in its type body). This finds every other write, in any proc (Initialize()
and New() included) of any file, unit tests included:

  - a bare write (`name = x`, `src.name = x`, `name |= x`, `name++`, ...) in a proc of a type
    related to a declaring type (the type, a subtype, or an ancestor an instance of it runs);
  - a dotted write (`thing.name = x`) whose receiver is not provably of an unrelated type: a
    receiver typed as a related type, or one whose type the lint can't resolve (a member var, a
    chained access), counts. Only a receiver declared in the proc as a type unrelated to every
    declaring type is skipped, since that is a different var of the same name.

om_set(E, "name", v) (fields.dm) is the by-name write path; `vars[...] =` is linted separately
(api_lints.py vars_write).

Used by tools/ci/api_lints.py (count `field_write`, which scans unit tests for this check);
run alone for a report:
    python tools/ci/field_write_lint.py
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import code_only  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

FIELD_RE = re.compile(r"^OM_FIELD\(\s*(/[\w/]+)\s*,\s*(\w+)\s*,")
FIELD_TYPED_RE = re.compile(r"^OM_FIELD_TYPED\(\s*(/[\w/]+)\s*,\s*[\w/]+\s*,\s*(\w+)\s*,")
# OM_FLAG_FIELD / OM_FLAG_FIELD_BITS (generated setters set_F, F_add, F_remove) and
# OM_FIELD_SETTER (a hand-written set_F on T): same shape as OM_FIELD for this lint.
FIELD_OTHER_RE = re.compile(r"^OM_(?:FLAG_FIELD(?:_BITS)?|FIELD_SETTER)\(\s*(/[\w/]+)\s*,\s*(\w+)\s*,")
FLAG_FIELD_RE = re.compile(r"^OM_FLAG_FIELD(?:_BITS)?\(\s*(/[\w/]+)\s*,\s*(\w+)\s*,")
PROC_DEF_RE = re.compile(r"^(/[\w/]+?)/(?:(?:proc|verb)/)?(\w+)\((.*)$")
TYPED_NAME_RE = re.compile(r"(?:var/)?((?:/?\w+)(?:/\w+)+)/(\w+)\b")
# An untyped proc parameter (`proc/f(on, state = 1)`) or local (`var/on`, `var/tmp/on`): it
# shadows a field of the same name.
UNTYPED_PARAM_RE = re.compile(r"(?:^|,)\s*(\w+)\s*(?==|,|\)|$)")
UNTYPED_VAR_RE = re.compile(r"\bvar/(?:(?:tmp|static|global|const)/)?(\w+)\b(?!/)")
WRITE_OPS = r"(?:=(?!=)|\+=|-=|\|=|&=|\^=|\*=|/=|\+\+|--)"


def dm_files():
    for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        yield rel, path


# DM's implicit parents: /obj and /mob are /atom/movable, /turf and /area are /atom, and /atom
# is a /datum, although their paths don't say so.
IMPLICIT = (("/obj", "/datum/atom/movable/obj"), ("/mob", "/datum/atom/movable/mob"),
            ("/turf", "/datum/atom/turf"), ("/area", "/datum/atom/area"), ("/atom", "/datum/atom"))


def canon(path):
    for top, full in IMPLICIT:
        if path == top or path.startswith(top + "/"):
            return full + path[len(top):]
    return path


def related(a, b):
    """True when type path a is b, a subtype of b, or an ancestor of b."""
    a, b = canon(a), canon(b)
    return a == b or a.startswith(b + "/") or b.startswith(a + "/")


def declared_fields():
    """field name -> list of declaring types, from every OM_FIELD()/OM_FIELD_TYPED() line."""
    fields = {}
    for _, path in dm_files():
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                m = FIELD_RE.match(line) or FIELD_TYPED_RE.match(line) or FIELD_OTHER_RE.match(line)
                if m:
                    fields.setdefault(m.group(2), []).append(m.group(1))
    return fields


TYPE_LINE_RE = re.compile(r"^(/[\w/]+)\s*(?:\{.*)?$")
MEMBER_RE = re.compile(r"^\s+var/((?:[\w]+/)*)(\w+)\b")
ABS_MEMBER_RE = re.compile(r"^(/[\w/]+?)/var/((?:[\w]+/)*)(\w+)\b")
MODIFIERS = {"tmp", "static", "global", "const", "final"}


def member_types():
    """type path -> member var name -> declared type (only typed members)."""
    members = {}

    def add(owner, path, name):
        parts = [p for p in path.split("/") if p and p not in MODIFIERS]
        if parts:
            members.setdefault(owner, {})[name] = "/" + "/".join(parts)

    for _, path in dm_files():
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = code_only(handle.read())
        current = None
        for line in text.split("\n"):
            if line and not line[0].isspace():
                m = ABS_MEMBER_RE.match(line)
                if m:
                    add(m.group(1), m.group(2), m.group(3))
                    current = None
                    continue
                m = TYPE_LINE_RE.match(line.rstrip())
                current = m.group(1) if m and "(" not in line else None
                continue
            if current:
                m = MEMBER_RE.match(line)
                if m:
                    add(current, m.group(1), m.group(2))
    return members


def member_type(owner, name):
    members = index_members()
    path = owner
    while path:
        t = members.get(path, {}).get(name)
        if t:
            return t
        path = path.rsplit("/", 1)[0] if path.count("/") > 1 else None
    return None


def norm(path):
    return path if path.startswith("/") else "/" + path


def violations(fields, rel, text):
    """(line, field, how) for every write to a declared field in this file outside its setter."""
    names = "|".join(sorted(fields, key=len, reverse=True))
    if not names:
        return
    bare = re.compile(r"(?<![\w./])(?:src\.)?(" + names + r")\s*" + WRITE_OPS)
    dotted = re.compile(r"(?<![\w])(\w+)(?:\?)?\.(" + names + r")\s*" + WRITE_OPS)
    owner, proc, locals_ = None, None, {}
    for no, line in enumerate(text.split("\n"), 1):
        if line and not line[0].isspace():
            m = PROC_DEF_RE.match(line)
            if m and not line.startswith("#"):
                owner, proc = norm(m.group(1)), m.group(2)
                locals_ = {}
                for tm in TYPED_NAME_RE.finditer(m.group(3)):
                    locals_[tm.group(2)] = norm(tm.group(1))
                for pm in UNTYPED_PARAM_RE.finditer(m.group(3)):
                    locals_.setdefault(pm.group(1), None)
                continue
            owner, proc = None, None
            continue
        if owner is None:
            continue
        for vm in UNTYPED_VAR_RE.finditer(line):
            locals_.setdefault(vm.group(1), None)
        for tm in TYPED_NAME_RE.finditer(line):
            if "var/" in line[max(0, tm.start() - 4):tm.start() + 4] or line[tm.start():].startswith("var/"):
                locals_[tm.group(2)] = norm(tm.group(1))
        for m in bare.finditer(line):
            field = m.group(1)
            if line[:m.start()].rstrip().endswith("var") or re.search(r"var/(?:[\w/]+/)?$", line[:m.start()]):
                continue
            if field in locals_:
                continue  # a local of the same name shadows the field
            before, after = line[:m.start()].rstrip(), line[m.end():].rstrip()
            if before.endswith(("(", ",")) or after.endswith(","):
                continue  # a named argument or a list entry (`f(x, on = y)`, `on = y,` in a list)
            if proc in ("set_" + field, field + "_add", field + "_remove") and any(owner == t for t in fields[field]):
                continue  # the generated setters (and only the declaring type's)
            if any(related(owner, t) for t in fields[field]):
                yield no, field, "%s/%s" % (owner, proc)
        for m in dotted.finditer(line):
            recv, field = m.group(1), m.group(2)
            if recv == "src":
                continue  # handled as a bare write
            if m.start() > 0 and line[m.start() - 1] == ".":
                rtype = chain_type(owner, locals_, line[:m.start()], recv)  # a.b.recv.field
            else:
                rtype = locals_.get(recv) or member_type(owner, recv)
            if rtype and not any(related(rtype, t) for t in fields[field]):
                continue  # a typed receiver of an unrelated type: a different var
            yield no, field, "%s.%s in %s/%s" % (recv, field, owner, proc)


CHAIN_RE = re.compile(r"((?:\w+\??\.)+)$")
GLOBAL_DATUM_RE = re.compile(r"GLOBAL_DATUM(?:_INIT)?\(\s*(\w+)\s*,\s*(/[\w/]+)")


def global_types():
    """GLOB var name -> declared type, from GLOBAL_DATUM()/GLOBAL_DATUM_INIT()."""
    if "globals" not in _CACHE:
        out = {}
        for _, path in dm_files():
            with open(path, encoding="utf-8", errors="replace") as handle:
                for gm in GLOBAL_DATUM_RE.finditer(handle.read()):
                    out[gm.group(1)] = gm.group(2)
        _CACHE["globals"] = out
    return _CACHE["globals"]


def chain_type(owner, locals_, before, recv):
    """The type of `recv` in `a.b.recv` (before = the text up to recv), walking typed members
    from the head (a local, a member of the owner, or GLOB.x); None when a link is unknown."""
    cm = CHAIN_RE.search(before)
    if not cm:
        return None
    links = [x.rstrip("?") for x in cm.group(1).split(".") if x] + [recv]
    head = links[0]
    if head == "GLOB" and len(links) > 1:
        t = global_types().get(links[1])
        links = links[1:]
    elif head == "src":
        t = owner
    else:
        t = locals_.get(head) or member_type(owner, head)
    for link in links[1:]:
        if not t:
            return None
        t = member_type(t, link)
    return t


_CACHE = {}


def index():
    if "fields" not in _CACHE:
        _CACHE["fields"] = declared_fields()
    return _CACHE["fields"]


def index_members():
    if "members" not in _CACHE:
        _CACHE["members"] = member_types()
    return _CACHE["members"]


def check(rel, text):
    """api_lints.py check: one line number per direct write."""
    for no, _, _ in violations(index(), rel, text):
        yield no


def main():
    fields = index()
    total = 0
    for rel, path in dm_files():
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = code_only(handle.read())
        for no, field, where in violations(fields, rel, text):
            print("%s:%d: direct write to declared field %s (%s): use set_%s()" % (rel, no, field, where, field))
            total += 1
    print("declared fields: %d; direct writes: %d" % (len(fields), total))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
