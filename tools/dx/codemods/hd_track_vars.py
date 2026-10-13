"""One-off driver (human draw conversion): makes named vars TRACKED through look_track's planner.

  python tools/dx/codemods/hd_track_vars.py <reader type> <var> [<var> ...] [--apply] [--owned-ok]
"""
import _guard  # noqa: F401
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "codemods"))
sys.path.insert(0, HERE)
import look_sweep  # noqa: E402
import look_convert  # noqa: E402
import look_track  # noqa: E402
from dmlib import File  # noqa: E402

pos = [a for a in sys.argv[1:] if not a.startswith("--")]
reader, wanted = pos[0], pos[1:]
owned_ok = "--owned-ok" in sys.argv
ix = look_convert.Index(ROOT, look_sweep.code_files())
files = ix.files
for var in wanted:
    p = look_track.plan(ix, var, {reader}, owned_ok)
    if isinstance(p, str):
        print("left  %s: %s" % (var, p))
        continue
    print("track %s on %s (%d writes)" % (var, p["owner"], len(p["writes"])))
    for rel, i, new in p["writes"]:
        files[rel].lines[i] = new
        files[rel].dirty = True
    rel, after = p["after"]
    files[rel].lines.insert(after + 1, p["macro"])
    files[rel].dirty = True
    look_track._write_index.clear()
for f in files.values():
    if getattr(f, "dirty", False):
        f.save()
