#!/usr/bin/env python3
"""TSX act() calls against act_<action> procs (doc/rewrite/dx_conventions.md §5; design review C1, C2).

The dispatcher (code/datums/capabilities/ui_actions.dm, ui_named_dispatch()) answers a client action
`x` with the host's proc `act_<ui_action_key(x)>`, passing the client's params as named arguments
whose names are ui_action_key(param) and writing the reserved names (user, src, usr, ui, state)
last. ui_action_key() lowercases, turns camelCase and hyphens into snake_case, and rejects anything
that isn't [A-Za-z0-9_-] (64 chars max). This lint reads that normalisation (the two regexes, the
replacement, the length limit and the reserved list) out of ui_actions.dm, so the two can't drift;
it fails if it can no longer find them.

Hosts are the types that set `tgui_id = "Interface"` (and their subtypes that define act_ procs),
with the TSX of tgui/packages/tgui/interfaces/Interface(.tsx | /**/*.tsx). A host answers an action
with its own act_ proc, else with an act_ proc of a capability it declares (the dispatcher runs
`/datum/capability/<x>/proc/act_<action>(mob/user, atom/holder, ...)` on the flyweight, `holder`
being reserved); the capabilities come from its lineage's capabilities() bodies, with every cap_*
constructor and preset followed to the `new /datum/capability/...` it builds (without()/replace()
and runtime add_capability() are not followed). A host is migrated when it answers any action below
/atom; hosts still on DECLARE_UI rows (and interfaces that share one) are skipped until they migrate.

Hard failures, for each interface whose hosts are migrated:
  - an act('x', ...) whose name the dispatcher rejects, or that no host answers with act_x;
  - a key the dispatcher rejects or reserves (it is dropped: the handler sees null);
  - a key that act_x on an answering host doesn't declare (a runtime at dispatch).

Ratchets on a fingerprint baseline (tools/ci/ui_actions_baseline.txt), target 0, for every act_
proc of a UI host:
  C1 ui_unsent_param       every parameter except `user` is sent by some TSX act('<action>', {..})
                           of an interface that reaches the proc (the nearest tgui_id at or above
                           its type, every tgui_id below it; the interfaces of every host declaring
                           the capability, for a capability's proc; any interface for /datum and
                           /atom procs). A parameter no client sends is an internal flag a client could
                           still set by naming it: move it to an internal proc. An act() whose
                           params aren't an object literal (a variable, a spread) sends anything.
  C2 ui_unvalidated_param  the first use of each parameter validates it. Accepted first uses:
                             - the first argument of ui_number/ui_text/ui_choice/ui_ref/ui_bool(...),
                             - `!!param`, `switch(param)`, `islist(param)` (lists have no ui_ validator),
                             - `param ==/!= <constant>` ("text", a number, TRUE/FALSE/null, an
                               ALL_CAPS define), either side.
                           Skipped on the way: an assignment target (`p = ui_number(p)`), a
                           named-argument key, a bare truthiness test (`!p`, `isnull(p)`).
                           APPROXIMATION: a parameter handed straight to a helper proc (resolved by
                           name on the host's lineage, or global) passes only when the helper's
                           matching parameter passes the same check in the helper, followed up to 3
                           levels; the helper's other callers and its return value are not looked
                           at, and a helper that can't be resolved (a member call, a macro) fails.
                           Text is matched after comments and string contents are blanked; a
                           parameter never used is fine.
A justified keep is `// ALLOW(ui_actions): <reason>` on the proc head (C1) or on the use (C2).

    python tools/ci/ui_actions_lint.py            # check, exit 1 on a mismatch or a new C1/C2 site
    python tools/ci/ui_actions_lint.py --selftest
    python tools/ci/ui_actions_lint.py --report   # every C1/C2 site
    python tools/ci/ui_actions_lint.py --seed     # (re)create the C1/C2 baseline
    python tools/ci/ui_actions_lint.py --update   # drop fixed sites from the baseline (never adds)
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "sys_rules"))
import _dx_dm as dm  # noqa: E402
from allow_annotations import allowed, check_sites, write_sites  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASELINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ui_actions_baseline.txt")
DISPATCHER = "code/datums/capabilities/ui_actions.dm"
INTERFACES = os.path.join(ROOT, "tgui", "packages", "tgui", "interfaces")
EXEMPT = ("code/modules/unit_tests/", "code/modules/benchmarks/")
RULES = {
    "ui_unsent_param": "every act_ parameter must be sent by some TSX act(); move internal flags to an internal proc (design review C1)",
    "ui_unvalidated_param": "validate the parameter first: ui_number/ui_text/ui_choice/ui_ref/ui_bool(param), or compare it to a constant (design review C2)",
}
VALIDATORS = ("ui_number", "ui_text", "ui_choice", "ui_ref", "ui_bool")
CONSTANT = r'(?:"[^"\n]*"|-?\d+(?:\.\d+)?|TRUE|FALSE|null|[A-Z][A-Z0-9_]+)\b'
# Framework types whose act_ procs every host inherits (the modal actions).
BUILTIN_HOSTS = ("/datum", "/atom")

TGUI_ID_IN_BLOCK = re.compile(r'^\s+tgui_id\s*=\s*"([^"\n]+)"')
TGUI_ID_LINE = re.compile(r'^(/[\w/]+?)/tgui_id\s*=\s*"([^"\n]+)"')
LEGACY = re.compile(r"^\s*DECLARE_UI\w*\(\s*(/[\w/]+)")


# ---- the dispatcher's normalisation ------------------------------------------------------------

class Normaliser:
    """ui_action_key() and the reserved names, as the dispatcher defines them."""

    def __init__(self, raw_pattern=r"^[A-Za-z0-9_-]+$", camel_pattern=r"([a-z0-9])([A-Z])",
                 replacement="$1_$2", max_length=64, reserved=("user", "src", "usr", "ui", "state")):
        self.raw = re.compile(raw_pattern)
        self.camel = re.compile(camel_pattern)
        self.replacement = re.sub(r"\$(\d)", r"\\\1", replacement)
        self.max_length = max_length
        self.reserved = set(reserved)

    def key(self, raw):
        """The dispatcher's ui_action_key(raw), or None where it rejects raw."""
        if not isinstance(raw, str) or not raw or len(raw) > self.max_length or not self.raw.search(raw):
            return None
        return self.camel.sub(self.replacement, raw).lower().replace("-", "_")


PARITY = {
    "raw": re.compile(r'GLOBAL_DATUM_INIT\(\s*ui_action_raw_regex\s*,\s*/regex\s*,\s*regex\(\s*@?"([^"]+)"'),
    "camel": re.compile(r'GLOBAL_DATUM_INIT\(\s*ui_action_camel_regex\s*,\s*/regex\s*,\s*regex\(\s*@?"([^"]+)"'),
    "replacement": re.compile(r'ui_action_camel_regex\.Replace\(\s*\w+\s*,\s*"([^"]+)"\s*\)'),
    "max_length": re.compile(r"length\(raw\)\s*>\s*(\d+)"),
    "reserved": re.compile(r"GLOBAL_LIST_INIT\(\s*ui_reserved_arg_names\s*,\s*list\(([^)]*)\)"),
    "lower": re.compile(r"lowertext\("),
    "hyphen": re.compile(r'replacetext\([^,]+,\s*"-"\s*,\s*"_"\s*\)'),
}


def normaliser_from(text):
    """The Normaliser read from the dispatcher source, or raises ValueError naming what's missing."""
    found = {}
    for name, pattern in PARITY.items():
        m = pattern.search(text)
        if not m:
            raise ValueError("ui_actions_lint: can't find the dispatcher's %s in %s; update PARITY "
                             "(and the lint) to match ui_action_key()" % (name, DISPATCHER))
        found[name] = m.group(1) if m.groups() else True
    reserved = tuple(re.findall(r'"(\w+)"', found["reserved"]))
    return Normaliser(found["raw"], found["camel"], found["replacement"], int(found["max_length"]), reserved)


# ---- TSX ---------------------------------------------------------------------------------------

ACT_CALL = re.compile(r"(?<![\w$])act\(\s*")


def _skip_string(text, i):
    """Index just past the JS string/template literal starting at text[i]."""
    quote = text[i]
    j = i + 1
    while j < len(text):
        c = text[j]
        if c == "\\":
            j += 2
            continue
        if c == quote:
            return j + 1
        if quote == "`" and text.startswith("${", j):
            end = _match_brace(text, j + 1)
            j = end + 1 if end > 0 else len(text)
            continue
        j += 1
    return j


def _match_brace(text, i):
    """Index of the bracket closing the one at text[i] ({, [ or (), skipping strings and comments."""
    pairs = {"{": "}", "[": "]", "(": ")"}
    stack = []
    j = i
    while j < len(text):
        c = text[j]
        if c in "'\"`":
            j = _skip_string(text, j)
            continue
        if text.startswith("//", j):
            k = text.find("\n", j)
            j = len(text) if k < 0 else k
            continue
        if text.startswith("/*", j):
            k = text.find("*/", j + 2)
            j = len(text) if k < 0 else k + 2
            continue
        if c in pairs:
            stack.append(pairs[c])
        elif c in ")]}":
            if not stack or stack.pop() != c:
                return -1
            if not stack:
                return j
        j += 1
    return -1


def _split_top(text):
    parts, depth, start, j = [], 0, 0, 0
    while j < len(text):
        c = text[j]
        if c in "'\"`":
            j = _skip_string(text, j)
            continue
        if c in "{[(":
            depth += 1
        elif c in "}])":
            depth -= 1
        elif c == "," and depth == 0:
            parts.append(text[start:j])
            start = j + 1
        j += 1
    parts.append(text[start:])
    return parts


OBJ_KEY = re.compile(r"""^\s*(?:(['"])(.*?)\1|([A-Za-z_$][\w$]*))\s*(:|\(|$)""", re.S)


def object_keys(body):
    """The keys of a JS object literal's body, or None when a spread/computed key makes them open."""
    keys = []
    for part in _split_top(body):
        part = part.strip()
        if not part:
            continue
        if part.startswith("...") or part.startswith("["):
            return None
        m = OBJ_KEY.match(part)
        if not m:
            return None
        keys.append(m.group(2) if m.group(1) else m.group(3))
    return keys


def tsx_calls(text):
    """(line, raw action, raw keys or None) for every act('literal', ...) in a TSX source; keys is
    None when the params are not an object literal (a variable, a spread), [] when absent."""
    for m in ACT_CALL.finditer(text):
        i = m.end()
        if i >= len(text) or text[i] not in "'\"`":
            continue  # act(variable): the action isn't static
        end = _skip_string(text, i)
        action = text[i + 1:end - 1]
        if text[i] == "`" and "${" in action:
            continue
        j = end
        while j < len(text) and text[j].isspace():
            j += 1
        keys = []
        if j < len(text) and text[j] == ",":
            j += 1
            while j < len(text) and text[j].isspace():
                j += 1
            if j < len(text) and text[j] == "{":
                close = _match_brace(text, j)
                keys = object_keys(text[j + 1:close]) if close > 0 else None
            elif j < len(text) and text[j] != ")":
                keys = None
        yield text.count("\n", 0, m.start()) + 1, action, keys


def interface_files(interface):
    paths = []
    for ext in ("tsx", "ts", "jsx", "js"):
        paths += glob.glob(os.path.join(INTERFACES, interface + "." + ext))
        paths += glob.glob(os.path.join(INTERFACES, interface, "**", "*." + ext), recursive=True)
    return [p for p in paths if not p.endswith(".d.ts") and os.path.isfile(p)]


_TSX = {}


def _read_calls(path):
    got = _TSX.get(path)
    if got is None:
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        got = _TSX[path] = [(rel, line, action, keys) for line, action, keys in tsx_calls(text)]
    return got


def tsx_acts(interface):
    """(rel, line, raw action, raw keys or None) for every act() in an interface's sources; the
    interface None means every source under interfaces/ (for the builtin /datum actions)."""
    if interface is None:
        paths = [p for ext in ("tsx", "ts") for p in glob.glob(os.path.join(INTERFACES, "**", "*." + ext), recursive=True)
                 if not p.endswith(".d.ts") and os.path.isfile(p)]
    else:
        paths = interface_files(interface)
    out = []
    for path in sorted(set(paths)):
        out.extend(_read_calls(path))
    return out


# ---- DM ----------------------------------------------------------------------------------------

CAP_ROOT = "/datum/capability"
NEW_CAP = re.compile(r"\bnew\s+(/datum/capability[\w/]*)|\bvar/(/datum/capability[\w/]*)/\w+\s*=\s*new\b")
CTOR_CALL = re.compile(r"(?<![\w./:])(cap_\w+)\s*\(")


class Hosts:
    """UI hosts, their act_ procs (their own, and those of the capabilities they declare) and the
    legacy DECLARE_UI types."""

    def __init__(self, tree):
        self.tree = tree
        self.ids = {}       # type -> interface
        self.legacy = set()
        self.acts = {}      # host type -> {action key: Proc}
        self.cap_acts = {}  # capability type -> {action key: Proc}
        for rel, raw_lines in tree.files:
            clean = tree.clean[rel]
            current = None
            for number, code in enumerate(clean):
                head = dm.TYPE_HEAD.match(code.rstrip())
                if head:
                    current = head.group(1)
                    continue
                if code and code[:1] not in " \t":
                    current = None
                    legacy = LEGACY.match(code)
                    if legacy:
                        self.legacy.add(legacy.group(1))
                    line = TGUI_ID_LINE.match(raw_lines[number])
                    if line:
                        self.ids[line.group(1)] = line.group(2)
                    continue
                if current and "tgui_id" in code:
                    t = TGUI_ID_IN_BLOCK.match(raw_lines[number])
                    if t:
                        self.ids[current] = t.group(1)
        ctor_bodies, caps_bodies = {}, {}
        for proc in tree.procs:
            if proc.name.startswith("act_") and not proc.is_global():
                table = self.cap_acts if dm.is_subtype(proc.path, CAP_ROOT) else self.acts
                table.setdefault(proc.path, {})[proc.name[4:]] = proc
            elif proc.is_global() and proc.name.startswith("cap_"):
                ctor_bodies[proc.name] = "\n".join(proc.body)
            elif proc.name == "capabilities" and not proc.is_global():
                caps_bodies.setdefault(proc.path, []).append("\n".join(proc.body))
        self._ctor_bodies = ctor_bodies
        self._ctor_caps = {}
        # host type -> capability types its own capabilities() body adds (constructors resolved).
        self.type_caps = {path: set().union(*(self.caps_in(b) for b in bodies)) for path, bodies in caps_bodies.items()}

    def ctor_caps(self, name, seen=None):
        """The capability types a global cap_* constructor (or preset) builds."""
        if name in self._ctor_caps:
            return self._ctor_caps[name]
        seen = set(seen or ())
        if name in seen or name not in self._ctor_bodies:
            return set()
        seen.add(name)
        got = self.caps_in(self._ctor_bodies[name], seen)
        self._ctor_caps[name] = got
        return got

    def caps_in(self, body, seen=None):
        out = set()
        for m in NEW_CAP.finditer(body):
            out.add(m.group(1) or m.group(2))
        for m in CTOR_CALL.finditer(body):
            out |= self.ctor_caps(m.group(1), seen)
        return out

    def caps_of(self, path):
        """Capability types a host type declares (its lineage's capabilities() bodies; over-approximate:
        without()/replace() are not followed, and runtime add_capability() is not seen)."""
        out = set()
        for anc in dm.lineage(path):
            out |= self.type_caps.get(anc, set())
        return out

    def interface_of(self, path):
        for anc in dm.lineage(path):
            if anc in self.ids:
                return self.ids[anc]
        return None

    def is_legacy(self, path):
        return any(anc in self.legacy for anc in dm.lineage(path))

    def cap_actions(self, cap_type):
        out = {}
        for anc in reversed(dm.lineage(cap_type)):
            out.update(self.cap_acts.get(anc, {}))
        return out

    def actions_of(self, path):
        """{action: Proc} answered by path: its own act_ procs (nearest definition wins), else one of
        its capabilities' act_ procs (the dispatcher's order)."""
        out = {}
        for cap in sorted(self.caps_of(path)):
            for action, proc in self.cap_actions(cap).items():
                out.setdefault(action, proc)
        for anc in reversed(dm.lineage(path)):
            out.update(self.acts.get(anc, {}))
        return out

    def is_migrated(self, path):
        if any(anc not in BUILTIN_HOSTS and self.acts.get(anc) for anc in dm.lineage(path)):
            return True
        return any(self.cap_actions(cap) for cap in self.caps_of(path))

    def by_interface(self):
        """{interface: [host types]}: the tgui_id types plus subtypes defining act_ procs or declaring
        capabilities."""
        out = {}
        for path in set(self.ids) | set(self.acts) | set(self.type_caps):
            if path in BUILTIN_HOSTS or dm.is_subtype(path, CAP_ROOT):
                continue
            interface = self.interface_of(path)
            if interface:
                out.setdefault(interface, []).append(path)
        return out

    def served_interfaces(self, path):
        """Interfaces whose windows reach an act_ proc on path; None means every interface. For a
        capability's act_ proc: the interfaces of every host that declares that capability."""
        if path in BUILTIN_HOSTS:
            return None
        if dm.is_subtype(path, CAP_ROOT):
            out = set()
            for host, caps in self.type_caps.items():
                if any(dm.is_subtype(c, path) for c in caps):
                    out |= self.served_interfaces(host)
            return out
        out = set()
        top = self.interface_of(path)
        if top:
            out.add(top)
        for t, interface in self.ids.items():
            if dm.is_subtype(t, path):
                out.add(interface)
        return out


def check(hosts, norm, acts_for=tsx_acts):
    """The hard failures: act() calls that don't match the act_ procs of a migrated interface."""
    problems = []
    for interface, types in sorted(hosts.by_interface().items()):
        if any(hosts.is_legacy(t) for t in types):
            continue  # still (partly) on DECLARE_UI rows
        migrated = sorted(t for t in types if hosts.is_migrated(t))
        if not migrated:
            continue
        where = ", ".join(migrated)
        for rel, line, raw_action, raw_keys in acts_for(interface):
            action = norm.key(raw_action)
            if action is None:
                problems.append("%s:%d: act('%s'): the dispatcher rejects this action name ([A-Za-z0-9_-], 64 max)" % (rel, line, raw_action))
                continue
            answering = [t for t in migrated if action in hosts.actions_of(t)]
            if not answering:
                problems.append("%s:%d: act('%s') has no act_%s on %s" % (rel, line, raw_action, action, where))
                continue
            for raw_key in raw_keys or ():
                key = norm.key(raw_key)
                if key is None:
                    problems.append("%s:%d: act('%s') key '%s' is rejected by the dispatcher (dropped)" % (rel, line, raw_action, raw_key))
                elif key in norm.reserved:
                    problems.append("%s:%d: act('%s') key '%s' is a reserved argument name (dropped)" % (rel, line, raw_action, raw_key))
                else:
                    procs_answering = {id(p): p for p in (hosts.actions_of(t)[action] for t in answering)}
                    for proc in procs_answering.values():
                        if key not in proc.params:
                            problems.append("%s:%d: act('%s') passes %s, which act_%s on %s doesn't declare" % (rel, line, raw_action, key, action, proc.path))
    return problems


def ui_procs(hosts):
    """The act_ procs that a client can reach: on a UI host's lineage or below it (not legacy), and
    every capability's act_ procs (any holder with a window reaches them)."""
    out = []
    for path, actions in hosts.acts.items():
        if hosts.is_legacy(path):
            continue
        served = hosts.served_interfaces(path)
        if served is not None and not served:
            continue
        out.extend(actions.values())
    for actions in hosts.cap_acts.values():
        out.extend(actions.values())
    return out


def unsent_params(procs_list, hosts, norm, acts_for=tsx_acts):
    """C1: [(proc, param)] for each parameter no act() of a reaching interface sends."""
    out = []
    for proc in procs_list:
        action = proc.name[4:]
        served = hosts.served_interfaces(proc.path)
        if served is not None and not served:
            continue  # a capability no host declares yet: no act() to compare with (C2 still runs)
        sent, anything = set(), False
        for interface in ([None] if served is None else sorted(served)):
            for _rel, _line, raw_action, raw_keys in acts_for(interface):
                if norm.key(raw_action) != action:
                    continue
                if raw_keys is None:
                    anything = True
                    continue
                sent |= {norm.key(k) for k in raw_keys}
        if anything:
            continue
        for param in proc.params:
            if param not in norm.reserved and param not in sent:
                out.append((proc, param))
    return out


def _uses(proc, param):
    """(line number, text, column) for each occurrence of param in the body, in order."""
    # Not a member (x.param), a path segment (/obj/param, var/obj/param/x) or a type::param.
    pattern = re.compile(r"(?<![\w./:])" + re.escape(param) + r"\b")
    for number, text in proc.lines():
        for m in pattern.finditer(text):
            yield number, text, m.start()


def first_bad_use(proc, param, find_proc, depth=0):
    """None when param's first real use validates it, else the offending line number."""
    for number, text, col in _uses(proc, param):
        before, after = text[:col], text[col + len(param):]
        if re.match(r"\s*=(?!=)", after):
            continue  # an assignment target or a named-argument key
        if re.search(r"(?<!!)!\s*$", before) and not re.match(r"\s*(?:==|!=|in\b)", after):
            continue  # a bare truthiness test
        if re.search(r"\bisnull\(\s*$", before):
            continue
        if re.search(r"!!\s*$", before):
            return None
        if re.search(r"\b(?:switch|islist)\s*\(\s*$", before) and re.match(r"\s*\)", after):
            return None
        if re.match(r"\s*(?:==|!=)\s*" + CONSTANT, after) or re.search(CONSTANT + r"\s*(?:==|!=)\s*$", before):
            return None
        call = dm.enclosing_call(text, col, member=True)
        if call and re.match(r"\s*[,)]", after):
            name, index, key, member = call
            if name in VALIDATORS and index == 0 and not key and not member:
                return None
            helper = None if member else find_proc(proc.path, name)
            if helper and depth < 3:
                target = key if key else (helper.params[index] if index < len(helper.params) else None)
                if target and target in helper.params and first_bad_use(helper, target, find_proc, depth + 1) is None:
                    return None
        return number
    return None


def proc_finder(tree):
    def find(path, name):
        best = None
        chain = dm.lineage(path)
        for proc in tree.procs_named(name):
            if proc.is_global() or proc.path in chain:
                rank = -1 if proc.is_global() else len(chain) - chain.index(proc.path)
                if best is None or rank > best[0]:
                    best = (rank, proc)
        return best[1] if best else None
    return find


def unvalidated_params(procs_list, tree, norm):
    """C2: [(proc, param, line)]."""
    find = proc_finder(tree)
    out = []
    for proc in procs_list:
        for param in proc.params:
            if param in norm.reserved:
                continue
            bad = first_bad_use(proc, param, find)
            if bad:
                out.append((proc, param, bad))
    return out


def dx_sites(tree, hosts, norm, acts_for=tsx_acts):
    """{rule: [(rel, line)]} for C1/C2, ALLOW(ui_actions) honoured."""
    procs_list = ui_procs(hosts)
    sites = {rule: [] for rule in RULES}
    for proc, _param in unsent_params(procs_list, hosts, norm, acts_for):
        if not allowed(tree.raw[proc.rel], proc.line, "ui_actions"):
            sites["ui_unsent_param"].append((proc.rel, proc.line))
    for proc, _param, line in unvalidated_params(procs_list, tree, norm):
        if not allowed(tree.raw[proc.rel], line, "ui_actions"):
            sites["ui_unvalidated_param"].append((proc.rel, line))
    return sites


def load_tree():
    files = []
    for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        if rel.startswith(EXEMPT):
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            files.append((rel, handle.read().split("\n")))
    return dm.tree(files)


# ---- selftest ----------------------------------------------------------------------------------

DISPATCHER_FIXTURE = r'''
/proc/ui_action_key(raw)
	if(!istext(raw) || !length(raw) || length(raw) > 64 || !GLOB.ui_action_raw_regex.Find(raw))
		return null
	var/out = GLOB.ui_action_camel_regex.Replace(raw, "$1_$2")
	out = replacetext(lowertext(out), "-", "_")
	return out
GLOBAL_DATUM_INIT(ui_action_raw_regex, /regex, regex(@"^[A-Za-z0-9_-]+$"))
GLOBAL_DATUM_INIT(ui_action_camel_regex, /regex, regex(@"([a-z0-9])([A-Z])", "g"))
GLOBAL_LIST_INIT(ui_reserved_arg_names, list("user", "src", "usr", "ui", "state", "holder"))
'''

DM_FIXTURE = """/datum/proc/act_modal_close(mob/user, id)
	return TRUE
/obj/thing
	tgui_id = "Thing"
/obj/thing/proc/act_go(mob/user, speed, force)
	speed = ui_number(speed, 0, 10)
	if(!speed)
		return
/obj/thing/proc/act_pick(mob/user, mode, ref, flag)
	var/datum/D = find_ref(user, ref)
	if(!!flag)
		return
	switch(mode)
		if("a")
			return
/obj/thing/proc/find_ref(mob/user, ref)
	return ui_ref(ref, null, /datum)
/obj/thing/proc/act_raw(mob/user, amount, name, kind, when, extra)
	if(!amount)
		return
	var/x = amount + 1
	to_chat(user, name)
	if(kind == MODE_FAST)
		return
	helper(when)
	src.helper(extra)
/obj/thing/proc/helper(value)
	world << value
/obj/thing/subtype/proc/act_sub(mob/user, level, list/items)
	var/obj/level/marker = null
	level = ui_bool(level)
	for(var/i in islist(items) ? items : list())
		return
/obj/thing/proc/act_bolt_toggle(mob/user, target_state)
	return ui_bool(target_state)
/obj/old
	tgui_id = "Old"
DECLARE_UI(/obj/old, UI_TITLE("Old"))
/obj/old/proc/act_whatever(mob/user, anything)
	return anything
/datum/capability/breakers
/proc/cap_breakers()
	return new /datum/capability/breakers
/proc/cap_thing_preset()
	. = list(cap_breakers())
/obj/thing/capabilities()
	. = ..()
	. += cap_thing_preset()
/datum/capability/breakers/proc/act_breaker(mob/user, atom/holder, channel, force)
	channel = ui_number(channel, 1, 3)
	if(!channel)
		return
/datum/capability/unused/proc/act_unused(mob/user, atom/holder, level)
	world << level
"""


def selftest():
    norm = normaliser_from(DISPATCHER_FIXTURE)
    assert norm.key("bolt-toggle") == "bolt_toggle" and norm.key("boltToggle") == "bolt_toggle", norm.key("boltToggle")
    assert norm.key("setScreen") == "set_screen" and norm.key("targetState") == "target_state"
    assert norm.key("bad key") is None and norm.key("x" * 65) is None and norm.key("") is None
    assert norm.reserved == {"user", "src", "usr", "ui", "state", "holder"}
    try:
        normaliser_from("nothing here")
        raise AssertionError("a dispatcher without the regexes must fail")
    except ValueError:
        pass
    # The live dispatcher must still parse (lint/dispatcher parity).
    with open(os.path.join(ROOT, DISPATCHER), encoding="utf-8") as handle:
        live = normaliser_from(handle.read())
    assert live.key("bolt-toggle") == "bolt_toggle", "the live ui_action_key() no longer matches"

    tsx = """
      <Button onClick={() => act('go', { speed: 5 })} />
      <Button onClick={() => act("pick", {mode: 'a', 'ref': x.ref, flag})} />
      act('raw', { amount: 1, name: `n`, kind, when: a ? b : c, extra: { nested: 1 } });
      act('sub', {level: true, items: [1, 2]});
      act('bolt-toggle', { targetState: true });
      act(dynamicName, { a: 1 });
      act('pick', { ...params });
      act('modal_close', params);
      act('bogus');
      act('go', { speed: 1, bogus: 2 });
      act('go', { user: 'x' });
      act('go', { 'bad key': 1 });
      act('bad name!');
      act('breaker', { channel: 2 });
    """
    calls = list(tsx_calls(tsx))
    assert calls[0][1:] == ("go", ["speed"]), calls[0]
    assert calls[1][1:] == ("pick", ["mode", "ref", "flag"]), calls[1]
    assert calls[2][1:] == ("raw", ["amount", "name", "kind", "when", "extra"]), calls[2]
    assert calls[4][1:] == ("bolt-toggle", ["targetState"]), calls[4]
    assert calls[5][1:] == ("pick", None) and calls[6][1:] == ("modal_close", None), calls[5:7]
    assert calls[7][1:] == ("bogus", []), calls[7]

    lines = DM_FIXTURE.split("\n")
    tree = dm.Tree([("x.dm", lines)])
    hosts = Hosts(tree)
    acts = {"Thing": [("x.tsx", n, a, k) for n, a, k in calls], "Old": [("o.tsx", 1, "nope", [])]}

    def acts_for(interface):
        if interface is None:
            return [c for v in acts.values() for c in v]
        return acts.get(interface, [])
    problems = check(hosts, norm, acts_for)
    assert len(problems) == 5, problems
    # act('breaker') is answered by the capability the host declares through a preset.
    assert "breaker" in hosts.actions_of("/obj/thing") and hosts.caps_of("/obj/thing") == {"/datum/capability/breakers"}
    assert "act('bogus') has no act_bogus" in problems[0], problems
    assert "passes bogus" in problems[1] and "reserved" in problems[2] and "'bad key' is rejected" in problems[3], problems
    assert "rejects this action name" in problems[4], problems

    sites = dx_sites(tree, hosts, norm, acts_for)

    def at(snippet):
        return [k + 1 for k, line in enumerate(lines) if snippet in line][0]
    # C1: `force` on act_go is sent by no act(); act_modal_close's params arrive as a variable.
    # act_whatever is skipped (DECLARE_UI). targetState reaches act_bolt_toggle's target_state.
    # act_breaker's `force` too (a capability's action, reached through /obj/thing's window); holder
    # is reserved. act_unused belongs to a capability no host declares: C2 only.
    assert sorted(sites["ui_unsent_param"]) == sorted([("x.dm", at("act_go(")), ("x.dm", at("act_breaker("))]), sites
    # C2: act_raw's amount (after the skipped !amount), name (raw to to_chat), when (the helper
    # doesn't validate) and extra (a member call is not followed); kind compares to a define.
    # act_go/act_pick/act_sub/act_bolt_toggle are clean (ui_number after the assignment target, a
    # helper that ui_refs, !!flag, switch(mode), ui_bool after a path segment that merely spells the
    # name, islist(items), a validator as the first use).
    got = sorted(n for _r, n in sites["ui_unvalidated_param"])
    assert got == sorted([at("var/x = amount + 1"), at("to_chat(user, name)"), at("helper(when)"),
                          at("src.helper(extra)"), at("world << level")]), got
    print("ui_actions_lint selftest ok")
    return 0


def main(argv):
    if "--selftest" in argv:
        return selftest()
    with open(os.path.join(ROOT, DISPATCHER), encoding="utf-8") as handle:
        try:
            norm = normaliser_from(handle.read())
        except ValueError as err:
            print(err)
            return 1
    tree = load_tree()
    hosts = Hosts(tree)
    sites = dx_sites(tree, hosts, norm)
    header = ["ui_actions_lint C1/C2 baseline (design review C1, C2); shrink-only, target 0"]
    if "--report" in argv:
        for rule, found in sites.items():
            for rel, number in found:
                print("%s:%d: %s" % (rel, number, rule))
        return 0
    if "--seed" in argv or "--update" in argv:
        write_sites(BASELINE, header, sites, rules=list(RULES), shrink_only="--update" in argv)
        return 0
    problems = check(hosts, norm)
    for p in problems:
        print(p)
    print("ui_actions_lint: %d problem(s)" % len(problems))
    failed = check_sites("ui_actions", sites, BASELINE, RULES)
    return 1 if problems or failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
