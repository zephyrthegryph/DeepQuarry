#!/usr/bin/env python3
r"""DECLARE_REAGENTS family -> reagents() entries in the type's CAPABILITIES block (doc/rewrite/reagents.md, codemod_rules.md "reagents").

    DECLARE_REAGENTS(/obj/item/reagent_containers, "volume", null)      CAPABILITIES(/obj/item/reagent_containers)
                                                                   ->       reagents(nameof(volume))
    DECLARE_REAGENTS(/obj/item/x/donut, null, list(A = 3))              CAPABILITIES(/obj/item/x/donut)
                                                                   ->       configure(reagents(add = list(A = 3)))
    DECLARE_REAGENTS_TINTED(T, V, C) adds `tint = TRUE`; DECLARE_REAGENTS_TYPED(T, V, C, H) adds `holder = H`;
    DECLARE_REAGENT_FROM_VAR(T, V, "id", "amt") is reagents(V, starts_from = list(nameof(id) = nameof(amt)));
    DECLARE_NO_REAGENTS(T) is without(CAP_REAGENTS); NO then DECLARE on one type is configure(reagents(starts = ...)).

The chain is read over the whole tree first: a type whose ancestor declares a holder gets configure() (its contents ADD to the inherited
ones, its volume replaces the inherited one only when given); a type with none above it gets reagents(). The entry goes under the type's
existing CAPABILITIES header (any file), else the declaration line becomes a new block in place. A string volume or var name is nameof().
A second run changes nothing. Residue (printed, file left alone): `indented_next` (the line is followed by an indented line that would fall
into the new block), `parent_traits` (NO then DECLARE under a parent with tint or a holder type), `parse`.

    python tools/dx/codemods/reagents_decl.py [--check]
"""
import pathlib
import re
import sys

FORMS = ("DECLARE_REAGENTS_TINTED", "DECLARE_REAGENTS_TYPED", "DECLARE_REAGENT_FROM_VAR", "DECLARE_NO_REAGENTS", "DECLARE_REAGENTS")
LINE = re.compile(r"^(" + "|".join(FORMS) + r")\((.*)$")
SKIP = ("code/__defines/lifecycle_decl.dm",)


def split_args(s):
    """Top-level comma split of `s` (the text inside the call's parens)."""
    out, depth, cur, in_str = [], 0, [], False
    i = 0
    while i < len(s):
        c = s[i]
        if in_str:
            cur.append(c)
            if c == "\\":
                cur.append(s[i + 1])
                i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
            cur.append(c)
        elif c in "([":
            depth += 1
            cur.append(c)
        elif c in ")]":
            depth -= 1
            cur.append(c)
        elif c == "," and depth == 0:
            out.append("".join(cur).strip())
            cur = []
        else:
            cur.append(c)
        i += 1
    out.append("".join(cur).strip())
    return out


def call_body(rest):
    """`rest` starts after the opening paren: (inside, trailing text after the closing paren) or None."""
    depth, in_str = 1, False
    for i, c in enumerate(rest):
        if in_str:
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
                return rest[:i], rest[i + 1:]
    return None


def nameof(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
        return "nameof(" + v[1:-1] + ")"
    return v


def is_null(v):
    return v is None or v.strip() == "null"


def parse_list(text):
    """list(A = 1, B = 2) -> [(A, 1), ...] keeping the key and amount text."""
    text = text.strip()
    m = re.match(r"^list\((.*)\)$", text, re.S)
    if not m:
        return None
    items = []
    for part in split_args(m.group(1)):
        if not part:
            continue
        if "=" in part:
            k, v = part.split("=", 1)
            items.append((k.strip(), v.strip()))
        else:
            items.append((part, "1"))
    return items


def list_text(items):
    """Amounts of a key named twice add up (the legacy table summed every line's contents)."""
    merged = {}
    for k, v in items:
        merged[k] = f"{merged[k]} + {v}" if k in merged else v
    for k, v in merged.items():
        parts = v.split(" + ")
        if len(parts) > 1 and all(re.fullmatch(r"[0-9.]+", x) for x in parts):
            total = sum(float(x) for x in parts)
            merged[k] = str(int(total)) if total == int(total) else str(total)
    return "list(" + ", ".join(f"{k} = {v}" for k, v in merged.items()) + ")"


def block_comment_after(line, in_comment):
    """Whether a /* */ comment is open at the end of `line`, given whether one was open at its start (strings and // ignored)."""
    s = re.sub(r'"(?:\\.|[^"\\])*"', '""', line)
    j = 0
    while True:
        if in_comment:
            k = s.find("*/", j)
            if k < 0:
                return True
            in_comment, j = False, k + 2
        else:
            k1, k2 = s.find("/*", j), s.find("//", j)
            if k1 < 0 or 0 <= k2 < k1:
                return False
            in_comment, j = True, k1 + 2


class Decl:
    def __init__(self, form, args, path, lineno, trailing):
        self.form, self.args, self.path, self.lineno, self.trailing = form, args, path, lineno, trailing


def scan(root):
    decls = {}  # type -> [Decl]
    headers = {}  # type -> (path, line index)
    residue = []
    for p in sorted(root.rglob("*.dm")):
        rel = p.relative_to(root.parent).as_posix() if root.name == "code" else p.as_posix()
        if any(rel.endswith(s) for s in SKIP):
            continue
        text = p.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")
        if "DECLARE_" not in text and "CAPABILITIES(" not in text:
            continue
        in_comment = False
        for i, line in enumerate(text.split("\n")):
            # a declaration inside a /* */ block is dead text: never a site, never a header
            was_in = in_comment
            in_comment = block_comment_after(line, in_comment)
            if was_in:
                continue
            if line.startswith("CAPABILITIES("):
                m = re.match(r"^CAPABILITIES\(([^)]+)\)\s*$", line)
                if m:
                    headers[m.group(1).strip()] = (p, i)
                continue
            m = LINE.match(line)
            if not m:
                continue
            body = call_body(m.group(2))
            if not body:
                residue.append(("parse", p, i + 1, line))
                continue
            args = split_args(body[0])
            trailing = body[1].strip()
            decls.setdefault(args[0], []).append(Decl(m.group(1), args, p, i, trailing))
    return decls, headers, residue


class State:
    def __init__(self):
        self.volume = None
        self.contents = []
        self.from_var = []
        self.holder = None
        self.tint = False

    def copy(self):
        s = State()
        s.volume, s.contents, s.from_var, s.holder, s.tint = self.volume, list(self.contents), list(self.from_var), self.holder, self.tint
        return s


def apply(state, d):
    """The legacy table's set_reagents()/clear_reagents() on `state` (None = no holder). Returns the new state."""
    if d.form == "DECLARE_NO_REAGENTS":
        return None
    s = state.copy() if state else State()
    a = d.args
    if d.form == "DECLARE_REAGENT_FROM_VAR":
        vol, id_var, amount = a[1], a[2], a[3]
        if not is_null(vol):
            s.volume = vol
        elif s.volume is None:
            s.volume = "0"
        s.from_var.append((id_var, amount))
        return s
    vol, contents = a[1], a[2]
    if not is_null(vol):
        s.volume = vol
    elif s.volume is None:
        s.volume = "0"
    if not is_null(contents):
        s.contents += parse_list(contents)
    if d.form == "DECLARE_REAGENTS_TYPED":
        s.holder = a[3]
    if d.form == "DECLARE_REAGENTS_TINTED":
        s.tint = True
    return s


def ancestors(t):
    parts = t.split("/")
    return ["/".join(parts[:k]) for k in range(2, len(parts))]


def effective(t, decls, memo):
    if t in memo:
        return memo[t]
    state = None
    for anc in ancestors(t):
        if anc in decls:
            state = effective(anc, decls, memo)
    for d in decls.get(t, []):
        state = apply(state, d)
    memo[t] = state
    return state


def inherited(t, decls, memo):
    state = None
    for anc in ancestors(t):
        if anc in decls:
            state = effective(anc, decls, memo)
    return state


def entry_for(t, decls, memo):
    """The entry text for t, '' for none, or ('residue', code)."""
    parent = inherited(t, decls, memo)
    own = decls[t]
    cleared = any(d.form == "DECLARE_NO_REAGENTS" for d in own)
    final = effective(t, decls, memo)
    if final is None:
        return "without(CAP_REAGENTS)" if parent else ""
    if parent is None or cleared:
        if parent is not None and cleared:
            # NO then DECLARE: replace the inherited contents (and volume, when given)
            if parent.tint or parent.holder or parent.from_var:
                return ("residue", "parent_traits")
            parts = []
            if final.volume != parent.volume and final.volume not in (None, "0"):
                parts.append("volume = " + nameof(final.volume))
            parts.append("starts = " + (list_text(final.contents) if final.contents else "list()"))
            if final.tint:
                parts.append("tint = TRUE")
            if final.holder:
                parts.append("holder = " + final.holder)
            if final.from_var:
                parts.append("starts_from = list(" + ", ".join(f"{nameof(k)} = {nameof(v)}" for k, v in final.from_var) + ")")
            return "configure(reagents(" + ", ".join(parts) + "))"
        parts = []
        if final.volume not in (None, "0"):
            parts.append(nameof(final.volume))
        if final.contents:
            if not parts:
                parts.append("0")
            parts.append("starts = " + list_text(final.contents))
        if final.tint:
            parts.append("tint = TRUE")
        if final.holder:
            parts.append("holder = " + final.holder)
        if final.from_var:
            parts.append("starts_from = list(" + ", ".join(f"{nameof(k)} = {nameof(v)}" for k, v in final.from_var) + ")")
        return "reagents(" + ", ".join(parts) + ")"
    # a subtype: what its own lines change
    parts = []
    added = []
    tint = False
    holder = None
    vol = None
    for d in own:
        a = d.args
        if not is_null(a[1]):
            vol = a[1]
        if d.form == "DECLARE_REAGENT_FROM_VAR":
            return ("residue", "from_var_subtype")
        if not is_null(a[2]):
            added += parse_list(a[2])
        if d.form == "DECLARE_REAGENTS_TINTED" and not parent.tint:
            tint = True
        if d.form == "DECLARE_REAGENTS_TYPED":
            holder = a[3]
    if vol is not None:
        parts.append("volume = " + nameof(vol))
    if added:
        parts.append("add = " + list_text(added))
    if tint:
        parts.append("tint = TRUE")
    if holder:
        parts.append("holder = " + holder)
    if not parts:
        return ""
    return "configure(reagents(" + ", ".join(parts) + "))"


def main():
    check = "--check" in sys.argv
    root = pathlib.Path("code")
    decls, headers, residue = scan(root)
    memo = {}
    edits = {}  # path -> list of (line index, action)
    converted = 0
    for t in sorted(decls):
        entry = entry_for(t, decls, memo)
        if isinstance(entry, tuple):
            residue.append((entry[1], decls[t][0].path, decls[t][0].lineno + 1, t))
            continue
        own = decls[t]
        trailing = " ".join(d.trailing for d in own if d.trailing)
        if trailing and not trailing.startswith("//"):
            residue.append(("trailing_code", own[0].path, own[0].lineno + 1, t))
            continue
        entry_line = ("\t" + entry + ((" " + trailing) if trailing else "")) if entry else None
        if t in headers:
            hp, hi = headers[t]
            if entry_line:
                edits.setdefault(hp, []).append((hi, "after", entry_line))
            for d in own:
                edits.setdefault(d.path, []).append((d.lineno, "delete", None))
        else:
            first = own[0]
            for d in own[1:]:
                edits.setdefault(d.path, []).append((d.lineno, "delete", None))
            if entry_line:
                edits.setdefault(first.path, []).append((first.lineno, "block", f"CAPABILITIES({t})\n{entry_line}"))
            else:
                edits.setdefault(first.path, []).append((first.lineno, "delete", None))
        converted += len(own)
    # residue check: a new block followed by an indented line
    for p, items in list(edits.items()):
        lines = p.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n").split("\n")
        for (i, kind, payload) in items:
            if kind != "block":
                continue
            j = i + 1
            while j < len(lines) and lines[j].strip() == "":
                j += 1
            nxt = lines[j] if j < len(lines) else ""
            if nxt[:1] in ("\t", " ") and not nxt.strip().startswith("//"):
                residue.append(("indented_next", p, i + 1, nxt.strip()[:60]))
    for code, p, n, what in residue:
        print(f"RESIDUE {code} {p}:{n} {what}")
    if check:
        print(f"{converted} declaration(s) would convert in {len(edits)} file(s); {len(residue)} residue")
        return 1 if converted else 0
    if any(r[0] == "indented_next" for r in residue):
        print("refusing: indented_next residue")
        return 1
    for p, items in edits.items():
        raw = p.read_bytes().decode("utf-8")
        crlf = "\r\n" in raw
        lines = raw.replace("\r\n", "\n").split("\n")
        after = {}
        delete = set()
        block = {}
        for (i, kind, payload) in items:
            if kind == "after":
                after.setdefault(i, []).append(payload)
            elif kind == "delete":
                delete.add(i)
            else:
                block[i] = payload
        out = []
        for i, line in enumerate(lines):
            if i in block:
                out.append(block[i])
            elif i not in delete:
                out.append(line)
            for e in after.get(i, []):
                out.append(e)
        text = "\n".join(out)
        p.write_bytes((text.replace("\n", "\r\n") if crlf else text).encode("utf-8"))
    print(f"{converted} declaration(s) converted in {len(edits)} file(s); {len(residue)} residue")
    return 0


if __name__ == "__main__":
    sys.exit(main())
