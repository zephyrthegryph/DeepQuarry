#!/usr/bin/env python3
r"""DECLARE_EMAG / DECLARE_EMAG_REPEATABLE -> the emag library capability (code/library/access/emag.dm).

    python tools/codemods/declare_emag.py [--check] --dirs code/game/objects ...

    DECLARE_EMAG_REPEATABLE(T, PROC_REF(h), null)   ->  CAPABILITIES(T): emag(then(PROC_REF(h)), repeatable = TRUE, powered = FALSE)
    DECLARE_EMAG(T, PROC_REF(h), null, null)        ->  emag(then(PROC_REF(h)), powered = FALSE)   (one-shot; T/mark_emagged() goes)
    h(remaining_charges, mob/user, obj/item/emag_source) -> h(datum/act/op/A), user = A.actor, emag_source = A.held,
                                                          remaining_charges = the card's uses

Returns: a positive count (1, TRUE) is OP_OK (the library pays one use and marks it subverted); 0, FALSE, null,
EMAG_DECLINED, a bare return and falling off the end decline (OP_DECLINE: nothing paid, the card goes on to its other
uses), except a handler that never returns a count (it always acted: OP_OK at its end). Items have no power: powered = FALSE.

Residue: messages (a MSG or ALREADY text: say = by hand), shape (the handler is not one 3-parameter proc of T), returns
(a return the table does not name), excluded (tools/codemods/exclusions.txt "emag" lines).
"""
import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _excl import excluded  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
EXCLUDED = excluded("emag")
HEAD = re.compile(r"^DECLARE_EMAG(_REPEATABLE)?\((/[\w/]+),\s*PROC_REF\((\w+)\)((?:,\s*\w+)*)\)\s*$")


def rel(p):
    return os.path.relpath(p, ROOT).replace("\\", "/")


def body_end(lines, i):
    j, last = i + 1, i
    while j < len(lines):
        if lines[j].strip() == "":
            j += 1
            continue
        if lines[j][0] in "\t ":
            last = j
            j += 1
            continue
        break
    return last


def main(argv):
    check = "--check" in argv
    dirs = [d.rstrip("/") + "/" for d in argv[argv.index("--dirs") + 1:] if not d.startswith("--")] if "--dirs" in argv else []
    files = {}
    for base, dd, fs in os.walk(os.path.join(ROOT, "code")):
        dd[:] = [d for d in dd if d != "_generated"]
        for f in fs:
            if f.endswith(".dm"):
                p = os.path.join(base, f)
                files[p] = open(p, encoding="utf-8", errors="surrogateescape", newline="").read()
    done, resid = 0, defaultdict(list)
    for p, text in files.items():
        if dirs and not any(rel(p).startswith(d) for d in dirs):
            continue
        nl = "\r\n" if "\r\n" in text else "\n"
        lines = text.split(nl)
        changed = False
        i = 0
        while i < len(lines):
            m = HEAD.match(lines[i])
            if not m:
                i += 1
                continue
            repeatable, T, h, rest = bool(m.group(1)), m.group(2), m.group(3), [x.strip() for x in m.group(4).split(",") if x.strip()]
            if T in EXCLUDED:
                resid["excluded"].append(T)
                i += 1
                continue
            if any(x != "null" for x in rest):
                resid["messages"].append(T)
                i += 1
                continue
            hd = [k for k, l in enumerate(lines) if re.match(r"^" + re.escape(T) + r"/proc/" + h + r"\(", l)]
            if len(hd) != 1:
                resid["shape"].append(T)
                i += 1
                continue
            k = hd[0]
            pm = re.match(r"^[^(]+\(([^)]*)\)", lines[k])
            params = [x.strip().split("=")[0].strip().split("/")[-1] for x in pm.group(1).split(",") if x.strip()]
            if len(params) != 3:
                resid["shape"].append(T)
                i += 1
                continue
            end = body_end(lines, k)
            body = lines[k + 1 : end + 1]
            rets = [re.match(r"^\s*return\b\s*(.*?)\s*(//.*)?$", b) for b in body]
            vals = [r.group(1) for r in rets if r]
            if any(v not in ("", "1", "TRUE", "0", "FALSE", "null", "EMAG_DECLINED", ".") for v in vals) or re.search(r"(^|\s)\.\s*=\s*(?!EMAG_DECLINED|emag_target)", "\n".join(body)):
                resid["returns"].append(T)
                i += 1
                continue
            counts = any(v in ("1", "TRUE") for v in vals)
            uses_dot = any(re.search(r"(^|\s)\.\s*=", b) for b in body)
            new_body = []
            for b in body:
                rm = re.match(r"^(\s*)return\b\s*(.*?)\s*(//.*)?$", b)
                if rm:
                    v = rm.group(2)
                    if v == "." :
                        b = rm.group(1) + "return (isnum(.) && . > 0) ? OP_OK : OP_DECLINE"
                    else:
                        b = rm.group(1) + "return " + ("OP_OK" if v in ("1", "TRUE") else "OP_DECLINE")
                new_body.append(b)
            last = [b for b in body if b.strip() and not b.strip().startswith("//")]
            if not last or not re.match(r"^\treturn\b", last[-1]):
                if uses_dot:
                    new_body.append("\treturn (isnum(.) && . > 0) ? OP_OK : OP_DECLINE")
                else:
                    new_body.append("\treturn " + ("OP_DECLINE" if counts else "OP_OK"))
            joined = "\n".join(body)
            pre = []
            if re.search(r"\b" + re.escape(params[1]) + r"\b", joined):
                pre.append("\tvar/mob/%s = A.actor" % params[1])
            if re.search(r"\b" + re.escape(params[2]) + r"\b", joined):
                pre.append("\tvar/obj/item/%s = A.held" % params[2])
            if re.search(r"\b" + re.escape(params[0]) + r"\b", joined):
                pre.append("\tvar/obj/item/card/emag/emag_card = A.held")
                pre.append("\tvar/%s = istype(emag_card) ? emag_card.uses : 1" % params[0])
            lines[k : end + 1] = ["%s/proc/%s(datum/act/op/A)" % (T, h)] + pre + new_body
            # the one-shot gate's own setter goes: the library marks it subverted
            for j, l in enumerate(lines):
                if l.rstrip() == "%s/mark_emagged()" % T:
                    e2 = body_end(lines, j)
                    del lines[j : e2 + 1]
                    break
            entry = "\temag(then(PROC_REF(%s))%s, powered = FALSE)" % (h, ", repeatable = TRUE" if repeatable else "")
            hi = next(n for n, l in enumerate(lines) if HEAD.match(l) and HEAD.match(l).group(2) == T)
            blk = next((n for n, l in enumerate(lines) if l.rstrip() == "CAPABILITIES(%s)" % T), None)
            if blk is not None:
                e = blk + 1
                while e < len(lines) and lines[e].startswith("\t"):
                    e += 1
                lines.insert(e, entry)
                hi = next(n for n, l in enumerate(lines) if HEAD.match(l) and HEAD.match(l).group(2) == T)
                del lines[hi]
            else:
                lines[hi : hi + 1] = ["CAPABILITIES(%s)" % T, entry, ""]
            changed = True
            done += 1
            i = 0
        if changed and not check:
            open(p, "w", encoding="utf-8", errors="surrogateescape", newline="").write(nl.join(lines))
            print("    wrote " + rel(p))
    print("declare_emag: %d convert%s; residue %d" % (done, " (check)" if check else "", sum(len(v) for v in resid.values())))
    for k, v in resid.items():
        print("    %-10s %s" % (k, " ".join(v)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
