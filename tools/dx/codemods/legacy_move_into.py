#!/usr/bin/env python3
"""thing.move_into(holder, slot_id, actor) -> move_into(holder, slot_id, thing, actor) (doc 17, the one transfer verb).

    X.move_into(H)            -> move_into(H, null, X)
    X.move_into(H, S, A)      -> move_into(H, S, X, A)
    X?.move_into(H, S)        -> move_into(H, S, X)

A bare move_into(...) inside an /atom/movable proc (the receiver is src) is not rewritten: list it with --bare.

    python tools/dx/codemods/legacy_move_into.py [--dry-run] [paths...]   (default: code/)
"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from own_transfers_survey import split_args  # noqa: E402

CALL = re.compile(r"(\?)?\.move_into\(")
SKIP_PARTS = ("code/engine/declare/transfer.dm",)


def receiver_start(text, end):
    """Index where the receiver expression that ends at `end` starts."""
    i = end
    depth = 0
    while i > 0:
        c = text[i - 1]
        if c in ")]":
            depth += 1
        elif c in "([":
            if depth == 0:
                break
            depth -= 1
        elif depth == 0 and not (c.isalnum() or c in "_.?:"):
            break
        i -= 1
    return i


def convert(text, path, report):
    out = []
    pos = 0
    for m in CALL.finditer(text):
        dot = m.start()
        if dot < pos:
            continue
        recv_start = receiver_start(text, dot)
        recv = text[recv_start:dot]
        if not recv or recv.endswith(":"):
            report.append(f"RESIDUE {path}:{text.count(chr(10), 0, dot) + 1}: receiver '{recv}'")
            continue
        i = m.end()
        depth = 1
        quote = None
        while i < len(text) and depth:
            c = text[i]
            if quote:
                if c == chr(92):
                    i += 1
                elif c == quote:
                    quote = None
            elif c in "\"'":
                quote = c
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            i += 1
        body = text[m.end():i - 1]
        args = [a.strip() for a in split_args(body)]
        if not 1 <= len(args) <= 3 or any(re.match(r"\w+\s*=[^=]", a) for a in args):
            report.append(f"RESIDUE {path}:{text.count(chr(10), 0, dot) + 1}: args '{body}'")
            continue
        holder = args[0]
        slot = args[1] if len(args) > 1 else "null"
        new = [holder, slot, recv] + args[2:]
        out.append(text[pos:recv_start])
        out.append("move_into(" + ", ".join(new) + ")")
        pos = i
    out.append(text[pos:])
    return "".join(out)


def main(argv):
    dry = "--dry-run" in argv
    roots = [pathlib.Path(a) for a in argv if not a.startswith("--")] or [pathlib.Path("code")]
    files = []
    for r in roots:
        files += [r] if r.is_file() else sorted(r.rglob("*.dm"))
    report = []
    changed = 0
    for p in files:
        norm = str(p).replace("\\", "/")
        if any(norm.endswith(s) for s in SKIP_PARTS):
            continue
        raw = p.read_bytes().decode("utf-8", errors="replace")
        text = raw.replace("\r\n", "\n")
        new = convert(text, norm, report)
        if new != text:
            changed += 1
            if not dry:
                crlf = "\r\n" in raw
                p.write_bytes((new.replace("\n", "\r\n") if crlf else new).encode("utf-8"))
    print("\n".join(report))
    print(f"{changed} file(s) {'would change' if dry else 'changed'}")


if __name__ == "__main__":
    main(sys.argv[1:])
