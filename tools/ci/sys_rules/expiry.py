"""Expiry lint (doc/rewrite/systems.md section 17).

`world_time_expiry` counts hand-rolled expiry/elapsed state read against world.time:
  * a compare of world.time with a recorded time (`world.time > x_until`, `expires < world.time`),
    that is, every world.time compare tools/ci/cooldown_lint.py does NOT count as a cooldown
    (a site is either a cooldown, owned by that lint, or an expiry, owned by this one);
  * an elapsed compare (`world.time - last_x > N`, `N < world.time - started`).
Write EXPIRY_ACTIVE / EXPIRY_LEFT / ELAPSED (code/__defines/sys_expiry.dm) instead.

Not counted: compares against a bare constant (`world.time > 30 MINUTES`, a round-age gate),
#define lines, lines marked `// ALLOW(cooldown)` (a cooldown), and the scheduler/MC internals
under code/datums/om/ and code/controllers/master.dm, failsafe.dm.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

RULES = {
    "world_time_expiry": "EXPIRY_DECLARE/EXPIRY_SET/EXPIRY_ACTIVE/EXPIRY_LEFT/ELAPSED "
                         "(code/__defines/sys_expiry.dm, doc/rewrite/systems.md section 17)",
}

def _cmp():
    import cooldown_lint  # noqa: E402  (lazy: allow_annotations imports this module)
    return cooldown_lint


SKIP = ("code/datums/om/", "code/controllers/master.dm", "code/controllers/failsafe.dm")
CMP = r"(?:>=|<=|(?<![<>=!])>(?![>=])|(?<![<>=])<(?![<=]))"
ELAPSED_RE = re.compile(
    rf"(?<![\w.])world\.time\s*-\s*[\w.\[\]\"]+(?:\s*\))?\s*{CMP}|{CMP}\s*\(?\s*world\.time\s*-\s*\w")


def scan(files):
    cooldown_lint = _cmp()
    from allow_annotations import allowed  # noqa: E402
    out = {"world_time_expiry": []}
    names = cooldown_lint.timestamp_names()
    stamp_re = re.compile(r"(?<![\w])(?:%s)\b" % "|".join(sorted(names))) if names else None
    for rel, lines in files:
        if rel.startswith(SKIP):
            continue
        if not any("world.time" in l for l in lines):
            continue
        for number, line in enumerate(lines, 1):
            code = line.split("//", 1)[0]
            if "world.time" not in code or code.lstrip().startswith("#"):
                continue
            hit = False
            if cooldown_lint.COMPARE.search(code) and not cooldown_lint.CONST_CMP.search(code.strip()):
                # A compare cooldown_lint counts (not a recorded time) belongs to that lint.
                if cooldown_lint.not_a_cooldown(rel, code, stamp_re) or not rel.startswith("code/"):
                    hit = not allowed(lines, number, "cooldown")
                elif rel.startswith(cooldown_lint.SKIP_DIRS):
                    hit = True
            if not hit and ELAPSED_RE.search(code):
                hit = True
            if hit:
                out["world_time_expiry"].append((rel, number))
    return out
