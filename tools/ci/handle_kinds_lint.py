"""Handle-kind lint (doc/rewrite/object_model_core.md, "Ownership").

Every datum has exactly one owner. An OM handle (om_handle(), a weak "id:gen"
text) is ONLY for a reference to another live entity whose lifetime something
else manages. A handle is not a reference: when it is the only thing naming its
target, BYOND frees the target at once (the shuttle landed_holder bug). Two
mistakes follow from using one anyway, and this lint refuses both:

  (a) static-target   a handle var whose target type is a singleton / flyweight
                      (OM_STATIC_TYPE, or a DEF_TYPES definition). Those are held
                      with REF_STATIC, or read from their registry at the use site.
                      Found through the handle's typed accessor
                      (`/T/proc/x() as /X` returning om_resolve(x_handle)), and
                      through `om_handle(SSfoo)` (a subsystem).
  (b) orphan          `om_handle(new /datum/...)`, or a local set from `new` and
                      then handed to om_handle() (or a fresh .clone()/.diverge()/
                      .Copy() handed straight to it) with no other use that could keep
                      it (stored in a var or list, passed to a call, returned).
                      The new datum has no owner: the holder owns it (REF_OWNED)
                      or holds it (REF_HELD / a tmp strong var). Atoms created on
                      a location are owned by that location and are not flagged.

A justified keep carries `// ALLOW(handle_kinds): <reason>` on the line or the
comment line above it (tools/ci/allow_annotations.py).

Usage:
    python tools/ci/handle_kinds_lint.py            # fail on any site
    python tools/ci/handle_kinds_lint.py --report   # list every site
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from allow_annotations import allowed, dm_files  # noqa: E402
from ref_kinds import is_static_type  # noqa: E402

LINT = "handle_kinds"
ACCESSOR = re.compile(r"^(/[\w/]+)/proc/(\w+)\(\)\s*as\s+(/[\w/]+)\s*\n\s*return om_resolve\((\w+)\)", re.M)
SUBSYSTEM_HANDLE = re.compile(r"\bom_handle\(\s*SS\w+\s*\)")
NEW_DATUM_HANDLE = re.compile(r"\bom_handle\(\s*new\s*(/datum/[\w/]*)?\s*[(\)]")
# A handle to a copy made on the spot: nothing else holds the copy.
COPY_HANDLE = re.compile(r"om_handle\([^()]*\.(?:clone|diverge|Copy|copy_\w+|duplicate)\(")
PROC_START = re.compile(r"^/\S")
NEW_LOCAL = re.compile(r"^\s*var/((?:[\w]+/)*)(\w+)\s*=\s*new\b")
ATOM_ROOTS = ("atom/", "turf/", "area/", "obj/", "mob/", "image/")


def code_part(line):
    return line.split("//", 1)[0]


def orphan_locals(body):
    """(index, name) of each om_handle(local) in a proc body where the local was
    set from `new` as a datum and has no other use that could keep it."""
    found = []
    for i0, line in enumerate(body):
        m = NEW_LOCAL.match(line)
        if not m:
            continue
        vtype, name = m.group(1), m.group(2)
        if vtype.startswith(ATOM_ROOTS) or not vtype.startswith("datum/"):
            continue
        use = re.compile(r"(?<![\w.])%s\b" % re.escape(name))
        handed = re.compile(r"\bom_handle\(\s*%s\s*\)" % re.escape(name))
        handles, kept = [], False
        for i in range(i0 + 1, len(body)):
            code = code_part(body[i])
            if handed.search(code):
                handles.append(i)
                code = handed.sub("", code)
            for u in use.finditer(code):
                rest = code[u.end():].lstrip()
                if rest.startswith((".", ":")):
                    continue  # field access / method call on it: does not keep it
                kept = True
                break
            if kept:
                break
        if handles and not kept:
            found.append((handles[0], name))
    return found


def main(argv):
    report = "--report" in argv
    sites = []
    for path, rel in dm_files():
        if not rel.startswith("code/"):
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        if "om_handle" not in text and "om_resolve" not in text:
            continue
        lines = text.split("\n")
        for m in ACCESSOR.finditer(text):
            owner, proc, target, var = m.groups()
            if is_static_type(target):
                no = text.count("\n", 0, m.start()) + 1
                if not allowed(lines, no, LINT) and not allowed(lines, no - 1, LINT):
                    sites.append((rel, no, "static-target", "%s.%s is a handle to %s (a singleton/flyweight): use REF_STATIC or the registry" % (owner, var, target)))
        for no, line in enumerate(lines, 1):
            code = code_part(line)
            if "om_handle(" not in code:
                continue
            if SUBSYSTEM_HANDLE.search(code) and not allowed(lines, no, LINT):
                sites.append((rel, no, "static-target", "om_handle() of a subsystem: hold it strongly or read SSfoo directly"))
            if COPY_HANDLE.search(code) and not allowed(lines, no, LINT):
                sites.append((rel, no, "orphan", "om_handle() of a fresh copy: nothing owns the copy, so it is collected at once"))
            if NEW_DATUM_HANDLE.search(code) and not allowed(lines, no, LINT):
                sites.append((rel, no, "orphan", "om_handle(new datum): nothing owns it, so it is collected at once"))
        starts = [i for i, l in enumerate(lines) if PROC_START.match(l)] + [len(lines)]
        for a, b in zip(starts, starts[1:]):
            body = lines[a:b]
            for i, name in orphan_locals(body):
                no = a + i + 1
                if not allowed(lines, no, LINT):
                    sites.append((rel, no, "orphan", "`%s` is a new datum whose only reference is a handle: own it (REF_OWNED) or hold it strongly" % name))
    if report or sites:
        for rel, no, kind, msg in sites:
            print("%s:%d: %s: %s" % (rel, no, kind, msg))
    if sites:
        print("handle_kinds_lint: %d site(s). Handles are only for other live entities whose "
              "lifetime something else manages (doc/rewrite/object_model_core.md, Ownership)." % len(sites))
        return 1
    print("handle_kinds_lint: no handles to singletons, no handle-only new datums.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
