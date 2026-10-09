"""Shared reader for the loot and map-resolver codemods (declare_loot.py, map_resolver.py).

Both move a column-0 macro (DECLARE_LOOT, MAP_RESOLVER, MAP_RESOLVER_VARS) into the CAPABILITIES block of the type it names: the block is
found anywhere under code/ (a type has one), or made where the macro was. Files keep their line endings and encoding.
"""
import os
import re

ROOT = os.environ.get("DQ_CODEMOD_ROOT") or os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SKIP_DIRS = ("code/__defines/", "code/_generated/", "code/engine/_generated/")


def rel(path):
    return os.path.relpath(path, ROOT).replace("\\", "/")


class File:
    def __init__(self, relpath):
        self.rel = relpath
        self.path = os.path.join(ROOT, relpath)
        with open(self.path, "rb") as fh:
            raw = fh.read()
        self.bom = raw.startswith(b"\xef\xbb\xbf")
        text = (raw[3:] if self.bom else raw).decode("utf-8", errors="surrogateescape")
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


def all_files(include_tests=False):
    out = []
    for base, dirs, files in os.walk(os.path.join(ROOT, "code")):
        dirs[:] = [d for d in dirs if d != "_generated"]
        for f in files:
            if f.endswith(".dm"):
                r = rel(os.path.join(base, f))
                if r.startswith(SKIP_DIRS):
                    continue
                out.append(r)
    out.sort()
    return out


def scan_code(line):
    """The line's code part: comments cut, string contents blanked (quotes kept). Also returns the comment text or None."""
    out = []
    i, n = 0, len(line)
    in_str = False
    while i < n:
        c = line[i]
        if in_str:
            if c == "\\":
                out.append("  "[: min(2, n - i)])
                i += 2
                continue
            if c == '"':
                in_str = False
                out.append(c)
            else:
                out.append(" ")
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        if c == "/" and i + 1 < n and line[i + 1] == "/":
            return "".join(out), line[i:]
        out.append(c)
        i += 1
    return "".join(out), None


def read_call(lines, i):
    """The column-0 call that starts at lines[i]: (last line index, text with comments cut and continuations joined, [comments])."""
    depth = 0
    started = False
    parts, comments = [], []
    j = i
    while j < len(lines):
        raw = lines[j]
        code, comment = scan_code(raw)
        if comment:
            comments.append(comment.strip())
            raw = raw[: len(code)] if len(code) <= len(raw) else raw
        text = raw
        cont = text.rstrip().endswith("\\")
        if cont:
            text = text.rstrip()[:-1]
            code = code.rstrip()[:-1] if code.rstrip().endswith("\\") else code
        parts.append(text.strip())
        for ch in code:
            if ch == "(":
                depth += 1
                started = True
            elif ch == ")":
                depth -= 1
        if started and depth <= 0 and not cont:
            break
        if not started and not cont:
            break
        j += 1
    return j, " ".join(p for p in parts if p), comments


def split_top(text):
    """Splits at top-level commas (parentheses and strings respected); each piece is stripped."""
    out, cur = [], []
    depth = 0
    in_str = False
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if in_str:
            cur.append(c)
            if c == "\\" and i + 1 < n:
                cur.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
        elif c in "([":
            depth += 1
        elif c in ")]":
            depth -= 1
        elif c == "," and depth == 0:
            out.append("".join(cur).strip())
            cur = []
            i += 1
            continue
        cur.append(c)
        i += 1
    last = "".join(cur).strip()
    if last or out:
        out.append(last)
    return out


def call_args(text):
    """('NAME', [args]) of 'NAME(a, b)'; None when the text is not one call."""
    m = re.match(r"^(\w+)\s*\(", text)
    if not m:
        return None
    open_at = m.end() - 1
    depth = 0
    in_str = False
    for k in range(open_at, len(text)):
        c = text[k]
        if in_str:
            if c == "\\":
                continue
            if c == '"':
                in_str = False
            continue
        if c == '"':
            in_str = True
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                if text[k + 1:].strip():
                    return None
                return m.group(1), split_top(text[open_at + 1:k])
    return None


def normalise_ws(text):
    """Collapses runs of whitespace outside strings to one space."""
    out = []
    in_str = False
    prev_space = False
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            prev_space = False
        elif c in " \t":
            if not prev_space:
                out.append(" ")
            prev_space = True
        else:
            out.append(c)
            prev_space = False
        i += 1
    return "".join(out).strip()


CAP_HEAD = re.compile(r"^CAPABILITIES\((/[\w/]+)(\)\s*(//.*)?$|\s*,)")


class Blocks:
    """Every CAPABILITIES block of code/: type -> (file, header line index, form 'block' | 'legacy')."""

    def __init__(self, files):
        self.by_type = {}
        self.files = files
        for f in files.values():
            for i, line in enumerate(f.lines):
                m = CAP_HEAD.match(line)
                if m:
                    form = "block" if m.group(2).startswith(")") else "legacy"
                    self.by_type[m.group(1)] = (f, i, form)

    def block_end(self, f, i):
        """Index of the last line of the block whose header is lines[i]: the indented lines under it (blank lines inside don't end it)."""
        last = i
        j = i + 1
        while j < len(f.lines):
            line = f.lines[j]
            if line.strip() == "":
                j += 1
                continue
            if line[0] in "\t ":
                last = j
                j += 1
                continue
            break
        return last


def type_ancestors(path):
    """The path's ancestors by name, nearest first: /a/b/c -> /a/b, /a."""
    parts = path.strip("/").split("/")
    return ["/" + "/".join(parts[:k]) for k in range(len(parts) - 1, 0, -1)]
