"""Shared helpers for the Phase C lifecycle codemods (tools/codemods/).

A small line-level reader for DM: files keep their line endings, procs are found by their column-0 header (the form the init,
qdel_src and usr lints read), bodies are the indented or blank lines under the header, and statements are joined across open
brackets and trailing backslashes. Nothing here evaluates DM; a codemod that cannot read a site with these rules leaves it.
"""
import os
import re

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

# Never rewritten by a lifecycle codemod: the macro library, the engine, tests, vendored code.
SKIP_PREFIXES = (
    "code/__defines/",
    "code/modules/unit_tests/",
    "code/modules/tgs/",
    "code/engine/",
    "code/controllers/kernel/",
    "code/_generated/",
)

# Other agents' folders (lifecycle-only, mechanical and small edits there; `--others` opts in).
OTHERS = (
    "code/modules/organs/",
    "code/modules/body/",
    "code/modules/medical/",
    "code/datums/om/",
    "code/datums/entity_state/",
    "code/modules/mob/living/life/",
    "code/game/objects/",
    "code/modules/power/",
    "code/ATMOSPHERICS/",
    "code/game/machinery/atmoalter/",
    "code/game/machinery/pipe/",
    "code/modules/pipes/",
)

PROC_HEAD = re.compile(r"^(/[\w/]+?)/(?:(proc|verb)/)?(\w+)\s*\((.*)$")


def rel(path):
    return os.path.relpath(path, ROOT).replace("\\", "/")


def dm_files(prefixes=("code/",), others=False):
    out = []
    for prefix in prefixes:
        base = os.path.join(ROOT, prefix)
        if os.path.isfile(base):
            out.append(rel(base))
            continue
        for root, _, files in os.walk(base):
            for f in files:
                if f.endswith(".dm"):
                    out.append(rel(os.path.join(root, f)))
    out = sorted(set(out))
    out = [f for f in out if not f.startswith(SKIP_PREFIXES)]
    if not others:
        out = [f for f in out if not f.startswith(OTHERS)]
    return out


class File:
    def __init__(self, relpath):
        self.rel = relpath
        self.path = os.path.join(ROOT, relpath)
        with open(self.path, "rb") as fh:
            raw = fh.read()
        self.bom = raw.startswith(b"\xef\xbb\xbf")
        text = raw[3:].decode("utf-8") if self.bom else raw.decode("utf-8", errors="surrogateescape")
        self.crlf = "\r\n" in text
        self.final_newline = text.endswith("\n")
        if self.crlf:
            text = text.replace("\r\n", "\n")
        self.lines = text.split("\n")
        if self.final_newline:
            self.lines.pop()
        self.dirty = False

    def save(self):
        if not self.dirty:
            return
        nl = "\r\n" if self.crlf else "\n"
        text = nl.join(self.lines) + (nl if self.final_newline else "")
        data = text.encode("utf-8", errors="surrogateescape")
        if self.bom:
            data = b"\xef\xbb\xbf" + data
        with open(self.path, "wb") as fh:
            fh.write(data)


def strip_code(s):
    """The line with comments removed and string text blanked (the code inside a string's [..] is kept)."""
    if '"' not in s and "/" not in s and "'" not in s:
        return s
    out = []
    stack = []
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        top = stack[-1] if stack else None
        if top in ("str", "sq"):
            if c == "\\":
                out.append("  "[: min(2, n - i)])
                i += 2
                continue
            if (c == '"' and top == "str") or (c == "'" and top == "sq"):
                stack.pop()
                out.append(c)
            elif c == "[" and top == "str":
                stack.append("expr")
                out.append(c)
            else:
                out.append(" ")
        else:
            if c == '"':
                stack.append("str")
                out.append(c)
            elif c == "'":
                stack.append("sq")
                out.append(c)
            elif c == "[" and top in ("expr", "br"):
                stack.append("br")
                out.append(c)
            elif c == "]" and top == "br":
                stack.pop()
                out.append(c)
            elif c == "]" and top == "expr":
                stack.pop()
                out.append(c)
            elif c == "/" and i + 1 < n and s[i + 1] == "/" and top is None:
                break
            elif c == "/" and i + 1 < n and s[i + 1] == "*" and top is None:
                j = s.find("*/", i + 2)
                if j < 0:
                    break
                out.append(" " * (j + 2 - i))
                i = j + 2
                continue
            else:
                out.append(c)
        i += 1
    return "".join(out)


def depth_delta(code):
    return code.count("(") + code.count("[") + code.count("{") - code.count(")") - code.count("]") - code.count("}")


def indent_of(line):
    n = 0
    for c in line:
        if c == "\t":
            n += 1
        elif c == " ":
            n += 0.25
        else:
            break
    return n


class Proc:
    def __init__(self, f, start, end, m):
        self.file = f
        self.start = start  # index of the header line
        self.end = end  # one past the last non-blank body line
        self.type = m.group(1)
        self.kind = m.group(2)
        self.name = m.group(3)
        self.params_text = m.group(4)

    @property
    def header(self):
        return self.file.lines[self.start]

    def body_lines(self):
        return list(range(self.start + 1, self.end))

    def params(self):
        """The parameter names (`mob/user` -> `user`, `...` kept), or None when the header spans lines."""
        code = strip_code(self.header)
        i = code.find("(")
        if i < 0:
            return None
        depth, j = 0, i
        while j < len(code):
            if code[j] == "(":
                depth += 1
            elif code[j] == ")":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        if j >= len(code):
            return None
        inner = code[i + 1 : j]
        out = []
        for part in split_args(inner):
            part = part.strip()
            if not part:
                continue
            if part == "...":
                out.append("...")
                continue
            name = part.split("=")[0].strip()
            name = re.sub(r"\bas\b.*$", "", name).strip()
            out.append(name.split("/")[-1].strip())
        return out


def procs_in(f):
    lines = f.lines
    n = len(lines)
    i = 0
    while i < n:
        m = PROC_HEAD.match(lines[i])
        if not m or "=" in strip_code(lines[i]).split("(")[0]:
            i += 1
            continue
        j = i + 1
        last = i
        while j < n and (lines[j].strip() == "" or lines[j][0] in " \t"):
            if lines[j].strip():
                last = j
            j += 1
        yield Proc(f, i, last + 1, m)
        i = j


def split_args(s):
    """Top-level comma split of an argument list's text (strings and brackets respected)."""
    out, depth, cur, q = [], 0, [], None
    i = 0
    while i < len(s):
        c = s[i]
        if q:
            cur.append(c)
            if c == "\\" and i + 1 < len(s):
                cur.append(s[i + 1])
                i += 2
                continue
            if c == q:
                q = None
        elif c in "\"'":
            q = c
            cur.append(c)
        elif c in "([{":
            depth += 1
            cur.append(c)
        elif c in ")]}":
            depth -= 1
            cur.append(c)
        elif c == "," and depth == 0:
            out.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    out.append("".join(cur))
    return out


class Stmt:
    """One logical statement: its first and last line index, indent level, joined code text (comments stripped)."""

    def __init__(self, first, last, indent, code, raw):
        self.first = first
        self.last = last
        self.indent = indent
        self.code = code
        self.raw = raw

    def __repr__(self):
        return "Stmt(%d-%d, %s, %r)" % (self.first, self.last, self.indent, self.code)


def statements(f, first, end):
    """Logical statements of lines[first:end] (blank and comment-only lines skipped)."""
    out = []
    i = first
    lines = f.lines
    while i < end:
        line = lines[i]
        code = strip_code(line).rstrip()
        if not code.strip():
            i += 1
            continue
        start = i
        parts = [code.strip()]
        raws = [line]
        depth = depth_delta(code)
        cont = code.endswith("\\")
        while (depth > 0 or cont) and i + 1 < end:
            i += 1
            c2 = strip_code(lines[i]).rstrip()
            raws.append(lines[i])
            if parts[-1].endswith("\\"):
                parts[-1] = parts[-1][:-1].rstrip()
            parts.append(c2.strip())
            depth += depth_delta(c2)
            cont = c2.endswith("\\")
        out.append(Stmt(start, i, indent_of(line), " ".join(p for p in parts if p), raws))
        i += 1
    return out


def word_in(text, name):
    return re.search(r"(?<![\w.])" + re.escape(name) + r"(?!\w)", text) is not None


def capabilities_index(files=None):
    """type -> (rel, header index) of every CAPABILITIES(T) block in code/ (all folders, tests included)."""
    idx = {}
    head = re.compile(r"^CAPABILITIES\((/[\w/]+)\)")
    for root, _, fs in os.walk(os.path.join(ROOT, "code")):
        for fn in fs:
            if not fn.endswith(".dm"):
                continue
            p = os.path.join(root, fn)
            with open(p, encoding="utf-8", errors="surrogateescape") as fh:
                for k, line in enumerate(fh):
                    if line.startswith("CAPABILITIES("):
                        m = head.match(line)
                        if m:
                            idx[m.group(1)] = (rel(p), k)
    return idx


def block_end(f, header):
    """One past the last indented line of the block whose header is at `header`."""
    j = header + 1
    last = header
    n = len(f.lines)
    while j < n and (f.lines[j].strip() == "" or f.lines[j][0] in " \t"):
        if f.lines[j].strip():
            last = j
        j += 1
    return last + 1
