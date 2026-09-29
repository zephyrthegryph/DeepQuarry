"""Map-time resolvers (doc/rewrite/systems.md section 9).

A map atom that does its work at Initialize and then deletes itself is a map-time resolver:
declare MAP_RESOLVER(path, proc) and do the work in the proc (code/__defines/map_resolvers.dm).

Rules:
  init_qdel         - an Initialize()/LateInitialize() that unconditionally ends its life:
                      `return INITIALIZE_HINT_QDEL` / `. = INITIALIZE_HINT_QDEL` at the proc's
                      top level, or any INITIALIZE_HINT_QDEL on a type in a resolvable family
                      (a type with a MAP_RESOLVER on it or an ancestor).
  init_self_delete  - an Initialize()/LateInitialize() that does its work then deletes itself at
                      its top level: qdel(src), expire(0), replace_with(src, ...), qdel_self().
"""
import re

RULES = {
    "init_qdel": "an atom that only works at load then goes: MAP_RESOLVER(path, proc) (systems.md §9)",
    "init_self_delete": "an Initialize that does its work then deletes itself: MAP_RESOLVER(path, proc) (systems.md §9)",
}

PROC_HEAD = re.compile(r"^(/[\w/]+?)/(Initialize|LateInitialize)\(")
RESOLVER = re.compile(r"^MAP_RESOLVER\((/[\w/]+),")
TOP_QDEL = re.compile(r"^\t(return|\.\s*=)\s*INITIALIZE_HINT_QDEL\b")
ANY_QDEL = re.compile(r"\bINITIALIZE_HINT_QDEL\b")
TOP_SELF_DELETE = re.compile(r"^\t(qdel\(src\)|expire\(0\)|replace_with\(src\b|qdel_self\(\))")


def _resolvable(path, roots):
    while path:
        if path in roots:
            return True
        cut = path.rfind("/")
        if cut <= 0:
            return False
        path = path[:cut]
    return False


def scan(files):
    out = {rule: [] for rule in RULES}
    roots = set()
    for rel, lines in files:
        for line in lines:
            m = RESOLVER.match(line)
            if m:
                roots.add(m.group(1))
    for rel, lines in files:
        cur = None
        for number, line in enumerate(lines, 1):
            m = PROC_HEAD.match(line)
            if m:
                cur = m.group(1)
                continue
            if line and not line[0].isspace():
                cur = None
                continue
            if not cur:
                continue
            code = line.split("//", 1)[0]
            if TOP_QDEL.match(code) or (ANY_QDEL.search(code) and _resolvable(cur, roots)):
                out["init_qdel"].append((rel, number))
            elif TOP_SELF_DELETE.match(code):
                out["init_self_delete"].append((rel, number))
    return out
