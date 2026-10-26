#!/usr/bin/env python3
"""Do two worlds run their global initializers in an order that can differ in behaviour?

    python3 tools/ci/global_init_order.py DMB-EQUIV A.dmb B.dmb

dmb-equiv reports `proc.global_init_order` whenever the statements of `<global-init>` (every `var/global` / `var/static` with an
initial value, in include order) run in another order. A generated include order moves hundreds of them (tools/ci/dme_order_equiv.sh),
so this decides which moves matter. It reads both worlds' `<global-init>` (`dmb-equiv dump-proc`), splits it into one statement per
global it sets, and requires, of every pair of statements that runs in the other order in B:

* both commute: a statement made only of constants (PushVal, list and assoc-list construction, formatting) writes its own global and
  reads nothing, so it commutes with everything;
* or neither has an effect the other can see, by the classes below, each checked against the worlds, not assumed:
  - a constructor `new /T(...)` of a type with no `New()` of its own on T or an ancestor short of `/datum` (checked in the world: no
    `/T/New` proc): it runs only `/datum/New()`, whose engine hooks fill lazily built per-type caches (the same result in any order);
  - a call or constructor in COMMUTING below, each with the reason it cannot observe or affect another initializer.
A statement that reads another global (`GetVar global:X`) must still run after X's initializer in B (it did in A).

Exit 0 when every moved pair commutes, 1 otherwise (each offending pair printed), 2 on a usage or decode problem.
"""
from __future__ import annotations

import re
import subprocess
import sys

PURE = {"PushVal", "PushInt", "NewList", "NewAssocList", "Format", "EmptyList", "Neg", "Add", "Sub", "Mul", "Div", "BitOr", "BitAnd",
        "BitShiftLeft", "Text2Path", "Ascii2Text", "TypesOf", "NewAList", "RegexNew", "NewImageArgList", "NewArgList"}

# Calls and constructors whose effects are private to their own result or keyed by an argument (an insertion into a keyed table
# commutes with every other insertion), read from the code they run:
COMMUTING = {
    "CallGlob /proc/typecacheof": "builds and returns a new typecache list from typesof(); touches no global",
    "CallGlob /proc/dq_register_material_mix": "GLOB_material_mix_registry[path] = template: one key per declaring type, and the "
                                               "template it interns is keyed by the mix's content (material_templates.dm)",
    "New /datum/shared_cache": "/datum/shared_cache/New() sets its own vars and appends itself to shared_cache_registry, which only "
                               "shared_cache_stats() iterates (the rows of the OM profiler panel: their order is the only change)",
    "New /regex": "a compiled pattern object; no global state",
    "New /icon": "an icon object from a file; no global state",
    "New /image": "an image object; no global state",
    "New /datum/destroy_effects_data": "/datum/destroy_effects_data/New() only copies its arguments into its own vars",
}


def statements(equiv: str, dmb: str) -> list[tuple[str, list[str]]]:
    out = subprocess.run([equiv, "dump-proc", dmb, "<global-init>"], capture_output=True, text=True, errors="replace")
    if out.returncode != 0:
        raise SystemExit(f"global_init_order: dump-proc failed on {dmb}: {out.stderr.strip()}")
    result: list[tuple[str, list[str]]] = []
    cur: list[str] = []
    for line in out.stdout.splitlines():
        m = re.match(r"\s+\d+ (.*)$", line)
        if not m:
            continue
        op = m.group(1)
        cur.append(op)
        if op.startswith("SetVar global:"):
            result.append((op.split("global:", 1)[1], cur))
            cur = []
    return result


_new_cache: dict[str, bool] = {}


def plain_constructor(equiv: str, dmb: str, path: str) -> bool:
    """No New() of its own on `path` or an ancestor below /datum (the world has no `/T/New` proc for any of them)."""
    if path in _new_cache:
        return _new_cache[path]
    parts = path.strip("/").split("/")
    plain = True
    for cut in range(len(parts), 1, -1):
        anc = "/" + "/".join(parts[:cut])
        out = subprocess.run([equiv, "dump-proc", dmb, f"{anc}/New"], capture_output=True, text=True, errors="replace")
        if re.search(rf"^== {re.escape(anc)}/New\b", out.stdout, re.M):
            plain = False
            break
    _new_cache[path] = plain
    return plain


def effect_class(equiv: str, dmb: str, ops: list[str]) -> str | None:
    """None when the statement commutes with every other; else a description of its effect."""
    body = ops[:-1]  # the last op stores the statement's own global
    effects = [o for o in body if o.split()[0] not in PURE and not o.startswith("GetVar global:")]
    reasons: list[str] = []
    pushed_path = None
    for o in body:
        m = re.match(r"PushVal path\d+ (/\S+)", o)
        if m:
            pushed_path = m.group(1)
        if o.startswith('PushVal "/icon"') or o.startswith('PushVal "/image"'):
            pushed_path = o.split('"')[1]
    for o in effects:
        head = o.split()[0]
        if head == "New":
            key = f"New {pushed_path}"
            if key in COMMUTING:
                continue
            if pushed_path and pushed_path.startswith("/datum") and plain_constructor(equiv, dmb, pushed_path):
                continue
            reasons.append(key)
        elif head == "CallGlob":
            proc = o.split(", ", 1)[1] if ", " in o else o
            key = f"CallGlob {proc}"
            if key in COMMUTING:
                continue
            reasons.append(key)
        else:
            reasons.append(o)
    return "; ".join(reasons) or None


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    equiv, a_path, b_path = argv
    a = statements(equiv, a_path)
    b = statements(equiv, b_path)
    if sorted(t for t, _ in a) != sorted(t for t, _ in b):
        print("global_init_order: the two worlds initialize different globals (that is not an order question)")
        return 1
    pos_b = {t: i for i, (t, _) in enumerate(b)}
    pos_a = {t: i for i, (t, _) in enumerate(a)}
    ops_a = dict(a)
    bad: list[str] = []
    # Reads: a statement reading global X runs after X's initializer in both.
    for t, ops in a:
        for o in ops:
            m = re.match(r"GetVar global:(\S+)", o)
            if m and m.group(1) in pos_a and pos_a[m.group(1)] < pos_a[t] and not pos_b[m.group(1)] < pos_b[t]:
                bad.append(f"{t} reads {m.group(1)}, which is now initialized after it")
    # Effects: every pair of effectful statements keeps its relative order.
    effectful = [(t, effect_class(equiv, a_path, ops)) for t, ops in a]
    effectful = [(t, e) for t, e in effectful if e]
    for i in range(len(effectful)):
        for j in range(i + 1, len(effectful)):
            (t1, e1), (t2, e2) = effectful[i], effectful[j]
            if pos_b[t1] > pos_b[t2]:
                bad.append(f"{t1} ({e1}) and {t2} ({e2}) run in the other order")
    moved = sum(1 for t, _ in a if pos_a[t] != pos_b[t])
    print(f"global_init_order: {len(a)} initializers, {moved} at another position, {len(effectful)} with an effect another can see")
    for line in bad:
        print(f"  ORDER: {line}")
    if bad:
        print(f"global_init_order: {len(bad)} pair(s) whose order can matter: keep their files in order with a `before` rule in "
              "tools/build/dme_spec.txt, or show they commute")
        return 1
    print("global_init_order: every reordered pair commutes")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
