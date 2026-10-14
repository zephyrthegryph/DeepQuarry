#!/usr/bin/env python3
"""Factor the op snapshot pins: inherited rows once per (base type, actor, held item), per-type deltas.

The op pins (code/modules/unit_tests/snapshots/{pins,i7_*,*_1008}/, rows like
`human|/obj/item/tool/crowbar menu: Deconstruct`) repeat the rows every type inherits ("Move To Top",
"Toggle Digestable", ...) in every file. Factored, a type file names a base block instead:

    @obj.item human|none          the rows of group `human|none` recorded in snapshots/op_bases/obj.item.txt
    -menu: Pick up                ...minus this row (`<group> menu: Pick up`)
    +2 menu: Use                  ...plus this row, at index 2 of the group
    keys: activate, ...           any other line is a literal row

A group is the run of rows sharing the text before the first space when that text holds a `|`
(`actor|held item`). The base files (snapshots/op_bases/<base type with / as .>.txt) are plain rows.
Expanding a factored file gives back exactly the rows it was made from, in order
(code/modules/unit_tests/dq_snapshot_files.dm reads both forms, so an unfactored file stays valid).

    python tools/dq_pin_factor.py                 # re-encode every op pin dir against the current bases (adds/refreshes
                                                  # a base block only when its users moved away from it); run by
                                                  # dq_focused_test.sh after a --bless or a recording run
    python tools/dq_pin_factor.py --rebase        # derive every base block from scratch
    python tools/dq_pin_factor.py --check         # exit 1 when a file is not in the canonical factored form
    python tools/dq_pin_factor.py --expand DIR    # write every op pin dir fully expanded under DIR/<dir>/ (the old format)
"""
import collections
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "code", "modules", "unit_tests", "snapshots")
BASES = "op_bases"
ACTORS = ("human|", "robot|", "ai|", "ghost|")


def group_key(row):
    sp = row.find(" ")
    if sp <= 0:
        return None
    key = row[:sp]
    return key if "|" in key else None


def read_rows(path):
    with open(path, encoding="utf-8", newline="") as f:
        text = f.read()
    return [l.replace("\r", "") for l in text.split("\n") if l.replace("\r", "")]


def type_of(name):
    return "/" + name[:-4].replace(".", "/")


def dotted(t):
    return t[1:].replace("/", ".")


def ancestors(t):
    """Strict path prefixes of a type, nearest first."""
    parts = t.split("/")[1:]
    return ["/" + "/".join(parts[:i]) for i in range(len(parts) - 1, 0, -1)]


def op_dirs():
    out = []
    for d in sorted(os.listdir(ROOT)):
        p = os.path.join(ROOT, d)
        if d == BASES or not os.path.isdir(p):
            continue
        for n in os.listdir(p):
            if not n.endswith(".txt"):
                continue
            with open(os.path.join(p, n), encoding="utf-8") as f:
                head = f.read(4096)
            if head.startswith("@") or any(head.startswith(a) for a in ACTORS) or "\n@" in head:
                out.append(d)
                break
    return out


class Bases:
    def __init__(self):
        self.blocks = {}  # (base type, key) -> tuple(rows)
        self.dir = os.path.join(ROOT, BASES)
        if os.path.isdir(self.dir):
            for n in os.listdir(self.dir):
                if n.endswith(".txt"):
                    for r in read_rows(os.path.join(self.dir, n)):
                        k = group_key(r)
                        b = (type_of(n), k)
                        self.blocks[b] = self.blocks.get(b, ()) + (r,)

    def nearest(self, t, key):
        for a in ancestors(t):
            if (a, key) in self.blocks:
                return a
        return None

    def write(self):
        os.makedirs(self.dir, exist_ok=True)
        by_base = collections.defaultdict(list)
        for (b, k), rows in self.blocks.items():
            by_base[b].append((k, rows))
        want = set()
        for b, groups in by_base.items():
            name = dotted(b) + ".txt"
            want.add(name)
            text = "".join(r + "\n" for _, rows in sorted(groups) for r in rows)
            write_if_changed(os.path.join(self.dir, name), text)
        for n in os.listdir(self.dir):
            if n.endswith(".txt") and n not in want:
                os.remove(os.path.join(self.dir, n))


def expand(lines, bases, where):
    rows, cur, cur_key, adds = [], None, None, []

    def flush():
        nonlocal cur, adds
        if cur is not None:
            for idx, r in sorted(adds):
                cur.insert(idx, r)
            rows.extend(cur)
        cur, adds = None, []

    for l in lines:
        if l.startswith("@"):
            flush()
            base, cur_key = l[1:].split(" ", 1)
            block = bases.blocks.get(("/" + base.replace(".", "/"), cur_key))
            if block is None:
                raise SystemExit(f"{where}: no base block {l}")
            cur = list(block)
        elif l.startswith("-") and cur is not None:
            r = cur_key + " " + l[1:]
            if r not in cur:
                raise SystemExit(f"{where}: {l} is not in its base block")
            cur.remove(r)
        elif l.startswith("+") and cur is not None:
            idx, rest = l[1:].split(" ", 1)
            adds.append((int(idx), cur_key + " " + rest))
        else:
            flush()
            rows.append(l)
    flush()
    return rows


def runs(rows):
    """Maximal runs of rows sharing a group key: [(key or None, [rows])]."""
    out = []
    for r in rows:
        k = group_key(r)
        if k is not None and out and out[-1][0] == k:
            out[-1][1].append(r)
        else:
            out.append((k, [r]))
    return out


def delta(block, run):
    """Delta lines turning `block` into `run`, or None when the kept rows changed order."""
    run_set, block_set = set(run), set(block)
    kept = [r for r in block if r in run_set]
    if [r for r in run if r in block_set] != kept or len(run_set) != len(run) or len(block_set) != len(block):
        return None
    key = group_key(run[0])
    lines = ["-" + r[len(key) + 1:] for r in block if r not in run_set]
    lines += [f"+{i} {r[len(key) + 1:]}" for i, r in enumerate(run) if r not in block_set]
    return lines


def encode(t, rows, bases):
    keys = collections.Counter(k for k, _ in runs(rows) if k)
    out = []
    for k, run in runs(rows):
        base = bases.nearest(t, k) if k and keys[k] == 1 else None
        d = delta(bases.blocks[(base, k)], run) if base else None
        # A run that keeps a base row refers to the block (inherited rows are written once, in the base), unless the
        # delta is longer than the run itself.
        if d is not None and len(d) <= len(run) and len(d) < len(run) + len(bases.blocks[(base, k)]):
            out.append(f"@{dotted(base)} {k}")
            out.extend(d)
        else:
            for r in run:
                if r.startswith(("@", "-", "+")):
                    raise SystemExit(f"{t}: a row starts with @, - or +, which the factored form reserves: {r}")
            out.extend(run)
    return out


def write_if_changed(path, text):
    try:
        with open(path, encoding="utf-8", newline="") as f:
            if f.read() == text:
                return False
    except FileNotFoundError:
        pass
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    return True


def load_all(bases):
    """{(dir, file name): expanded rows}"""
    data = {}
    for d in op_dirs():
        p = os.path.join(ROOT, d)
        for n in sorted(os.listdir(p)):
            if n.endswith(".txt"):
                f = os.path.join(p, n)
                data[(d, n)] = expand(read_rows(f), bases, f)
    return data


def derive(data, bases, keys_to_derive, rebase):
    """Record base blocks for the given group keys (all blocks when rebase)."""
    occ = collections.defaultdict(list)  # key -> [(type, run tuple)]
    for (d, n), rows in data.items():
        t = type_of(n)
        rs = runs(rows)
        cnt = collections.Counter(k for k, _ in rs if k)
        for k, run in rs:
            if k and cnt[k] == 1 and (rebase or k in keys_to_derive):
                occ[k].append((t, tuple(run)))
    for k, items in occ.items():
        for b in [b for b in bases.blocks if b[1] == k]:
            del bases.blocks[b]
        cands = sorted({a for t, _ in items for a in ancestors(t)}, key=lambda a: (a.count("/"), a))
        for b in cands:
            desc = [run for t, run in items if t.startswith(b + "/")]
            mode, n = collections.Counter(desc).most_common(1)[0]
            inh = bases.nearest(b + "/x", k)
            # nearest() looks at strict ancestors of b/x, which include b itself only once recorded: none yet.
            inherited = bases.blocks.get((inh, k)) if inh else None
            if n >= 2 and mode != inherited and n > sum(1 for r in desc if r == inherited):
                bases.blocks[(b, k)] = mode


def refresh(data, bases):
    """Incremental: replace a block when fewer than half of the runs that use it still match it; drop unused blocks."""
    users = collections.defaultdict(list)
    seen_keys = set()
    for (d, n), rows in data.items():
        t = type_of(n)
        rs = runs(rows)
        cnt = collections.Counter(k for k, _ in rs if k)
        for k, run in rs:
            if k and cnt[k] == 1:
                seen_keys.add(k)
                b = bases.nearest(t, k)
                if b:
                    users[(b, k)].append(tuple(run))
    stale = set()
    for b in list(bases.blocks):
        u = users.get(b, [])
        if not u:
            del bases.blocks[b]
            continue
        exact = sum(1 for r in u if r == bases.blocks[b])
        if exact * 2 < len(u):
            mode, n = collections.Counter(u).most_common(1)[0]
            if n >= 2 and n > exact:
                stale.add(b[1])
    have = {k for _, k in bases.blocks}
    new_keys = {k for k in seen_keys if k not in have}
    return stale | new_keys


def main(argv):
    bases = Bases()
    if argv[:1] == ["--expand"]:
        out = argv[1]
        for (d, n), rows in load_all(bases).items():
            os.makedirs(os.path.join(out, d), exist_ok=True)
            with open(os.path.join(out, d, n), "w", encoding="utf-8", newline="") as f:
                f.write("\n".join(rows) + "\n\n" if rows else "")
        return 0
    data = load_all(bases)
    check = argv[:1] == ["--check"]
    if not check:
        if argv[:1] == ["--rebase"]:
            bases.blocks = {}
            derive(data, bases, None, True)
        else:
            keys = refresh(data, bases)
            if keys:
                derive(data, bases, keys, False)
    changed = []
    for (d, n), rows in data.items():
        lines = encode(type_of(n), rows, bases)
        if expand(lines, bases, n) != rows:
            raise SystemExit(f"internal error: {d}/{n} does not round-trip")
        text = "".join(l + "\n" for l in lines)
        path = os.path.join(ROOT, d, n)
        if check:
            with open(path, encoding="utf-8", newline="") as f:
                if f.read() != text:
                    changed.append(f"{d}/{n}")
        elif write_if_changed(path, text):
            changed.append(f"{d}/{n}")
    if check:
        for c in changed:
            print(f"not factored: {c} (python tools/dq_pin_factor.py)")
        return 1 if changed else 0
    bases.write()
    print(f"dq_pin_factor: {len(data)} pin files, {len(bases.blocks)} base blocks, {len(changed)} file(s) rewritten")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
