#!/usr/bin/env python3
r"""Merges repeated extend() entries of one CAPABILITIES block: one `extend(key, ...)` line per key, carrying all its parts.

    extend("construction.undo:apc_secured", when(COVER_OPEN))
    extend("construction.undo:apc_secured", priority(above("panel.open")))
        ->  extend("construction.undo:apc_secured", when(COVER_OPEN), priority(above("panel.open")))

The merged entry sits where the key first appears; later ones are deleted. A key is left alone (and reported) when the merge would give one
entry two `when(...)`, two `priority(...)` or two `drop =` arguments. A second run changes nothing.

    python tools/dx/codemods/extend_merge.py [--check] [paths...]
"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import re
import subprocess
import sys

BS = chr(92)
HEAD = re.compile(r"^(CAPABILITIES|STATE_GRAPH)\(")
ENTRY_EXTEND = re.compile(r'^\textend\(')


def split_top(s):
    out, depth, cur, in_str, i = [], 0, "", False, 0
    while i < len(s):
        c = s[i]
        if in_str:
            cur += c
            if c == BS and i + 1 < len(s):
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


def entries_of(lines, lo, hi):
    """(start, end_exclusive, text) of each entry statement between lines lo..hi: an entry starts at one tab and runs to the line that balances."""
    out = []
    i = lo
    while i < hi:
        line = lines[i]
        if line.strip() == "" or not line.startswith("\t") or line.startswith("\t\t") or line.lstrip().startswith("//"):
            i += 1
            continue
        j = i
        depth = 0
        in_str = False
        text = ""
        while j < hi:
            l = lines[j]
            text += l if j == i else "\n" + l
            for k, c in enumerate(l):
                if in_str:
                    if c == BS:
                        continue
                    if c == '"':
                        in_str = False
                elif c == '"':
                    in_str = True
                elif c == "/" and l[k : k + 2] == "//":
                    break
                elif c in "([{":
                    depth += 1
                elif c in ")]}":
                    depth -= 1
            j += 1
            if depth <= 0:
                break
        out.append((i, j, text))
        i = j
    return out


def kind_of(part):
    m = re.match(r"^(when|priority|drop)\b", part)
    return m.group(1) if m else None


def convert(text):
    nl = "\r\n" if "\r\n" in text else "\n"
    lines = text.replace("\r\n", "\n").split("\n")
    skipped = []
    merged = 0
    i = 0
    while i < len(lines):
        if not HEAD.match(lines[i]):
            i += 1
            continue
        j = i + 1
        while j < len(lines) and (lines[j] == "" or lines[j][0] in " \t"):
            j += 1
        ents = entries_of(lines, i + 1, j)
        groups = {}
        for (s, e, t) in ents:
            if not ENTRY_EXTEND.match(t.split("\n")[0]):
                continue
            body = t.strip()
            inner = body[len("extend(") : body.rindex(")")]
            parts = split_top(inner.replace("\n", " ").replace("\t", " "))
            parts = [re.sub(r"\s+", " ", p) for p in parts]
            if not parts:
                continue
            groups.setdefault(parts[0], []).append((s, e, parts[1:], t))
        delete = set()
        replace = {}
        for key, occ in groups.items():
            if len(occ) < 2:
                continue
            allparts = [p for (_, _, ps, _) in occ for p in ps]
            kinds = [k for k in (kind_of(p) if not p.startswith("drop") else "drop" for p in allparts) if k]
            if len(kinds) != len(set(kinds)):
                skipped.append(key)
                continue
            # Named arguments (drop = x) go last.
            pos = [p for p in allparts if not re.match(r"^drop\s*=", p)]
            named = [p for p in allparts if re.match(r"^drop\s*=", p)]
            new = "\textend(" + ", ".join([key] + pos + named) + ")"
            first = occ[0]
            replace[first[0]] = (first[1], new)
            for (s, e, _, _) in occ[1:]:
                delete.update(range(s, e))
            merged += len(occ) - 1
        if replace or delete:
            out = []
            k = 0
            while k < len(lines):
                if k in replace:
                    end, new = replace[k]
                    out.append(new)
                    k = end
                    continue
                if k in delete:
                    k += 1
                    continue
                out.append(lines[k])
                k += 1
            # Lines before the block are untouched, so indices after it shift: rebuild and rescan from the block start.
            lines = out
            j = i + 1
            while j < len(lines) and (lines[j] == "" or lines[j][0] in " \t"):
                j += 1
        i = j
    return nl.join(lines), merged, skipped


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check = "--check" in sys.argv
    files = args or subprocess.check_output(["git", "ls-files", "-z", "*.dm"]).decode("utf-8", "surrogateescape").split("\0")
    changed = sites = 0
    for f in files:
        if not f or f.startswith("tools/analyze/fixtures/"):
            continue
        with open(f, encoding="utf-8", errors="surrogateescape", newline="") as fh:
            text = fh.read()
        if "extend(" not in text:
            continue
        new, n, skipped = convert(text)
        for k in skipped:
            print(f"extend_merge: {f}: {k} left alone (two when/priority/drop)")
        if n and new != text:
            changed += 1
            sites += n
            if not check:
                with open(f, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
                    fh.write(new)
    print(f"extend_merge: {sites} extends merged in {changed} files{' (check)' if check else ''}")
    return 1 if (check and changed) else 0


if __name__ == "__main__":
    sys.exit(main())
