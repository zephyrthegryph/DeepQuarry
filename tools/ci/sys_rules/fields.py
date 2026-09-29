"""Core state as declared fields (doc/rewrite/systems.md section 2).

Rules (every one must reach 0):

  stat_bits     A raw read or write of a machine's (or vehicle's) `stat` bits outside the field
                runtime: any bare `stat` in a proc of an /obj/machinery or /obj/vehicle subtype
                (`stat & BROKEN`, `if(stat)`, `stat |= X`, `stat &= ~X`, `stat = 0`), and any
                `thing.stat` used with a bit operator (`&`, `|`, `|=`, `&=`, `^=`) or whose
                receiver is typed as a machine or vehicle. Use operable() for "powered and
                working", has_stat(BITS) for one condition, stat_add()/stat_remove()/set_stat()
                to change it.
  stat_helper   The old duplicate readers inoperable() / is_operational(): use operable().
  field_write   A direct write to a declared core field (on, active, state, mode, locked,
                emagged, stat, anchored, density, use_power) anywhere but its setter: use set_<field>()
                (and stat_add()/stat_remove()). The rule shares tools/ci/field_write_lint.py's
                resolution (owner type, typed receivers).
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import field_write_lint as fwl  # noqa: E402

RULES = {
    "stat_bits": "operable() / has_stat(BITS) to read, stat_add()/stat_remove()/set_stat() to write (systems.md section 2)",
    "stat_helper": "operable() is the one reader; inoperable()/is_operational() are gone (systems.md section 2)",
    "field_write": "set_<field>() (stat_add()/stat_remove() for bits); no direct writes to a core field (systems.md section 2)",
}

CORE = ("on", "active", "state", "mode", "locked", "emagged", "stat", "anchored", "density", "use_power")
STAT_ROOTS = ("/obj/machinery", "/obj/vehicle")
RUNTIME = ("code/game/machinery/machinery_fields.dm", "code/__defines/om.dm", "code/datums/om/fields.dm")

BARE_STAT = re.compile(r"(?<![\w.])(?:src\.)?stat\b(?!\s*\()")
DOTTED_STAT = re.compile(r"(?<![\w])(\w+)\??\.stat\b(?!\s*\()")
BIT_AFTER = re.compile(r"^\s*(?:&(?!&)|\|(?!\|)|\^)")
BIT_BEFORE = re.compile(r"(?:[^&]&|[^|]\||\^)\s*\(?\s*$")
HELPER = re.compile(r"\b(?:inoperable|is_operational)\s*\(")
LOCAL_STAT = re.compile(r"\bvar/(?:[\w/]+/)?stat\b")


def under(path, roots):
    return any(path == r or path.startswith(r + "/") for r in roots)


def scan(files):
    out = {rule: [] for rule in RULES}
    fields = {k: v for k, v in fwl.index().items() if k in CORE}
    for rel, lines in files:
        text = fwl.code_only("\n".join(lines))
        code_lines = text.split("\n")
        if rel not in RUNTIME:
            for no, line in enumerate(code_lines, 1):
                if HELPER.search(line):
                    out["stat_helper"].append((rel, no))
            for no, field, _ in fwl.violations(fields, rel, text):
                out["field_write"].append((rel, no))
        if rel in RUNTIME:
            continue
        owner, locals_, stat_local = None, {}, False
        for no, line in enumerate(code_lines, 1):
            if line and not line[0].isspace():
                m = fwl.PROC_DEF_RE.match(line)
                if m and not line.startswith("#"):
                    owner = fwl.norm(m.group(1))
                    locals_ = {}
                    for tm in fwl.TYPED_NAME_RE.finditer(m.group(3)):
                        locals_[tm.group(2)] = fwl.norm(tm.group(1))
                    stat_local = bool(re.search(r"(?<![\w/])stat\b", m.group(3)))
                else:
                    owner = None
                continue
            if owner is None:
                continue
            for tm in fwl.TYPED_NAME_RE.finditer(line):
                if line[tm.start():].startswith("var/") or "var/" in line[max(0, tm.start() - 4):tm.start() + 4]:
                    locals_[tm.group(2)] = fwl.norm(tm.group(1))
            if LOCAL_STAT.search(line):
                stat_local = True
                continue
            hit = False
            if under(owner, STAT_ROOTS) and not stat_local:
                for m in BARE_STAT.finditer(line):
                    if not line[:m.start()].rstrip().endswith("var"):
                        hit = True
                        break
            if not hit:
                for m in DOTTED_STAT.finditer(line):
                    recv = m.group(1)
                    if recv == "src":
                        if under(owner, STAT_ROOTS):
                            hit = True
                            break
                        continue
                    rtype = locals_.get(recv) or fwl.member_type(owner, recv)
                    if rtype and under(rtype, STAT_ROOTS):
                        hit = True
                        break
                    if BIT_AFTER.match(line[m.end():]) or BIT_BEFORE.search(line[:m.start()]):
                        if rtype and not under(rtype, STAT_ROOTS) and not rtype.startswith("/obj"):
                            continue  # a mob's (or other typed) stat: not machine bits
                        hit = True
                        break
            if hit:
                out["stat_bits"].append((rel, no))
    return out
