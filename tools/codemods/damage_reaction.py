#!/usr/bin/env python3
r"""DAMAGE_REACTION(T, DAMAGE_X, PROC_REF(h)) -> a hit hook in CAPABILITIES(T) (doc/rewrite/api_mapping.tsv DAMAGE_REACTION).

    python tools/codemods/damage_reaction.py [--check] [--sites] [--dirs code/game/objects ...]

    handler that can return DAMAGE_REACTION_BLOCK  -> extend(/datum/act/hit/<x>, instead(then(PROC_REF(h))))
                                                     h(datum/act/hit/<x>/A): BLOCK -> OP_OK (takes the hit over), any other
                                                     return and falling off the end -> HOOK_DECLINE (the hit goes on, as before)
    handler that never blocks                     -> on_notice(/datum/notice/hit/<x>, then(PROC_REF(h)))
                                                     h(datum/act/A); var/datum/notice/hit/<x>/N = A (the reaction runs after the
                                                     hit instead of before it: the precedent of the console and the airlock)
    TYPE_PROC_REF(/atom, damage_reaction_block)   -> extend(/datum/act/hit/<x>, instead())

`packet` in the body becomes the act's or notice's `packet` field. Residue: handler_shape (not one 1-parameter proc of T),
handler_shared (named elsewhere), dot_used, return_expr, local_A, trigger (not one of the four entries).
"""
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ENTRIES = {"DAMAGE_EMP": "emp", "DAMAGE_EXPLOSION": "explosion", "DAMAGE_PROJECTILE": "projectile", "DAMAGE_BLOB": "blob"}
HEAD = re.compile(r"^DAMAGE_REACTION\((/[\w/]+),\s*(DAMAGE_\w+),\s*(PROC_REF\((\w+)\)|TYPE_PROC_REF\(/atom,\s*damage_reaction_block\))\)\s*(//.*)?$")


def rel(p):
    return os.path.relpath(p, ROOT).replace("\\", "/")


def read(p):
    with open(p, "r", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        return fh.read()


def write(p, text):
    with open(p, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        fh.write(text)


def strip_strings(l):
    """A string literal's text goes; its embedded expressions ("[user]") stay, as code."""
    return re.sub(r'"(?:[^"\\]|\\.)*"', lambda m: '"' + " ".join(re.findall(r"\[([^\]]*)\]", m.group(0))) + '"', l)


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
    sites = "--sites" in argv
    dirs = []
    if "--dirs" in argv:
        dirs = [d.rstrip("/") + "/" for d in argv[argv.index("--dirs") + 1:] if not d.startswith("--")]
    files = {}
    for base, _d, fs in os.walk(os.path.join(ROOT, "code")):
        _d[:] = [d for d in _d if d != "_generated"]  # build output (analyze gen), not source
        for f in fs:
            if f.endswith(".dm"):
                p = os.path.join(base, f)
                files[p] = read(p)
    all_text = "\n".join(files.values())
    plans, resid = [], defaultdict(list)
    for p, t in files.items():
        if dirs and not any(rel(p).startswith(d) for d in dirs):
            continue
        lines = t.splitlines()
        for i, l in enumerate(lines):
            m = HEAD.match(l)
            if not m:
                continue
            T, trig, _ref, h = m.group(1), m.group(2), m.group(3), m.group(4)
            if trig not in ENTRIES:
                resid["trigger"].append(T)
                continue
            entry = ENTRIES[trig]
            if not h:
                plans.append({"path": p, "line": i, "type": T, "entry": entry, "entry_text": "extend(/datum/act/hit/%s, instead())" % entry, "handler": None})
                continue
            # the handler: one definition on T
            defs = [(dp, di) for dp, dt in files.items() for di, dl in enumerate(dt.splitlines()) if re.match(r"^" + re.escape(T) + r"/proc/" + h + r"\(", dl)]
            others = len(re.findall(r"/" + h + r"\(", all_text)) - 1
            if len(defs) != 1 or others:
                resid["handler_shape"].append(T)
                continue
            if len(re.findall(r"\b" + h + r"\b", all_text)) != 2:
                resid["handler_shared"].append(T)
                continue
            dp, di = defs[0]
            dl = files[dp].splitlines()
            sig = dl[di]
            pm = re.match(r"^/[\w/]+/proc/\w+\(([^)]*)\)", sig)
            params = [x.strip() for x in pm.group(1).split(",") if x.strip()]
            if len(params) > 1:
                resid["handler_shape"].append(T)
                continue
            pname = params[0].split("/")[-1] if params else None
            end = body_end(dl, di)
            body = dl[di + 1 : end + 1]
            code = "\n".join(strip_strings(x) for x in body)
            if re.search(r"(^|[^\w.])\.\s*=", code, re.M):
                resid["dot_used"].append(T)
                continue
            if re.search(r"\bA\b", code):
                resid["local_A"].append(T)
                continue
            blocks = "DAMAGE_REACTION_BLOCK" in code
            bad = False
            for x in body:
                rm = re.match(r"^\s*return\b\s*(.*?)\s*(//.*)?$", strip_strings(x))
                if rm and rm.group(1) not in ("", "DAMAGE_REACTION_BLOCK", "FALSE", "0", "null", "TRUE", "1", "NONE"):
                    bad = True
            if bad:
                resid["return_expr"].append(T)
                continue
            if blocks:
                entry_text = "extend(/datum/act/hit/%s, instead(then(PROC_REF(%s))))" % (entry, h)
            else:
                entry_text = "on_notice(/datum/notice/hit/%s, then(PROC_REF(%s)))" % (entry, h)
            plans.append({"path": p, "line": i, "type": T, "entry": entry, "entry_text": entry_text, "handler": (dp, di, end, pname, blocks)})
    print("damage_reaction: %d convert%s; residue %d" % (len(plans), " (check)" if check else "", sum(len(v) for v in resid.values())))
    for k, v in resid.items():
        print("    %-16s %d" % (k, len(v)))
        if sites:
            for t in v:
                print("        " + t)
    if check:
        return 0
    edits = defaultdict(list)
    blocks_add = defaultdict(list)
    for pl in plans:
        blocks_add[pl["type"]].append((pl["path"], pl["line"], pl["entry_text"]))
        edits[pl["path"]].append((pl["line"], pl["line"], None))  # the macro line goes
        if pl["handler"]:
            dp, di, end, pname, blocks = pl["handler"]
            dl = files[dp].splitlines()
            entry = pl["entry"]
            body = dl[di + 1 : end + 1]
            uses_packet = pname and any(re.search(r"\b" + re.escape(pname) + r"\b", strip_strings(x)) for x in body)
            if blocks:
                head = re.sub(r"\([^)]*\)", "(datum/act/hit/%s/A)" % entry, dl[di], count=1)
                pre = ["\tvar/datum/damage_packet/%s = A.packet" % pname] if uses_packet else []
                new_body = []
                for x in body:
                    rm = re.match(r"^(\s*)return\b\s*(.*?)\s*(//.*)?$", x)
                    if rm:
                        val = rm.group(2)
                        cmt = (" " + rm.group(3)) if rm.group(3) else ""
                        x = "%sreturn %s%s" % (rm.group(1), "OP_OK" if val == "DAMAGE_REACTION_BLOCK" else "HOOK_DECLINE", cmt)
                    new_body.append(x)
                last = [x for x in body if x.strip() and not x.strip().startswith("//")]
                if not last or not re.match(r"^\treturn\b", last[-1]):
                    new_body.append("\treturn HOOK_DECLINE")
            else:
                head = re.sub(r"\([^)]*\)", "(datum/act/A)", dl[di], count=1)
                pre = (["\tvar/datum/notice/hit/%s/N = A" % entry, "\tvar/datum/damage_packet/%s = N.packet" % pname] if uses_packet else [])
                new_body = list(body)
            edits[dp].append((di, end, [head] + pre + new_body))
    # the hook entries: into the type's block, else a new block where the macro stood
    for T, items in blocks_add.items():
        placed = False
        for p, t in files.items():
            lines = t.splitlines()
            for i, l in enumerate(lines):
                if l.rstrip() == "CAPABILITIES(%s)" % T:
                    j = i + 1
                    while j < len(lines) and (lines[j].strip() == "" or lines[j][0] in "\t "):
                        j += 1
                    while j - 1 > i and lines[j - 1].strip() == "":
                        j -= 1
                    edits[p].append((j, j - 1, ["\t" + e for _, _, e in items]))
                    placed = True
                    break
            if placed:
                break
        if not placed:
            p, line, _ = items[0]
            # replace the first macro line by the new block (its None edit is dropped below)
            edits[p] = [e for e in edits[p] if not (e[0] == line and e[2] is None)]
            edits[p].append((line, line, ["CAPABILITIES(%s)" % T] + ["\t" + e for _, _, e in items]))
    for p, es in edits.items():
        text = files[p]
        nl = "\r\n" if "\r\n" in text else "\n"
        trailing = text.endswith(("\n", "\r\n"))
        lines = text.splitlines()
        for s, e, new in sorted(es, key=lambda x: (x[0], x[1]), reverse=True):
            if new is None:
                lines[s : e + 1] = []
            else:
                lines[s : e + 1] = new
        write(p, nl.join(lines) + (nl if trailing else ""))
        print("    wrote " + rel(p))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
