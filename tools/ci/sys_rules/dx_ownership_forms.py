"""sys_lint module: the ownership declaration forms replaced by own()/shared()/proto()/rel()
(doc/rewrite/ownership.md §2). The baseline is empty: every rule is 0 and stays 0.
"""
import re

RULES = {
    "old_ownership_macro": "declare_ownership(decl) with own()/shared()/proto()/rel() and named options (ownership.md §2)",
    "old_destroy_macro": "an override of the well-known teardown proc (destroy_step/destroy_capture/destroy_after) (ownership.md §6)",
    "string_accessor_var": "nameof(var) / nameof(/type::var) for the var name of an own_*/rel_*/proto_* accessor (ownership.md §2)",
}

OLD_MACROS = (
    "OWN", "OWN_POLICY", "OWN_IF", "SHARED", "PROTO", "REL", "REL_LIST", "REL_PAIR",
    "REL_PAIR_LIST", "REL_SET", "REL_KEYED", "REL_KEYED_LIST", "KEYED_TARGET",
    "KEEP_AFTER_DESTROY", "POOL_RESET", "FORWARD_STATE",
)
PATTERNS = {
    "old_ownership_macro": re.compile(r"(?<![\w#])(%s)\s*\(" % "|".join(OLD_MACROS)),
    "old_destroy_macro": re.compile(r"\b(DESTROY_STEP|DESTROY_CAPTURE|DESTROY_AFTER)\b"),
    "string_accessor_var": re.compile(r"\b(own|rel|proto)_[a-z_]+\(\s*[^,()\"]+,\s*\"[A-Za-z_][A-Za-z0-9_]*\""),
}


def scan(files):
    out = {rule: [] for rule in RULES}
    for rel, lines in files:
        for number, line in enumerate(lines, 1):
            code = line.split("//", 1)[0]
            for rule, pattern in PATTERNS.items():
                if pattern.search(code):
                    out[rule].append((rel, number))
    return out
