#!/usr/bin/env python3
r"""qdel() in content -> the caused endings (doc/rewrite/final_api.html section 6 "Lifecycle forms", form 8; code/engine/lifeforms/lifetimes.dm).

    python tools/codemods/endings.py [--apply] [--sites] [--others] [--paths prefix ...]

Every `qdel(X)` statement outside the engine (code/engine, code/library, code/datums/lifecycle, the defines, tests) becomes the verb that says
why X ends, chosen from where it happens:

  destroyed(X, by)   in a damage, breaking or deconstruction path (ex_act, emp_act, bullet_act, take_damage, atom_break, deconstruct,
                     dismantle, a tool's *_act, die, gib, explode, detonate, burst, collapse, impact, ...)
  consumed(X, by)    in an eating or drinking path (eat, bite, consume, drink, feed, digest, absorb, ...) and, for an X other than src,
                     in an item interaction (attackby, interaction_item, item_interact, afterattack, load, insert, merge, refill, ...):
                     the item is used up into src, which is `by`
  dissolved(X, by)   in an acid, melting, digestion, decay or evaporation path
  ended_with(X, src) for an X other than src in an owner's teardown (on_destroy, *_teardown)
  lapsed(X)          in an expiry, duration, timeout or fade path
  spent(X, by)       anywhere else: the thing has done what it was for (a used charge, a finished effect, a closed window, a dropped record)

`by` is the proc's acting mob when it takes one (`user`, `M`, `L`, `H`, `attacker`, `eater`, `feeder`, `user_mob`), src for a consumed()
X other than src, else nothing. An `// ALLOW(lifecycle): reason` that kept the site is removed; its reason text picks the verb first when it
names one (used up, eaten, dissolved, broken). `return qdel(X)` becomes the verb then `return`. Left alone (counted by escape_hatches): a
forced qdel(X, TRUE), a qdel used as a value, a preprocessor line.
"""
import argparse
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dmlib import File, dm_files, procs_in, strip_code  # noqa: E402

ENGINE = ("code/engine/", "code/library/", "code/datums/lifecycle/", "code/__defines/", "code/modules/unit_tests/", "code/modules/benchmarks/",
          "code/tests/", "code/modules/tgs/", "code/controllers/subsystems/garbage.dm", "code/controllers/kernel/")

QDEL = re.compile(r"(?<![\w.])qdel\s*\(")
DESTROY = re.compile(r"(ex_act|emp_act|bullet_act|take_damage|damage|atom_break|atom_destruction|deconstruct|dismantle|_act_tool|tool_done|welder|crowbar|"
                     r"wrench|screwdriver|wirecutter|break|shatter|smash|destroy|explode|explosion|detonate|burst|blow|crush|collapse|impact|"
                     r"die\b|death|gib|kill|hit|fire_act|burn|ignite|overload|meteor|bump|crossed|throw)", re.I)
# A word start: "eat" must not match create/treat/feature/repeat (the first run consumed() 40 such sites; ending_fix.py re-caused them).
CONSUME = re.compile(r"(?<![a-z])(eat|bite|consume|drink|feed|absorb|devour|ingest|swallow|slurp|nom)", re.I)
OWNER_TEARDOWN = re.compile(r"^(on_destroy|Destroy|\w*_teardown|caps_destroy|legacy_holder_destroy)$")
LAPSE = re.compile(r"(expire|duration|timeout|timed_out|lapse|flick|fade)", re.I)
INTERACT = re.compile(r"(attackby|interaction_item|item_interact|afterattack|attack_obj|use_on|load|insert|merge|combine|refill|stack|transfer|"
                      r"apply|install|attach|add_to|put_in|feed)", re.I)
DISSOLVE = re.compile(r"(acid|melt|dissolve|decay|rot\b|rotting|evaporate|dry_|wither|corrode)", re.I)
REASON_VERB = [
    (re.compile(r"(?i)\b(used up|single[- ]use|spent|last charge|empty)\b"), "spent"),
    (re.compile(r"(?i)\b(eaten|drunk|consumed|swallowed|absorbed)\b"), "consumed"),
    (re.compile(r"(?i)\b(dissolve[sd]?|melts?|melted|decays?|evaporates?)\b"), "dissolved"),
    (re.compile(r"(?i)\b(broken|breaks|shatter|destroyed|explodes?|blown up|smashed|wrecked|deconstruct)"), "destroyed"),
]
ACTORS = ("user", "M", "L", "H", "attacker", "eater", "feeder", "user_mob", "actor")
ALLOW_LIFECYCLE = re.compile(r"\s*//\s*ALLOW\(([^)]*)\)\s*:.*$")


def call_span(code, start):
    """(open paren index, close paren index) of the call whose name starts at `start`."""
    i = code.index("(", start)
    depth = 0
    for j in range(i, len(code)):
        if code[j] == "(":
            depth += 1
        elif code[j] == ")":
            depth -= 1
            if depth == 0:
                return i, j
    return i, None


def split_top(s):
    out, depth, cur, q = [], 0, [], None
    for c in s:
        if q:
            cur.append(c)
            if c == q:
                q = None
            continue
        if c in "\"'":
            q = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            out.append("".join(cur).strip())
            cur = []
            continue
        cur.append(c)
    if "".join(cur).strip():
        out.append("".join(cur).strip())
    return out


def allow_reason(lines, k):
    """The ALLOW(lifecycle) reason kept on line k or the comment line above, and where it sits: (reason, line index, same_line) or None."""
    for at, same in ((k, True), (k - 1, False)):
        if at < 0:
            continue
        line = lines[at]
        if "ALLOW(" not in line or "lifecycle" not in line:
            continue
        if not same and not line.lstrip().startswith("//"):
            continue
        m = re.search(r"ALLOW\(([^)]*)\)\s*:\s*(.*)$", line)
        if m and "lifecycle" in [x.strip().split("/")[0] for x in m.group(1).split(",")]:
            return m.group(2).strip(), at, same, m.group(1)
    return None


def choose(proc_name, target, reason):
    if reason:
        for pat, verb in REASON_VERB:
            if pat.search(reason):
                return verb
    name = proc_name or ""
    if OWNER_TEARDOWN.search(name) and target != "src":
        return "ended_with"
    if LAPSE.search(name):
        return "lapsed"
    if DISSOLVE.search(name):
        return "dissolved"
    if CONSUME.search(name):
        return "consumed"
    if DESTROY.search(name):
        return "destroyed"
    if target != "src" and INTERACT.search(name):
        return "consumed"
    return "spent"


def actor_of(params):
    for p in params or []:
        if p in ACTORS:
            return p
    return None


def convert(f, counts, sites, apply):
    procs = list(procs_in(f))
    changed = False
    for k in range(len(f.lines) - 1, -1, -1):
        raw = f.lines[k]
        code = strip_code(raw)
        if "qdel" not in code or code.lstrip().startswith("#"):
            continue
        m = QDEL.search(code)
        if not m:
            continue
        if len(QDEL.findall(code)) > 1:
            counts["skip:several"] += 1
            continue
        start = m.start()
        o, c = call_span(code, start)
        if c is None:
            counts["skip:spans_lines"] += 1
            continue
        args = split_top(code[o + 1:c])
        if len(args) != 1:
            counts["skip:forced"] += 1
            continue
        target = args[0]
        before = code[:start].strip()
        after = code[c + 1:].strip()
        is_return = before == "return"
        if (before and not is_return and not re.fullmatch(r"(else|if\s*\(.*\))", before)) or after:
            counts["skip:value"] += 1
            continue
        proc = next((p for p in procs if p.start < k < p.end), None)
        pname = proc.name if proc else None
        reason_at = allow_reason(f.lines, k)
        reason = reason_at[0] if reason_at else None
        verb = choose(pname, "src" if target == "src" else "other", reason)
        by = None
        is_global = proc is None or f.lines[proc.start].startswith("/proc/")
        if verb == "ended_with":
            by = None if is_global else "src"
        elif verb == "consumed" and target != "src" and not (pname and CONSUME.search(pname)):
            by = None if is_global else "src"
        else:
            by = actor_of(proc.params() if proc else None)
            if by == target:
                by = None
        call = "%s(%s%s)" % (verb, target, (", " + by) if by else "")
        counts[verb] += 1
        sites.append("%s\t%s:%d\t%s\t%s" % (verb, f.rel, k + 1, pname, raw.strip()))
        if not apply:
            continue
        # Rewrite on the raw line: the call text sits at the same offset (strip_code keeps columns).
        new = raw[:start] + call + raw[c + 1:]
        if is_return:
            indent = raw[: len(raw) - len(raw.lstrip())]
            new_lines = [indent + call, indent + "return"]
            tail = raw[c + 1:]
            comment = tail[tail.find("//"):] if "//" in tail else ""
            if comment:
                new_lines[0] += " " + comment.strip()
            f.lines[k:k + 1] = new_lines
            new_first = k
        else:
            f.lines[k] = new
            new_first = k
        # The keep that justified the raw qdel goes with it.
        if reason_at:
            _, at, same, names = reason_at
            names_list = [x.strip() for x in names.split(",") if x.strip()]
            others = [x for x in names_list if x.split("/")[0] != "lifecycle"]
            if same:
                line = f.lines[new_first]
                cut = re.sub(r"\s*//\s*ALLOW\([^)]*\)\s*:.*$", "", line)
                if others:
                    cut += " // ALLOW(%s): %s" % (", ".join(others), reason)
                f.lines[new_first] = cut.rstrip()
            elif not others:
                del f.lines[at]
            else:
                f.lines[at] = re.sub(r"ALLOW\([^)]*\)", "ALLOW(%s)" % ", ".join(others), f.lines[at])
        changed = True
    if changed:
        f.dirty = True
    return changed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--sites", action="store_true")
    ap.add_argument("--others", action="store_true", help="include other agents' folders (mechanical edits)")
    ap.add_argument("--paths", nargs="*", default=["code/", "maps/"])
    a = ap.parse_args()
    counts = collections.Counter()
    sites = []
    touched = 0
    for rel in dm_files(a.paths, others=a.others):
        if rel.startswith(ENGINE):
            continue
        f = File(rel)
        if "qdel" not in "\n".join(f.lines):
            continue
        if convert(f, counts, sites, a.apply):
            touched += 1
            f.save()
    if a.sites:
        print("\n".join(sites))
    print("endings: %s; files %s: %d" % (dict(counts.most_common()), "changed" if a.apply else "to change", touched))


if __name__ == "__main__":
    main()
