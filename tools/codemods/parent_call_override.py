#!/usr/bin/env python3
r"""A subtype interaction whose handler first calls its parent's handler for the same input -> an override of the parent's handler.

    python tools/codemods/parent_call_override.py [--check] /child/type child_handler parent_handler [...]

The old form had two entries for one input (the child's own, first, and the inherited one through the declare chain) and the
child's handler ran the parent's itself. As ops that is one op of the parent with the child overriding its handler:

    EXTEND_INTERACTIONS(/C, INTERACT_ITEM(null, PROC_REF(c_item)))        (the line goes; a spec list with other specs keeps them)
    /C/proc/c_item(mob/user, obj/item/W, datum/interaction/i)        ->   /C/p_item(mob/user, obj/item/W, datum/interaction/i)
        . = p_item(user, W, i)                                               . = ..()

Run tools/dx/codemods/interact_declare.py afterwards: it converts the parent's spec and every override of its handler together.
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def main(argv):
    check = "--check" in argv
    args = [a for a in argv if not a.startswith("--")]
    triples = [args[i : i + 3] for i in range(0, len(args), 3)]
    files = {}
    for base, dd, fs in os.walk(os.path.join(ROOT, "code")):
        dd[:] = [d for d in dd if d != "_generated"]
        for f in fs:
            if f.endswith(".dm"):
                files[os.path.join(base, f)] = None
    for child, ch, ph in triples:
        hit = None
        for p in files:
            t = open(p, encoding="utf-8", errors="surrogateescape", newline="").read()
            if re.search(r"^" + re.escape(child) + r"/proc/" + ch + r"\(", t, re.M):
                hit = (p, t)
                break
        if not hit:
            print("not found:", child, ch)
            continue
        p, t = hit
        nl = "\r\n" if "\r\n" in t else "\n"
        # the definition becomes an override of the parent's handler
        t2 = re.sub(r"^" + re.escape(child) + r"/proc/" + ch + r"\(", child + "/" + ph + "(", t, count=1, flags=re.M)
        # the call of the parent's handler (with the legacy arguments) becomes ..()
        t2, n = re.subn(r"\b" + ph + r"\(\s*\w+\s*,\s*\w+\s*,\s*\w+\s*\)", "..()", t2, count=1)
        if n != 1:
            print("no parent call in", child, ch)
            continue
        # the child's own spec goes
        spec = r"INTERACT_\w+\((?:[^()]|\([^()]*\))*PROC_REF\(" + ch + r"\)(?:[^()]|\([^()]*\))*\)"
        m = re.search(r"^EXTEND_INTERACTIONS\(" + re.escape(child) + r",\s*(" + spec + r")\s*\)[ \t]*\r?\n", t2, re.M)
        if m:
            t2 = t2[: m.start()] + t2[m.end() :]
        else:
            t2, n2 = re.subn(r"\t" + spec + r",?\s*\\?" + nl, "", t2, count=1)
            if n2 != 1:
                print("spec not found for", child, ch)
                continue
        print("override:", child, ch, "->", ph)
        if not check:
            open(p, "w", encoding="utf-8", errors="surrogateescape", newline="").write(t2)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
