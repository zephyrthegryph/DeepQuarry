"""Shared DM scanning helpers for the dx_* lints (tools/ci/sys_rules/dx_*.py, tools/ci/ui_actions_lint.py).

Not a rule module (the leading underscore keeps sys_lint.py from loading it). Everything here is a
static approximation of DM, good enough for ratchet lints:

  sanitize(lines)     same-length lines with comments removed and string text blanked; the code
                      inside an embedded "[expr]" is kept, so reads in messages still count.
                      Memoized on the text (every dx module shares one pass over the tree).
  tree(files)         the parsed tree, built once per `files` list and shared by every module:
                      .raw {rel: lines}, .clean {rel: sanitized lines}, .procs [Proc], .type_vars.
  procs(files)        every absolute proc definition: Proc(rel, line, path, name, params, body).
  type_vars(files)    {type path: set(var names)} declared in the tree (both `/T/var/x` and a
                      `var/x` line inside a `/T` block, and grouped `var` blocks).
  lineage(T)          T and its ancestors, path prefixes plus DM's implicit parents
                      (/obj and /mob -> /atom/movable -> /atom -> /datum; /turf, /area -> /atom).
  vars_of(table, T)   the vars of T and its lineage plus DM's builtin atom vars.
  call_args(text, i)  the argument strings of the call whose "(" is at text[i].
  enclosing_call(text, i)  (proc name, arg index, arg name) of the call an expression at i sits in.

Limits: relative proc definitions are not seen (the codebase bans them), parent_type overrides
are ignored (ancestry is the path prefix plus DM's implicit parents), and macro-generated procs are
invisible.
"""
import re

# `/T/proc/name(args)`, `/T/verb/name(args)`, `/T/name(args)` (an override) and `/proc/name(args)`,
# optionally followed by a return type (`as /obj/item`).
PROC_HEAD = re.compile(r"^(/[\w/]*?)/(?:(?:proc|verb)/)?(\w+)\((.*)\)\s*(?:as\s+[\w/|]+\s*)?$")
TYPE_HEAD = re.compile(r"^(/[\w/]+)\s*$")
VAR_LINE = re.compile(r"^(/[\w/]+?)/var/(?:(?:global|static|tmp|const|final)/)*(?:[\w/]+/)?(\w+)\b")
VAR_IN_BLOCK = re.compile(r"^\s+var/(?:[\w/]+/)?(\w+)\s*(?:=|$|\bas\b)")
VAR_GROUP = re.compile(r"^(\s+)var\s*$")
IDENT = re.compile(r"[A-Za-z_]\w*")

# DM's builtin vars (datum, atom, movable, mob, obj, turf, area, client-facing), never declared in code.
BUILTIN_VARS = {
    "type", "parent_type", "tag", "vars", "name", "desc", "suffix", "text", "icon", "icon_state",
    "icon_w", "icon_h", "dir", "layer", "plane", "alpha", "color", "blend_mode", "appearance",
    "appearance_flags", "density", "opacity", "anchored", "loc", "locs", "x", "y", "z",
    "contents", "overlays", "underlays", "vis_contents", "vis_locs", "vis_flags", "verbs",
    "luminosity", "invisibility", "infra_luminosity", "mouse_opacity", "mouse_over_pointer",
    "mouse_drag_pointer", "mouse_drop_pointer", "mouse_drop_zone", "pixel_x", "pixel_y", "pixel_w",
    "pixel_z", "step_x", "step_y", "step_size", "bound_x", "bound_y", "bound_width", "bound_height",
    "glide_size", "gender", "maptext", "maptext_width", "maptext_height", "maptext_x", "maptext_y",
    "transform", "filters", "render_source", "render_target", "screen_loc", "animate_movement",
    "override", "ckey", "key", "client", "sight", "see_in_dark", "see_invisible", "see_infrared",
    "group", "particles", "areas", "world",
}

# ---- sanitizing -------------------------------------------------------------------------------

_CODE_SPECIAL = re.compile(r'//|/\*|@\{"|@"|\{"|"|\'')
_EMBED_SPECIAL = re.compile(r'//|/\*|@\{"|@"|\{"|"|\'|\[|\]')
_BLOCK_SPECIAL = re.compile(r"\*/|/\*")
_STR_SPECIAL = re.compile(r'\\|"|\[|\n')
_MSTR_SPECIAL = re.compile(r'\\|"\}|\[')
_NOT_NL = re.compile(r"[^\n]")


def _blank(chunk):
    return _NOT_NL.sub(" ", chunk)


def _sanitize_text(text):
    out = []
    i, n = 0, len(text)
    stack = []  # "str", "mstr", "embed", "block"
    while i < n:
        top = stack[-1] if stack else "code"
        if top in ("code", "embed"):
            m = (_EMBED_SPECIAL if top == "embed" else _CODE_SPECIAL).search(text, i)
            if not m:
                out.append(text[i:])
                break
            out.append(text[i:m.start()])
            tok = m.group(0)
            j = m.end()
            if tok == "//":
                k = text.find("\n", j)
                k = n if k < 0 else k
                out.append(" " * (k - m.start()))
                i = k
            elif tok == "/*":
                stack.append("block")
                out.append("  ")
                i = j
            elif tok in ('@"', '@{"'):
                # A raw string: no escapes, no embedded expressions.
                close = '"}' if tok == '@{"' else '"'
                k = text.find(close, j)
                if close == '"':
                    nl = text.find("\n", j)
                    if k < 0 or (0 <= nl < k):
                        k = nl if nl >= 0 else n
                        out.append(" " + tok[1:] + _blank(text[j:k]))
                        i = k
                        continue
                k = n if k < 0 else k
                out.append(" " + tok[1:] + _blank(text[j:k]) + text[k:k + len(close)])
                i = k + len(close)
            elif tok == '{"':
                stack.append("mstr")
                out.append('{"')
                i = j
            elif tok == '"':
                stack.append("str")
                out.append('"')
                i = j
            elif tok == "'":
                k = j
                while k < n and text[k] not in "'\n":
                    k += 2 if text[k] == "\\" else 1
                k = min(k, n - 1)
                out.append("'" + " " * max(0, k - m.start() - 1) + ("'" if k > m.start() and text[k] == "'" else text[k]))
                i = k + 1
            elif tok == "[":
                stack.append("embed")
                out.append("[")
                i = j
            else:  # "]" closes an embed
                stack.pop()
                out.append("]")
                i = j
            continue
        if top == "block":
            m = _BLOCK_SPECIAL.search(text, i)
            if not m:
                out.append(_blank(text[i:]))
                break
            out.append(_blank(text[i:m.start()]) + "  ")
            if m.group(0) == "*/":
                stack.pop()
            else:
                stack.append("block")
            i = m.end()
            continue
        # inside a string
        m = (_MSTR_SPECIAL if top == "mstr" else _STR_SPECIAL).search(text, i)
        if not m:
            out.append(_blank(text[i:]))
            break
        out.append(_blank(text[i:m.start()]))
        tok = m.group(0)
        if tok == "\\":
            nxt = text[m.end():m.end() + 1]
            out.append(" " + ("\n" if nxt == "\n" else (" " if nxt else "")))
            i = m.end() + (1 if nxt else 0)
        elif tok == '"':
            stack.pop()
            out.append('"')
            i = m.end()
        elif tok == '"}':
            stack.pop()
            out.append('"}')
            i = m.end()
        elif tok == "[":
            stack.append("embed")
            out.append("[")
            i = m.end()
        else:  # a newline ends an unterminated plain string: recover at the line end
            stack.pop()
            out.append("\n")
            i = m.end()
    return "".join(out)


_SANITIZED = {}


def sanitize_text(text):
    """The text with comments blanked and string contents blanked (embedded [..] kept). Same length
    and same newlines, so offsets and line numbers still map to the raw file."""
    got = _SANITIZED.get(text)
    if got is None:
        got = _SANITIZED[text] = _sanitize_text(text)
    return got


def sanitize(lines):
    return sanitize_text("\n".join(lines)).split("\n")


# ---- small parsing helpers --------------------------------------------------------------------

def split_top(text, sep=","):
    """Splits text on sep outside (), [], {} and quotes."""
    parts, depth, cur, quote = [], 0, [], None
    for c in text:
        if quote:
            cur.append(c)
            if c == quote:
                quote = None
            continue
        if c in "\"'":
            quote = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == sep and depth == 0:
            parts.append("".join(cur))
            cur = []
            continue
        cur.append(c)
    parts.append("".join(cur))
    return parts


def param_names(params):
    names = []
    for part in split_top(params):
        name = part.split("=")[0].strip()
        name = re.sub(r"\bas\b.*$", "", name).strip().split("/")[-1].strip()
        if name and name != "...":
            names.append(name)
    return names


class Proc:
    __slots__ = ("rel", "line", "path", "name", "params", "body", "body_start", "raw_body", "head")

    def __init__(self, rel, line, path, name, params, body, body_start, raw_body, head=""):
        self.rel, self.line, self.path, self.name = rel, line, path, name
        self.params, self.body, self.body_start, self.raw_body = params, body, body_start, raw_body
        self.head = head

    def lines(self):
        """(line number, sanitized text) for each body line."""
        for k, text in enumerate(self.body):
            yield self.body_start + k, text

    def is_global(self):
        return self.path == "/"

    def __repr__(self):
        return "Proc(%s:%d %s/%s)" % (self.rel, self.line, self.path, self.name)


def procs_in(rel, raw_lines, clean=None):
    clean = clean if clean is not None else sanitize(raw_lines)
    out = []
    i, n = 0, len(clean)
    while i < n:
        m = PROC_HEAD.match(clean[i].rstrip())
        if not m or "/var/" in m.group(1) + "/":
            i += 1
            continue
        path = m.group(1) or "/"
        if path in ("/proc", "/verb"):
            path = "/"  # `/proc/x(` is a global proc
        start = i + 1
        j = start
        while j < n and (not clean[j].strip() or clean[j][:1] in " \t"):
            j += 1
        out.append(Proc(rel, i + 1, path, m.group(2), param_names(m.group(3)),
                        clean[start:j], start + 1, raw_lines[start:j], clean[i]))
        i = j
    return out


def procs(files, cleaned=None):
    out = []
    for rel, lines in files:
        out.extend(procs_in(rel, lines, cleaned.get(rel) if cleaned else None))
    return out


def type_vars(files, cleaned=None):
    table = {}
    for rel, lines in files:
        clean = cleaned.get(rel) if cleaned else sanitize(lines)
        current = None
        group_indent = None
        for line in clean:
            m = VAR_LINE.match(line)
            if m:
                table.setdefault(m.group(1), set()).add(m.group(2))
                current = None
                continue
            head = TYPE_HEAD.match(line.rstrip())
            if head:
                current = head.group(1)
                group_indent = None
                continue
            if line and line[:1] not in " \t":
                current = None
                continue
            if not current:
                continue
            if group_indent is not None:
                indent = len(line) - len(line.lstrip())
                if line.strip() and indent > group_indent:
                    name = IDENT.match(line.strip().split("/")[-1] if "=" not in line else line.split("=")[0].strip().split("/")[-1])
                    if name:
                        table.setdefault(current, set()).add(name.group(0))
                    continue
                group_indent = None
            g = VAR_GROUP.match(line)
            if g:
                group_indent = len(g.group(1))
                continue
            v = VAR_IN_BLOCK.match(line)
            if v:
                table.setdefault(current, set()).add(v.group(1))
    return table


class Tree:
    """One parse of the tree, shared by every dx module that sys_lint.py runs on the same files."""

    def __init__(self, files):
        self.files = files
        self.raw = dict(files)
        self.clean = {rel: sanitize(lines) for rel, lines in files}
        self._procs = None
        self._type_vars = None
        self._by_name = None

    @property
    def procs(self):
        if self._procs is None:
            self._procs = procs(self.files, self.clean)
        return self._procs

    @property
    def type_vars(self):
        if self._type_vars is None:
            self._type_vars = type_vars(self.files, self.clean)
        return self._type_vars

    def procs_named(self, name):
        if self._by_name is None:
            self._by_name = {}
            for proc in self.procs:
                self._by_name.setdefault(proc.name, []).append(proc)
        return self._by_name.get(name, ())


_TREES = []


def tree(files):
    """The shared Tree for this exact `files` list (the list object sys_lint.py hands every module)."""
    for built in _TREES:
        if built.files is files:
            return built
    built = Tree(files)
    _TREES[:] = [built]  # keep only the latest (and a live ref, so the id can't be reused)
    return built


# ---- types ------------------------------------------------------------------------------------

_IMPLICIT = {"/obj": "/atom/movable", "/mob": "/atom/movable", "/atom/movable": "/atom",
             "/turf": "/atom", "/area": "/atom", "/atom": "/datum"}


def ancestors(path):
    """The path prefixes of path, shortest first (path included)."""
    parts = path.rstrip("/").split("/")
    return ["/".join(parts[:k]) for k in range(2, len(parts) + 1)]


def lineage(path):
    """path and every ancestor, nearest first, including DM's implicit parents; ends with /datum
    for every datum path (not for "/" or /client, /world, /list, ...)."""
    out = list(reversed(ancestors(path)))
    root = out[-1] if out else None
    while root in _IMPLICIT:
        root = _IMPLICIT[root]
        out.append(root)
    if out and out[-1] != "/datum" and out[-1] not in ("/client", "/world", "/list", "/savefile",
                                                      "/regex", "/icon", "/image", "/sound",
                                                      "/matrix", "/database", "/exception",
                                                      "/generator", "/mutable_appearance",
                                                      "/particles", "/dm_filter", "/callee"):
        out.append("/datum")
    return out


def is_subtype(path, base):
    return base in lineage(path)


def related(a, b):
    """a and b are the same type, or one descends from the other."""
    return is_subtype(a, b) or is_subtype(b, a)


def vars_of(table, path, builtins=True):
    out = set(BUILTIN_VARS) if builtins else set()
    for anc in lineage(path):
        out |= table.get(anc, set())
    return out


# ---- calls ------------------------------------------------------------------------------------

def match_paren(text, i):
    """Index of the ")" closing the "(" at text[i], or -1."""
    depth = 0
    for j in range(i, len(text)):
        if text[j] in "([":
            depth += 1
        elif text[j] in ")]":
            depth -= 1
            if depth == 0:
                return j
    return -1


def call_args(text, i):
    end = match_paren(text, i)
    if end < 0:
        return None
    return [a.strip() for a in split_top(text[i + 1:end])]


def call_arg_spans(text, i):
    """[(start, end)] offsets of each argument of the call whose "(" is at text[i], or None."""
    end = match_paren(text, i)
    if end < 0:
        return None
    spans, depth, start = [], 0, i + 1
    for k in range(i + 1, end):
        c = text[k]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            spans.append((start, k))
            start = k + 1
    spans.append((start, end))
    return spans


NAMED_ARG = re.compile(r"^\s*([A-Za-z_]\w*)\s*=(?!=)")


def pick_arg(args, index, name):
    """The argument at positional `index` (counting only positional args before any named one) or
    named `name`, from call_args() output; None if absent."""
    positional = []
    for arg in args:
        m = NAMED_ARG.match(arg)
        if m:
            if m.group(1) == name:
                return arg[m.end():].strip()
            continue
        positional.append(arg)
    if index is not None and index < len(positional):
        return positional[index]
    return None


def enclosing_call(text, i):
    """For the expression starting at text[i]: (name, positional index, named-arg key) of the
    innermost call it is a direct argument of, or None."""
    depth, commas = 0, 0
    j = i - 1
    while j >= 0:
        c = text[j]
        if c in ")]":
            depth += 1
        elif c in "([":
            if depth == 0:
                if c == "[":
                    return None
                m = re.search(r"([A-Za-z_]\w*)\s*$", text[:j])
                if not m:
                    return None
                # the start of this argument, to spot `key = value`
                seg_start, d2 = j + 1, 0
                for k in range(j + 1, i):
                    if text[k] in "([":
                        d2 += 1
                    elif text[k] in ")]":
                        d2 -= 1
                    elif text[k] == "," and d2 == 0:
                        seg_start = k + 1
                key = re.match(r"\s*([A-Za-z_]\w*)\s*=(?!=)", text[seg_start:i])
                return m.group(1), commas, key.group(1) if key else None
            depth -= 1
        elif c == "," and depth == 0:
            commas += 1
        j -= 1
    return None


PROC_REF_ARG = re.compile(r"^\s*(?:PROC_REF\(\s*(\w+)\s*\)|TYPE_PROC_REF\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\)|"
                          r"GLOBAL_PROC_REF\(\s*(\w+)\s*\)|TYPE_VERB_REF\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\)|"
                          r"VERB_REF\(\s*(\w+)\s*\))\s*$")


def proc_ref(arg):
    """(kind, type or None, name) for a PROC_REF-family argument, else None. kind is "src" (PROC_REF,
    VERB_REF: the calling type), "type" (TYPE_PROC_REF/TYPE_VERB_REF) or "global"."""
    if not arg:
        return None
    m = PROC_REF_ARG.match(arg)
    if not m:
        return None
    if m.group(1):
        return ("src", None, m.group(1))
    if m.group(3):
        return ("type", m.group(2), m.group(3))
    if m.group(4):
        return ("global", None, m.group(4))
    if m.group(6):
        return ("type", m.group(5), m.group(6))
    return ("src", None, m.group(7))
