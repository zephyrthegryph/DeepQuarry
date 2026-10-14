#!/usr/bin/env python3
"""own_put(H, V, K, X) -> rel_add(H, V, X, K), declaring the keyed var owns_many on the way (doc 17: own_put is rel_add(key =)).

The analyze own_add codemod declares an undeclared var owns_many and renames own_add to rel_add; it does not know own_put. So:

    python tools/dx/codemods/own_puts.py --mark       own_put(H, V, K, X)  ->  own_add(H, V, X) /*MP:n*/
    analyze codemod own_add --apply                      declares, renames (owns_many in the holder type's CAPABILITIES block)
    python tools/dx/codemods/own_puts.py --finish     rel_add(H, V, X) /*MP:n*/  ->  rel_add(H, V, X, K)

Unit tests and benchmarks (which the codemod skips) are converted directly. A `rel_add(.., K)` on a var nobody declared would not reach the
owned-var accessor, so check `analyze gen --check` and the unit tests after.
"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from own_transfers_survey import calls, split_args  # noqa: E402

MARKS = []
MARK_RE = re.compile(r"\s*/\*MP:(\d+)\*/")
SKIP = ("code/datums/ownership/",)
DIRECT = ("code/modules/unit_tests/", "code/modules/benchmarks/", "code/tests/")


def mark(text, path):
    out, pos = [], 0
    for start, name, a, b, body in calls(text, ["own_put"]):
        if start < pos:
            continue
        line_start = text.rfind("\n", 0, start) + 1
        if text[line_start:start].lstrip().startswith("//"):
            continue
        args = [x.strip() for x in split_args(body)]
        if len(args) != 4 or any(re.match(r"\w+\s*=[^=]", x) for x in args):
            print(f"RESIDUE {path}:{text.count(chr(10), 0, start) + 1}: {body}")
            continue
        holder, var, key, value = args
        final = f"rel_add({holder}, {var}, {value}, {key})"
        out.append(text[pos:start])
        if path.startswith(DIRECT):
            out.append(final)
        else:
            MARKS.append(final)
            out.append(f"own_add({holder}, {var}, {value}) /*MP:{len(MARKS) - 1}*/")
        pos = b + 1
    out.append(text[pos:])
    return "".join(out)


def finish(text):
    out, pos = [], 0
    for start, name, a, b, body in calls(text, ["own_add", "rel_add"]):
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


def main(argv):
    marks_file = pathlib.Path("data/own_puts_marks.json")
    fin = "--finish" in argv
    if fin:
        MARKS.extend(json.loads(marks_file.read_text()))
    changed = 0
    for p in sorted(pathlib.Path("code").rglob("*.dm")):
        norm = str(p).replace("\\", "/")
        if norm.startswith(SKIP):
            continue
        raw = p.read_bytes().decode("utf-8", errors="replace")
        text = raw.replace("\r\n", "\n")
        new = finish(text) if fin else mark(text, norm)
        if new != text:
            changed += 1
            p.write_bytes((new.replace("\n", "\r\n") if "\r\n" in raw else new).encode("utf-8"))
    if not fin:
        marks_file.parent.mkdir(exist_ok=True)
        marks_file.write_text(json.dumps(MARKS))
    print(f"{changed} file(s) changed")


if __name__ == "__main__":
    main(sys.argv[1:])
