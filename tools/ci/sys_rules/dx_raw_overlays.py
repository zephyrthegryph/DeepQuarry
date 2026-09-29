"""sys_lint module: raw overlay writes outside the look builder (design review M9).

draw(datum/look/look) builds an atom's appearance through look.state()/overlay()/gauge()/glow(), and
the builder dedupes by key (code/datums/capabilities/look.dm). A raw overlay write next to it
bypasses that dedupe and is stomped (or leaks) on the next draw.

Rule:
  dx_raw_overlays   add_overlay( / cut_overlay( / cut_overlays( / overlays += / overlays -= outside
                    the look builder and the legacy appearance runtime (the overlay subsystem that
                    defines the procs, and code/datums/sys/appearance.dm).

The baseline (tools/ci/sys_baseline/dx_raw_overlays.txt) is every legacy site; it only shrinks as
types move to draw().
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _dx_dm as dm  # noqa: E402

RULES = {
    "dx_raw_overlays": "draw the layer in draw(datum/look/look) (look.overlay/glow/gauge), not a raw overlay write (design review M9)",
}

RAW = re.compile(r"(?<![\w/])(?:add_overlay|cut_overlays?)\s*\(|(?<![\w/])overlays\s*[-+]=")
EXEMPT = (
    "code/datums/capabilities/look.dm",
    "code/controllers/subsystems/overlays.dm",
    "code/datums/sys/appearance.dm",
    "code/__defines/sys_appearance.dm",
)


def scan_file(rel, lines, clean=None):
    found = []
    for number, code in enumerate(clean if clean is not None else dm.sanitize(lines), 1):
        if RAW.search(code):
            found.append((rel, number))
    return found


def scan(files):
    out = {rule: [] for rule in RULES}
    tree = dm.tree(files)
    for rel, lines in files:
        if rel in EXEMPT or "overlay" not in tree.raw_text(rel):
            continue
        out["dx_raw_overlays"].extend(scan_file(rel, lines, tree.clean[rel]))
    return out


def selftest():
    fixture = [
        "add_overlay(\"lights\")",          # 1 bad
        "A.cut_overlay(old)",               # 2 bad
        "overlays += image(icon, \"x\")",   # 3 bad
        "src.overlays -= glow",             # 4 bad
        "cut_overlays()",                   # 5 bad
        "look.overlay(\"lights\")",         # 6 ok
        "// add_overlay(x)",                # 7 ok
        "/atom/proc/add_overlay(list/add_overlays, priority)",  # 8 ok: a definition
        "var/list/my_overlays = list()",    # 9 ok
        "add_overlay_lighting(src, 3, 1)",  # 10 ok: another proc
        "overlays == null",                 # 11 ok
    ]
    got = [n for _rel, n in scan_file("x.dm", fixture)]
    assert got == [1, 2, 3, 4, 5], got
    assert not scan([("code/datums/capabilities/look.dm", ["A.add_overlay(added)"])])["dx_raw_overlays"]
    return "dx_raw_overlays"
