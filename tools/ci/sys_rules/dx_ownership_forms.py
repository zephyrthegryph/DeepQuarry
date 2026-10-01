"""sys_lint module: the ownership declaration forms replaced by the ownership() and relations()
list overrides (doc/rewrite/ownership.md §1.2, §4.1): the 16 declaration macros and the interim
declare_ownership(decl) form, string var names in accessors, and a var owned twice (by a
capability's owned() entries and by the type's own ownership()). The baseline is empty: every rule
is 0 and stays 0.
"""
import re

RULES = {
    "old_ownership_macro": "ownership() with owns()/shares()/proto() and relations() with rel_one()/rel_many()/rel_key() (ownership.md §1.2, §4.1)",
    "old_destroy_macro": "an override of the well-known teardown proc (destroy_step/destroy_capture/destroy_after) (ownership.md §6)",
    "string_accessor_var": "nameof(var) / nameof(/type::var) for the var name of an own_*/rel_*/proto_* accessor (ownership.md §1.2)",
    "owned_twice": "drop the ownership() line: the capability (cap_slot) already owns this var through its owned() entries (ownership.md §1.2)",
}

# Capability constructors whose owned() entries own the holder var named by their first argument.
OWNING_CAPS = ("cap_slot", "cap_cell_holder")
PROC_HEAD = re.compile(r"^(/[\w/]+)/(capabilities|ownership)\(\)")
CAP_OWNS = re.compile(r"\b(%s)\(\s*nameof\((\w+)\)" % "|".join(OWNING_CAPS))
TYPE_OWNS = re.compile(r"^\s*\.\s*\+=\s*owns\(\s*nameof\((\w+)\)")


def related(a, b):
    """The same type, or one an ancestor of the other (the hierarchy shares one ownership table chain)."""
    return a == b or a.startswith(b + "/") or b.startswith(a + "/")

OLD_MACROS = (
    "OWN", "OWN_POLICY", "OWN_IF", "SHARED", "PROTO", "REL", "REL_LIST", "REL_PAIR",
    "REL_PAIR_LIST", "REL_SET", "REL_KEYED", "REL_KEYED_LIST", "KEYED_TARGET",
    "KEEP_AFTER_DESTROY", "POOL_RESET", "FORWARD_STATE",
)
PATTERNS = {
    "old_ownership_macro": re.compile(r"(?<![\w#])(%s)\s*\(|/declare_ownership\(|\b(own|shared|proto|rel)\(\s*decl\b" % "|".join(OLD_MACROS)),
    "old_destroy_macro": re.compile(r"\b(DESTROY_STEP|DESTROY_CAPTURE|DESTROY_AFTER)\b"),
    "string_accessor_var": re.compile(r"\b(own|rel|proto)_[a-z_]+\(\s*[^,()\"]+,\s*\"[A-Za-z_][A-Za-z0-9_]*\""),
}


def scan(files):
    out = {rule: [] for rule in RULES}
    cap_owned = {}   # var -> [holder type]
    type_owned = []  # (holder type, var, rel, number)
    for rel, lines in files:
        head = None
        for number, line in enumerate(lines, 1):
            code = line.split("//", 1)[0]
            for rule, pattern in PATTERNS.items():
                if pattern.search(code):
                    out[rule].append((rel, number))
            if line and not line[0].isspace():
                m = PROC_HEAD.match(line)
                head = (m.group(1), m.group(2)) if m else None
                continue
            if not head:
                continue
            if head[1] == "capabilities":
                for m in CAP_OWNS.finditer(code):
                    cap_owned.setdefault(m.group(2), []).append(head[0])
            else:
                m = TYPE_OWNS.match(code)
                if m:
                    type_owned.append((head[0], m.group(1), rel, number))
    for holder, var, rel, number in type_owned:
        if any(related(holder, other) for other in cap_owned.get(var, ())):
            out["owned_twice"].append((rel, number))
    return out
