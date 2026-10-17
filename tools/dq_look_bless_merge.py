#!/usr/bin/env python3
"""Merge the partial rows of a sharded look bless into the snapshot files.

Every shard world of `dq_focused_test.sh --bless dq_look_state_pin dq_look_tree_pin` writes, instead of the snapshot files, its own
rows under <dir>/shard<i>/<pin>/<root>.txt (code/modules/unit_tests/dq_look_sweep.dm, dq_look_bless_partial): one row per line as
"<position of the type in typesof(root)><TAB><row>". This script joins the shards of each root in (position, shard, line) order,
which is the order an unsharded sweep writes (a type's rows all come from one shard, in the order the probe made them), and writes
code/modules/unit_tests/snapshots/<pin>/<root>.txt. The result does not depend on the shard count or on which shard finished first.

  python3 tools/dq_look_bless_merge.py DIR [SNAPSHOT_ROOT]
"""
import os
import sys

ROOTS = {"look_trees": "look_trees", "look_states": "look_states"}


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    src = argv[1]
    dest_root = argv[2] if len(argv) > 2 else "code/modules/unit_tests/snapshots"
    shards = sorted(
        (d for d in os.listdir(src) if d.startswith("shard") and d[5:].isdigit()),
        key=lambda d: int(d[5:]),
    )
    if not shards:
        print("dq_look_bless_merge: no shard output under %s" % src, file=sys.stderr)
        return 1
    files = {}  # (pin, file name) -> [(position, shard, line number, row)]
    for shard in shards:
        sid = int(shard[5:])
        shard_dir = os.path.join(src, shard)
        for pin in sorted(os.listdir(shard_dir)):
            if pin not in ROOTS:
                continue
            pin_dir = os.path.join(shard_dir, pin)
            for name in sorted(os.listdir(pin_dir)):
                rows = files.setdefault((pin, name), [])
                with open(os.path.join(pin_dir, name), encoding="utf-8", newline="") as fh:
                    for n, line in enumerate(fh.read().split("\n")):
                        line = line.rstrip("\r")
                        if not line:
                            continue
                        pos, _, row = line.partition("\t")
                        rows.append((int(pos), sid, n, row))
    total = 0
    for (pin, name), rows in sorted(files.items()):
        rows.sort(key=lambda r: (r[0], r[1], r[2]))
        out_dir = os.path.join(dest_root, ROOTS[pin])
        os.makedirs(out_dir, exist_ok=True)
        # BYOND's text2file adds a newline of its own: a file the sweep writes itself ends with a blank line (an empty one is a lone newline).
        text = "".join(r[3] + "\n" for r in rows) + "\n"
        with open(os.path.join(out_dir, name), "w", encoding="utf-8", newline="") as fh:
            fh.write(text)
        total += len(rows)
    print("dq_look_bless_merge: wrote %d files, %d rows from %d shards" % (len(files), total, len(shards)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
