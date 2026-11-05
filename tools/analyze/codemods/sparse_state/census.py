#!/usr/bin/env python3
"""Census of sparse() slots for the sparse_state codemod: declarations, and the defaults their call sites give.

  python3 tools/analyze/codemods/sparse_state/census.py          prints slots whose call sites disagree on the default
  python3 tools/analyze/codemods/sparse_state/census.py --json   the whole census as JSON
"""
import json, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
DECL = re.compile(r"^\s*sparse\((/[\w/]+),\s*(\w+)(?:,\s*type\s*=\s*([^)]*))?\)")
CALL = re.compile(r"\b(sparse_get_or|sparse_set_or|sparse_get|sparse_set|sparse_ref_set|sparse_ref|sparse_has)\(")


def files():
    out = subprocess.run(["git", "ls-files", "code/*.dm"], cwd=ROOT, capture_output=True, text=True, encoding="utf8").stdout
    return [f for f in out.split("\n") if f]


def split_args(text, start):
    """Arguments of the call whose '(' is at text[start]; returns (args, end)."""
    depth, i, cur, args, in_str = 0, start, "", [], False
    while i < len(text):
        c = text[i]
        if in_str:
            cur += c
            if c == "\\":
                i += 1
                cur += text[i]
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
            cur += c
        elif c in "([{":
            depth += 1
            if depth > 1:
                cur += c
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                args.append(cur.strip())
                return args, i
            cur += c
        elif c == "," and depth == 1:
            args.append(cur.strip())
            cur = ""
        else:
            cur += c
        i += 1
    return args, i


def census():
    slots = {}
    for rel in files():
        text = open(os.path.join(ROOT, rel), encoding="utf8", errors="replace").read()
        prev_comment = []
        for n, line in enumerate(text.split("\n"), 1):
            m = DECL.match(line)
            if m:
                slots[(m.group(1), m.group(2))] = {"holder": m.group(1), "slot": m.group(2), "kind": (m.group(3) or "").strip(), "file": rel, "line": n, "doc": " ".join(prev_comment), "defaults": {}, "calls": {}}
                prev_comment = []
            elif line.strip().startswith("//"):
                prev_comment.append(line.strip()[2:].strip())
            else:
                prev_comment = []
    by_name = {}
    for (h, s), v in slots.items():
        by_name.setdefault(s, []).append(v)
    for rel in files():
        if rel.startswith(("code/defines/", "code/engine/")):
            continue
        text = open(os.path.join(ROOT, rel), encoding="utf8", errors="replace").read()
        for m in CALL.finditer(text):
            func = m.group(1)
            args, _ = split_args(text, m.end() - 1)
            if len(args) < 2:
                continue
            name = args[1]
            for v in by_name.get(name, []):
                v["calls"][func] = v["calls"].get(func, 0) + 1
                d = None
                if func == "sparse_get_or" and len(args) >= 3:
                    d = args[2]
                if func == "sparse_set_or" and len(args) >= 4:
                    d = args[3]
                if d is not None:
                    v["defaults"].setdefault(d, []).append(f"{rel}")
    return list(slots.values())


if __name__ == "__main__":
    data = census()
    if "--json" in sys.argv:
        print(json.dumps(data, indent=1))
    else:
        bad = [v for v in data if len(v["defaults"]) > 1]
        print(f"{len(data)} slots, {sum(1 for v in data if v['defaults'])} with a default at some call site, {len(bad)} with disagreeing defaults")
        for v in bad:
            print(v["holder"], v["slot"], {k: len(x) for k, x in v["defaults"].items()})
        print("unused slots:", [v["slot"] for v in data if not v["calls"]])
