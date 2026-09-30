"""Ownership lint (doc/rewrite/ownership.md sec 7-8): the static half of own / shared / proto /
relation.

Every object-typed var is exactly one kind. Most carry no declaration: the kind is inferred from a
codebase-wide assignment index of how the var is written, and this lint fails where the evidence
contradicts itself or a declaration. It checks:

  raw_write       an entity var (typed as an entity, or a list that holds entities) written
                  outside the ownership accessors: own_set/own_take/own_add/own_remove/own_put/
                  own_transfer/own_clear, rel_set/rel_add/rel_remove/rel_clear, proto_set/
                  proto_private, shared_set. Bare assignment, +=, -=, |=, [k] =, Cut/Add/Remove/
                  Insert, QDEL_NULL, QDEL_LIST*, LAZY* list macros. A registry-typed var (implicitly
                  SHARED) or a SHARED declaration is exempt. The initial value in a type body is
                  not a write.
  contradiction   one var written both as owned and as a relation (own_* and rel_*), or its
                  writes disagree with its declaration.
  kinds           one kind per var across the hierarchy: related types declaring different kinds.
  matrix          OWN or REL of a registry type (it is SHARED; a per-holder copy is PROTO),
                  SHARED of a non-registry type, a gas mixture written as a relation (a holder
                  owns its mixture), SPILL / CONTAINED on a non-movable var type.
  callback        CALLBACK( outside the core (code/datums/om, code/controllers, code/__defines,
                  code/datums/ownership): deferred calls are om_after(), which holds arguments as
                  handles.
  handle          om_handle()/om_resolve() or a `*_handle` var outside the core: a content var
                  naming an entity is a relation.
  unknown_var     an accessor naming a var (by string) that the receiver's type doesn't have.
  string_name     an accessor naming its var with a string literal: var names are nameof(var) /
                  nameof(x.var) / nameof(/type::var), so the compiler checks them.
  removed         the deleted forms: DECLARE_REF, OM_STATIC_TYPE, REFKIND_*, link_set/link_clear,
                  WEAK_LIST_*, weak_list_live, DuplicateObject, and the declaration macros that
                  ownership()/relations() replaced (OWN, OWN_POLICY, OWN_IF, SHARED, PROTO, REL,
                  REL_LIST, REL_PAIR, REL_PAIR_LIST, REL_SET, REL_KEYED, REL_KEYED_LIST,
                  KEYED_TARGET, KEEP_AFTER_DESTROY, POOL_RESET, FORWARD_STATE) with their procs
                  (declared_ownership, own_declare, keyed_target_var, declared_keep_vars,
                  declared_pool_reset, declared_forward_vars, declare_ownership).

Declarations are read from `/type/ownership()` and `/type/relations()` overrides: each body line
`. += owns(nameof(v), policy = ...)`, `shares(...)`, `proto(...)`, `rel_one(...)` or `rel_many(...)`
declares v on the type.

A site kept on purpose carries `// ALLOW(ownership): <reason>` (tools/ci/allow_annotations.py).

    python tools/ci/ownership_lint.py              # the CI check
    python tools/ci/ownership_lint.py --summary    # counts per check and per directory
    python tools/ci/ownership_lint.py --check raw_write --under code/modules/mob
"""
import argparse
import collections
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import code_only  # noqa: E402
from allow_annotations import allowed  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

CORE_DIRS = ("code/datums/ownership/", "code/datums/om/", "code/datums/lifecycle/", "code/datums/state/",
             "code/__defines/", "code/controllers/", "code/datums/containment/", "code/datums/shared_cache/")
CALLBACK_OK = ("code/datums/om/", "code/controllers/", "code/__defines/", "code/datums/ownership/",
               "code/datums/callback.dm", "code/_helpers/")
HANDLE_OK = ("code/datums/om/", "code/datums/ownership/", "code/datums/state/", "code/datums/lifecycle/",
             "code/__defines/", "code/datums/containment/", "code/modules/unit_tests/")

ENTITY_ROOTS = ("/datum", "/atom", "/obj", "/mob", "/turf")
# Values, not entities: never tracked.
VALUE_TYPES = ("/datum/gas_mixture/__never__",)
MODIFIERS = {"tmp", "static", "global", "const", "final"}

PROC_DEF = re.compile(r"^(/[\w/]+?)/(?:(?:proc|verb)/)?(\w+)\s*\((.*)$")
TYPE_LINE = re.compile(r"^(/[\w/]+)\s*(?:\{.*)?$")
MEMBER = re.compile(r"^\s+(?:var|VAR_PRIVATE|VAR_PROTECTED|VAR_FINAL)/((?:[\w]+/)*)(\w+)\b")
OM_FIELD_DECL = re.compile(r"^OM_FIELD(?:(?:_TYPED|_VIEW)\(\s*(/[\w/]+)\s*,\s*([\w/]+)\s*,|\(\s*(/[\w/]+)\s*,())\s*(\w+)\s*,")
ABS_MEMBER = re.compile(r"^(/[\w/]+?)/(?:var|VAR_PRIVATE|VAR_PROTECTED|VAR_FINAL)/((?:[\w]+/)*)(\w+)\b")
TYPED_NAME = re.compile(r"(?:var/)?((?:/?\w+)(?:/\w+)+)/(\w+)\b")
DECLARE_HEAD = re.compile(r"^(/[\w/]+)/(?:ownership|relations)\(\)")
DECLARE_CALL = re.compile(r"^\s+\.\s*\+=\s*(owns|shares|proto|rel_one|rel_many)\(\s*nameof\((\w+)\)\s*(?:,\s*(.*?))?\)\s*(?://.*)?$")
# An accessor's var-name argument: a string literal (banned, `string_name`) or nameof(v) /
# nameof(x.v) / nameof(/type::v). Group: the var name.
VAR_ARG = r"(?:\"|nameof\((?:/[\w/]+::|\w+\.)?)(\w+)(?:\"|\))"
REGISTRY = re.compile(r"^REGISTRY_TYPE\(\s*(/[\w/]+)\s*,")
ACCESSOR = re.compile(r"\b(own_set|own_take|own_add|own_remove|own_put|own_take_member|own_clear|own_transfer|rel_set|rel_add|rel_remove|rel_clear|rel_link|rel_unlink|proto_set|proto_private|shared_set)\(\s*([\w.]+)\s*,\s*" + VAR_ARG)
TRANSFER_DEST = re.compile(r"\bown_transfer\([^,]+,\s*" + VAR_ARG.replace("(\\w+)", "\\w+") + r"\s*,\s*([\w.]+)\s*,\s*" + VAR_ARG)
STRING_NAME = re.compile(r"\b(own_set|own_take|own_add|own_remove|own_put|own_take_member|own_take_all|own_clear|own_values|own_transfer|rel_set|rel_add|rel_remove|rel_clear|rel_link|rel_unlink|rel_targets|rel_names|proto_set|proto_private|proto_replace|proto_is_private|shared_set|keyed_set_id)\((?:[^,()\"]|\([^()]*\))*,\s*\"\w+\""
                         r"|\b(own_move)\((?:[^,()\"]|\([^()]*\))*,(?:[^,()\"]|\([^()]*\))*,\s*\"\w+\"")
OWN_FUNCS = {"own_set", "own_take", "own_add", "own_remove", "own_put", "own_take_member", "own_clear", "own_transfer"}
REL_FUNCS = {"rel_set", "rel_add", "rel_remove", "rel_clear", "rel_link", "rel_unlink"}
PROTO_FUNCS = {"proto_set", "proto_private"}

WRITE_ASSIGN = re.compile(r"(?<![\w.])((?:\w+\??\.)*)(\w+)\s*(=(?!=)|\+=|-=|\|=|&=|\^=)")
WRITE_INDEX = re.compile(r"(?<![\w.])((?:\w+\??\.)*)(\w+)\[[^\]\n]*\]\s*=(?!=)")
WRITE_METHOD = re.compile(r"(?<![\w.])((?:\w+\??\.)*)(\w+)\??\.(Cut|Add|Remove|Insert|Swap|RemoveAll)\(")
WRITE_MACRO = re.compile(r"\b(QDEL_NULL|QDEL_LIST|QDEL_LIST_ASSOC|QDEL_LIST_ASSOC_VAL|QDEL_LAZYLIST|LAZYADD|LAZYREMOVE|LAZYSET|LAZYOR|LAZYINITLIST|LAZYCLEARLIST|LAZYNULL|UNSETEMPTY|LAZYADDASSOC|LAZYREMOVEASSOC|LAZYADDASSOCLIST|LAZYDISTINCTADD|LAZYINSERT)\(\s*((?:\w+\??\.)*)(\w+)\b")
CALLBACK = re.compile(r"\bCALLBACK\(")
HANDLE_CALL = re.compile(r"\bom_(handle|resolve|handle_of|handle_is|resolve_all)\(")
HANDLE_VAR = re.compile(r"^\s*var/(?:[\w]+/)*(\w+_handle)\b|^(/[\w/]+?)/var/(?:[\w]+/)*(\w+_handle)\b")
REMOVED = re.compile(r"\b(DECLARE_REF|OM_STATIC_TYPE|REFKIND_\w+|link_set|link_clear|link_backlist_add|link_backlist_remove|WEAK_LIST_ADD|WEAK_LIST_REMOVE|WEAK_LIST_HAS|weak_list_live|DuplicateObject|dq_lifecycle_link_table|declared_refs|declared_ownership|own_declare|keyed_target_var|declared_keep_vars|declared_pool_reset|declared_forward_vars|declare_ownership)\b"
                     r"|\b(?:OWN|OWN_POLICY|OWN_IF|SHARED|PROTO|REL|REL_LIST|REL_PAIR|REL_PAIR_LIST|REL_SET|REL_KEYED|REL_KEYED_LIST|KEYED_TARGET|KEEP_AFTER_DESTROY|POOL_RESET|FORWARD_STATE)(?=\()")
LOCAL_DECL = re.compile(r"\bvar/(?:[\w]+/)*(\w+)")


def rel(path):
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


def under(path, roots):
    return bool(path) and any(path == r or path.startswith(r + "/") for r in roots)


def related(a, b):
    return a == b or a.startswith(b + "/") or b.startswith(a + "/")


IMPLICIT_ROOTS = {"/obj": ("/atom/movable", "/atom", "/datum"), "/mob": ("/atom/movable", "/atom", "/datum"),
                  "/turf": ("/atom", "/datum"), "/area": ("/atom", "/datum"), "/atom": ("/datum",)}


def parents(path):
    """The type and its ancestors, nearest first, including DM's implicit roots (/obj -> /atom/movable
    -> /atom -> /datum)."""
    root = None
    while path and path.count("/") >= 1:
        yield path
        if path.count("/") == 1:
            root = path
            break
        path = path.rsplit("/", 1)[0]
    for implicit in IMPLICIT_ROOTS.get(root, ()):
        yield implicit


class Index:
    def __init__(self):
        self.files = {}  # rel -> (raw lines, code lines)
        self.members = {}  # type -> var -> (vtype, is_list)
        self.decls = collections.defaultdict(dict)  # type -> var -> (kind, args, rel, line)
        self.registry = []
        self.usage = collections.defaultdict(lambda: collections.defaultdict(set))  # var -> kind -> {(type or None, rel, line)}
        self.name_decls = collections.defaultdict(list)  # var -> [(type, vtype, is_list)]

    def load(self):
        for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
            r = rel(path)
            with open(path, encoding="utf-8", errors="replace") as handle:
                text = handle.read()
            raw = text.split("\n")
            code = code_only(text).split("\n")
            self.files[r] = (raw, code)
        for r, (raw, code) in self.files.items():
            self.index_file(r, raw, code)

    def add_member(self, owner, segs, name):
        parts = [p for p in segs.split("/") if p and p not in MODIFIERS]
        is_list = bool(parts) and parts[0] == "list"
        if is_list:
            parts = parts[1:]
        vtype = "/" + "/".join(parts) if parts else ""
        self.members.setdefault(owner, {})[name] = (vtype, is_list)
        self.name_decls[name].append((owner, vtype, is_list))

    def add_decl(self, owner, func, name, opts, r, no):
        """One entry in owner's ownership()/relations() list: recorded under the kind's old macro name
        (the checks below key on it). An own() with no policy only annotates: no kind."""
        opts = opts or ""
        if func == "owns":
            if "policy_proc" in opts:
                macro = "OWN_POLICY"
            elif "if_var" in opts:
                macro = "OWN_IF"
            elif re.search(r"\bpolicy\s*=\s*OWN_NONE\b", opts):
                macro = "ANNOTATE"
            else:
                macro = "OWN"
        elif func == "shares":
            macro = "SHARED"
        elif func in ("rel_one", "rel_many"):
            # kind = RELK_OWNED is an ownership declaration written through rel_one()
            macro = "OWN" if re.search(r"\bkind\s*=\s*RELK_OWNED\b", opts) else "REL"
        else:
            macro = func.upper()
        self.decls[owner][name] = (macro, opts, r, no)

    def index_file(self, r, raw, code):
        current = None
        declaring = None
        for no, line in enumerate(code, 1):
            if line and line[0] in "\"'":
                continue  # the tail of a multi-line string, not a new top-level line
            if declaring and line and line[0].isspace():
                m = DECLARE_CALL.match(raw[no - 1])
                if m:
                    self.add_decl(declaring, m.group(1), m.group(2), m.group(3), r, no)
                continue
            declaring = None
            if line and not line[0].isspace():
                m = DECLARE_HEAD.match(line)
                if m:
                    declaring = m.group(1)
                    current = None
                    continue
                m = REGISTRY.match(raw[no - 1].strip())
                if m:
                    self.registry.append(m.group(1))
                    continue
                m = ABS_MEMBER.match(line)
                if m:
                    self.add_member(m.group(1), m.group(2), m.group(3))
                    current = None
                    continue
                m = OM_FIELD_DECL.match(line)
                if m:  # OM_FIELD(T, F, ...) / OM_FIELD_TYPED|_VIEW(T, VT, F, ...) declare T/var/F
                    vt = (m.group(2).strip('/') + '/') if m.group(2) else ''
                    self.add_member(m.group(1) or m.group(3), vt, m.group(5))
                    current = None
                    continue
                m = TYPE_LINE.match(line.rstrip())
                current = m.group(1) if m and "(" not in line else None
                continue
            if current:
                m = MEMBER.match(line)
                if m:
                    self.add_member(current, m.group(1), m.group(2))

    def member(self, owner, name):
        """(declaring type, vtype, is_list) for var `name` as seen from type `owner`, or None."""
        for p in parents(owner):
            got = self.members.get(p, {}).get(name)
            if got:
                return (p, got[0], got[1])
        return None

    def decl(self, owner, name):
        for p in parents(owner):
            got = self.decls.get(p, {}).get(name)
            if got:
                return (p,) + got
        return None

    def is_registry(self, vtype):
        return under(vtype, self.registry)

    def is_entity(self, vtype):
        return under(vtype, ENTITY_ROOTS) and not self.is_registry(vtype)


def proc_scopes(code):
    """Yields (line number, line, owner type, proc name, locals dict) for every proc body line."""
    owner = proc = None
    local_types = {}
    for no, line in enumerate(code, 1):
        if line and line[0] in "\"'":
            continue  # the tail of a multi-line string
        if line and not line[0].isspace():
            m = PROC_DEF.match(line)
            if m and not line.startswith("#"):
                owner, proc = m.group(1), m.group(2)
                local_types = {}
                for tm in TYPED_NAME.finditer(m.group(3)):
                    local_types[tm.group(2)] = "/" + tm.group(1).lstrip("/")
                for am in re.finditer(r"(?:^|,)\s*(\w+)\s*(?:=|,|\)|$)", m.group(3)):
                    local_types.setdefault(am.group(1), None)
            else:
                owner = proc = None
            continue
        if owner is None:
            continue
        for tm in TYPED_NAME.finditer(line):
            start = tm.start()
            if line[max(0, start - 4):start].endswith("var/") or line[start:].startswith("var/"):
                local_types[tm.group(2)] = "/" + tm.group(1).lstrip("/")
        for lm in LOCAL_DECL.finditer(line):
            local_types.setdefault(lm.group(1), None)
        yield no, line, owner, proc, local_types


def receiver_type(idx, chain, owner, local_types):
    """The static type of a `a.b.` receiver chain ('' for a bare write), or None when unknown."""
    if not chain:
        return owner
    segs = [s.rstrip("?") for s in chain.rstrip(".").split(".")]
    if segs == ["src"]:
        return owner
    if len(segs) != 1:
        return None
    name = segs[0]
    if name in local_types:
        return local_types[name]
    got = idx.member(owner, name)
    return got[1] if got else None


RAW_SITES = []
OBJLIST_WRITES = ("+=", "|=", "[]=", "LAZYADD", "LAZYOR", "LAZYSET", "LAZYDISTINCTADD", "LAZYINSERT", ".Add", ".Insert")
OBJ_TOKEN = re.compile(r"(?<![\w.\"])(src|new|[A-Za-z_]\w*)(?![\w.\[(?:])")


REGISTRY_ROOTS = ()
NEW_VALUE = re.compile(r"^\s*new\s*(/[\w/]+)?")
VALUE_TYPES = ("/image", "/mutable_appearance", "/icon", "/matrix", "/regex", "/list", "/sound", "/savefile",
               "/database", "/generator", "/particles", "/filter", "/alist")


def creates_entity(rhs):
    """True when the assigned value is `new /entity/type(...)` (not a value type such as an image)."""
    m = NEW_VALUE.match(rhs.split("//", 1)[0])
    if not m:
        return False
    path = m.group(1)
    if not path:
        return False  # implicit type: the declared type decides (already handled)
    return not under(path, VALUE_TYPES)


def puts_object(rhs, local_types, owner):
    """True when the written value (or key) is recognisably an entity: src, a new expression, or a
    local/argument declared with an entity type."""
    text = rhs.split("//", 1)[0]
    # A proc call's arguments are not the written value: EXPIRY_AT(src, ...) writes a number.
    prev = None
    while prev != text:
        prev = text
        text = re.sub(r"\b(?!new\b)[A-Za-z_]\w*\s*\([^()]*\)", "0", text)
    for m in OBJ_TOKEN.finditer(text):
        tok = m.group(1)
        if tok == "src" or tok == "new":
            return True
        t = local_types.get(tok)
        if t and under(t, ENTITY_ROOTS) and not under(t, REGISTRY_ROOTS):
            return True
    return False
UNKNOWN_VARS = []


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--json")
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--check", action="append")
    ap.add_argument("--under", action="append")
    args = ap.parse_args(argv)

    idx = Index()
    idx.load()
    global REGISTRY_ROOTS
    REGISTRY_ROOTS = tuple(idx.registry)

    # ---- the assignment index: accessor usage per var name and receiver type
    for r, (raw, code) in idx.files.items():
        for no, line, owner, proc, local_types in proc_scopes(code):
            for m in ACCESSOR.finditer(raw[no - 1]):
                func, recv, name = m.group(1), m.group(2), m.group(3)
                rtype = owner if recv == "src" else local_types.get(recv)
                if rtype is None and recv != "src":
                    got = idx.member(owner, recv)
                    rtype = got[1] if got else None
                kind = "OWN" if func in OWN_FUNCS else "REL" if func in REL_FUNCS else "PROTO" if func in PROTO_FUNCS else "SHARED"
                idx.usage[name][kind].add((rtype, r, no))
                # The var named by the string must exist: on the receiver's type when it is known,
                # else on some type (a string var name can't be checked by the compiler).
                if rtype and under(rtype, ENTITY_ROOTS):
                    if not idx.member(rtype, name) and not any(t.startswith(rtype + "/") for (t, _, _) in idx.name_decls.get(name, ())):
                        UNKNOWN_VARS.append((r, no, "%s(%s, \"%s\"): %s has no var %s" % (func, recv, name, rtype, name)))
                elif not idx.name_decls.get(name):
                    UNKNOWN_VARS.append((r, no, "%s(%s, \"%s\"): no type declares a var %s" % (func, recv, name, name)))
            for m in TRANSFER_DEST.finditer(raw[no - 1]):
                recv, name = m.group(1), m.group(2)
                rtype = owner if recv == "src" else local_types.get(recv)
                idx.usage[name]["OWN"].add((rtype, r, no))

    problems = []

    def report(check, r, no, msg):
        problems.append((check, r, no, msg))

    for (r, no, msg) in UNKNOWN_VARS:
        report("unknown_var", r, no, msg)

    for r, (raw, code) in idx.files.items():
        for no, line in enumerate(code, 1):
            # code_only() blanks string contents, so match the raw line where the code line has a call
            if "(" not in line:
                continue
            hit = STRING_NAME.search(raw[no - 1].split("//", 1)[0])
            # the call itself must be code (a name inside a string or comment is blanked in `line`)
            if hit and re.search(r"%s\(" % (hit.group(1) or hit.group(2)), line) and not allowed(raw, no, "ownership"):
                report("string_name", r, no, "%s(): name the var with nameof(), not a string" % (hit.group(1) or hit.group(2)))

    decl_kind_of = {"OWN": "OWN", "OWN_POLICY": "OWN", "OWN_IF": "OWN", "SHARED": "SHARED", "PROTO": "PROTO",
                    "REL": "REL", "REL_LIST": "REL", "REL_PAIR": "REL", "REL_PAIR_LIST": "REL", "REL_SET": "REL",
                    "REL_KEYED": "REL", "REL_KEYED_LIST": "REL"}

    # ---- kinds: one kind per var across the hierarchy
    by_name = collections.defaultdict(list)
    for t, vs in idx.decls.items():
        for v, (macro, a, r, no) in vs.items():
            if macro in decl_kind_of:
                by_name[v].append((t, decl_kind_of[macro], r, no, macro, a))
    for v, entries in by_name.items():
        for i, (t1, k1, r1, n1, _, _) in enumerate(entries):
            for t2, k2, r2, n2, _, _ in entries[i + 1:]:
                if k1 != k2 and related(t1, t2):
                    report("kinds", r2, n2, "%s.%s is %s here but %s on %s (%s:%d): one kind per var" % (t2, v, k2, k1, t1, r1, n1))

    # ---- matrix
    for t, vs in idx.decls.items():
        for v, (macro, a, r, no) in vs.items():
            got = idx.member(t, v)
            if not got:
                continue
            _, vtype, is_list = got
            kind = decl_kind_of.get(macro)
            if kind in ("OWN", "REL") and idx.is_registry(vtype):
                report("matrix", r, no, "%s.%s is typed %s, a registry type: it is SHARED (a per-holder copy is PROTO)" % (t, v, vtype))
            if kind == "SHARED" and vtype and under(vtype, ENTITY_ROOTS) and not idx.is_registry(vtype):
                report("matrix", r, no, "%s.%s is SHARED but typed %s, which is not a REGISTRY_TYPE" % (t, v, vtype))
            if macro == "OWN" and ("OWN_SPILL" in a or "OWN_CONTAINED" in a) and vtype and not under(vtype, ("/atom/movable", "/obj", "/mob")):
                report("matrix", r, no, "%s.%s: %s needs a movable var type (got %s)" % (t, v, a.strip(), vtype or "untyped"))

    # ---- contradictions (usage vs usage, usage vs declaration, resources)
    for name, kinds in idx.usage.items():
        own = kinds.get("OWN", set())
        relu = kinds.get("REL", set())
        for (t1, r1, n1) in own:
            for (t2, r2, n2) in relu:
                if t1 and t2 and related(t1, t2) and idx.member(t1, name) and idx.member(t1, name) == idx.member(t2, name):
                    report("contradiction", r2, n2, "%s.%s is written as a relation here and as owned at %s:%d" % (t2, name, r1, n1))
                    break
        for (t, r, n) in relu:
            if not t:
                continue
            got = idx.member(t, name)
            if got and got[1] == "/datum/gas_mixture":
                report("matrix", r, n, "%s.%s holds a gas mixture: a holder owns its mixture (own_set), a network's is PROTO" % (t, name))
            d = idx.decl(t, name)
            if d and decl_kind_of.get(d[1]) not in (None, "REL"):
                report("contradiction", r, n, "%s.%s is declared %s but written with rel_*" % (t, name, d[1]))
        for (t, r, n) in own:
            if not t:
                continue
            d = idx.decl(t, name)
            if d and decl_kind_of.get(d[1]) not in (None, "OWN"):
                report("contradiction", r, n, "%s.%s is declared %s but written with own_*" % (t, name, d[1]))
            got = idx.member(t, name)
            if got and idx.is_registry(got[1]) and not (d and d[1] == "PROTO"):
                report("matrix", r, n, "%s.%s is typed %s, a registry type: it is SHARED, not owned" % (t, name, got[1]))

    # ---- per-line checks
    def var_kind(owner_type, name):
        """'entity' for a single entity var, 'list' for an entity list, None otherwise (from owner_type)."""
        got = idx.member(owner_type, name)
        if not got:
            return None, None
        dtype, vtype, is_list = got
        d = idx.decl(owner_type, name)
        if d and decl_kind_of.get(d[1]) == "SHARED":
            return None, dtype
        if d and decl_kind_of.get(d[1]) in ("OWN", "REL", "PROTO"):
            return ("list" if is_list or not vtype else "entity"), dtype
        used = idx.usage.get(name)
        if used:
            for k in ("OWN", "REL", "PROTO"):
                for (t, _, _) in used.get(k, ()):
                    # The usage must name this same var: its receiver resolves the member to the
                    # same declaring type (not merely a related type with a same-named var).
                    if t and related(t, owner_type):
                        got_t = idx.member(t, name)
                        if got_t and got_t[0] == dtype:
                            return ("list" if is_list else "entity"), dtype
        if is_list:
            return ("list" if idx.is_entity(vtype) else None), dtype
        return ("entity" if idx.is_entity(vtype) else None), dtype

    ambiguous = {}

    def unknown_receiver_kind(name):
        """For an untyped receiver: the kind when every declaration of `name` agrees."""
        if name in ambiguous:
            return ambiguous[name]
        kinds = set()
        for (t, vtype, is_list) in idx.name_decls.get(name, ()):
            k, _ = var_kind(t, name)
            kinds.add(k)
        ambiguous[name] = kinds.pop() if len(kinds) == 1 else None
        return ambiguous[name]

    for r, (raw, code) in idx.files.items():
        in_core = r.startswith(CORE_DIRS)
        for no, line in enumerate(raw, 1):
            c = code[no - 1] if no - 1 < len(code) else ""
            if REMOVED.search(c) and not r.startswith("tools/"):
                if not allowed(raw, no, "ownership"):
                    report("removed", r, no, "%s was removed (doc/rewrite/ownership.md)" % REMOVED.search(c).group(0))
            if CALLBACK.search(c) and not r.startswith(CALLBACK_OK) and not allowed(raw, no, "ownership"):
                report("callback", r, no, "CALLBACK outside the core: use om_after() (arguments held as handles)")
            if not r.startswith(HANDLE_OK):
                if HANDLE_CALL.search(c) and not allowed(raw, no, "ownership"):
                    report("handle", r, no, "om_%s() in content: a var naming an entity is a relation view (rel_set)" % HANDLE_CALL.search(c).group(1))
                hm = HANDLE_VAR.match(c)
                if hm and not allowed(raw, no, "ownership"):
                    report("handle", r, no, "var %s: a content var naming an entity is a relation view, not a handle" % (hm.group(1) or hm.group(3)))
        if in_core:
            continue
        for no, line, owner, proc, local_types in proc_scopes(code):
            hits = []
            for m in WRITE_ASSIGN.finditer(line):
                chain, name, op = m.group(1), m.group(2), m.group(3)
                before = line[:m.start()].rstrip()
                if before.endswith("var") or re.search(r"var/(?:[\w/]+/)?$", line[:m.start()]):
                    continue
                if not chain and before.endswith(("(", ",")):
                    continue  # a named argument or an assoc key in list(...)
                if not chain and name in local_types:
                    continue
                if op == "=" and line[m.end():].lstrip().startswith("="):
                    continue
                hits.append((chain, name, op, line[m.end():]))
            for m in WRITE_INDEX.finditer(line):
                if not m.group(1) and m.group(2) in local_types:
                    continue
                key_and_value = line[m.start():m.end()]
                key_and_value = key_and_value[key_and_value.find("[") + 1:key_and_value.rfind("]")] + " " + line[m.end():]
                hits.append((m.group(1), m.group(2), "[]=", key_and_value))
            for m in WRITE_METHOD.finditer(line):
                if not m.group(1) and m.group(2) in local_types:
                    continue
                hits.append((m.group(1), m.group(2), "." + m.group(3), line[m.end():]))
            for m in WRITE_MACRO.finditer(line):
                if not m.group(2) and m.group(3) in local_types:
                    continue
                hits.append((m.group(2), m.group(3), m.group(1), line[m.end():]))
            for chain, name, how, rhs in hits:
                if name in ("src", "usr", "loc", "contents", "vars", "overlays", "underlays", "vis_contents", "verbs", "screen", "images"):
                    continue
                rtype = receiver_type(idx, chain, owner, local_types)
                if rtype:
                    kind, dtype = var_kind(rtype, name)
                elif chain:
                    kind, dtype = unknown_receiver_kind(name), None
                else:
                    continue
                if not kind and rtype and how == "=" and creates_entity(rhs):
                    # A member var assigned a new entity: whatever its declared type, the holder made
                    # it, so it owns it (own_set), unless declared otherwise.
                    got = idx.member(rtype, name)
                    d = idx.decl(rtype, name)
                    if got and not (d and decl_kind_of.get(d[1]) == "SHARED"):
                        kind, dtype = "entity", got[0]
                if not kind and rtype and how in OBJLIST_WRITES and puts_object(rhs, local_types, owner):
                    # An untyped list var collecting entities (src, a new object, an entity-typed local):
                    # an object-keyed roster, which is an owned or relation list.
                    got = idx.member(rtype, name)
                    d = idx.decl(rtype, name)
                    if got and got[2] and not (d and decl_kind_of.get(d[1]) == "SHARED"):
                        kind, dtype = "list", got[0]
                if not kind:
                    continue
                if allowed(raw, no, "ownership"):
                    continue
                recv = chain.rstrip(".") or "src"
                report("raw_write", r, no, "%s%s %s in %s/%s: %s var; use the ownership accessors (own_*/rel_*)" % (
                    chain, name, how, owner, proc, "an entity" if kind == "entity" else "an entity list"))
                RAW_SITES.append(dict(file=r, line=no, chain=chain, name=name, how=how, kind=kind, owner=owner,
                                      rtype=rtype, dtype=dtype, proc=proc))

    if args.json:
        import json
        with open(args.json, "w") as handle:
            json.dump(RAW_SITES, handle)
    if args.check:
        problems = [p for p in problems if p[0] in args.check]
    if args.under:
        problems = [p for p in problems if p[1].startswith(tuple(args.under))]
    if args.summary:
        counts = collections.Counter(p[0] for p in problems)
        dirs = collections.Counter((p[0], "/".join(p[1].split("/")[:3])) for p in problems)
        for check, n in counts.most_common():
            print("%-14s %d" % (check, n))
        print()
        for (check, d), n in sorted(dirs.items(), key=lambda x: (-x[1])):
            print("%-14s %-50s %d" % (check, d, n))
        return 1 if problems else 0
    for check, r, no, msg in sorted(problems, key=lambda p: (p[1], p[2])):
        print("%s:%d: [%s] %s" % (r, no, check, msg))
    counts = collections.Counter(p[0] for p in problems)
    print("ownership lint: %d problem%s (%s)" % (len(problems), "" if len(problems) == 1 else "s",
                                                ", ".join("%s %d" % kv for kv in counts.most_common()) or "clean"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
