#!/usr/bin/env python3
r"""Rewrites the backslash-continued declaration markers into the block form (doc/rewrite/final_api.html section 1).

    CAPABILITIES(/obj/x, \          CAPABILITIES(/obj/x)
        a(1), \             ->          a(1)
        b(2))                            b(2)

CAPABILITIES(T) and STATE_GRAPH(graph) take one header argument; every later top-level argument becomes one indented entry
statement. Comments, CRLF and the layout inside an entry survive; a marker already in block form is left alone, so a second run
changes nothing. Entries that shared a line are split onto their own lines (the only edit that moves line numbers).

    python tools/dx/codemods/capabilities_block.py [--check] [paths...]
"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import subprocess
import sys

BS = chr(92)
HEADER_ARITY = {"CAPABILITIES": 1, "STATE_GRAPH": 1}
SKIP_PREFIXES = ("tools/analyze/fixtures/",)


def marker_spans(text):
    """(start, open, close) of each column-0 marker whose name is in HEADER_ARITY."""
    out = []
    pos = 0
    while True:
        best = None
        for name in HEADER_ARITY:
            i = text.find("\n" + name + "(", pos - 1 if pos else -1) if pos else (0 if text.startswith(name + "(") else text.find("\n" + name + "("))
            if i != -1:
                start = i if (pos == 0 and i == 0 and text.startswith(name + "(")) else i + 1
                if best is None or start < best[0]:
                    best = (start, name)
        if best is None:
            return out
        start, name = best
        op = start + len(name)
        depth = 0
        k = op
        in_str = False
        while k < len(text):
            c = text[k]
            if in_str:
                if c == BS:
                    k += 1
                elif c == '"':
                    in_str = False
            else:
                if c == '"':
                    in_str = True
                elif c == "(":
                    depth += 1
                elif c == ")":
                    depth -= 1
                    if depth == 0:
                        break
            k += 1
        out.append((start, name, op, k))
        pos = k + 1


def rewrite_calls(text, name, fn):
    """Replaces each `name(args)` call (not a method, path or longer name) with fn(args) -> str."""
    import re

    out = []
    i = 0
    pat = re.compile(r"(?<![\w./])" + name + r"\(")
    while True:
        m = pat.search(text, i)
        if not m:
            out.append(text[i:])
            return "".join(out)
        op = m.end() - 1
        depth = 0
        k = op
        in_str = False
        while k < len(text):
            c = text[k]
            if in_str:
                if c == BS:
                    k += 1
                elif c == '"':
                    in_str = False
            elif c == '"':
                in_str = True
            elif c in "([{":
                depth += 1
            elif c in ")]}":
                depth -= 1
                if depth == 0:
                    break
            k += 1
        inner = text[op + 1 : k]
        out.append(text[i : m.start()])
        out.append(fn(inner))
        i = k + 1


def first_arg(inner):
    depth = 0
    in_str = False
    for i, c in enumerate(inner):
        if in_str:
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            return inner[:i], inner[i + 1 :]
    return inner, None


CAP_NAMES = {}


def adapt_entries(body):
    """The three spellings the marker form allowed and the block form (real calls) does not."""
    import re

    # link(A::a, B::b) -> links(...): `link` is a BYOND reserved word.
    body = re.sub(r"(?<![\w./])link\(", "links(", body)

    # configure(CAP_X, k = v) -> configure(ctor(k = v)): the constructor of the capability carries the params.
    def conf(inner):
        head, rest = first_arg(inner)
        name = CAP_NAMES.get(head.strip())
        if name is None:
            return "configure(" + inner + ")"
        return "configure(" + name + "(" + (rest.strip() if rest is not None else "") + "))"

    body = rewrite_calls(body, "configure", conf)

    # adjusts(packet.amount, ...) -> adjusts("packet.amount", ...): the field path is text.
    def adj(inner):
        head, rest = first_arg(inner)
        h = head.strip()
        if h.startswith('"'):
            return "adjusts(" + inner + ")"
        return "adjusts(" + head.replace(h, '"' + h + '"', 1) + ("," + rest if rest is not None else "") + ")"

    return rewrite_calls(body, "adjusts", adj)


def collect_cap_names(files):
    import re

    pat = re.compile(r"^CAPABILITY_(?:TYPE|DEF)\((\w+),\s*(\w+)", re.M)
    for f in files:
        if not f or f.startswith(SKIP_PREFIXES):
            continue
        try:
            with open(f, encoding="utf-8", errors="surrogateescape", newline="") as fh:
                for m in pat.finditer(fh.read()):
                    CAP_NAMES[m.group(2)] = m.group(1)
        except OSError:
            pass


def convert(text):
    spans = marker_spans(text)
    if not spans:
        return text, 0
    out = []
    last = 0
    n = 0
    for start, name, op, close in spans:
        seg = text[op + 1 : close]  # inside the parentheses
        # Top-level comma positions (depth 0 inside the marker) and the arity of the call.
        commas = []
        depth = 0
        in_str = False
        i = 0
        while i < len(seg):
            c = seg[i]
            if in_str:
                if c == BS:
                    i += 1
                elif c == '"':
                    in_str = False
            elif c == '"':
                in_str = True
            elif c in "([{":
                depth += 1
            elif c in ")]}":
                depth -= 1
            elif c == "," and depth == 0:
                commas.append(i)
            i += 1
        if len(commas) < HEADER_ARITY[name]:
            continue  # already a block (or a header with no entries)
        res = []
        i = 0
        ci = 0
        while i < len(seg):
            c = seg[i]
            if ci < len(commas) and i == commas[ci]:
                ci += 1
                # Skip the comma and the blanks (and a continuation backslash) after it.
                j = i + 1
                while j < len(seg) and seg[j] in " \t":
                    j += 1
                if j < len(seg) and seg[j] == BS:
                    j += 1
                    while j < len(seg) and seg[j] in " \t":
                        j += 1
                if ci == HEADER_ARITY[name]:
                    res.append(")")
                eol = seg[j : j + 2].startswith("\n") or seg[j : j + 2].startswith("\r\n")
                if not eol:
                    res.append("\n\t")
                i = j
                continue
            if c == BS:
                j = i + 1
                while j < len(seg) and seg[j] in " \t":
                    j += 1
                if seg[j : j + 2] == "\r\n" or seg[j : j + 1] == "\n":
                    # A continuation: drop the backslash and the blanks before it.
                    while res and res[-1] in " \t":
                        res.pop()
                    i = j
                    continue
            res.append(c)
            i += 1
        body = adapt_entries("".join(res))
        # Rebuild: header is `NAME(` + header args + `)`; the last entry's closing paren is dropped with the marker's.
        new = name + "(" + body
        out.append(text[last:start])
        out.append(new)
        last = close + 1
        n += 1
    out.append(text[last:])
    return "".join(out), n


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check = "--check" in sys.argv
    if args:
        files = args
    else:
        files = subprocess.check_output(["git", "ls-files", "-z", "*.dm"]).decode("utf-8", "surrogateescape").split("\0")
    collect_cap_names(subprocess.check_output(["git", "ls-files", "-z", "*.dm"]).decode("utf-8", "surrogateescape").split("\0"))
    changed = 0
    sites = 0
    for f in files:
        if not f or f.startswith(SKIP_PREFIXES):
            continue
        with open(f, encoding="utf-8", errors="surrogateescape", newline="") as fh:
            text = fh.read()
        new, n = convert(text)
        if n and new != text:
            changed += 1
            sites += n
            if not check:
                with open(f, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
                    fh.write(new)
    print(f"capabilities_block: {sites} markers in {changed} files{' (check)' if check else ''}")
    return 1 if (check and changed) else 0


if __name__ == "__main__":
    sys.exit(main())
