"""Declared-reference kinds shared by declared_refs_lint.py and scheduler_lints.py
(doc/rewrite/lifecycle.md sec 4, code/__defines/lifecycle.dm).

One place for: the DECLARE_REF(PATH, "var", KIND, OPT) form and its kinds,
pooled types (POOL_DECLARE), the implicit DEF types (DEF_TYPES) and the
singleton / flyweight types marked OM_STATIC_TYPE (static_types()).
"""
import glob
import os
import re

from state_schema_lint import DEF_TYPES, under

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

# Every kind DECLARE_REF(PATH, "var", KIND, OPT) accepts (code/__defines/lifecycle.dm,
# REFKIND_*), and what OPT is for it: None (OPT must be null) or a description.
REF_KINDS = {
    "OWNED": None, "OWNED_LIST": None, "OWNED_VALUES": None, "SPILL": None, "SPILL_LIST": None,
    "HELD": None, "DROP": None, "KEEP": None, "DEF": None, "STATIC": None, "WEAK_LIST": None,
    "TRANSIENT": None,
    "PAIR": "the partner's var pointing back",
    "BACKLIST": "the owner's list var",
    "BACKLIST_HANDLE": "the partner's list var(s)",
    "BACK_HANDLE": "the partner's var naming us",
    "BACK_VIA": "the partner's var(s) naming us",
    "LIST_BACK": "the member var(s) naming us",
    "BACK": "the owner's var pointing at us, or null",
    "QUEUE": "a global getter proc path, or a list of them",
}
# Kinds whose var may legitimately hold objects in a list.
OBJLIST_KINDS = ("OWNED_LIST", "OWNED_VALUES", "SPILL_LIST", "DEF", "STATIC", "DROP", "LIST_BACK", "WEAK_LIST")
REF_DECL = re.compile(r'^DECLARE_REF\(\s*(/[\w/]+)\s*,\s*"([^"]*)"\s*,\s*(\w+)\s*,(.*)\)\s*(//.*)?$')
OM_STATIC_TYPE = re.compile(r"^OM_STATIC_TYPE\(\s*(/[\w/]+)\s*\)", re.M)
POOL_DECLARE = re.compile(r"^POOL_DECLARE\(\s*(/[\w/]+)\s*\)\s*$", re.M)
# The one hand-written declaration proc left: OM caches (code/datums/om/entity.dm).
DECLARED_PROCS = ("declared_cache_vars",)


def ref_decl(line):
    """A DECLARE_REF line -> (owner, var, kind, opt) with opt stripped, or None.
    Raises ValueError for an unknown kind."""
    m = REF_DECL.match(line.strip())
    if not m:
        return None
    owner, var, kind, opt = m.group(1), m.group(2), m.group(3), m.group(4).strip()
    if kind not in REF_KINDS:
        raise ValueError("unknown DECLARE_REF kind %s (one of %s)" % (kind, ", ".join(sorted(REF_KINDS))))
    return owner.rstrip("/"), var, kind, opt


_POOLED = None


def pooled_types():
    """Every type declared with POOL_DECLARE across code/ (read once)."""
    global _POOLED
    if _POOLED is None:
        found = set()
        for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
            with open(path, encoding="utf-8", errors="replace") as handle:
                text = handle.read()
            if "POOL_DECLARE(" in text:
                found.update(POOL_DECLARE.findall(text))
        _POOLED = tuple(sorted(found))
    return _POOLED


def is_pooled(type_path):
    return under(type_path, pooled_types())


def is_def_type(vtype):
    """An implicit DEF declaration: the var's declared type is a frozen definition type."""
    return under(vtype, DEF_TYPES)


_STATIC = None


def static_types():
    """Every type marked OM_STATIC_TYPE across code/ (read once), plus the frozen
    definition types (DEF_TYPES): singletons and flyweights, which a reference
    holds with DECLARE_REF(..., STATIC) and never with a handle."""
    global _STATIC
    if _STATIC is None:
        found = set(DEF_TYPES)
        for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
            with open(path, encoding="utf-8", errors="replace") as handle:
                text = handle.read()
            if "OM_STATIC_TYPE(" in text:
                found.update(OM_STATIC_TYPE.findall(text))
        _STATIC = tuple(sorted(found))
    return _STATIC


def is_static_type(type_path):
    """A singleton / flyweight type (OM_STATIC_TYPE or DEF_TYPES), or a subtype of one."""
    return under(type_path, static_types())
