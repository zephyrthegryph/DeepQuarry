#!/usr/bin/env python3
r"""Tool-op handlers that start a legacy use_tool() timer -> a timed op (wait(), begins(), starts(), then()).

    python tools/codemods/use_tool_wait.py [--check] [--dirs code/game ...]

The shape (what tools/codemods/tool_act.py left behind for a timed _act proc):

    op("use_<q>", tool(TOOL_Q), wait(0), [costs(RES_FUEL, 0),] then(PROC_REF(<q>_used)))
    /T/proc/<q>_used(datum/act/op/A)
        var/mob/user = A.actor
        var/obj/item/X = A.held
        [if(COND)                       <- at most one guard, on the holder's own state
            return OP_DECLINE | OP_OK]
        use_tool(user, X, src, delay = D, quality = Q, [amount = N,] [volume = V,] [start_self = "...",] [start_others = "...",]
            receiver = src, on_done = PROC_REF(DONE), done_args = list(user))
        return OP_OK | OP_DECLINE
    /T/proc/DONE(mob/user)

becomes

    op("use_<q>", tool(TOOL_Q) | lit_welder(fuel = N), [when(PROC_REF(<q>_applies))], [needs(req(PROC_REF(<q>_refusal), silent = TRUE))],
        [starts(PROC_REF(<q>_started))], [begins(PROC_REF(<q>_begins))], wait(D | PROC_REF(<q>_duration)), then(PROC_REF(DONE)))
    /T/proc/DONE(datum/act/op/A)

A guard that declined becomes when() (the op is no candidate, the click goes on as before); a guard that swallowed the click becomes a silent
requirement (refused, nothing said, as before). The guard is sampled with read_once(). The start sound is the held tool's use sound at the
old volume; the start messages are begins(). A handler of any other shape, or a DONE proc something else calls, is left alone and listed.
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
QUALITIES = {"screwdriver": "TOOL_SCREWDRIVER", "crowbar": "TOOL_CROWBAR", "wrench": "TOOL_WRENCH", "wirecutter": "TOOL_WIRECUTTER",
             "multitool": "TOOL_MULTITOOL", "welder": "TOOL_WELDER"}
BANNED = ("code/engine/", "code/modules/unit_tests/", "code/tests/", "code/__defines/", "code/datums/interactions/", "code/library/")
ALLOWED_KW = {"delay", "quality", "amount", "volume", "start_self", "start_others", "receiver", "on_done", "done_args"}


def split_args(s):
    out, depth, cur, in_str, prev = [], 0, "", False, ""
    for c in s:
        if in_str:
            cur += c
            if c == '"' and prev != "\\":
                in_str = False
            prev = c
            continue
        if c == '"':
            in_str = True
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
            prev = c
            continue
        cur += c
        prev = c
    if cur.strip():
        out.append(cur.strip())
    return out


def rel(p):
    return os.path.relpath(p, ROOT).replace("\\", "/")


def proc_span(lines, header_index):
    j = header_index + 1
    while j < len(lines) and (lines[j] == "" or lines[j][0] in "\t "):
        j += 1
    while j > header_index + 1 and lines[j - 1] == "":
        j -= 1
    return header_index, j


def convert_text(text, path, report, all_text):
    nl = "\r\n" if "\r\n" in text else "\n"
    lines = text.replace("\r\n", "\n").split("\n")
    changed = False
    for q, quality in QUALITIES.items():
        for i, line in enumerate(list(lines)):
            m = re.match(r"^(/[\w/]+?)/proc/(%s_used)\(datum/act/op/A\)\s*$" % q, line)
            if not m:
                continue
            typ, handler = m.group(1), m.group(2)
            start, end = proc_span(lines, i)
            body = [l for l in lines[start + 1:end] if l.strip()]
            why = None
            held = None
            guard = None
            guard_kind = None
            call = None
            final = None
            k = 0
            if k < len(body) and body[k].strip() == "var/mob/user = A.actor":
                k += 1
            else:
                why = "no user line"
            hm = re.match(r"^\tvar/obj/item/(?:\w+/)*(\w+) = A\.held$", body[k]) if not why and k < len(body) else None
            if hm:
                held = hm.group(1)
                k += 1
            elif not why:
                why = "no held line"
            if not why and k + 1 < len(body) and re.match(r"^\tif\((.*)\)$", body[k]) and re.match(r"^\t\treturn (OP_DECLINE|OP_OK)$", body[k + 1]):
                guard = re.match(r"^\tif\((.*)\)$", body[k]).group(1)
                guard_kind = re.match(r"^\t\treturn (OP_DECLINE|OP_OK)$", body[k + 1]).group(1)
                if re.search(r"\b(user|%s|A)\b" % held, guard):
                    why = "guard reads the actor or the tool"
                k += 2
            if not why and k < len(body) and body[k].startswith("\tuse_tool("):
                call = body[k].strip()
                k += 1
            elif not why:
                why = "no use_tool line"
            if not why and k < len(body) and re.match(r"^\treturn (OP_OK|OP_DECLINE)$", body[k]):
                final = body[k].strip()
                k += 1
            elif not why:
                why = "no final return"
            if not why and k != len(body):
                why = "more lines"
            kw = {}
            if not why:
                args = split_args(call[len("use_tool("):-1])
                if len(args) < 3 or args[0] != "user" or args[1] != held or args[2] != "src":
                    why = "use_tool positional arguments"
                else:
                    for a in args[3:]:
                        if "=" not in a:
                            why = "positional argument %s" % a
                            break
                        name, value = a.split("=", 1)
                        name, value = name.strip(), value.strip()
                        if name not in ALLOWED_KW:
                            why = "use_tool(%s =)" % name
                            break
                        kw[name] = value
            if not why:
                if kw.get("receiver") != "src" or kw.get("done_args") != "list(user)" or not kw.get("on_done", "").startswith("PROC_REF("):
                    why = "receiver/done_args/on_done"
                elif kw.get("quality", quality) != quality:
                    why = "quality differs"
            if why:
                report.append("skip %s %s/%s: %s" % (rel(path), typ, handler, why))
                continue
            done = kw["on_done"][len("PROC_REF("):-1]
            # the done proc: in this file, one parameter (mob/user), called by nothing else
            di = next((n for n, l in enumerate(lines) if re.match(r"^%s/proc/%s\(mob/user\)\s*$" % (re.escape(typ), done), l)), None)
            if di is None:
                report.append("skip %s %s/%s: done proc %s not found as (mob/user)" % (rel(path), typ, handler, done))
                continue
            # done procs have generic names (welder_act_tool_done): count the calls in this file, and any override on a subtype elsewhere
            here = "\n".join(lines)
            callers = len(re.findall(r"\b%s\(" % done, here))
            refs = len(re.findall(r"PROC_REF\(%s\)" % done, here))
            if any(re.search(r"^%s/(?!proc/)[\w/]+/%s\(" %(re.escape(typ), done), t, re.M) for t in all_text.values()):
                callers += 1
            if callers - 1 > 0 or refs != 1:
                report.append("skip %s %s/%s: %s is called or referenced elsewhere" % (rel(path), typ, handler, done))
                continue
            # build the new op and procs
            parts = []
            if q == "welder":
                parts.append("lit_welder(fuel = %s)" % kw.get("amount", "0"))
            else:
                parts.append("tool(%s)" % quality)
            new_procs = []
            if guard:
                if guard_kind == "OP_DECLINE":
                    parts.append("when(PROC_REF(%s_applies))" % q)
                    new_procs += ["/// When the %s answers (it did nothing otherwise and the click went on)." % q,
                                  "%s/proc/%s_applies(datum/act/op/A)" % (typ, q),
                                  ("\treturn !!read_once(%s)" % guard[1:]) if re.match(r"^![\w.()]+$", guard) else ("\treturn !read_once(%s)" % guard), ""]
                else:
                    parts.append("needs(req(PROC_REF(%s_refusal), silent = TRUE))" % q)
                    new_procs += ["/// When the %s does nothing (the click is used up, nothing is said)." % q,
                                  "%s/proc/%s_refusal(datum/act/op/A)" % (typ, q), "\treturn read_once(%s) ? \"no\" : null" % guard, ""]
            volume = kw.get("volume", "50")
            if volume not in ("0", "null"):
                parts.append("starts(PROC_REF(%s_started))" % q)
                new_procs += ["%s/proc/%s_started(datum/act/op/A)" % (typ, q), "\tplaysound(src, sounds_of(A.held).use, %s, TRUE)" % volume, ""]
            if "start_self" in kw or "start_others" in kw:
                def fix(t):
                    return t.replace("[user]", "[A.actor]").replace("[%s]" % held, "[A.held]")
                parts.append("begins(PROC_REF(%s_begins))" % q)
                new_procs += ["%s/proc/%s_begins(datum/act/op/A)" % (typ, q),
                              "\treturn msg_text(%s, %s)" % (fix(kw.get("start_self", "null")), fix(kw.get("start_others", "null"))), ""]
            delay = kw.get("delay", "0")
            if re.match(r"^\d+(\.\d+)?( SECONDS?| MINUTES?)?$", delay):
                parts.append("wait(%s)" % delay)
            else:
                parts.append("wait(PROC_REF(%s_duration))" % q)
                new_procs += ["%s/proc/%s_duration(datum/act/op/A)" % (typ, q), "\treturn %s" % delay, ""]
            parts.append("then(PROC_REF(%s))" % done)
            # the op line, in any CAPABILITIES block of the type in this file
            opi = next((n for n, l in enumerate(lines) if re.match(r'^\top\("use_%s", tool\(%s\), (priority\([^)]*\), )?wait\(0\)(, costs\(RES_FUEL, 0\))?, then\(PROC_REF\(%s\)\)\)\s*$' % (q, quality, handler), l)), None)
            if opi is None:
                report.append("skip %s %s/%s: op line not found" % (rel(path), typ, handler))
                continue
            pr = re.search(r"priority\([^)]*\)", lines[opi])
            if pr:
                parts.insert(1, pr.group(0))
            # done proc rewrite
            ds, de = proc_span(lines, di)
            dbody = lines[ds + 1:de]
            if any(re.search(r"\bA\b", l) for l in dbody):
                report.append("skip %s %s/%s: %s already names a local A" % (rel(path), typ, handler, done))
                continue
            uses_user = any(re.search(r"\buser\b", l) for l in dbody)
            newd = ["%s/proc/%s(datum/act/op/A)" % (typ, done)]
            if uses_user:
                newd.append("\tvar/mob/user = A.actor")
            for l in dbody:
                l = re.sub(r"^(\s*)return (ITEM_INTERACT_SUCCESS|ITEM_INTERACT_BLOCKING|TRUE|1)\s*$", r"\1return OP_OK", l)
                newd.append(l)
            # apply bottom-up
            edits = sorted([(ds, de, newd), (start, end, new_procs[:-1] if new_procs else []), (opi, opi + 1, ['\top("use_%s", %s)' % (q, ", ".join(parts))])],
                           key=lambda e: e[0], reverse=True)
            for s0, e0, rep in edits:
                lines[s0:e0] = rep
            changed = True
            report.append("convert %s %s/%s" % (rel(path), typ, handler))
            break
    return (nl.join(lines), True) if changed else (text, False)


def main(argv):
    check = "--check" in argv
    dirs = ["code/"]
    if "--dirs" in argv:
        dirs = [d.rstrip("/") + "/" for d in argv[argv.index("--dirs") + 1:] if not d.startswith("--")]
    all_text = {}
    for base, ds, fs in os.walk(os.path.join(ROOT, "code")):
        ds[:] = [d for d in ds if d != "_generated"]
        for f in fs:
            if f.endswith(".dm"):
                p = os.path.join(base, f)
                with open(p, encoding="utf-8", errors="surrogateescape", newline="") as fh:
                    all_text[p] = fh.read()
    report = []
    for p, t in all_text.items():
        r = rel(p)
        if r.startswith(BANNED) or not any(r.startswith(d) for d in dirs) or "_used(datum/act/op/A)" not in t or "use_tool(" not in t:
            continue
        new, changed = t, True
        while changed:  # one handler at a time: each pass re-reads the file's lines
            new, changed = convert_text(new, p, report, all_text)
        if new != t and not check:
            with open(p, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
                fh.write(new)
    for line in report:
        print(line)
    print("use_tool_wait: %d converted, %d left%s" % (sum(1 for l in report if l.startswith("convert")), sum(1 for l in report if l.startswith("skip")), " (check)" if check else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
