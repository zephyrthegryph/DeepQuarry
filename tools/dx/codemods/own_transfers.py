#!/usr/bin/env python3
"""own_set / own_add / own_put with transfer arguments -> move_into() (doc 17: a call that passed into= or user= placed an atom).

    own_set(H, V, X, user = U, into = TRUE)      -> move_into(H, V, X, U)
    own_add(H, V, X, user = U, slot = S)         -> move_into(H, V, X, U, ledger_slot = S)
    own_put(H, V, K, X, user = U)                -> move_into(H, V, X, U, key = K)
    own_set(H, V, X, into = FALSE)               -> rel_set(H, V, X)         (no move: the value stays where it is)
    own_add(H, V, X, into = FALSE)               -> rel_add(H, V, X)
    own_put(H, V, K, X, into = FALSE)            -> rel_add(H, V, X, K)

move_into() returns TRUE or FALSE, not the value: a call whose result is used any other way is printed as a CHECK line.
A call with into = FALSE and a user or slot is left alone (printed as RESIDUE).

    python tools/dx/codemods/own_transfers.py [--dry-run] [paths...]   (default: code/)
"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from own_transfers_survey import calls, split_args  # noqa: E402

NAMED = re.compile(r"^\s*(\w+)\s*=(?!=)\s*(.*?)\s*$", re.S)
SKIP = ("code/datums/ownership/",)
OLD = {"own_set": 3, "own_add": 3, "own_put": 4}
TRANSFER_ARGS = {"user", "into", "slot", "force", "log"}
# Where a bare boolean use of the result is fine.
BOOL_BEFORE = re.compile(r"(if\s*\(\s*!?\s*|while\s*\(\s*!?\s*|&&\s*!?\s*|\|\|\s*!?\s*|\(!\s*|^\s*|return\s+|\.\s*=\s*)$")


MARKS = []  # the final text of each mark, in --mark mode
MARK_RE = re.compile(r"\s*/\*MI:(\d+)\*/")


def finish(text):
    """--finish: `own_set(...) /*MI:n*/` (or the rel_set the declaring codemod made of it) becomes the n-th final text."""
    out, pos = [], 0
    for start, name, a, b, body in sorted(calls(text, ["own_set", "own_add", "own_put", "rel_set", "rel_add"])):
        if start < pos:
            continue
        m = MARK_RE.match(text, b + 1)
        if not m:
            continue
        out.append(text[pos:start])
        out.append(MARKS[int(m.group(1))])
        pos = m.end()
    out.append(text[pos:])
    return "".join(out)


def convert(text, path, report, mark=False):
    out = []
    pos = 0
    for start, name, a, b, body in sorted(calls(text, list(OLD))):
        if start < pos:
            continue
        args = split_args(body)
        positional = [x.strip() for x in args if not NAMED.match(x)]
        named = {}
        for x in args:
            m = NAMED.match(x)
            if m:
                named[m.group(1)] = m.group(2)
        if not (named.keys() & TRANSFER_ARGS) or len(positional) != OLD[name] or set(named) - TRANSFER_ARGS:
            continue
        line = text.count("\n", 0, start) + 1
        holder, var = positional[0], positional[1]
        key = positional[2] if name == "own_put" else None
        value = positional[-1]
        into = named.get("into")
        if into in ("FALSE", "0"):
            if named.keys() & {"user", "slot", "force", "log"}:
                report.append(f"RESIDUE {path}:{line}: into = FALSE with {sorted(named.keys() - {'into'})}")
                continue
            if name == "own_set":
                new = f"rel_set({holder}, {var}, {value})"
            elif name == "own_add":
                new = f"rel_add({holder}, {var}, {value})"
            else:
                new = f"rel_add({holder}, {var}, {value}, {key})"
        else:
            parts = [holder, var, value]
            if "user" in named:
                parts.append(named["user"])
            extra = []
            if "slot" in named:
                extra.append(f"ledger_slot = {named['slot']}")
            if "force" in named:
                extra.append(f"force = {named['force']}")
            if "log" in named:
                extra.append(f"log = {named['log']}")
            if key is not None:
                extra.append(f"key = {key}")
            new = "move_into(" + ", ".join(parts + extra) + ")"
            before = text[max(0, text.rfind("\n", 0, start) + 1):start]
            if not BOOL_BEFORE.search(before):
                report.append(f"CHECK {path}:{line}: result used: {before.strip()}{new}")
        out.append(text[pos:start])
        if mark and "unit_tests" not in path and name != "own_put":
            # Stage 1: back to the plain call the declaring codemod (analyze codemod own_set / own_add) knows, tagged.
            MARKS.append(new)
            out.append(f"{name}({holder}, {var}, {value}) /*MI:{len(MARKS) - 1}*/")
        else:
            out.append(new)
        pos = b + 1
    out.append(text[pos:])
    return "".join(out)


def main(argv):
    dry = "--dry-run" in argv
    mark = "--mark" in argv
    fin = "--finish" in argv
    marks_file = pathlib.Path("data/own_transfers_marks.json")
    if fin:
        import json

        MARKS.extend(json.loads(marks_file.read_text()))
    roots = [pathlib.Path(a) for a in argv if not a.startswith("--")] or [pathlib.Path("code")]
    files = []
    for r in roots:
        files += [r] if r.is_file() else sorted(r.rglob("*.dm"))
    report = []
    changed = 0
    for p in files:
        raw = p.read_bytes().decode("utf-8", errors="replace")
        text = raw.replace("\r\n", "\n")
        norm = str(p).replace("\\", "/")
        if norm.startswith(SKIP) or "/code/datums/ownership/" in "/" + norm or norm.startswith("code/engine/declare/"):
            continue
        new = finish(text) if fin else convert(text, norm, report, mark)
        if new != text:
            changed += 1
            if not dry:
                crlf = "\r\n" in raw
                p.write_bytes((new.replace("\n", "\r\n") if crlf else new).encode("utf-8"))
    if mark and not dry:
        import json

        marks_file.parent.mkdir(exist_ok=True)
        marks_file.write_text(json.dumps(MARKS))
    print("\n".join(report))
    print(f"{changed} file(s) {'would change' if dry else 'changed'}")


if __name__ == "__main__":
    main(sys.argv[1:])
