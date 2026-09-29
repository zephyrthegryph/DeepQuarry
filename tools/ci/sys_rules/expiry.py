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


# ---- partial-migration rules (lead review: the lint must fail on a half migration) ----
RULES["world_time_write"] = ("a stored time is written with EXPIRY_SET/EXPIRY_EXTEND/EXPIRY_STAMP "
                             "(or EXPIRY_AT for list slots/records), never `x = world.time (+ N)`")
RULES["expiry_undeclared"] = "a var read/written by EXPIRY_*/ELAPSED is declared with EXPIRY_DECLARE/EXPIRY_TMP_DECLARE"

# `x = world.time`, `x = world.time + N`, `x += ...` excluded; `==` excluded. A local declared on the
# same line (`var/t = world.time`) is a snapshot for this proc, not stored state: not counted.
WRITE_RE = re.compile(r"(?<![=!<>])=(?!=)\s*\(?\s*world\.time\b(?!\s*[-*/%])")
LOCAL_RE = re.compile(r"^\s*var/(?!static)")
MACRO_USE = re.compile(r"\b(?:EXPIRY_(?:SET|EXTEND|CLEAR|ACTIVE|EXPIRED|LEFT|STAMP)|ELAPSED)\(\s*[^,()]+(?:\([^()]*\))?\s*,\s*(\w+)")
DECLARED = re.compile(r"\b(?:STATIC_)?EXPIRY(?:_TMP)?_DECLARE\(\s*(\w+)\s*\)")

_scan_compare = scan


def scan(files):  # noqa: F811
    out = _scan_compare(files)
    out["world_time_write"] = []
    out["expiry_undeclared"] = []
    declared = set()
    uses = []
    for rel, lines in files:
        for line in lines:
            if "EXPIRY" in line:
                declared.update(DECLARED.findall(line))
        if rel.startswith(SKIP):
            continue
        for number, line in enumerate(lines, 1):
            code = line.split("//", 1)[0]
            if code.lstrip().startswith("#"):
                continue
            if "world.time" in code and WRITE_RE.search(code) and not LOCAL_RE.match(code):
                out["world_time_write"].append((rel, number))
            if "EXPIRY_" in code or "ELAPSED(" in code:
                for name in MACRO_USE.findall(code):
                    uses.append((rel, number, name))
    for rel, number, name in uses:
        if name not in declared:
            out["expiry_undeclared"].append((rel, number))
    return out


# A member written through EXPIRY_AT (`x = EXPIRY_AT(D, clock, N)`, `obj.x = ...`) is EXPIRY_SET /
# EXPIRY_STAMP on a declared var dressed up; EXPIRY_AT is for list slots, records, locals, args.
AT_WRITE = re.compile(r"^\s*((?:\w+\.)*)(\w+)\s*=\s*EXPIRY_AT\(")
PROC_HEAD = re.compile(r"^/[\w/]*\(([^)]*)\)")
LOCAL_DECL = re.compile(r"\bvar/(?:[\w]+/)*(\w+)")

_scan_writes = scan


def scan(files):  # noqa: F811
    out = _scan_writes(files)
    for rel, lines in files:
        if rel.startswith(SKIP) or not any("EXPIRY_AT(" in l for l in lines):
            continue
        local = set()
        for number, line in enumerate(lines, 1):
            if line and not line[0].isspace():
                local = set()
                head = PROC_HEAD.match(line)
                if head:
                    local.update(LOCAL_DECL.findall(head.group(1)))
                    local.update(w.strip().split("=")[0].strip() for w in head.group(1).split(","))
                continue
            code = line.split("//", 1)[0]
            local.update(LOCAL_DECL.findall(code))
            m = AT_WRITE.match(code)
            if not m or code.lstrip().startswith("var/"):
                continue
            owner, name = m.groups()
            if owner.startswith("GLOB."):
                owner = owner[5:]
                if not owner:
                    continue  # a GLOBAL_VAR cannot be EXPIRY_DECLAREd
            if owner or name not in local:
                out["world_time_write"].append((rel, number))
    return out
