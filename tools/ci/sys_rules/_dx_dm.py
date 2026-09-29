"""Shared DM scanning helpers for the dx_* lints (tools/ci/sys_rules/dx_*.py, tools/ci/ui_actions_lint.py).

Not a rule module (the leading underscore keeps sys_lint.py from loading it). Everything here is a
static approximation of DM, good enough for ratchet lints:

  sanitize(lines)     same-length lines with comments removed and string text blanked; the code
                      inside an embedded "[expr]" is kept, so reads in messages still count.
  procs(files)        every absolute proc definition: Proc(rel, line, path, name, params, body).
  type_vars(files)    {type path: set(var names)} declared in the tree (both `/T/var/x` and a
                      `var/x` line inside a `/T` block, and grouped `var` blocks).
  vars_of(table, T)   the vars of T and its path ancestors plus DM's builtin atom vars.
  call_args(text, i)  the argument strings of the call whose "(" is at text[i].
  enclosing_call(text, i)  (proc name, arg index, arg name) of the call an expression at i sits in.

Limits: relative proc definitions are not seen (the codebase bans them), parent_type overrides
are ignored (ancestry is the path prefix), and macro-generated procs are invisible.
"""
import re

PROC_HEAD = re.compile(r"^(/[\w/]*?)/(?:(?:proc|verb)/)?(\w+)\((.*)\)\s*$")
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



def sanitize_text(text):
    """The text with comments blanked and string contents blanked (embedded [..] kept). Same length
    and same newlines, so offsets and line numbers still map to the raw file."""
    out = []
    i, n = 0, len(text)
    stack = []  # "str", "mstr", "embed", "block"
    while i < n:
        c = text[i]
        top = stack[-1] if stack else "code"
        if top in ("code", "embed"):
            if text.startswith("//", i):
                j = text.find("\n", i)
                j = n if j < 0 else j
                out.append(" " * (j - i))
                i = j
                continue
            if text.startswith("/*", i):
                stack.append("block")
                out.append("  ")
                i += 2
                continue
            if text.startswith('{"', i):
                stack.append("mstr")
                out.append('{"')
                i += 2
                continue
            if c == '"':
                stack.append("str")
                out.append('"')
                i += 1
                continue
            if c == "'":
                j = i + 1
                while j < n and text[j] not in "'\n":
                    j += 2 if text[j] == "\\" else 1
                j = min(j, n - 1)
                out.append("'" + " " * max(0, j - i - 1) + ("'" if j > i and text[j] == "'" else text[j]))
                i = j + 1
                continue
            if top == "embed":
                if c == "[":
                    stack.append("embed")
                elif c == "]":
                    stack.pop()
            out.append(c)
            i += 1
            continue
        if top == "block":
            if text.startswith("*/", i):
                stack.pop()
                out.append("  ")
                i += 2
                continue
            if text.startswith("/*", i):
                stack.append("block")
                out.append("  ")
                i += 2
                continue
            out.append("\n" if c == "\n" else " ")
            i += 1
            continue
        # inside a string
        if c == "\\" and i + 1 < n:
            out.append(" " + ("\n" if text[i + 1] == "\n" else " "))
            i += 2
            continue
        if top == "str" and c == '"':
            stack.pop()
            out.append('"')
            i += 1
            continue
        if top == "mstr" and text.startswith('"}', i):
            stack.pop()
            out.append('"}')
            i += 2
            continue
        if c == "[":
            stack.append("embed")
            out.append("[")
            i += 1
            continue
        if c == "\n":
            if top == "str":
                stack.pop()  # unterminated: recover at the line end
            out.append("\n")
            i += 1
            continue
        out.append(" ")
        i += 1
    return "".join(out)


def sanitize(lines):
    return sanitize_text("\n".join(lines)).split("\n")


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
    __slots__ = ("rel", "line", "path", "name", "params", "body", "body_start", "raw_body")

    def __init__(self, rel, line, path, name, params, body, body_start, raw_body):
        self.rel, self.line, self.path, self.name = rel, line, path, name
        self.params, self.body, self.body_start, self.raw_body = params, body, body_start, raw_body

    def lines(self):
        """(line number, sanitized text) for each body line."""
        for k, text in enumerate(self.body):
            yield self.body_start + k, text


def procs_in(rel, raw_lines, clean=None):
    clean = clean if clean is not None else sanitize(raw_lines)
    out = []
    i, n = 0, len(clean)
    while i < n:
        m = PROC_HEAD.match(clean[i].rstrip())
        if not m or "/var/" in m.group(1) + "/":
            i += 1
            continue
        start = i + 1
        j = start
        while j < n and (not clean[j].strip() or clean[j][:1] in " \t"):
            j += 1
        out.append(Proc(rel, i + 1, m.group(1) or "/", m.group(2), param_names(m.group(3)),
                        clean[start:j], start + 1, raw_lines[start:j]))
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


def ancestors(path):
    parts = path.rstrip("/").split("/")
    return ["/".join(parts[:k]) for k in range(2, len(parts) + 1)]


def vars_of(table, path, builtins=True):
    out = set(BUILTIN_VARS) if builtins else set()
    for anc in ancestors(path):
        out |= table.get(anc, set())
    out |= table.get("/datum", set())
    return out


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
