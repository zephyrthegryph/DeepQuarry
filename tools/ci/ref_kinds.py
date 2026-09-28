"""Declared-reference kinds shared by declared_refs_lint.py and scheduler_lints.py
(doc/rewrite/lifecycle.md sec 4, code/__defines/lifecycle.dm).

One place for: the one-line REF_* macro forms, the one-place REF_VAR forms,
pooled types (POOL_DECLARE), the implicit REF_DEF types (DEF_TYPES) and the
singleton / flyweight types marked OM_STATIC_TYPE (static_types()).
"""
import glob
import os
import re

from state_schema_lint import DEF_TYPES, under

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

# REF_OWNED(/type, NAMES) and friends -> the declared_*_vars() override they expand to.
REF_MACRO_PROC = {
    "OWNED": "declared_owned_vars",
    "OWNED_LIST": "declared_owned_list_vars",
    "OWNED_VALUES": "declared_owned_value_vars",
    "SPILL": "declared_spill_vars",
    "SPILL_LIST": "declared_spill_list_vars",
    "HELD": "declared_held_vars",
    "PAIR": "declared_pair_vars",
    "BACKLIST": "declared_backlist_vars",
    "BACK": "declared_back_vars",
    "KEEP": "declared_keep_vars",
    "DEF": "declared_def_vars",
    "STATIC": "declared_static_vars",
    "TRANSIENT": "declared_transient_vars",
}
_KINDS = "|".join(sorted(REF_MACRO_PROC, key=len, reverse=True))
REF_MACRO = re.compile(r"^REF_(" + _KINDS + r")\(\s*(/[\w/]+)\s*,(.*)\)\s*$")
# REF_VAR(/type, KIND, /vartype, name), REF_PAIR_VAR(/type, /vartype, name, "other"),
# REF_BACKLIST_VAR(/type, /vartype, name, "list_var").
REF_VAR = re.compile(r"^REF_VAR\(\s*(/[\w/]+)\s*,\s*(" + _KINDS + r")\s*,\s*(/[\w/]+)\s*,\s*(\w+)\s*\)\s*$")
REF_PAIRED_VAR = re.compile(r"^REF_(PAIR|BACKLIST)_VAR\(\s*(/[\w/]+)\s*,\s*(/[\w/]+)\s*,\s*(\w+)\s*,\s*\"(\w+)\"\s*\)\s*$")
OM_STATIC_TYPE = re.compile(r"^OM_STATIC_TYPE\(\s*(/[\w/]+)\s*\)", re.M)
POOL_DECLARE = re.compile(r"^POOL_DECLARE\(\s*(/[\w/]+)\s*\)\s*$", re.M)

DECLARED_PROCS = tuple(REF_MACRO_PROC.values()) + ("declared_cache_vars",)


def ref_var_decl(line):
    """A one-place declaration line -> (owner, kind, vartype, name), or None.
    kind is a REF_MACRO_PROC key."""
    m = REF_VAR.match(line)
    if m:
        return m.group(1), m.group(2), m.group(3), m.group(4)
    m = REF_PAIRED_VAR.match(line)
    if m:
        return m.group(2), m.group(1), m.group(3), m.group(4)
    return None


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
    """An implicit REF_DEF: the var's declared type is a frozen definition type."""
    return under(vtype, DEF_TYPES)


_STATIC = None


def static_types():
    """Every type marked OM_STATIC_TYPE across code/ (read once), plus the frozen
    definition types (DEF_TYPES): singletons and flyweights, which a reference
    holds with REF_STATIC and never with a handle."""
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
