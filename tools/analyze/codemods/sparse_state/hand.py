#!/usr/bin/env python3
"""The sites the sparse_state codemod leaves as residue (a receiver it cannot type, several calls on a line): the same rewrite, by text.

  python3 tools/analyze/codemods/sparse_state/hand.py [--wave N] FILE...      convert wave N (default 1) sparse_get/_or/_set/_or calls
  python3 tools/analyze/codemods/sparse_state/hand.py --retrofit FILE...      wave-1 writes `x_of(R).set_f(v)` and `if(R.x) R.x.set_f(d)` -> STATE_SET(R, x, f, v)

The rules are the codemod's: a read is STATE_GET (a mob holder) or STATE_PEEK (a table holder), a write is STATE_SET, a null write writes the field's default.
The receiver is whatever the text says; the compiler and the tests check it afterwards. A call it cannot convert (the value is used, a get with no default on a
slot that has one, a default that differs) is printed and left alone.
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from census import split_args, ROOT

HERE = os.path.dirname(os.path.abspath(__file__))
rows = [l.split("\t") for l in open(os.path.join(HERE, "groups.tsv"), encoding="utf8").read().split("\n") if l]
CALL = re.compile(r"\b(sparse_get_or|sparse_set_or|sparse_get|sparse_set|sparse_has)\(")
norm = lambda s: re.sub(r"\s+", "", s)


def convert(text, rel, slots):
    out, pos, left = [], 0, []
    while True:
        m = CALL.search(text, pos)
        if not m:
            out.append(text[pos:])
            break
        func = m.group(1)
        args, end = split_args(text, m.end() - 1)
        inner = [convert(a, rel, slots)[0] for a in args]  # the inner calls first
        row = slots.get(args[1]) if len(args) > 1 else None
        want = {"sparse_has": 2, "sparse_get": 2, "sparse_get_or": 3, "sparse_set": 3, "sparse_set_or": 4}[func]
        if not row or len(args) != want:
            out.append(text[pos:end + 1]); pos = end + 1; continue
        holder, slot, feature, kind, default, wave = row
        table = not holder.startswith("/mob")
        recv = inner[0]
        new = None
        if func == "sparse_has":
            read = f"{'STATE_PEEK' if table else 'STATE_GET'}({recv}, {feature}, {slot})"
            new = f"({read} != {default})" if default else f"(!isnull({read}))"
        elif func.startswith("sparse_get"):
            if func == "sparse_get_or" and norm(args[2]) != norm(default):
                left.append((rel, "default_mismatch", text[m.start():end + 1][:100]))
            elif func == "sparse_get" and default:
                left.append((rel, "get_default_differs", text[m.start():end + 1][:100]))
            else:
                new = f"{'STATE_PEEK' if table else 'STATE_GET'}({recv}, {feature}, {slot})"
        else:
            line_start = text.rfind("\n", 0, m.start()) + 1
            stmt = text[line_start:m.start()].strip() in ("", "else") or text[line_start:m.start()].rstrip().endswith(")")
            if not stmt or not re.match(r"[ \t]*(//.*)?(\r?\n|$)", text[end + 1:end + 200]):
                left.append((rel, "value_used", text[m.start():end + 1][:100]))
            elif func == "sparse_set_or" and norm(args[3]) != norm(default) and not (not default and norm(args[3]) == "null"):
                left.append((rel, "default_mismatch", text[m.start():end + 1][:100]))
            else:
                value = inner[2]
                if norm(value) == "null" and default:
                    value = default
                new = f"STATE_SET({recv}, {feature}, {slot}, {value})"
        out.append(text[pos:m.start()])
        out.append(new if new else text[m.start():end + 1])
        pos = end + 1
    return "".join(out), left


def retrofit(text, features):
    """`feature_of(R).set_field(v)` and `if(R.feature) R.feature.set_field(d)` -> STATE_SET(R, feature, field, v)."""
    pat = re.compile(r"\b(" + "|".join(sorted(features, key=len, reverse=True)) + r")_of\(")
    out, pos = [], 0
    while True:
        m = pat.search(text, pos)
        if not m:
            out.append(text[pos:])
            break
        feature = m.group(1)
        args, end = split_args(text, m.end() - 1)
        after = re.match(r"\.set_(\w+)\(", text[end + 1:])
        if len(args) != 1 or not after:
            out.append(text[pos:end + 1]); pos = end + 1; continue
        wstart = end + 1 + after.end() - 1
        wargs, wend = split_args(text, wstart)
        if len(wargs) != 1:
            out.append(text[pos:wend + 1]); pos = wend + 1; continue
        out.append(text[pos:m.start()])
        out.append(f"STATE_SET({args[0]}, {feature}, {after.group(1)}, {wargs[0]})")
        pos = wend + 1
    text = "".join(out)
    reset = re.compile(r"if\(([\w.]+)\.(" + "|".join(sorted(features, key=len, reverse=True)) + r")\) \1\.\2\.set_(\w+)\(")
    while True:
        m = reset.search(text)
        if not m:
            break
        args, end = split_args(text, m.end() - 1)
        text = text[:m.start()] + f"STATE_SET({m.group(1)}, {m.group(2)}, {m.group(3)}, {args[0]})" + text[end + 1:]
    return text


if __name__ == "__main__":
    argv = sys.argv[1:]
    wave = "1"
    if "--wave" in argv:
        i = argv.index("--wave")
        wave = argv[i + 1]
        del argv[i:i + 2]
    do_retrofit = "--retrofit" in argv
    argv = [a for a in argv if a != "--retrofit"]
    slots = {r[1]: r for r in rows if r[5] == wave}
    features = sorted({r[2] for r in rows if r[5] == "1"})
    for rel in argv:
        p = os.path.join(ROOT, rel)
        text = open(p, encoding="utf8", newline="").read()
        if do_retrofit:
            new, left = retrofit(text, features), []
        else:
            new, left = convert(text, rel, slots)
        if new != text:
            open(p, "w", encoding="utf8", newline="").write(new)
            print("converted", rel)
        for l in left:
            print("LEFT", *l)
