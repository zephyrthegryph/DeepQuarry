"""look_sweep.py convert: legacy appearance declarations -> draw(look) (doc/rewrite/codemod_rules.md, "The draw sweep").

A component is a set of drawing types joined by ancestry (a type with APPEARANCE_TEMPLATE, DECLARE_APPEARANCE, APPEARANCE_NONE,
DECLARE_APPEARANCE_PROC or an update_icon() override, and every such type above or below it). A component converts whole or not
at all, so no chain mixes a legacy declaration with a draw(). Per type, in the legacy order of application:

    /T/draw(datum/look/look)
        ..()                                    the parent's draw and the capabilities' layers
        look.state("<template as a DM string>") APPEARANCE_TEMPLATE: {x} is [x] (or [x()] for a proc), {x?A:B} is [x ? "A" : "B"]
        switch("[v]")                           DECLARE_APPEARANCE(T, "v", rows): one if("key") per row, else for the "*" row
            if("1")
                look.overlay("state")
        <the provider body>                     DECLARE_APPEARANCE_PROC: . += x is look.overlay(x), icon_state = x is look.state(x),
                                                color/alpha/... look.set_*(), set_light() look.light() / look.light_off(),
                                                flick(x, src) look.play_flick(x); a body that reads its own icon_state keeps it in
                                                a local (var/drawn_state = look.state_so_far(src); drawn_state = look.state(x))

The draw replaces the provider proc where there is one, else it takes the place of the type's first declaration line. A type that
already has a draw() gets the generated lines after its ..() (residue `own_draw_late` when its ..() is not the first statement).

What a component's draws read decides what happens to the update_icon() calls on its types (receivers inside the component's chain):
covered (every var read is TRACKED, SETTER, an OM field, a relation, density/opacity/anchored, and no proc is called) -> the calls
go; uncovered -> each becomes changed(src) (changed(X) for X.update_icon()), so the redraw still happens where it did. Calls in
Initialize() always go: the first refresh draws every atom after its init. Calls whose receiver is above the component (a proc of
an ancestor that still serves unconverted types) stay; for an uncovered component a changed(src) is added beside them.

Residue (the component stays as it is), by code: level / emissive / slot (APPEARANCE_LEVEL, _EMISSIVE, _SLOT: by hand),
none (APPEARANCE_NONE below a type that draws), override (an update_icon() override), layer_override (a subtype layers a var an
ancestor layers), order (a keyed state below a provider or layer that sets the state: the legacy order differs), template_parse,
rows_parse, provider codes (super_late, replaces_parent, dot_use, returns_value, reads_layers, writes_state:<var>,
side_effect:<proc>, look_var_read:<var>, multi_def, name_clash), held_icon (update_held_icon() in a provider).
"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import collections
import json
import os
import re

from dmlib import File, split_args, strip_code  # noqa: F401

DECL_KINDS = ("APPEARANCE_TEMPLATE", "APPEARANCE_LEVEL", "APPEARANCE_EMISSIVE", "APPEARANCE_SLOT", "APPEARANCE_NONE", "DECLARE_APPEARANCE_PROC", "DECLARE_APPEARANCE")
DECL_START = re.compile(r"^(" + "|".join(DECL_KINDS) + r")\((/[\w/]+)")
NO_EDIT = ("code/modules/unit_tests/", "code/tests/", "code/engine/", "code/__defines/", "code/_generated/", "code/modules/benchmarks/")
LOOK_SETTERS = {"color": "set_color", "alpha": "set_alpha", "layer": "set_layer", "plane": "set_plane", "dir": "set_dir", "icon": "set_icon", "transform": "set_transform"}
COVERED_BUILTINS = {"density", "opacity", "anchored"}
KEYWORDS = {
    "if", "else", "for", "while", "do", "switch", "return", "var", "in", "to", "step", "as", "new", "del", "null", "src", "usr", "TRUE", "FALSE",
    "list", "world", "GLOB", "look", "break", "continue", "set", "global", "proc", "verb", "tmp", "static", "const", "drawn_state", "INFINITY",
}
ATOM_BUILTINS = {
    "name", "desc", "icon", "icon_state", "color", "alpha", "layer", "plane", "dir", "density", "opacity", "anchored", "invisibility", "pixel_x",
    "pixel_y", "pixel_w", "pixel_z", "overlays", "underlays", "loc", "x", "y", "z", "contents", "mouse_opacity", "blend_mode", "appearance",
    "transform", "luminosity", "verbs", "vis_contents", "maptext", "type", "parent_type", "tag", "vars", "gender", "suffix", "text",
}


class Residue(Exception):
    pass


# id(locals set of a provider body) -> the locals that body builds itself (provider_lines() fills it for translate_stmt())
BUILT_LOCALS = {}


def code_and_comment(raw):
    code = strip_code(raw)
    kept = raw[: len(code.rstrip())]
    return kept, raw[len(kept):]


def ancestors(t, po):
    out, seen = [], set()
    while t and t not in seen:
        seen.add(t)
        out.append(t)
        if t in po:
            t = po[t]
        elif t.count("/") > 1:
            t = t.rsplit("/", 1)[0]
        else:
            t = None
    return out


class Index:
    def __init__(self, root, rels):
        self.files = {}
        self.decls = collections.defaultdict(list)  # T -> [(kind, rel, first, last, text)]
        self.providers = collections.defaultdict(list)  # T -> [(rel, start, end)]
        self.draws = collections.defaultdict(list)
        self.ui_overrides = collections.defaultdict(list)
        self.vars = collections.defaultdict(set)  # T -> var names declared there
        self.procs = collections.defaultdict(set)  # T -> proc names defined there
        self.proc_defs = collections.defaultdict(list)  # (T, name) -> [(rel, start, end)]
        self.tracked = collections.defaultdict(set)  # T -> vars tracked from T down
        self.writes = collections.defaultdict(set)  # T -> vars its procs write (bare, src. or through set_<var>())
        self.po = {}
        for rel in rels:
            f = File(rel)
            self.files[rel] = f
            self.scan(rel, f)

    def scan(self, rel, f):
        L = f.lines
        n = len(L)
        block = None
        cap = None
        i = 0
        while i < n:
            line = L[i]
            if line and line[0] not in " \t":
                block = None
                cap = None
                m = DECL_START.match(line)
                if m:
                    first = i
                    text = strip_code(line)
                    depth = text.count("(") - text.count(")")
                    cont = text.rstrip().endswith("\\")
                    j = i
                    while (depth > 0 or cont) and j + 1 < n:
                        j += 1
                        t2 = strip_code(L[j])
                        text += "\n" + t2
                        depth += t2.count("(") - t2.count(")")
                        cont = t2.rstrip().endswith("\\")
                    raw = "\n".join(L[first : j + 1])
                    self.decls[m.group(2)].append((m.group(1), rel, first, j, raw))
                    i = j + 1
                    continue
                mt = re.match(r"^(TRACKED|TRACKED_BRIDGED|TRACKED_SCHEMA|SETTER)\((/[\w/]+),\s*(\w+)", line)
                if mt:
                    self.tracked[mt.group(2)].add(mt.group(3))
                mo = re.match(r"^OM_(?:FLAG_)?FIELD\((/[\w/]+),\s*(\w+)", line)
                if mo:
                    self.tracked[mo.group(1)].add(mo.group(2))
                    self.vars[mo.group(1)].add(mo.group(2))
                mo = re.match(r"^OM_FIELD_TYPED\((/[\w/]+),\s*[^,]+,\s*(\w+)", line)
                if mo:
                    self.tracked[mo.group(1)].add(mo.group(2))
                    self.vars[mo.group(1)].add(mo.group(2))
                mc = re.match(r"^CAPABILITIES\((/[\w/]+)\)", line)
                if mc:
                    cap = mc.group(1)
                hm = re.match(r"^(/[\w/]+?)/(?:proc/|verb/)?(\w+)\(", line)
                if hm and "=" not in strip_code(line).split("(")[0]:
                    t, name = hm.group(1), hm.group(2)
                    j = i + 1
                    while j < n and (L[j].strip() == "" or L[j][0] in " \t"):
                        j += 1
                    end = j
                    while end > i + 1 and L[end - 1].strip() == "":
                        end -= 1
                    self.procs[t].add(name)
                    self.proc_defs[(t, name)].append((rel, i, end))
                    if name in ("ownership", "relations"):
                        for k in range(i + 1, end):
                            for rm in re.finditer(r"\b(?:owns|owns_one|owns_many|refs|rel_one|rel_many|ref_one|ref_many|link\w*)\(\s*nameof\((\w+)\)", strip_code(L[k])):
                                self.tracked[t].add(rm.group(1))
                    for k in range(i + 1, end):
                        code = strip_code(L[k])
                        for wm in re.finditer(r"(?<![\w.])(?:src\.)?([a-z_]\w*)\s*(?:=(?!=)|\+=|-=|\|=|&=|\+\+|--)", code):
                            self.writes[t].add(wm.group(1))
                        for wm in re.finditer(r"(?<![\w.])(?:src\.)?set_(\w+)\(", code):
                            self.writes[t].add(wm.group(1))
                        # a list changed in place: LAZYSET(x, ...), x[k] = v, x.Cut(), x.Add()...
                        for wm in re.finditer(r"\b(?:LAZY\w+|UNTYPED_LIST_\w+|listclearnulls)\(\s*(?:src\.)?([a-z_]\w*)\b", code):
                            self.writes[t].add(wm.group(1))
                        for wm in re.finditer(r"(?<![\w.])(?:src\.)?([a-z_]\w*)\[[^\]]*\]\s*(?:=(?!=)|\+=|-=|\|=)", code):
                            self.writes[t].add(wm.group(1))
                        for wm in re.finditer(r"(?<![\w.])(?:src\.)?([a-z_]\w*)\.(?:Cut|Add|Remove|Insert|Swap|Splice|Copy)\(", code):
                            if not wm.group(0).endswith("Copy("):
                                self.writes[t].add(wm.group(1))
                    if name == "appearance_overlays":
                        self.providers[t].append((rel, i, end))
                    elif name == "draw":
                        self.draws[t].append((rel, i, end))
                    elif name == "update_icon":
                        self.ui_overrides[t].append((rel, i, end))
                    i = j
                    continue
                vm = re.match(r"^(/[\w/]+)/var/(?:(?:tmp|static|global|const|final)/)*(?:[\w/]+/)?(\w+)\s*(=.*)?$", strip_code(line).rstrip())
                if vm:
                    self.vars[vm.group(1)].add(vm.group(2))
                    i += 1
                    continue
                bm = re.match(r"^(/[\w/]+)\s*$", strip_code(line).rstrip())
                if bm:
                    block = bm.group(1)
                i += 1
                continue
            if block and line.strip():
                code = strip_code(line)
                vm = re.match(r"^\t(?:var/)(?:(?:tmp|static|global|const|final)/)*(?:[\w/]+/)?(\w+)\s*(=|$)", code)
                if vm:
                    self.vars[block].add(vm.group(1))
                pm = re.match(r"^\s+parent_type\s*=\s*(/[\w/]+)", code)
                if pm:
                    self.po[block] = pm.group(1)
                pr = re.match(r"^\t(?:proc/|verb/)?(\w+)\(", code)
                if pr and not code.startswith("\tvar/"):
                    self.procs[block].add(pr.group(1))
            if cap and line.strip():
                rm = re.match(r"^\s+(?:owns_one|ref_one|owns_many|ref_many|slot|derives)\(\s*nameof\((\w+)\)", strip_code(line))
                if rm:
                    self.tracked[cap].add(rm.group(1))
            i += 1

    def chain(self, t):
        return ancestors(t, self.po)

    def is_var(self, t, name):
        return name in ATOM_BUILTINS or any(name in self.vars.get(a, ()) for a in self.chain(t))

    def is_proc(self, t, name):
        return any(name in self.procs.get(a, ()) for a in self.chain(t))

    def tracked_on(self, t, name):
        return name in COVERED_BUILTINS or any(name in self.tracked.get(a, ()) for a in self.chain(t))

    def related(self, a, b):
        return a in self.chain(b) or b in self.chain(a)


# ---------------------------------------------------------------- template and rows

def dm_text(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("[", "\\[")


def template_expr(ix, t, tmpl):
    """The DM string expression of a template, or Residue."""
    out = []
    pos = 0
    while pos < len(tmpl):
        o = tmpl.find("{", pos)
        if o < 0:
            out.append(dm_text(tmpl[pos:]))
            break
        out.append(dm_text(tmpl[pos:o]))
        c = tmpl.find("}", o + 1)
        if c < 0:
            raise Residue("template_parse")
        tok = tmpl[o + 1 : c].strip()
        pos = c + 1
        m = re.match(r"^initial\((\w+)\)$", tok)
        if m:
            out.append("[initial(%s)]" % m.group(1))
            continue
        if "?" in tok:
            name, rest = tok.split("?", 1)
            if ":" not in rest:
                raise Residue("template_parse")
            a, b = rest.split(":", 1)
            out.append("[%s ? %s : %s]" % (read_name(ix, t, name.strip()), branch(ix, t, a), branch(ix, t, b)))
            continue
        out.append("[%s]" % read_name(ix, t, tok))
    return '"' + "".join(out) + '"'


def read_name(ix, t, name):
    if not re.match(r"^\w+$", name):
        raise Residue("template_parse")
    if ix.is_var(t, name):
        return name
    if ix.is_proc(t, name):
        return name + "()"
    raise Residue("template_name:" + name)


def branch(ix, t, text):
    if text.startswith("@"):
        return read_name(ix, t, text[1:])
    return '"%s"' % dm_text(text)


def macro_args(raw):
    """The top-level arguments of a macro call spanning lines (continuations joined, comments dropped)."""
    joined = " ".join(code_and_comment(x)[0].rstrip().rstrip("\\") for x in raw.split("\n"))
    o = joined.find("(")
    depth, j = 0, o
    while j < len(joined):
        if joined[j] == "(":
            depth += 1
        elif joined[j] == ")":
            depth -= 1
            if depth == 0:
                break
        j += 1
    return [a.strip() for a in split_args(joined[o + 1 : j])]


def parse_rows(text):
    """list("k" = list(APPEARANCE_ICON_STATE = "x", APPEARANCE_OVERLAYS = list(...), ...), APPEARANCE_ANY = ...) -> [(key, {field: value})]."""
    m = re.match(r"^list\((.*)\)$", text.strip(), re.S)
    if not m:
        raise Residue("rows_parse")
    rows = []
    for item in split_args(m.group(1)):
        item = item.strip()
        if not item:
            continue
        km = re.match(r'^("(?:[^"\\]|\\.)*"|APPEARANCE_ANY|\w+)\s*=\s*(list\(.*\))$', item, re.S)
        if not km:
            raise Residue("rows_parse")
        key = km.group(1)
        fields = {}
        fm = re.match(r"^list\((.*)\)$", km.group(2), re.S)
        for f in split_args(fm.group(1)):
            f = f.strip()
            if not f:
                continue
            m2 = re.match(r"^(APPEARANCE_ICON_STATE|APPEARANCE_OVERLAYS|APPEARANCE_COLOR|APPEARANCE_ICON)\s*=\s*(.*)$", f, re.S)
            if not m2:
                raise Residue("rows_parse")
            fields[m2.group(1)] = m2.group(2).strip()
        rows.append((key, fields))
    return rows


def row_lines(fields, ind):
    out = []
    if "APPEARANCE_ICON" in fields:
        out.append(ind + "look.set_icon(%s)" % fields["APPEARANCE_ICON"])
    if "APPEARANCE_ICON_STATE" in fields:
        out.append(ind + "look.state(%s)" % fields["APPEARANCE_ICON_STATE"])
    if "APPEARANCE_COLOR" in fields:
        out.append(ind + "look.set_color(%s)" % fields["APPEARANCE_COLOR"])
    if "APPEARANCE_OVERLAYS" in fields:
        m = re.match(r"^list\((.*)\)$", fields["APPEARANCE_OVERLAYS"], re.S)
        if not m:
            raise Residue("rows_parse")
        for o in split_args(m.group(1)):
            if o.strip():
                out.append(ind + "look.overlay(%s)" % o.strip())
    return out


def layer_lines(ix, t, var_arg, rows_text):
    rows = parse_rows(rows_text)
    if var_arg == "null":
        any_rows = [f for k, f in rows if k == "APPEARANCE_ANY"]
        out = []
        for f in any_rows:
            out += row_lines(f, "\t")
        return out
    vm = re.match(r'^"(\w+)"$', var_arg)
    if not vm:
        raise Residue("rows_parse")
    expr = read_name(ix, t, vm.group(1))
    keyed = [(k, f) for k, f in rows if k != "APPEARANCE_ANY"]
    fallback = [f for k, f in rows if k == "APPEARANCE_ANY"]
    if not keyed and not fallback:
        return []
    if len(keyed) == 1 and not fallback and re.match(r'^"\d+"$', keyed[0][0]):
        k, f = keyed[0]
        return ["\tif(%s == %s)" % (expr, k.strip('"'))] + (row_lines(f, "\t\t") or ["\t\t// the row draws nothing"])
    out = ["\tswitch(\"[%s]\")" % expr]
    for k, f in keyed:
        body = row_lines(f, "\t\t\t")
        out.append("\t\tif(%s)" % k)
        out += body or ["\t\t\t// the row draws nothing"]
    if fallback:
        out.append("\t\telse")
        out += row_lines(fallback[0], "\t\t\t") or ["\t\t\t// the row draws nothing"]
    return out


# ---------------------------------------------------------------- provider bodies

def replace_word(raw, word, repl, skip_member=True):
    """Replaces the identifier `word` in the code of raw (not in strings, comments, initial(word) or X.word)."""
    code = strip_code(raw)
    out = []
    last = 0
    for m in re.finditer(r"(?<![\w.])" + re.escape(word) + r"(?!\w)", code):
        before = code[: m.start()].rstrip()
        if before.endswith("initial(") or named_arg(code, m):
            continue
        out.append(raw[last : m.start()])
        out.append(repl)
        last = m.end()
    out.append(raw[last:])
    return "".join(out)


def named_arg(code, m):
    """TRUE when the match is a named argument of a call (`image(icon, icon_state = "x")`): inside parentheses, then `=`."""
    if not re.match(r"^\s*=(?!=)", code[m.end():]):
        return False
    depth = 0
    for ch in code[: m.start()]:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
    return depth > 0


def has_word(code, word):
    for m in re.finditer(r"(?<![\w.])" + re.escape(word) + r"(?!\w)", code):
        if not code[: m.start()].rstrip().endswith("initial(") and not named_arg(code, m):
            return True
    return False


def provider_lines(ix, t, rel, start, end, has_parent_provider):
    """The translated body of /t/appearance_overlays() (lines without the header, the leading ..() left out), or Residue."""
    f = ix.files[rel]
    raw = f.lines[start + 1 : end]
    codes = [strip_code(x) for x in raw]
    text = "\n".join(codes)
    if has_word(text, "look") or has_word(text, "drawn_state"):
        raise Residue("name_clash")
    if re.search(r"(?<![\w.])(overlays|underlays)(?!\w)", text):
        raise Residue("reads_layers")
    locals_ = set(re.findall(r"\bvar/(?:[\w/]+/)?(\w+)", text))
    # the locals the body builds itself (an image, a matrix, a list): a call on one changes nothing outside the draw
    BUILT_LOCALS[id(locals_)] = set(re.findall(r"\bvar/(?:[\w/]+/)?(\w+)\s*=\s*(?:image|mutable_appearance|matrix|icon|list|new)\b", text))
    # the state local: the body reads its own icon_state (anything but a plain write)
    state_reads = False
    for c in codes:
        s = c.strip()
        body_expr = re.sub(r"^icon_state\s*=(?!=)", "", s)
        if has_word(body_expr, "icon_state"):
            state_reads = True
    for v in LOOK_SETTERS:
        for c in codes:
            s = c.strip()
            body_expr = re.sub(r"^" + v + r"\s*=(?!=)", "", s)
            body_expr = re.sub(r"(?<![\w.])(if|else if)\s*\(.*?\)\s*" + v + r"\s*=(?!=)", "", body_expr)
            if v in ("icon", "dir", "layer", "color", "alpha") and has_word(body_expr, v):
                # a read of a look var: icon/dir/layer are often read for images (image(icon, ...)), which is fine when nothing writes them
                if any(re.match(r"^(?:(?:if|else if)\s*\(.*\)\s*)?(?:src\.)?" + v + r"\s*=(?!=)", x.strip()) for x in codes):
                    raise Residue("look_var_read:" + v)
    out = []
    saw_super = False
    seen_code = False
    for k, line in enumerate(raw):
        code = codes[k]
        if not code.strip():
            out.append(line)
            continue
        kept, comment = code_and_comment(line)
        ind = re.match(r"^[ \t]*", line).group(0)
        stmt = kept.strip()
        scode = code.strip()
        if scode == ". = list()" and not seen_code:
            continue
        if scode in ("..()", ". = ..()", ". += ..()"):
            if saw_super or seen_code:
                raise Residue("super_late")
            saw_super = True
            continue
        if re.search(r"(?<![\w.])\.\.\(", scode):
            raise Residue("super_late")
        seen_code = True
        # a control prefix with an inline tail: if(c) x / else x / else if(c) x
        prefix, tail_raw = split_control(stmt)
        if prefix is not None and tail_raw:
            prefix_t = fix_expr(prefix, state_reads)
            tail = translate_stmt(ix, t, tail_raw, locals_, state_reads)
            out.append(ind + prefix_t + " " + tail + comment)
            continue
        if prefix is not None:
            out.append(ind + fix_expr(stmt, state_reads) + comment)
            continue
        out.append(ind + translate_stmt(ix, t, stmt, locals_, state_reads) + comment)
    if has_parent_provider and not saw_super:
        raise Residue("replaces_parent")
    # trailing blank lines, and a bare return that ends the body, go
    while out and (not out[-1].strip() or (strip_code(out[-1]).strip() == "return" and re.match(r"^\t\S", out[-1]))):
        out.pop()
    if state_reads:
        ind = next((re.match(r"^[ \t]*", x).group(0) for x in out if x.strip()), "\t")
        out.insert(0, ind + "var/drawn_state = look.state_so_far(src)")
    return out


CONTROL_HEAD = re.compile(r"^(if|else if|while|for|switch)\s*\(")


def split_control(stmt):
    """(control prefix, inline tail) of a control statement; (None, None) for a plain statement."""
    if stmt == "else" or stmt.startswith("else ") and not stmt.startswith("else if"):
        if stmt == "else":
            return "else", ""
        return "else", stmt[5:].strip()
    if re.match(r"^(do)$", stmt):
        return stmt, ""
    m = CONTROL_HEAD.match(stmt)
    if not m:
        if re.match(r"^(var/|//)", stmt):
            return None, None
        return None, None
    depth = 0
    code = strip_code(stmt)
    k = m.end() - 1
    while k < len(code):
        if code[k] == "(":
            depth += 1
        elif code[k] == ")":
            depth -= 1
            if depth == 0:
                break
        k += 1
    return stmt[: k + 1], stmt[k + 1 :].strip()


def fix_expr(expr, state_reads):
    code = strip_code(expr)
    if re.search(r"(?<![\w.])\.(?![\w.])", code.replace("..", "")):
        raise Residue("dot_use")
    if state_reads:
        expr = replace_word(expr, "icon_state", "drawn_state")
    return expr


def translate_stmt(ix, t, stmt, locals_, state_reads):
    code = strip_code(stmt).strip()
    if code in ("return", "return ."):
        return "return"
    if code.startswith("return"):
        raise Residue("returns_value")
    m = re.match(r"^\.\s*(\+|\|)=\s*(.*)$", code)
    if m:
        expr = stmt[stmt.index("=") + 1 :].strip()
        return "look.overlay(%s)" % fix_expr(expr, state_reads)
    if re.match(r"^\.\s*[-&]?=", code) or code == ".":
        raise Residue("dot_use")
    if code.startswith("var/"):
        return fix_expr(stmt, state_reads)
    am = re.match(r"^(?:src\.)?([A-Za-z_][\w]*(?:\s*\??\.\s*[A-Za-z_]\w*)*)\s*(=(?!=)|\+=|-=|\|=|&=|\*=|/=)\s*(.*)$", code)
    if am:
        lhs = am.group(1).replace(" ", "")
        op = am.group(2)
        rhs = stmt[len(stmt) - len(am.group(3)) :] if am.group(3) else ""
        rhs = stmt.split(op, 1)[1].strip()
        root = lhs.split(".")[0].rstrip("?")
        if lhs == "icon_state" and op == "=":
            if state_reads:
                return "drawn_state = look.state(%s)" % fix_expr(rhs, True)
            return "look.state(%s)" % fix_expr(rhs, False)
        if lhs in LOOK_SETTERS and op == "=":
            return "look.%s(%s)" % (LOOK_SETTERS[lhs], fix_expr(rhs, state_reads))
        if lhs == "item_state" and op == "=":
            return "look.held_state(%s)" % fix_expr(rhs, state_reads)
        if lhs in ("name", "desc") and op == "=":
            return "look.identity(%s = %s)" % (lhs, fix_expr(rhs, state_reads))
        if root in locals_:
            return fix_expr(stmt, state_reads)
        raise Residue("writes_state:" + lhs)
    im = re.match(r"^([A-Za-z_]\w*)\s*(\+\+|--)$", code) or re.match(r"^(\+\+|--)\s*([A-Za-z_]\w*)$", code)
    if im:
        name = im.group(1) if im.group(1) not in ("++", "--") else im.group(2)
        if name in locals_:
            return stmt
        raise Residue("writes_state:" + name)
    if code in ("break", "continue"):
        return stmt
    # a call on a local (a matrix being turned, an image being built) changes nothing of the holder
    lm = re.match(r"^([A-Za-z_]\w*)\s*\??\.\s*[A-Za-z_]\w*\s*\(.*\)$", code)
    if lm and lm.group(1) in BUILT_LOCALS.get(id(locals_), ()):
        return fix_expr(stmt, state_reads)
    # a shared appearance cache filled on a miss (GLOB.x_cache[key] = built) is a memo, not state
    if re.match(r"^GLOB\.\w*cache\w*\[[^\]]*\]\s*=(?!=)", code):
        return fix_expr(stmt, state_reads)
    cm = re.match(r"^([A-Za-z_][\w]*)\s*\((.*)\)$", code)
    if cm:
        name = cm.group(1)
        args_raw = stmt[stmt.index("(") + 1 : stmt.rindex(")")]
        if name == "set_light":
            args = [a.strip() for a in split_args(args_raw)]
            if len(args) == 1 and args[0] in ("0", "FALSE"):
                return "look.light_off()"
            if len(args) == 1:
                args.append("light_power")
            return "look.light(%s)" % ", ".join(fix_expr(a, state_reads) for a in args[:3])
        if name == "update_held_icon" and not args_raw.strip():
            return "// the hands that hold it redraw when the look changes its sprite (look.apply_to())"
        if name == "flick":
            args = [a.strip() for a in split_args(args_raw)]
            if len(args) == 2 and args[1] == "src":
                return "look.play_flick(%s)" % fix_expr(args[0], state_reads)
        raise Residue("side_effect:" + name)
    raise Residue("side_effect:" + code.split("(")[0][:30])


# ---------------------------------------------------------------- reads

def body_reads(ix, t, lines):
    """(vars of t's chain the lines read, procs of t's chain they call, member hops) for the tracking verdict."""
    text = "\n".join(strip_code(x) for x in lines)
    locals_ = set(re.findall(r"\bvar/(?:[\w/]+/)?(\w+)", text))
    reads, calls, hops = set(), set(), set()
    for m in re.finditer(r"(?<![\w./\"'])([A-Za-z_]\w*)", text):
        name = m.group(1)
        if name in KEYWORDS or name in locals_:
            continue
        before = text[: m.start()]
        if re.search(r"\binitial\(\s*$", before):
            continue
        rest = text[m.end() :]
        if rest.lstrip().startswith("("):
            if ix.is_proc(t, name) and not before.rstrip().endswith("."):
                calls.add(name)
            continue
        if before.rstrip().endswith(".") or name.isupper() or re.match(r"^[A-Z]", name):
            continue  # a member of something else (counted at its root), a define or a constant
        if re.match(r"^\s*=(?!=)", rest) and re.search(r"(^|\n)\s*$", before):
            continue
        if re.match(r"^\s*\??\.\s*[A-Za-z_]", rest):
            hops.add(name)  # a read through another object: whatever it is, it is not this holder's tracked state
            continue
        if re.match(r"^\s*(\(|=)", rest) and named_arg(text, m):
            continue
        reads.add(name)
    return reads, calls, hops


def proc_reads(ix, t, name, depth, seen):
    """Vars read (transitively, a few calls deep) by src.name() on t; None when it reaches a proc it cannot see or a hop."""
    if (t, name) in seen:
        return set()
    seen.add((t, name))
    defs = []
    for a in ix.chain(t):
        defs += ix.proc_defs.get((a, name), [])
    if not defs or depth > 3:
        return None
    reads = set()
    for rel, s, e in defs:
        lines = ix.files[rel].lines[s + 1 : e]
        r, c, h = body_reads(ix, t, lines)
        if h:
            return None
        reads |= r
        for cn in c:
            sub = proc_reads(ix, t, cn, depth + 1, seen)
            if sub is None:
                return None
            reads |= sub
    return reads


# ---------------------------------------------------------------- the driver

def components(ix):
    drawing = set(ix.decls) | set(ix.providers) | set(ix.ui_overrides)
    drawing = {t for t in drawing if t.startswith(("/atom", "/obj", "/mob", "/turf", "/area"))}
    parent = {t: t for t in drawing}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    by_anc = collections.defaultdict(list)
    for t in drawing:
        for a in ix.chain(t):
            by_anc[a].append(t)
    for a, ts in by_anc.items():
        if a in drawing:
            for t in ts:
                ra, rt = find(a), find(t)
                if ra != rt:
                    parent[ra] = rt
    comps = collections.defaultdict(list)
    for t in drawing:
        comps[find(t)].append(t)
    return [sorted(v, key=lambda x: (x.count("/"), x)) for v in comps.values()]


def plan_component(ix, comp):
    """{type: plan} for a component, or Residue."""
    plans = {}
    members = set(comp)
    keyed_state = {}  # type -> TRUE when its keyed decls set the state
    provider_sets_state = {}
    layer_vars = collections.defaultdict(set)
    for t in comp:
        if any(r.startswith(NO_EDIT) for (_k, r, _a, _b, _x) in ix.decls.get(t, [])):
            raise Residue("protected")
        if ix.ui_overrides.get(t):
            raise Residue("override")
        kinds = [d[0] for d in ix.decls.get(t, [])]
        for k in ("APPEARANCE_LEVEL", "APPEARANCE_EMISSIVE", "APPEARANCE_SLOT"):
            if k in kinds:
                raise Residue(k.split("_")[1].lower())
        if len(ix.providers.get(t, [])) > 1 or len(ix.draws.get(t, [])) > 1:
            raise Residue("multi_def")
        if ix.providers.get(t) and "DECLARE_APPEARANCE_PROC" not in kinds and not any("DECLARE_APPEARANCE_PROC" in [d[0] for d in ix.decls.get(a, [])] for a in ix.chain(t)):
            # an appearance_overlays() nobody declared runs only through an ancestor's update_icon(): out of scope
            raise Residue("undeclared_provider")
    # parts mode: a provider that does not call ..() under another provider replaces it, so the providers stay one virtual
    # proc (look_parts(look)) that the topmost provider type's draw calls; draw()'s own chain always runs its parent.
    def has_super(t):
        rel, s, e = ix.providers[t][0]
        return any(strip_code(x).strip() in ("..()", ". = ..()", ". += ..()") for x in ix.files[rel].lines[s + 1 : e])
    parts_mode = any(ix.providers.get(t) and not has_super(t) and any(ix.providers.get(a) for a in ix.chain(t)[1:] if a in members) for t in comp)
    for t in comp:
        lines = []
        anc = [a for a in ix.chain(t)[1:] if a in members]
        if parts_mode and ix.decls.get(t) and any(ix.providers.get(a) for a in anc):
            if any(d[0] in ("APPEARANCE_TEMPLATE", "DECLARE_APPEARANCE", "APPEARANCE_NONE") for d in ix.decls[t]):
                raise Residue("order")
        for kind, rel, first, last, raw in ix.decls.get(t, []):
            if kind == "APPEARANCE_NONE":
                lines += none_lines(t, [plans[a]["lines"] for a in anc if a in plans])
                continue
            if kind == "APPEARANCE_TEMPLATE":
                args = macro_args(raw)
                if len(args) != 2 or not re.match(r'^"[^"]*"$', args[1]):
                    raise Residue("template_parse")
                lines.append("\tlook.state(%s)" % template_expr(ix, t, args[1][1:-1]))
                keyed_state[t] = True
                if any(provider_sets_state.get(a) or keyed_state.get(a) == "layer" for a in anc):
                    raise Residue("order")
            elif kind == "DECLARE_APPEARANCE":
                args = macro_args(raw)
                if len(args) != 3:
                    raise Residue("rows_parse")
                var = args[1].strip('"')
                if var != "null" and any(var in layer_vars[a] for a in anc):
                    raise Residue("layer_override")
                layer_vars[t].add(var)
                ll = layer_lines(ix, t, args[1], args[2])
                if any("look.state(" in x for x in ll):
                    if any(provider_sets_state.get(a) for a in anc):
                        raise Residue("order")
                    keyed_state.setdefault(t, "layer")
                lines += ll
        prov = ix.providers.get(t)
        if prov and parts_mode:
            rel, s, e = prov[0]
            body = provider_lines(ix, t, rel, s, e, False)
            root = not any(ix.providers.get(a) for a in anc)
            if root:
                lines.append("\tlook_parts(look)")
            plans[t] = {"lines": lines, "parts": body, "parts_root": root, "parts_super": has_super(t)}
            continue
        if prov:
            rel, s, e = prov[0]
            has_parent_provider = any(ix.providers.get(a) for a in anc)
            body = provider_lines(ix, t, rel, s, e, has_parent_provider)
            if any(re.search(r"\blook\.state\(", x) for x in body):
                provider_sets_state[t] = True
            lines += body
        plans[t] = {"lines": lines}
    for t in comp:
        lint_shape(plans[t]["lines"] + plans[t].get("parts", []))
    return plans


def lint_shape(lines):
    """Residue for generated lines a draw may not hold (sys/dx_reactive): a write to a member of anything, or a read through another object
    (anything but src, look, GLOB, the reagents relation, or a local the body built: an image, a matrix, a list)."""
    text = "\n".join(strip_code(x) for x in lines)
    built = set(re.findall(r"\bvar/(?:[\w/]+/)?(\w+)\s*=\s*(?:image|mutable_appearance|matrix|icon|list|look_appearance|emissive_appearance)\b", text))
    for code in text.split("\n"):
        c = code.strip()
        c = re.sub(r"^(?:else\s+)?if\s*\((?:[^()]|\([^()]*\))*\)\s*", "", c)
        if re.match(r"^[A-Za-z_]\w*(?:\s*\??\.\s*[A-Za-z_]\w*)+\s*(?:=(?!=)|\+=|-=|\|=|\*=)", c) and not c.startswith("look."):
            raise Residue("member_write")
        for m in re.finditer(r"(?<![\w.\]\)\"'/:])([A-Za-z_]\w*)\s*\??\.\s*([A-Za-z_]\w*)", code):
            root, seg = m.group(1), m.group(2)
            if root in ("look", "src", "GLOB", "reagents", "world") or root in built or seg in ("len", "type", "parent_type"):
                continue
            if re.match(r"^[A-Z][A-Z0-9_]+$", root) or root.startswith("SS"):
                continue
            raise Residue("hop_read")


def none_lines(t, ancestor_lines):
    """APPEARANCE_NONE as a draw: the type keeps its mapped sprite and none of what its ancestors' converted declarations draw.
    Possible when those draw only literal states and overlays (look.hide() drops an overlay by its state); Residue otherwise."""
    states = False
    hides = []
    if not any(ancestor_lines):
        return []
    for lines in ancestor_lines:
        for x in lines:
            code = strip_code(x)
            if re.search(r"\blook\.(set_icon|set_color|set_alpha|light|light_off|play_flick|set_layer|set_plane|set_dir|set_transform)\(", code):
                raise Residue("none_dynamic")
            if "look.state(" in code:
                states = True
            for m in re.finditer(r"\blook\.overlay\(", code):
                arg = x[m.end():]
                lm = re.match(r'^("(?:[^"\\\[]|\\.)*")\)', arg)
                if not lm:
                    raise Residue("none_dynamic")
                if lm.group(1) not in hides:
                    hides.append(lm.group(1))
    out = ["\t// APPEARANCE_NONE: the mapped sprite, without the parent's declared states and layers"]
    if states:
        out.append("\tlook.state(null)")
    for h in hides:
        out.append("\tlook.hide(%s)" % h)
    return out


def verdict(ix, comp, plans):
    """(covered, untracked names) for the component's draws."""
    untracked = set()
    written = set()
    for w, vs in ix.writes.items():
        if any(ix.related(w, m) for m in comp):
            written |= vs

    def covered_var(t, v):
        # tracked, or never written by a proc of the chain (a type constant: icon, a base state...)
        return ix.tracked_on(t, v) or v not in written

    for t in comp:
        reads, calls, hops = body_reads(ix, t, plans[t]["lines"] + plans[t].get("parts", []))
        calls.discard("look_parts")
        for h in hops:
            if not ix.tracked_on(t, h) or True:
                untracked.add(h + ".*")
        for v in reads:
            if v in hops:
                continue
            if not covered_var(t, v):
                untracked.add(v)
        for c in calls:
            sub = proc_reads(ix, t, c, 0, set())
            if sub is None:
                untracked.add(c + "()")
                continue
            for v in sub:
                if not covered_var(t, v):
                    untracked.add("%s (via %s())" % (v, c))
    return not untracked, sorted(untracked)


_coverage_cache = {}


def draw_coverage(ix, t):
    """(has draws, covered, untracked) for the draw() procs in t's chain (its ancestors, itself and every subtype): what a
    redraw request on a t can change. A chain with no draw() has nothing to redraw."""
    ds = sorted(d for d in ix.draws if ix.related(d, t))
    key = tuple(ds)
    if key not in _coverage_cache:
        if not ds:
            _coverage_cache[key] = (False, True, [])
        else:
            plans = {}
            for d in ds:
                rel, s, e = ix.draws[d][0]
                plans[d] = {"lines": ix.files[rel].lines[s + 1 : e]}
            # look_parts() overrides of every type in the chain (a subtype's part is drawn through the root's call)
            for (pt, name), defs in ix.proc_defs.items():
                if name == "look_parts" and ix.related(pt, t):
                    rel, s, e = defs[0]
                    plans.setdefault(pt, {"lines": []})
                    plans[pt]["lines"] = plans[pt]["lines"] + ix.files[rel].lines[s + 1 : e]
            ds = sorted(plans)
            covered, untracked = verdict(ix, ds, plans)
            _coverage_cache[key] = (True, covered, untracked)
    return _coverage_cache[key]


def draw_text(t, lines, note):
    head = "/// The look%s (converted from the legacy appearance declarations by the draw sweep)." % note
    body = ["\t..()"] + [x for x in lines]
    return [head, "%s/draw(datum/look/look)" % t] + body


def apply_component(ix, comp, plans, covered, untracked, edits):
    """Queues the edits for one component: edits[rel] is a list of (first, last, new lines or None)."""
    for t in comp:
        lines = plans[t]["lines"]
        decls = ix.decls.get(t, [])
        prov = ix.providers.get(t)
        own = ix.draws.get(t)
        if "parts" in plans[t]:
            if own:
                raise Residue("own_draw_parts")
            rel, s, e = prov[0]
            body = plans[t]["parts"] or []
            if plans[t]["parts_root"]:
                text = ["%s/draw(datum/look/look)" % t, "\t..()"] + lines + [""]
                text += ["/// What this chain's providers drew: each type's own part of the look, a subtype replacing or extending it (..())."]
                text += ["%s/proc/look_parts(datum/look/look)" % t]
            else:
                text = ["%s/look_parts(datum/look/look)" % t] + (["\t..()"] if plans[t]["parts_super"] else [])
            if not [x for x in body if strip_code(x).strip()] and not plans[t]["parts_super"]:
                body = ["\treturn"]
            edits[rel].append((s, e - 1, text + body))
            for kind, drel, first, last, raw in decls:
                edits[drel].append((first, last, None))
            continue
        drawn = [x for x in lines if x.strip()]
        placed = False
        if own:
            rel, s, e = own[0]
            L = ix.files[rel].lines
            # after the ..() of the existing draw
            k = next((x for x in range(s + 1, e) if strip_code(L[x]).strip()), None)
            if k is None or strip_code(L[k]).strip() not in ("..()", ". = ..()"):
                raise Residue("own_draw_late")
            if drawn:
                edits[rel].append((k + 1, k, [x for x in lines]))
            placed = True
        if prov:
            rel, s, e = prov[0]
            if placed:
                edits[rel].append((s, e - 1, None))
            else:
                L = ix.files[rel].lines
                doc = []
                edits[rel].append((s, e - 1, ["%s/draw(datum/look/look)" % t, "\t..()"] + lines))
                placed = True
        for kind, rel, first, last, raw in decls:
            if kind in ("APPEARANCE_TEMPLATE", "DECLARE_APPEARANCE", "DECLARE_APPEARANCE_PROC", "APPEARANCE_NONE"):
                if not placed and drawn:
                    edits[rel].append((first, last, ["/// The look (the draw sweep: from %s)." % kind_names(decls), "%s/draw(datum/look/look)" % t, "\t..()"] + lines))
                    placed = True
                else:
                    edits[rel].append((first, last, None))


def kind_names(decls):
    names = []
    for d in decls:
        n = {"APPEARANCE_TEMPLATE": "its template", "DECLARE_APPEARANCE": "its layers", "DECLARE_APPEARANCE_PROC": "its provider", "APPEARANCE_NONE": "APPEARANCE_NONE"}.get(d[0])
        if n and n not in names:
            names.append(n)
    return " and ".join(names)


def flush_edits(ix, edits):
    for rel, es in edits.items():
        f = ix.files[rel]
        L = f.lines
        for first, last, new in sorted(es, key=lambda e: (e[0], e[1]), reverse=True):
            if new is None:
                del L[first : last + 1]
                # a blank line left doubled by the removal goes
                if first < len(L) and first > 0 and not L[first].strip() and not L[first - 1].strip():
                    del L[first]
            elif last < first:
                L[first:first] = new
            else:
                L[first : last + 1] = new
        # a generated draw is followed by a blank line
        k = 0
        while k < len(L) - 1:
            if re.match(r"^/[\w/]+/draw\(datum/look/look\)$", L[k]):
                e = k + 1
                while e < len(L) and (L[e][:1] in ("\t", " ") or (not L[e].strip() and e + 1 < len(L) and L[e + 1][:1] in ("\t", " "))):
                    e += 1
                if e < len(L) and L[e].strip():
                    L.insert(e, "")
                k = e
            k += 1
        f.dirty = True
        f.save()


def run(args, root, rels, live_after):
    ix = Index(root, rels)
    comps = components(ix)
    report = {"converted": [], "residue": {}}
    edits = collections.defaultdict(list)
    codes = collections.Counter()
    conv_types = 0
    only = set(args.types or [])
    for comp in sorted(comps, key=lambda c: c[0]):
        if only and not any(t in only or any(t.startswith(o + "/") for o in only) for t in comp):
            continue
        if args.paths and not all(any(r.startswith(p) for p in args.paths) for t in comp for (_k, r, _a, _b, _x) in ix.decls.get(t, [])):
            continue
        try:
            plans = plan_component(ix, comp)
            covered, untracked = verdict(ix, comp, plans)
            if getattr(args, "show", False):
                for t in comp:
                    print("%s/draw(datum/look/look)  // %s" % (t, "covered" if covered else "uncovered: " + ", ".join(untracked)))
                    print("\t..()")
                    print("\n".join(plans[t]["lines"]))
            if args.apply:
                apply_component(ix, comp, plans, covered, untracked, edits)
        except Residue as e:
            code = str(e)
            codes[code.split(":")[0]] += 1
            report["residue"][comp[0]] = {"code": code, "types": comp}
            continue
        conv_types += len(comp)
        report["converted"].append({"root": comp[0], "types": comp, "covered": covered, "untracked": untracked})
    if args.apply:
        flush_edits(ix, edits)
    if args.report:
        json.dump(report, open(args.report, "w"), indent=1)
    cov = sum(1 for c in report["converted"] if c["covered"])
    print("look_sweep convert: %d components (%d types) %s, %d covered by tracked state; residue %d components" % (
        len(report["converted"]), conv_types, "converted" if args.apply else "convertible", cov, len(report["residue"])))
    for code, n in codes.most_common():
        print("    %-22s %4d" % (code, n))
    if args.sites:
        for code in sorted({v["code"] for v in report["residue"].values()}):
            print("  %s" % code)
            for r, v in sorted(report["residue"].items()):
                if v["code"] == code:
                    print("      %s (%d types)" % (r, len(v["types"])))
    return report
