#!/usr/bin/env python3
r"""DECLARE_UI / UI_ACT / UI_DATA rows -> interface() / op(ui_act()) entries (doc/rewrite/codemod_rules.md, "DECLARE_UI / UI_ACT").

    python tools/dx/codemods/ui_declare.py [--check] [--sites] [--only /type] [paths...]

One host type at a time: all of its legacy UI rows convert together or none does. A type that does not match the rules exactly is residue with a
code (listed with --sites). Idempotent: a converted type has no legacy rows left. Run `analyze gen` afterwards.
"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import re
import subprocess
import sys
from collections import defaultdict

SKIP = ("code/engine/_generated/", "code/__defines/", "code/modules/unit_tests/", "code/tests/", "tools/", "code/modules/tgs/")
ROW = re.compile(r"^(DECLARE_UI|DECLARE_UI_STATE|UI_[A-Z_]+)\((/[\w/]+)(.*)$")
OVERRIDES = ("ui_act_allowed", "tgui_data", "tgui_act", "ui_status", "tgui_interact", "ui_data", "ui_interact")
RESERVED = {"in", "as", "to", "step", "if", "else", "for", "while", "do", "set", "var", "new", "del", "null", "return", "src", "usr", "args", "list", "text", "num", "user", "A", "ui", "state", "action", "params"}
# Questions at the head of a button's handler (act_ask) become asks() steps of its op (leading_asks.py). --asks / --no-asks override the default.
ASKS_DEFAULT = True
LA = None
SETTINGS = ("EVENT_HANDLER", "SHOULD_", "PRIVATE_PROC", "PROTECTED_PROC", "RETURN_TYPE", "CAN_BE_REDEFINED")


def related(a, b):
    return a == b or a.startswith(b + "/") or b.startswith(a + "/")


def strip_code(s, keep=False):
    """The line without comments, string text blanked; the code inside a string's [..] interpolation is kept."""
    if '"' not in s and "//" not in s:
        return s
    out = []
    stack = []  # "str" (inside string text), "expr" (inside a [..] of a string), "br" (a bracket inside that)
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        top = stack[-1] if stack else None
        if top == "str":
            if c == chr(92):
                out.append(c if keep else " ")
                if i + 1 < n:
                    out.append(s[i + 1] if keep else " ")
                i += 2
                continue
            if c == '"':
                stack.pop()
                out.append(c)
            elif c == "[":
                stack.append("expr")
                out.append(c)
            else:
                out.append(c if keep else " ")
        else:
            if c == '"':
                stack.append("str")
                out.append(c)
            elif c == "[" and top in ("expr", "br"):
                stack.append("br")
                out.append(c)
            elif c == "]" and top in ("expr", "br"):
                stack.pop()
                out.append(c)
            elif c == "/" and s[i : i + 2] == "//" and not stack:
                break
            else:
                out.append(c)
        i += 1
    return "".join(out)


def split_args(s):
    out, depth, cur, in_str, i = [], 0, "", False, 0
    while i < len(s):
        c = s[i]
        if in_str:
            cur += c
            if c == chr(92) and i + 1 < len(s):
                cur += s[i + 1]
                i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
            cur += c
        elif c in "([{":
            depth += 1
            cur += c
        elif c in ")]}":
            depth -= 1
            cur += c
        elif c == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += c
        i += 1
    if cur.strip() or out:
        out.append(cur.strip())
    return out


def inner_of_call(row_text, name):
    """The text between the outer parentheses of `NAME(...)` at the start of row_text, or None when unbalanced."""
    i = row_text.index("(")
    depth = 0
    in_str = False
    for k in range(i, len(row_text)):
        c = row_text[k]
        if in_str:
            if c == chr(92):
                continue
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return row_text[i + 1 : k]
    return None


class File:
    def __init__(self, rel):
        self.rel = rel
        with open(rel, encoding="utf-8", errors="surrogateescape", newline="") as fh:
            raw = fh.read()
        self.crlf = "\r\n" in raw
        self.lines = raw.replace("\r\n", "\n").split("\n")
        self.dirty = False

    def save(self):
        eol = "\r\n" if self.crlf else "\n"
        out = []
        prev_blank_before_none = None
        for l in self.lines:
            if l is None:
                if prev_blank_before_none is None:
                    prev_blank_before_none = (not out) or out[-1].strip() == ""
                continue
            if prev_blank_before_none and l.strip() == "":
                prev_blank_before_none = None
                continue  # a removed row between two blank lines takes one of them
            prev_blank_before_none = None
            out.append(l)
        text = eol.join(out)
        if self.crlf:
            text = text.replace("\r\n", "\n").replace("\n", "\r\n")
        with open(self.rel, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
            fh.write(text)


def body_range(lines, sig_idx):
    """Indices of the body lines under a column-0 signature line (blank lines included), and the index of the last non-blank one."""
    j = sig_idx + 1
    last = sig_idx
    while j < len(lines):
        l = lines[j]
        if l is None:
            j += 1
            continue
        if l.strip() == "":
            j += 1
            continue
        if l[0] in " \t":
            last = j
            j += 1
            continue
        break
    return sig_idx + 1, last


def rename_local_a(line, new):
    """The word A in the code of `line` (not in a string or comment, not a member `.A`) becomes `new`; `var/obj/A` declares it."""
    masked = strip_code(line)
    out = []
    at = 0
    for m in re.finditer(r"(?<![\w.])A(?![\w])|(?<=\bvar/)(?:[\w]+/)*A(?![\w])", masked):
        start = m.end() - 1
        out.append(line[at:start])
        out.append(new)
        at = m.end()
    out.append(line[at:])
    return "".join(out)


def collect_vars(files):
    """type -> the var names its block declares (a holder var named in a question's field is read through nameof())."""
    vars_by_type = defaultdict(set)
    var_head = re.compile(r"^(/[\w/]+)\s*(//.*)?$")
    var_line = re.compile(r"^" + chr(9) + r"+var/(?:[\w/]+/)?(\w+)")
    var_path = re.compile(r"^(/[\w/]+)/var/(?:[\w/]+/)?(\w+)")
    for f in files.values():
        cur = None
        for l in f.lines:
            if not l:
                continue
            if l[0] == "/":
                hm = var_head.match(l)
                cur = hm.group(1) if hm else None
                vm0 = var_path.match(l)
                if vm0:
                    vars_by_type[vm0.group(1)].add(vm0.group(2))
            elif cur and l[0] == chr(9):
                vm = var_line.match(l)
                if vm:
                    vars_by_type[cur].add(vm.group(1))
    return vars_by_type


def holder_vars_of(vars_by_type, t):
    out = set()
    for u, vs in vars_by_type.items():
        if t == u or t.startswith(u + "/"):
            out |= vs
    return out


def arg_source_expr(source, holder_vars=None):
    """The DM expression of a UI_ARG_REF / UI_ARG_CHOICE source (ui_arg_source(): a list, "glob:x", "proc:x", a host var), None for a null
    source (a ref located anywhere), False when it is none of those."""
    s = source.strip()
    if s == "null":
        return None
    m = re.match(r'^"(proc|glob):(\w+)"$', s)
    if m:
        return ("%s()" % m.group(2)) if m.group(1) == "proc" else ("GLOB.%s" % m.group(2))
    m = re.match(r'^"(\w+)"$', s)
    if m:
        if holder_vars is not None and m.group(1) not in holder_vars and m.group(1) not in ("contents", "vars", "overlays", "underlays", "verbs"):
            return False  # no such var: the legacy parse refused every value (stack_trace), a hand fix
        if m.group(1) == "contents":
            return "contents_of(src)"  # the spatial read API, not a raw contents read (containment.md section 2a)
        return "src.%s" % m.group(1)
    if re.match(r"^list\(.*\)$", s):
        return s
    return False


def arg_schema_text(kind, name, bounds):
    """The arg() part of one legacy UI_ARG_* spec."""
    if kind == "VALUE" or kind == "LIST" or kind == "CHOICE":
        return 'arg("%s")' % name
    if kind == "TEXT":
        return 'arg("%s", schema_text(%s))' % (name, bounds[0] if bounds else "4096")
    if kind == "BOOL":
        return 'arg("%s", bool())' % name
    if kind == "PATH":
        return 'arg("%s", schema_path(%s))' % (name, bounds[0])
    if kind == "REF":
        types = bounds[1:]
        return 'arg("%s", schema_ref(%s))' % (name, types[0] if len(types) == 1 else "")
    fn = "num" if kind == "NUM" else "int"
    return 'arg("%s", %s(%s))' % (name, fn, ", ".join(bounds))


def arg_guards(kind, local, bounds, body):
    """The handler's first lines that keep what the legacy spec checked and the schema does not: a ref or choice must be in its source, a ref
    of one of several types, a list a list. A ref the handler never null-checks must be there (the legacy parse refused an unknown ref)."""
    out = []
    if kind == "LIST":
        out.append("if(!isnull(%s) && !islist(%s))" % (local, local))
    if kind in ("REF", "CHOICE"):
        src = arg_source_expr(bounds[0])
        if src:
            out.append("if(!isnull(%s) && !(%s in %s))" % (local, local, src))
    if kind == "REF":
        types = bounds[1:]
        if len(types) > 1:
            out.append("if(!isnull(%s) && !(%s))" % (local, " || ".join("istype(%s, %s)" % (local, ty) for ty in types)))
        aliases = [local] + re.findall(r"var/[\w/]*?(\w+)\s*=\s*%s\b" % re.escape(local), body)
        handles_null = any(re.search(r"(?<![\w.])(?:!\s*%s\b|isnull\(\s*%s\s*\)|%s\s*\?\.|QDELETED\(\s*%s\s*\)|istype\(\s*%s\b|%s\s*==\s*null|if\(\s*%s\s*\))" % ((re.escape(al),) * 7), body) for al in aliases)
        if not handles_null:
            out.append("if(isnull(%s))" % local)
    return out


def words_in(text, name):
    return [m.start() for m in re.finditer(r"(?<![\w./])" + re.escape(name) + r"(?![\w])", text)]


FORCE = set()


def forced(code):
    """A residue code the run was told to accept (--force CODE: convert anyway, the rest is a hand fix the compile points at)."""
    return None if (code in FORCE or code.split(":")[0] + ":*" in FORCE) else code


def main():
    global LA
    asks_on = ("--no-asks" not in sys.argv) and (ASKS_DEFAULT or "--asks" in sys.argv)
    if asks_on:
        import leading_asks as LA_module

        LA = LA_module
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check = "--check" in sys.argv
    sites = "--sites" in sys.argv
    skip = set()
    while "--skip" in sys.argv:
        k = sys.argv.index("--skip")
        skip.add(sys.argv[k + 1])
        del sys.argv[k : k + 2]
    while "--force" in sys.argv:
        k = sys.argv.index("--force")
        FORCE.add(sys.argv[k + 1])
        del sys.argv[k : k + 2]
    exclude = []  # --exclude PREFIX: types whose rows stand in a file under PREFIX are left alone (another branch owns those files)
    while "--exclude" in sys.argv:
        k = sys.argv.index("--exclude")
        exclude.append(sys.argv[k + 1])
        del sys.argv[k : k + 2]
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1]
        args = [a for a in args if a != only]
    if "--files" in sys.argv:
        names = args  # exactly these files (the self-test)
    else:
        names = subprocess.check_output(["git", "ls-files", "-z", "*.dm"]).decode("utf-8", "surrogateescape").split("\0")
        names = [n for n in names if n and not n.startswith(SKIP)]
    files = {}
    rows = defaultdict(list)  # type -> [(kind, rel, idx, text)]
    code_text = {}
    for rel in names:
        try:
            f = File(rel)
        except OSError:
            continue
        files[rel] = f
        code_text[rel] = "\n".join(strip_code(l) for l in f.lines)
        for i, l in enumerate(f.lines):
            m = ROW.match(l)
            if m:
                rows[m.group(2)].append((m.group(1), rel, i, l))
    types = set(rows)
    residue = {}  # type -> reason
    plans = {}
    vars_by_type = collect_vars(files) if asks_on else None
    vars_all = collect_vars(files)
    all_code = "\n".join(code_text.values())
    # Mentions that are neither a UI row nor a definition: calls, PROC_REFs, whatever could depend on a handler's signature.
    other_mentions = "\n".join(
        l for l in all_code.split("\n") if not re.match(r"^(UI_[A-Z_]+|DECLARE_UI\w*)\(", l) and not re.match(r"^/[\w/]+/(proc/)?\w+\(", l)
    )
    tree_text = "\n".join("\n".join(f.lines) for f in files.values())
    word_re = re.compile(r"(?<![\w./])[A-Za-z_]\w*")
    # Each mention of a name with the type whose code it stands in (the proc's type, the CAPABILITIES block's, a macro row's first path):
    # a bare name in an unrelated type's code is not this type's proc. TYPE_PROC_REF(/path, x) counts for /path.
    mention_ctx = defaultdict(list)  # name -> [ctx type or None]
    ctx_def = re.compile(r"^(/[\w/]+?)/(?:proc/|verb/)?\w+\(")
    ctx_head = re.compile(r"^(/[\w/]+)\s*(//.*)?$")
    ctx_macro = re.compile(r"^[A-Z_][A-Z0-9_]*\(\s*(/[\w/]+)")
    tpr = re.compile(r"TYPE_PROC_REF\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\)")
    for rel, ctext in code_text.items():
        ctx = None
        for l in ctext.split("\n"):
            if l and l[0] not in " \t":
                if re.match(r"^(UI_[A-Z_]+|DECLARE_UI\w*)\(", l):
                    ctx = None
                    continue
                m = ctx_def.match(l)
                if m:
                    ctx = m.group(1)
                    continue  # the definition line itself
                m = ctx_head.match(l) or ctx_macro.match(l)
                ctx = m.group(1) if m else None
            for m in tpr.finditer(l):
                mention_ctx[m.group(2)].append(m.group(1))
            for w in word_re.findall(tpr.sub(" ", l)):
                mention_ctx[w].append(ctx)

    def mentions(name, t):
        return sum(1 for c in mention_ctx.get(name, ()) if c is None or c == "/proc" or related(c, t))

    code_words = set(word_re.findall(all_code))
    # Indexes (one pass over the tree): column-0 proc definitions, UI_ACT_PROC headers, CAPABILITIES blocks.
    defs_idx = defaultdict(list)  # (type, proc) -> [(rel, i)]
    actproc_idx = {}  # (type, proc) -> (rel, i)
    caps_idx = {}  # type -> (rel, i)
    def_re = re.compile(r"^(/[\w/]+?)/(?:proc/|verb/)?(\w+)\(")
    ap_re = re.compile(r"^UI_ACT_PROC\((/[\w/]+),\s*(\w+)\)\s*(//.*)?$")
    cap_re = re.compile(r"^CAPABILITIES\((/[\w/]+)\)\s*(//.*)?$")
    for rel, f in files.items():
        for i, l in enumerate(f.lines):
            if not l or l[0] not in "/UC":
                continue
            m = def_re.match(l)
            if m:
                defs_idx[(m.group(1), m.group(2))].append((rel, i))
                continue
            m = ap_re.match(l)
            if m:
                actproc_idx[(m.group(1), m.group(2))] = (rel, i)
                continue
            m = cap_re.match(l)
            if m:
                caps_idx[m.group(1)] = (rel, i)

    def block_has_interface(t):
        if t not in caps_idx:
            return False
        rel, i = caps_idx[t]
        first, last = body_range(files[rel].lines, i)
        return any(l and re.match(r"^[ \t]+interface\(", l) for l in files[rel].lines[first : last + 1])

    overrides_of = defaultdict(set)
    for ty, pn in defs_idx:
        if pn in OVERRIDES:
            overrides_of[ty].add(pn)
    # `ui_act_allowed` definitions: type -> (rel, line index). The op path never calls it, so a type that overrides it converts only when
    # the override is `if(!..()) return FALSE; add_fingerprint(user); return TRUE` and no related type defines one: then the guard is
    # always TRUE and the fingerprint moves to the head of every handler (the same effect, once per press, before anything else).
    allowed_defs = defaultdict(list)
    uaa = re.compile(r"^(/[\w/]+?)/(?:proc/)?ui_act_allowed\(")
    for rel, f in files.items():
        for i, l in enumerate(f.lines):
            if l and l[0] == "/":
                um = uaa.match(l)
                if um:
                    allowed_defs[um.group(1)].append((rel, i))
    FP_BODY_A = ["if(!..())", "return FALSE", "add_fingerprint(ui.user)", "return TRUE"]
    FP_BODY_B = ["if(!..())", "return FALSE", "add_fingerprint(user)", "return TRUE"]

    def fingerprint_only(t):
        defs = allowed_defs.get(t, [])
        if len(defs) != 1:
            return None
        rel, i = defs[0]
        f = files[rel]
        first, last = body_range(f.lines, i)
        lines = [strip_code(l).strip() for l in f.lines[first : last + 1]]
        lines = [l for l in lines if l]
        if lines in (FP_BODY_A, FP_BODY_B):
            return ("fp", rel, i, first, last)
        return predicate_guard(t, rel, i, first, last, lines)

    BANNED = ("to_chat", "add_fingerprint", "visible_message", "playsound", "play_sfx", "message", "qdel", "spawn", "sleep", "stoplag", "usr")
    PRED_HEAD = ["if(!..())", "return FALSE"]

    def predicate_guard(t, rel, i, first, last, lines):
        """`if(!..()) return FALSE` then a pure test of the actor and the host, ending `return TRUE`: the guard of every window button, as one
        silent requirement (the op path never calls ui_act_allowed)."""
        body = "\n".join(lines[2:] if lines[:2] == PRED_HEAD else lines)
        if re.search(r"\.\.\(|\bstate\b|\bparams\b|\bsrc\.ui\b", body) or re.search(r"\bui\b(?!\.user)", body):
            return None
        if (t, "ui_gate") in defs_idx or any(u != t and related(t, u) and pn == "ui_gate" and not u.startswith(t + "/") for (u, pn) in defs_idx):
            return None  # a ui_gate of its own, or an ancestor's that is not one of this conversion's
        return ("pred", rel, i, first, last)

    def fam_ancestors(fam, t):
        """The family's types that are proper ancestors of t, root first."""
        return sorted((u for u in fam["types"] if t.startswith(u + "/")), key=lambda u: u.count("/"))

    def ancestor_blocks_touch_open(ancestors_any):
        """An ancestor's CAPABILITIES block changes the window's open op (an extend of "ui_open"): declaring the window again would drop it."""
        for u in ancestors_any:
            if u in caps_idx:
                rel, i = caps_idx[u]
                first, last = body_range(files[rel].lines, i)
                if any(l and "ui_open" in l for l in files[rel].lines[first : last + 1]):
                    return True
        return False

    def block_interface(u):
        """(line index, rel, args) of the interface() entry in u's own CAPABILITIES block, or None."""
        if u not in caps_idx:
            return None
        rel, i = caps_idx[u]
        first, last = body_range(files[rel].lines, i)
        for k in range(first, last + 1):
            l = files[rel].lines[k]
            m = re.match(r"^[ \t]+interface\((.*)\)\s*(//.*)?$", l or "")
            if m:
                return (k, rel, split_args(m.group(1)))
        return None

    def ancestor_paths(t):
        parts = t.strip("/").split("/")
        return ["/" + "/".join(parts[: k + 1]) for k in range(len(parts) - 1)]

    def windows_below(t):
        """Types under t that declare a window: a DECLARE_UI row or an interface() in their block."""
        out = [u for u in rows if u.startswith(t + "/") and any(r[0] == "DECLARE_UI" for r in rows[u])]
        out += [u for u in caps_idx if u.startswith(t + "/") and block_interface(u)]
        return out

    def plan_type(t, rs, fam):
        """The plan of one host type of a family (fam: the family's types and what its ancestors already declared, filled parents first),
        or (None, residue code)."""
        if t in skip:
            return None, "ui_gate_reads"  # --skip: the reads lint rejects the guard's untracked reads (see codemod_rules.md)
        kinds = [r[0] for r in rs]
        decl = [r for r in rs if r[0] == "DECLARE_UI"]
        if len(decl) > 1:
            return None, "ui_forms"  # several declarations
        window = title = None
        window_extra = []
        if decl:
            dparts = split_args(inner_of_call(decl[0][3], "DECLARE_UI") or "")
            if len(dparts) < 2 or dparts[0] != t:
                return None, "ui_options"
            window_extra = []
            wm = re.match(r'^"([^"]*)"$', dparts[1])
            vm = re.match(r'^UI_FROM_VAR\("(\w+)"\)$', dparts[1])
            if wm:
                window = wm.group(1)
            elif vm:
                # the window from a var each subtype sets (interface(null, window_var = nameof(x)))
                window = None
                window_extra.append("window_var = nameof(%s)" % vm.group(1))
            else:
                return None, "ui_options"
            for opt in dparts[2:]:
                tm = re.match(r'^UI_TITLE\("([^"]*)"\)$', opt)
                if tm:
                    title = tm.group(1)
                elif opt in ("UI_AUTOUPDATE", "UI_PINNED", "UI_PREINITIALIZED"):
                    window_extra.append("%s = TRUE" % opt[3:].lower())
                else:
                    return None, "ui_options"
            if window is None:
                window = "__var__"
        if any(k not in ("DECLARE_UI", "DECLARE_UI_STATE", "UI_ACT", "UI_ACT_PROC", "UI_DATA", "UI_DATA_REPLACE", "UI_ACT_FALLBACK", "UI_ACT_FORWARD", "UI_ACT_OVERRIDE") for k in kinds):
            return None, "ui_forms"
        ancestors = fam_ancestors(fam, t)
        # a related type outside the family (no legacy rows) that guards every button: the op path would skip its guard
        if any(related(t, u) and u != t and u != "/datum" and u not in fam["types"] for u in allowed_defs):
            return None, "ui_override:related_allowed"
        tre = re.escape(t)
        fp = fingerprint_only(t)
        guard = fp[0] if fp else None
        fp = fp if guard else None
        if allowed_defs.get(t) and not fp:
            return None, "ui_override:allowed"
        # A type's own window procs stay beside the declaration: tgui_interact()/ui_interact()/ui_status() open and gate the window, a
        # tgui_data() override chains to the base that merges ui_data(), a tgui_act() override chains to the base that runs the ops. Only
        # an own ui_data() collides, with the data rows the codemod turns into one.
        if "ui_data" in overrides_of.get(t, ()) and any(r[0] in ("UI_DATA", "UI_DATA_REPLACE") for r in rs):
            return None, "ui_override:ui_data"
        if block_has_interface(t):
            srows = [r for r in rs if r[0] == "DECLARE_UI_STATE"]
            if len(srows) == len(rs) == 1:
                sparts = split_args(inner_of_call(srows[0][3], "DECLARE_UI_STATE") or "")
                gm = re.match(r"^GLOB\.(\w+)$", sparts[1]) if len(sparts) == 2 else None
                am = re.match(r"^ADMIN_STATE\((.+)\)$", sparts[1]) if len(sparts) == 2 else None
                if gm or am:
                    return {"type": t, "state_into_block": ("state = nameof(GLOB.%s)" % gm.group(1)) if gm else ("rights = %s" % am.group(1)), "row": srows[0],
                            "window": None, "title": None, "acts": [], "data": None, "rows": rs, "handlers": [], "fp": None, "pred": None, "state": None,
                            "forward": None, "anc_gate": False, "anc_fp": False, "inherited": None, "fam_gated": False, "fam_root": None, "interface_args": None}, None
            return None, "ui_override:interface"
        anc_gate = any(fam["gate"].get(u) for u in ancestors)
        anc_fp = any(fam["fp"].get(u) for u in ancestors)
        if guard == "fp" and fam["gated"]:
            # in a family with a guard every handler asks ui_gate(A): a fingerprint guard is a gate like any other
            guard = "pred"
        if (guard or fam["gated"]) and [r for r in rs if r[0] == "UI_ACT_FORWARD"]:
            return None, "ui_override:gate_forward"  # the forwarded buttons are the target's ops: they would not ask this holder's guard
        acts = []
        bad = None
        for k, rel, idx, text in rs:
            if k != "UI_ACT":
                continue
            inner = inner_of_call(text, "UI_ACT")
            if inner is None:
                bad = "ui_forms"
                break
            parts = split_args(inner)
            if len(parts) < 3 or parts[0] != t:
                bad = "ui_forms"
                break
            am = re.match(r'^"([A-Za-z0-9_ -]+)"$', parts[1]) or re.match(r'^([A-Z][A-Z0-9_]*)$', parts[1])
            if not am or not re.match(r"^[A-Za-z_]\w*$", parts[2]):
                bad = "act_name"
                break
            specs = []
            for sp in parts[3:]:
                sm = re.match(r'^UI_ARG_(NUM|INT|VALUE|TEXT|BOOL|PATH|REF|CHOICE|LIST)\(\s*"([A-Za-z_][A-Za-z0-9_-]*)"\s*(?:,\s*(.*))?\)$', sp)
                if not sm:
                    bad = "arg_kind"
                    break
                bounds = split_args(sm.group(3)) if sm.group(3) else []
                if sm.group(1) in ("BOOL", "LIST") and bounds:
                    bad = "arg_kind"
                    break
                if sm.group(1) == "PATH" and (len(bounds) != 1 or not re.match(r"^/[\w/]+$", bounds[0])):
                    bad = "arg_kind"
                    break
                if sm.group(1) == "CHOICE" and len(bounds) != 1:
                    bad = "arg_kind"
                    break
                if sm.group(1) == "REF" and (len(bounds) < 1 or any(not re.match(r"^/[\w/]+$", b) for b in bounds[1:])):
                    bad = "arg_kind"
                    break
                if sm.group(1) in ("REF", "CHOICE"):
                    src = arg_source_expr(bounds[0], holder_vars_of(vars_all, t))
                    if src is False:
                        bad = "arg_kind"
                        break
                if sm.group(1) == "VALUE" and len(bounds) > 1:
                    bad = "arg_kind"
                    break
                if sm.group(1) == "TEXT" and len(bounds) > 1:
                    bad = "arg_kind"
                    break
                if sm.group(1) in ("NUM", "INT") and len(bounds) not in (0, 2):
                    bad = "arg_kind"
                    break
                specs.append((sm.group(1), sm.group(2), bounds))
            if bad:
                break
            acts.append({"rel": rel, "idx": idx, "action": am.group(1), "expr": parts[1], "proc": parts[2], "specs": specs})
        if bad:
            return None, bad
        fb_rows = [r for r in rs if r[0] == "UI_ACT_FALLBACK"]
        fwd_rows = [r for r in rs if r[0] == "UI_ACT_FORWARD"]
        if len(fb_rows) > 1 or len(fwd_rows) > 1:
            return None, "ui_forms"
        for k, rel, idx, text in fb_rows:
            # UI_ACT_FALLBACK(T, proc): every window action no row names. It is the op ui_act("*"); the handler reads which action with A.window_action().
            fparts = split_args(inner_of_call(text, "UI_ACT_FALLBACK") or "")
            if len(fparts) != 2 or fparts[0] != t or not re.match(r"^[A-Za-z_]\w*$", fparts[1]):
                bad = "ui_forms"
                break
            acts.append({"rel": rel, "idx": idx, "action": "*", "key": re.sub(r"^ui_act_", "", fparts[1]) or fparts[1], "proc": fparts[1], "specs": [], "fallback": True})
        if bad:
            return None, bad
        acts.sort(key=lambda x: (x["rel"], x["idx"]))
        forward = None
        for k, rel, idx, text in fwd_rows:
            # UI_ACT_FORWARD(T, proc) with `proc(mob/user, action)` returning one var of the holder: interface(forwards = nameof(var))
            fparts = split_args(inner_of_call(text, "UI_ACT_FORWARD") or "")
            if len(fparts) != 2 or fparts[0] != t or not re.match(r"^[A-Za-z_]\w*$", fparts[1]):
                bad = "ui_forms"
                break
            fdef = None
            for frel, fi in defs_idx.get((t, fparts[1]), []):
                if re.match(r"^" + re.escape(t) + r"/(?:proc/)?" + re.escape(fparts[1]) + r"\(\s*mob/user\s*,\s*action\s*\)\s*(//.*)?$", files[frel].lines[fi]):
                    fdef = (frel, fi)
                    break
            if not fdef or mentions(fparts[1], t) != 0:
                bad = "ui_forward_expr"
                break
            ffirst, flast = body_range(files[fdef[0]].lines, fdef[1])
            fbody = [strip_code(l).strip() for l in files[fdef[0]].lines[ffirst : flast + 1] if strip_code(l).strip()]
            fm = re.match(r"^return\s+([a-z_]\w*)$", fbody[0]) if len(fbody) == 1 else None
            if not fm or fm.group(1) not in holder_vars_of(vars_all, t):
                bad = "ui_forward_expr"
                break
            forward = {"var": fm.group(1), "def": fdef, "first": ffirst, "last": flast, "row": (rel, idx)}
        if bad:
            return None, bad
        if len({a["action"] for a in acts}) != len(acts):
            return None, "proc_shared"
        # one handler for several buttons with the same args: one op each, the handler reads which with A.window_action()
        by_proc = {}
        for a in acts:
            other = by_proc.setdefault(a["proc"], a)
            if other is not a and other["specs"] != a["specs"]:
                return None, "proc_shared"
        # UI_ACT_OVERRIDE(T, proc): this type's handler of a button an ancestor declares
        overrides = []
        for k, rel, idx, text in rs:
            if k != "UI_ACT_OVERRIDE" or any(re.match(r"^UI_ACT_OVERRIDE\(" + re.escape(t) + r",\s*" + re.escape(a["proc"]) + r"\)", text) for a in acts):
                continue
            om = re.match(r"^UI_ACT_OVERRIDE\((/[\w/]+),\s*(\w+)\)\s*(//.*)?$", text)
            spec = None
            for u in reversed(ancestors):
                spec = fam["acts"].get((u, om.group(2))) if om else None
                if spec:
                    break
            if not om or om.group(1) != t or not spec:
                return None, "ui_override_other"
            overrides.append({"act": spec, "owner": t, "row": (rel, idx)})
        data_rows = [r for r in rs if r[0] in ("UI_DATA", "UI_DATA_REPLACE")]
        if window and not acts and not data_rows and not forward:
            return None, "no_ops"  # a window with no buttons and no data has nothing to type (ui_types)
        data = None
        if len(data_rows) > 1:
            return None, "data_rows"
        if data_rows:
            dinner = inner_of_call(data_rows[0][3], "UI_DATA")
            dparts = split_args(dinner) if dinner is not None else []
            if len(dparts) < 2 or dparts[0] != t:
                return None, "data_rows"
            fields = []
            shape = []  # (data key, legacy type) for ui_shape()
            for dp in dparts[1:]:
                fm = re.match(r'^"([^"]*)"$', dp)
                if not fm:
                    fields = None
                    break
                txt = fm.group(1)
                mm = re.match(r"^merge:(\w+)(?:\{([^}]*)\})?$", txt)
                if mm:
                    fields.append(("merge", mm.group(1), None))
                    for kv in (mm.group(2) or "").split(","):
                        if ":" in kv:
                            shape.append(tuple(x.strip() for x in kv.split(":", 1)))
                    continue
                key = None
                if "=" in txt:
                    key, txt = txt.split("=", 1)
                    if not re.match(r"^[A-Za-z_]\w*$", key):
                        fields = None
                        break
                kind = "var"
                if txt.startswith("proc:"):
                    kind = "proc"
                    txt = txt[5:]
                elif txt.startswith("slot:") or txt.startswith("merge:"):
                    fields = None
                    break
                name = txt.split(":", 1)[0]
                if not re.match(r"^[A-Za-z_]\w*$", name):
                    fields = None
                    break
                fields.append((kind, name, key or name))
                shape.append((key or name, txt.split(":", 1)[1] if ":" in txt else "unknown"))
            if not fields:
                return None, "data_rows"
            additive = data_rows[0][0] == "UI_DATA" and (any(fam["data"].get(u) for u in ancestors) or any(pn == "ui_data" and u != "/datum" and related(t, u) and not u.startswith(t + "/") for (u, pn) in defs_idx))
            if data_rows[0][0] == "UI_DATA_REPLACE" and any(pn == "ui_data" and u != "/datum" and u not in fam["types"] and t.startswith(u + "/") for (u, pn) in defs_idx):
                return None, "data_rows"  # replaces the legacy fields of its parents but not an ancestor's own ui_data()
            data = {"row": data_rows[0], "fields": fields, "shape": shape, "additive": additive}
        # the window: its own declaration, or (a state row of its own) the inherited one declared again with the state
        inherited = None
        for u in reversed(ancestor_paths(t)):
            if fam["window"].get(u):
                inherited = fam["window"][u]
                break
            bi = block_interface(u)
            if bi:
                inherited = {"args": bi[2]}
                break
        plan = {"type": t, "window": window, "title": title, "acts": acts, "data": data, "rows": rs, "handlers": [], "fp": fp if guard == "fp" else None, "pred": fp if guard == "pred" else None, "state": None, "forward": forward,
                "anc_gate": anc_gate, "anc_fp": anc_fp, "inherited": inherited, "fam_gated": fam["gated"], "fam_root": fam["root"]}
        # DECLARE_UI_STATE(T, GLOB.tgui_x_state) -> interface(.., state = nameof(GLOB.tgui_x_state)); (T, ADMIN_STATE(rights)) -> interface(.., rights = rights):
        # the row goes. Any other expression (an instance's own state) keeps its row, which ui_open() still reads.
        state_rows = [r for r in rs if r[0] == "DECLARE_UI_STATE"]
        if len(state_rows) == 1:
            sinner = inner_of_call(state_rows[0][3], "DECLARE_UI_STATE")
            sparts = split_args(sinner) if sinner is not None else []
            if len(sparts) == 2 and sparts[0] == t:
                gm = re.match(r"^GLOB\.(\w+)$", sparts[1])
                am = re.match(r"^ADMIN_STATE\((.+)\)$", sparts[1])
                if gm:
                    plan["state"] = ("state = nameof(GLOB.%s)" % gm.group(1), state_rows[0])
                elif am:
                    plan["state"] = ("rights = %s" % am.group(1), state_rows[0])
            if plan["state"] and not window:
                if inherited:
                    # a subtype that changes only who may use the window declares the window again with its state
                    if ancestor_blocks_touch_open(ancestor_paths(t)):
                        return None, "ui_state:open_extended"
                elif windows_below(t):
                    # a parent of windows: its state goes to every window below it that has no nearer state of its own (the legacy state row won over theirs)
                    plan["state_down"] = plan["state"]
                else:
                    # no window declared anywhere above or below: the state is the type's tgui_state() (the base the window falls back to)
                    if "tgui_state" in overrides_of.get(t, ()):
                        return None, "ui_state:no_window"
                    plan["state_proc"] = plan["state"]
        if window and not plan["state"]:
            for u in reversed(ancestors):
                if fam["state_down"].get(u):
                    plan["state"] = (fam["state_down"][u][0], None)
                    break
        if not window and forward:
            if not inherited:
                return None, "ui_forms"
        plan["interface_args"] = None
        if window:
            plan["interface_args"] = [('"%s"' % window) if window != "__var__" else "null"] + (['title = "%s"' % title] if title is not None else []) + ([plan["state"][0]] if plan["state"] else []) + (["forwards = nameof(%s)" % forward["var"]] if forward else []) + window_extra
        elif (plan["state"] and not plan.get("state_down") and not plan.get("state_proc")) or forward:
            keep = [a for a in inherited["args"] if not re.match(r"^(state|rights)\s*=", a) and not (forward and re.match(r"^forwards\s*=", a))]
            plan["redeclared"] = keep + ([plan["state"][0]] if plan["state"] else []) + (["forwards = nameof(%s)" % forward["var"]] if forward else [])
        # ---- handlers
        handler_jobs = [{"act": a, "owner": t, "row": None} for a in acts if by_proc[a["proc"]] is a] + overrides
        bad = None
        for job in handler_jobs:
            a = job["act"]
            hit = job["row"]
            if not hit:
                hit = actproc_idx.get((t, a["proc"]))
                if not hit:
                    # a subtype that declares the button again and overrides its parent's handler (UI_ACT then UI_ACT_OVERRIDE)
                    for k2, rel2, idx2, text2 in rs:
                        if k2 == "UI_ACT_OVERRIDE" and re.match(r"^UI_ACT_OVERRIDE\(" + tre + r",\s*" + re.escape(a["proc"]) + r"\)", text2):
                            hit = (rel2, idx2)
                            job["row"] = hit
            if not hit:
                bad = "proc_missing"
                break
            rel, i = hit
            f = files[rel]
            first, last = body_range(f.lines, i)
            body_lines = f.lines[first : last + 1]
            # questions at the head of the handler (act_ask) become asks() steps of the op; the rest of the body is the effect
            asks = []
            if asks_on and any(LA.ASK_CALL.search(strip_code(l)) for l in body_lines):
                asks, why_ask = LA.parse_leading(f.lines, first, last, a["proc"], "user", ("act_ask",))
                if asks is None or not asks:
                    # --force ask: the questions stay in the body as they are, for the hand pass
                    bad = forced("ask:" + (why_ask if asks is None else "ask_not_first"))
                    if bad:
                        break
                    asks = []
                else:
                    body_lines = LA.edited_lines(f.lines, first, last, asks)
                    if any(LA.ASK_CALL.search(strip_code(l)) for l in body_lines):
                        bad = forced("ask:ask_later")
                        if bad:
                            break
            body = "\n".join(strip_code(l) for l in body_lines)
            # references elsewhere: the row, the definition and nothing else
            occ = mentions(a["proc"], t)
            if occ != 0:
                bad = "proc_shared"
                break
            body_no_user = re.sub(r"(?<![\w.])ui\.user\b", "user", body)  # ui.user is the viewer: the handler's `user`
            if re.search(r"(?<![\w.])open_request\(", body):
                bad = forced("body_uses:open_request")  # a question asked from an effect is an asks() step (dx_review request_in_effect): by hand
                if bad:
                    break
            # the window a handler touched (ui.close(), ui.send_asset(), its state) is the actor's open window of the holder: looked up
            uses_ui = bool(words_in(body_no_user, "ui")) or bool(words_in(body_no_user, "state"))
            declared = [s[1] for s in a["specs"]]
            body_c = "\n".join(strip_code(l, keep=True) for l in body_lines)
            for m2 in re.finditer(r"\bparams\b(\s*\[\s*\"([A-Za-z_][A-Za-z0-9_-]*)\"\s*\])?", body_c):
                if not m2.group(1) or m2.group(2) not in declared:
                    bad = forced("body_uses:params")
                    break
            if bad:
                break
            rename_a = None
            if words_in(body, "A") or re.search(r"\bvar/[\w/]*\bA\b", body):
                # a local named A: it takes another name (the handler's act is A)
                for cand in ("A2", "A3", "A4", "A5"):
                    if not words_in(body, cand) and not re.search(r"\b" + cand + r"\b", body_c):
                        rename_a = cand
                        break
                if not rename_a:
                    bad = "name_clash"
                    break
            local_names = {}
            for d in declared:
                # a declared name that is already a word of the body outside params["d"] (a host var, a local) is not the parameter's name: the handler
                # takes its arguments in order, so the parameter is called `<d>_arg` (the op's arg key stays `d`)
                stripped = re.sub(r"\bparams\s*\[\s*\"" + re.escape(d) + r"\"\s*\]", "", body_c)
                stripped = "\n".join(strip_code(x) for x in stripped.split("\n"))
                local_names[d] = d
                if words_in(stripped, d) or d in RESERVED or d == "src" or "-" in d:
                    local_names[d] = d.replace("-", "_") + "_arg"
                    if words_in(stripped, local_names[d]) or any(local_names[d] == o for o in declared):
                        bad = "name_clash"
                        break
            if bad:
                break
            for bl in body.split("\n"):
                t2 = bl.strip()
                rm = re.match(r"^return\b\s*(.*)$", t2)
                if rm and rm.group(1).strip() not in ("", "TRUE", "FALSE", "1", "0", "null"):
                    bad = forced("body_uses:return")
                    break
                if re.match(r"^\.\s*[^\w\s=]", t2) or re.match(r"^\.\s*=\s*(?!(?:TRUE|FALSE|1|0|null)\s*$)\S", t2) or re.search(r"\.\.\(", t2):
                    bad = forced("body_uses:dot")
                    break
            if bad:
                break
            plan["handlers"].append({"act": a, "rel": rel, "idx": i, "first": first, "last": last, "rename_a": rename_a, "local_names": local_names, "uses_ui": uses_ui, "uses_state": bool(words_in(body_no_user, "state")), "asks": asks, "body": body, "owner": job["owner"], "override": job["row"] is not None})
        if bad:
            return None, bad
        # ---- the questions of the handlers
        if asks_on:
            holder_vars = holder_vars_of(vars_by_type, t)
            for h in plan["handlers"]:
                h["ask_parts"] = []
                h["helpers"] = []
                for ask in h["asks"]:
                    text, helpers, why_ask = LA.build_ask(ask, holder_vars, "%s_%s" % (h["act"]["proc"], ask["key"]), t, "user", None)
                    if why_ask:
                        bad = why_ask
                        break
                    for hp in helpers:
                        hname = re.match(r"^/[\w/]+/proc/(\w+)\(", hp).group(1)
                        if hname in code_words:
                            bad = "name_clash"
                            break
                    if bad:
                        break
                    h["ask_parts"].append(text)
                    h["helpers"] += helpers
                if bad:
                    break
            if bad:
                return None, bad
        else:
            for h in plan["handlers"]:
                h["ask_parts"] = []
                h["helpers"] = []
        # ---- the data proc
        if data:
            helper_bad = False
            helpers = {}
            for kind, name, key in data["fields"]:
                if kind not in ("merge", "proc"):
                    continue
                dpat = re.compile(r"^" + tre + r"/(?:proc/)?" + re.escape(name) + r"\(([^)]*)\)\s*(//.*)?$")
                hit = None
                for rel, i in defs_idx.get((t, name), []):
                    dm = dpat.match(files[rel].lines[i])
                    if dm:
                        hit = (rel, i, dm.group(1))
                        break
                if not hit or mentions(name, t) != 0 or name in helpers:
                    helper_bad = True
                    break
                rel, i, params = hit
                ps = [p.strip() for p in params.split(",")]
                if len(ps) != 3:
                    helper_bad = True
                    break
                un = ps[0].split("/")[-1]
                uin, stn = ps[1].split("/")[-1], ps[2].split("/")[-1]
                f = files[rel]
                first, last = body_range(f.lines, i)
                body = "\n".join(strip_code(l) for l in f.lines[first : last + 1])
                if words_in(body, uin) or words_in(body, stn) or re.search(r"\.\.\(", body):
                    helper_bad = True
                    break
                helpers[name] = {"rel": rel, "idx": i, "first": first, "last": last, "user": un, "uses_user": bool(words_in(body, un)), "uses_a": bool(words_in(body, "A")), "speaks": bool(re.search(r"(?<![\w.])(to_chat|atom_say|playsound|play_sfx|balloon_alert)\(", body))}
            if helper_bad:
                return None, "data_rows"
            data["helpers"] = helpers
            # a lone merge proc becomes ui_data() itself, unless it speaks (an output says nothing: dx_review output_side_effect; it stays a
            # helper ui_data() calls, for a hand fix)
            data["rename"] = len(data["fields"]) == 1 and data["fields"][0][0] == "merge" and not any(h["speaks"] or h["uses_a"] for h in helpers.values())
        return plan, None

    # ---- families: the types related by path convert together, parents first (a subtype's buttons, data and state build on its parents')
    fam_types = sorted(u for u in rows if u != "/datum")  # the root /datum row (change_ui_state) is every window's: it stays legacy
    comp_of = {u: u for u in fam_types}

    def find(u):
        while comp_of[u] != u:
            comp_of[u] = comp_of[comp_of[u]]
            u = comp_of[u]
        return u

    for i, u in enumerate(fam_types):
        for v in fam_types[i + 1 :]:
            if v.startswith(u + "/"):
                comp_of[find(v)] = find(u)
    comps = defaultdict(list)
    for u in fam_types:
        comps[find(u)].append(u)
    for root, members in sorted(comps.items()):
        if only and only not in members:
            continue
        if exclude and any(r[1].startswith(tuple(exclude)) for u in members for r in rows[u]):
            continue
        members.sort(key=lambda u: (u.count("/"), u))
        fam = {"types": set(members), "window": {}, "acts": {}, "acts_of": {}, "gate": {}, "fp": {}, "data": {}, "state_down": {}, "root": members[0],
               # a guard anywhere in a family of several types: every handler of the family asks ui_gate(A) (the root has one, TRUE when it had no guard)
               "gated": len(members) > 1 and any(allowed_defs.get(u) for u in members)}
        got = []
        why = None
        for u in members:
            plan, why = plan_type(u, rows[u], fam)
            if not plan:
                why = why or "ui_forms"
                if len(members) > 1:
                    why = "%s%s" % (why, "" if u == members[0] else "@" + u[len(members[0]) :])
                break
            got.append(plan)
            if plan["window"]:
                fam["window"][u] = {"args": plan["interface_args"]}
            elif plan.get("redeclared"):
                fam["window"][u] = {"args": plan["redeclared"]}
            if plan.get("state_down"):
                fam["state_down"][u] = plan["state_down"]
            for a in plan["acts"]:
                fam["acts"][(u, a["proc"])] = a
            fam["acts_of"][u] = plan["acts"]
            fam["gate"][u] = bool(plan["pred"]) or plan["anc_gate"]
            fam["fp"][u] = bool(plan["fp"]) or plan["anc_fp"]
            fam["data"][u] = bool(plan["data"])
        if why:
            for u in members:
                residue[u] = why
            continue
        for plan in got:
            plans[plan["type"]] = plan
    # ---- apply
    converted_acts = 0
    for t, plan in sorted(plans.items()):
        converted_acts += len(plan["acts"])
        if check:
            continue
        if plan.get("state_into_block"):
            bi = block_interface(t)
            k, brel, bargs = bi
            bargs = [a for a in bargs if not re.match(r"^(state|rights)\s*=", a)] + [plan["state_into_block"]]
            indent = re.match(r"^[ \t]*", files[brel].lines[k]).group(0)
            cm = re.search(r"\)\s*(//.*)$", files[brel].lines[k])
            files[brel].lines[k] = indent + "interface(%s)" % ", ".join(bargs) + ((" " + cm.group(1)) if cm else "")
            files[brel].dirty = True
            r = plan["row"]
            files[r[1]].lines[r[2]] = None
            files[r[1]].dirty = True
            continue
        tre = re.escape(t)
        entries = []
        iargs = plan["interface_args"] or plan.get("redeclared")
        win = bool(iargs)
        if iargs:
            # its own window, or the inherited one declared again with this type's state or forward
            entries.append("interface(%s)" % ", ".join(iargs))
            if not t.startswith("/datum"):
                # The legacy window had no click of its own: the type opens it from its own interactions (tgui_interact()), with their
                # checks (access, power, the hand that holds it). interface()'s open op would add a click and a silicon's remote open
                # that skip them, so it goes; the conversion pins show the menus and clicks unchanged.
                entries.append('without("ui_open")')
        if plan.get("state_down"):
            # the state of a parent of windows: every window below it without a nearer legacy state row takes it
            for u in sorted(caps_idx):
                if not u.startswith(t + "/") or u in plans:
                    continue
                if any(v.startswith(t + "/") and (u == v or u.startswith(v + "/")) and any(r[0] == "DECLARE_UI_STATE" for r in rows[v]) for v in rows):
                    continue
                bi = block_interface(u)
                if not bi:
                    continue
                k, brel, bargs = bi
                bargs = [a for a in bargs if not re.match(r"^(state|rights)\s*=", a)] + [plan["state_down"][0]]
                indent = re.match(r"^[ \t]*", files[brel].lines[k]).group(0)
                cm = re.search(r"\)\s*(//.*)$", files[brel].lines[k])
                files[brel].lines[k] = indent + "interface(%s)" % ", ".join(bargs) + ((" " + cm.group(1)) if cm else "")
                files[brel].dirty = True
        d = plan["data"]
        if win and not plan["acts"] and d:
            # a window with no buttons of its own is typed from its data (ui_types needs a ui_shape() or a ui_act() op in the block)
            kinds = {"num": "num()", "bool": "bool()", "text": "schema_text()", "list": "list_of()"}
            shape = list(d["shape"])
            if not shape:
                # an untyped merge proc: the keys it writes
                for hp in d.get("helpers", {}).values():
                    for l in files[hp["rel"]].lines[hp["first"] : hp["last"] + 1]:
                        for km in re.finditer(r'\bdata\[\s*"(\w+)"\s*\]\s*(?:\+)?=', l or ""):
                            if km.group(1) not in [k for k, _ in shape]:
                                shape.append((km.group(1), "unknown"))
            entries.append("ui_shape(%s)" % ", ".join("%s = %s" % (k, kinds.get(ty, "any")) for k, ty in shape))
        for a in plan["acts"]:
            parts = ['"%s"' % a["action"]]
            for kind, name, bounds in a["specs"]:
                parts.append(arg_schema_text(kind, name, bounds))
            ui = 'ui_act(%s%s)' % (a.get("expr") or '"%s"' % a["action"], "".join(", " + p for p in parts[1:]))
            need = ""
            hh = sorted((h for h in plan["handlers"] if h["act"]["proc"] == a["proc"]), key=lambda h: h["override"])[0]
            asks_text = "".join(", " + x for x in hh["ask_parts"])
            entries.append('op(%s, %s%s%s, then(PROC_REF(%s)))' % ('"%s"' % a["key"] if a.get("key") else (a.get("expr") or '"%s"' % a["action"]), ui, need, asks_text, a["proc"]))
        # handlers
        for h in plan["handlers"]:
            a = h["act"]
            f = files[h["rel"]]
            declared = [s[1] for s in a["specs"]]
            # the questions' statements and guards go; what they returned is a local read from the answered step
            for ask in h["asks"]:
                for k in ask["remove"]:
                    f.lines[k] = None
                for k, txt in ask["rewrite"].items():
                    f.lines[k] = txt
            for k in range(h["first"], h["last"] + 1):
                l = f.lines[k]
                if l is None:
                    continue
                for d in declared:
                    l = re.sub(r"\bparams\s*\[\s*\"" + re.escape(d) + r"\"\s*\]", h["local_names"][d], l)
                l = re.sub(r"(?<![\w.])ui\.user\b", "user", l)
                if h.get("rename_a"):
                    l = rename_local_a(l, h["rename_a"])
                f.lines[k] = l
            body = "\n".join(strip_code(l or "") for l in f.lines[h["first"] : h["last"] + 1])
            sig = (h["owner"] + "/" if h["override"] else t + "/proc/") + a["proc"] + "(datum/act/op/A" + "".join(", " + h["local_names"][d] for d in declared) + ")"
            if h["helpers"]:
                sig = "\n\n".join(h["helpers"]) + "\n\n" + sig
            # insert `user` after the leading settings
            extra = ""
            heads = (["var/mob/user = A.actor"] if (words_in(body, "user") or h["uses_ui"]) else [])
            if h["uses_ui"]:
                heads.append("var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in")
            if h["uses_state"]:
                heads.append("var/datum/tgui_state/state = ui?.state()")
            heads += [] + (["var/action = A.window_action()"] if words_in(body, "action") else []) + (["if(!ui_gate(A))\n\treturn FALSE"] if (plan["pred"] or plan["fam_gated"]) else []) + (["add_fingerprint(A.actor)"] if (plan["fp"] or plan["anc_fp"]) else []) + [LA.answer_local(ask) for ask in h["asks"] if words_in(body, ask["name"])]
            for kind, name, bounds in a["specs"]:
                for g in arg_guards(kind, h["local_names"][name], bounds, body):
                    heads.append(g + "\n\treturn FALSE")
            if heads:
                after = h["idx"]
                k = h["first"]
                while k <= h["last"]:
                    s = strip_code(f.lines[k] or "").strip()
                    if s == "":
                        k += 1
                        continue
                    if s.startswith(SETTINGS) and (("(" not in s) or s.endswith(")")):
                        after = k
                        k += 1
                        continue
                    break
                indent = "\t"
                for k2 in range(h["first"], h["last"] + 1):
                    if f.lines[k2] and f.lines[k2].strip():
                        indent = re.match(r"^[ \t]*", f.lines[k2]).group(0)
                        break
                line = ("\n").join(indent + hl.replace("\n", "\n" + indent) for hl in heads)
                if after == h["idx"]:
                    extra = "\n" + line
                else:
                    f.lines[after] = f.lines[after] + "\n" + line
            f.lines[h["idx"]] = sig + extra
        # data proc
        d = plan["data"]
        if d and d["rename"] and not d["additive"]:
            # one merge proc and nothing else: the proc is the output (the SMES, afbbe2a3c8)
            h = d["helpers"][d["fields"][0][1]]
            f = files[h["rel"]]
            sig = t + "/ui_data(datum/act/eval/A)"
            extra = ""
            if h["uses_user"]:
                indent = "\t"
                for k2 in range(h["first"], h["last"] + 1):
                    if f.lines[k2].strip():
                        indent = re.match(r"^[ \t]*", f.lines[k2]).group(0)
                        break
                extra = "\n" + indent + "var/mob/%s = A.actor" % h["user"]
            f.lines[h["idx"]] = sig + extra
            f.dirty = True
        elif d:
            # fields and procs composed into one output, each helper kept as it is and called with the viewer
            out = [t + "/ui_data(datum/act/eval/A)", "\tvar/list/data = ..()" if d["additive"] else "\tvar/list/data = list()"]
            n = 0
            for kind, name, key in d["fields"]:
                if kind == "var":
                    out.append('\tdata["%s"] = %s' % (key, name))
                elif kind == "proc":
                    out.append('\tdata["%s"] = %s(A.actor, null, null)' % (key, name))
                else:
                    n += 1
                    out += ["\tvar/list/merged_%d = %s(A.actor, null, null)" % (n, name), "\tif(islist(merged_%d))" % n, "\t\tfor(var/merged_key_%d in merged_%d)" % (n, n), "\t\t\tdata[merged_key_%d] = merged_%d[merged_key_%d]" % (n, n, n)]
            out.append("\treturn data")
            # placed where the data row was
            drow = d["row"]
            files[drow[1]].lines[drow[2]] = "\n".join(out)
            files[drow[1]].dirty = True
        if plan["fp"]:
            _, frel, fi, ffirst, flast = plan["fp"]
            ff = files[frel]
            for k in range(fi, flast + 1):
                ff.lines[k] = None
            ff.dirty = True
        if plan["pred"]:
            _, frel, fi, ffirst, flast = plan["pred"]
            ff = files[frel]
            # the override becomes the requirement's proc: the head guard goes, `ui.user` is the actor, `user` is read from the act
            body_lines = ff.lines[ffirst : flast + 1]
            kept = []
            skipped = 0
            for bl in body_lines:
                st = strip_code(bl).strip()
                if skipped < 2 and st in ("if(!..())", "return FALSE") and not (plan["fam_gated"] and t != plan["fam_root"]):
                    skipped += 1
                    continue
                if st:
                    kept.append(bl)
            text = "\n".join(kept)
            uses_user = bool(words_in("\n".join(strip_code(l) for l in kept), "user")) or "ui.user" in text
            text = text.replace("ui.user", "user")
            uses_action = bool(words_in("\n".join(strip_code(l) for l in kept), "action"))
            # check_rights() reads usr; the requirement asks the actor's client (admin_can(), READS_FROM())
            text = re.sub(r"(?<![\w.])check_rights\(\s*([^,()]+(?:\([^()]*\))?[^,()]*?)\s*(?:,\s*(?:0|FALSE|1|TRUE))?\s*\)", r"admin_can(A.actor?.client, \1)", text)
            indent = re.match(r"^[ \t]*", kept[0]).group(0) if kept else "\t"
            head = t + ("/ui_gate(datum/act/op/A)" if (plan["fam_gated"] and t != plan["fam_root"]) else "/proc/ui_gate(datum/act/op/A)")
            if uses_user:
                head += "\n" + indent + "var/mob/user = A.actor"
            if uses_action:
                head += "\n" + indent + "var/action = A.window_action()"
            ff.lines[fi] = head
            for k in range(ffirst, flast + 1):
                ff.lines[k] = None
            ff.lines[ffirst] = text
            ff.dirty = True
        if plan["forward"]:
            frel, fi = plan["forward"]["def"]
            for k in range(fi, plan["forward"]["last"] + 1):
                files[frel].lines[k] = None
            files[frel].dirty = True
            # the doc comment of the row goes with it
            rrel, ridx = plan["forward"]["row"]
            k = ridx - 1
            while k >= 0 and files[rrel].lines[k] is not None and files[rrel].lines[k].startswith("///"):
                files[rrel].lines[k] = None
                k -= 1
            files[rrel].dirty = True
        # delete the legacy rows; the declaration line becomes the block (or goes, when the type already has one)
        block_file = caps_idx.get(t)
        base = ""
        if plan["fam_gated"] and t == plan["fam_root"] and not plan["pred"]:
            base = "\n\n/// The guard every window button of the family asks first (a subtype overrides it).\n%s/proc/ui_gate(datum/act/op/A)\n\treturn TRUE" % t
            if not entries:
                return_base_needs_block = True
        placed = False
        first_gone = None
        for kind, rel, idx, text in sorted(plan["rows"], key=lambda r: (r[1], r[2])):
            f = files[rel]
            if kind == "DECLARE_UI_STATE" and plan.get("state_proc") and plan["state_proc"][1][1] == rel and plan["state_proc"][1][2] == idx:
                sexpr = plan["state_proc"][0]
                sexpr = ("GLOB." + sexpr[len("state = nameof(GLOB."):-1]) if sexpr.startswith("state = ") else "ADMIN_STATE(%s)" % sexpr[len("rights = "):]
                f.lines[idx] = "%s/tgui_state(mob/user)\n\treturn %s" % (t, sexpr)
                placed = True
                continue
            if kind == "DECLARE_UI_STATE" and plan["state"] and plan["state"][1] and plan["state"][1][1] == rel and plan["state"][1][2] == idx:
                f.lines[idx] = None  # carried by interface(): state = / rights =
                if first_gone is None:
                    first_gone = (rel, idx)
                continue
            if kind in ("UI_ACT_PROC", "UI_ACT_OVERRIDE", "DECLARE_UI_STATE"):
                continue  # a state that is not a GLOB state or an ADMIN_STATE stays: it is its own legacy form, read by ui_open() whether or not a DECLARE_UI stands beside it
            if kind in ("UI_DATA", "UI_DATA_REPLACE") and d and not (d["rename"] and not d["additive"]):
                continue  # the composed ui_data() stands where the row was
            if kind == "DECLARE_UI":
                if block_file or not entries:
                    f.lines[idx] = None
                else:
                    f.lines[idx] = "CAPABILITIES(%s)" % t + "".join("\n\t" + e for e in entries) + base
                    placed = True
            else:
                f.lines[idx] = None
                if first_gone is None:
                    first_gone = (rel, idx)
        if not block_file and not placed and entries:
            # no declaration row of its own: the block stands where its first removed row was (or before its first row)
            block = "CAPABILITIES(%s)" % t + "".join("\n\t" + e for e in entries) + base
            if first_gone:
                files[first_gone[0]].lines[first_gone[1]] = block
            else:
                r0 = [r for r in sorted(plan["rows"], key=lambda r: (r[1], r[2])) if files[r[1]].lines[r[2]] is not None][0]
                files[r0[1]].lines[r0[2]] = block + "\n\n" + files[r0[1]].lines[r0[2]]
        if block_file and entries:
            rel, i = block_file
            f = files[rel]
            first, last = body_range(f.lines, i)
            f.lines[last] = f.lines[last] + "".join("\n\t" + e for e in entries) + base
        for rel in {r[1] for r in plan["rows"]} | {h["rel"] for h in plan["handlers"]} | ({hp["rel"] for hp in d["helpers"].values()} if d else set()) | ({block_file[0]} if block_file else set()):
            files[rel].dirty = True
    if not check:
        for f in files.values():
            if f.dirty:
                f.save()
    if "--why" in sys.argv:
        for t, why in sorted(residue.items()):
            print("WHY	%s	%s	%s" % (why, t, ",".join(sorted({r[0] for r in rows[t]}))))
    by = defaultdict(list)
    for t, why in residue.items():
        by[why].append(t)
    print("ui_declare: %d types converted (%d ui_act ops)%s; residue %d types" % (len(plans), converted_acts, " (check)" if check else "", len(residue)))
    for why, ts in sorted(by.items(), key=lambda kv: -len(kv[1])):
        print("    %-14s %4d" % (why, len(ts)))
        if sites:
            for t in sorted(ts):
                print("        " + t)
    return 1 if (check and plans) else 0


if __name__ == "__main__":
    sys.exit(main())
