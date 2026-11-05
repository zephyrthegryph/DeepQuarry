#!/usr/bin/env python3
"""The sites the sparse_state codemod leaves as residue (a receiver it cannot type, several calls on a line): the same rewrite, by text.

  python3 tools/analyze/codemods/sparse_state/hand.py FILE...

It applies the codemod's rules to every sparse_get/_or/_set/_or call of a wave-1 slot in the named files, whatever the receiver; the compiler and the tests
check the receivers afterwards. A call it cannot convert (the value is used, a get with no default on a slot that has one, a default that differs) is
printed and left alone.
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from census import split_args, ROOT

HERE = os.path.dirname(os.path.abspath(__file__))
rows = [l.split("\t") for l in open(os.path.join(HERE, "groups.tsv"), encoding="utf8").read().split("\n") if l]
SLOT = {r[1]: r for r in rows if r[5] == "1"}
CALL = re.compile(r"\b(sparse_get_or|sparse_set_or|sparse_get|sparse_set)\(")
norm = lambda s: re.sub(r"\s+", "", s)


def convert(text, rel):
    out, pos, left = [], 0, []
    while True:
        m = CALL.search(text, pos)
        if not m:
            out.append(text[pos:])
            break
        func = m.group(1)
        args, end = split_args(text, m.end() - 1)
        # the inner calls first: convert the arguments, then this call
        inner = [convert(a, rel)[0] for a in args]
        row = SLOT.get(args[1]) if len(args) > 1 else None
        want = {"sparse_get": 2, "sparse_get_or": 3, "sparse_set": 3, "sparse_set_or": 4}[func]
        if not row or len(args) != want:
            out.append(text[pos:end + 1]); pos = end + 1; continue
        holder, slot, feature, kind, default, wave = row
        recv = inner[0]
        new = None
        if func.startswith("sparse_get"):
            if func == "sparse_get_or" and norm(args[2]) != norm(default):
                left.append((rel, "default_mismatch", text[m.start():end + 1][:100]))
            elif func == "sparse_get" and default:
                left.append((rel, "get_default_differs", text[m.start():end + 1][:100]))
            else:
                new = f"STATE_GET({recv}, {feature}, {slot})"
        else:
            line_start = text.rfind("\n", 0, m.start()) + 1
            stmt = text[line_start:m.start()].strip() in ("", "else")
            after = text[end + 1:end + 3]
            if not (stmt or text[line_start:m.start()].rstrip().endswith(")")) or not re.match(r"[ \t]*(//.*)?(\r?\n|$)", text[end + 1:end + 200]):
                left.append((rel, "value_used", text[m.start():end + 1][:100]))
            elif func == "sparse_set_or" and norm(args[3]) != norm(default) and not (not default and norm(args[3]) == "null"):
                left.append((rel, "default_mismatch", text[m.start():end + 1][:100]))
            elif norm(inner[2]) == "null":
                new = f"if({recv}.{feature}) {recv}.{feature}.set_{slot}({default or 'null'})"
            else:
                new = f"{feature}_of({recv}).set_{slot}({inner[2]})"
        out.append(text[pos:m.start()])
        out.append(new if new else text[m.start():end + 1])
        pos = end + 1
    return "".join(out), left


if __name__ == "__main__":
    for rel in sys.argv[1:]:
        p = os.path.join(ROOT, rel)
        text = open(p, encoding="utf8", newline="").read()
        new, left = convert(text, rel)
        if new != text:
            open(p, "w", encoding="utf8", newline="").write(new)
            print("converted", rel)
        for l in left:
            print("LEFT", *l)
