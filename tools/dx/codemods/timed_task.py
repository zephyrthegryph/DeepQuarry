#!/usr/bin/env python3
r"""task_timed() in an op handler -> a wait() part on the op (doc/rewrite/final_api.html section 9, "Waiting and asking").

    python tools/dx/codemods/timed_task.py [--apply] [--sites] [--files paths...] [--dirs dirs...]

(A literal start message becomes begins(MSG(...)).) The one mechanical shape: an op whose `then(PROC_REF(P))` handler does nothing but start a timed action,

    op("key", binding..., then(PROC_REF(P)))
    /T/proc/P(datum/act/op/A)
        var/mob/user = A.actor                     (any `var/x = A.actor|A.held|A.target`, kept as aliases)
        to_chat(user, "You begin ...")             (optional start messages: dropped, an op's wait() says nothing at the start)
        task_timed(user, DUR, target = src, receiver = src, on_done = PROC_REF(D), done_args = list(user[, alias...]))
        return OP_PASS|TRUE|OP_OK                  (optional)
    /T/proc/D(mob/user[, X...])

becomes

    op("key", binding..., wait(DUR), then(PROC_REF(D)))
    /T/proc/D(datum/act/op/A)
        var/mob/user = A.actor
        var/X = A.held

and P is deleted. DUR must be a constant (digits and time defines), P must be referenced by that one op and nowhere else, `claims = TRUE` becomes
claims(). Everything else is residue, printed with a code by --sites (the worklist for the hand conversion):

    not_op_handler   the call is in a proc no op names (a legacy attackby/attack_hand/attack_self body)
    prechecks        the handler checks things before the call (they become needs(), by hand)
    named_task       task_start(/datum/task/timed/x ...) (the task type becomes the op's wait + then)
    done_args_state  done_args carries something that is not the actor or an alias of A.held/A.target
    dynamic_duration the duration is a variable or a call (wait(PROC_REF(x)))
    start_message    the start message is not a literal to_chat/act_message of the user (it becomes begins(MSG(x)) by hand)
    options          on_fail, check_proc, flags, busy, max_distance, target_zone... (map by hand)
    other_target     target is not src
    shared_proc      P or D is also called or referenced elsewhere

Idempotent. Run `analyze gen` afterwards.
"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import os
import re
import subprocess
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ui_declare import File, body_range, split_args  # noqa: E402

SKIP = ("code/__defines/", "code/modules/unit_tests/", "code/tests/", "tools/", "code/modules/tgs/", "code/datums/om/", "code/engine/", "code/game/machinery/", "code/modules/power/")
CALL = re.compile(r"^\s*(task_timed|task_start)\((.*)\)\s*(//.*)?$")
DUR = re.compile(r"^[\d.]+(\s*(SECONDS?|MINUTES?|DECISECONDS?|TICKS?))?$|^\d+\s*\*\s*[\d.]+\s*(SECONDS?|MINUTES?)$")
ALIAS = re.compile(r"^\s*var/(?:[\w/]+/)?(\w+)\s*=\s*(A\.(?:actor|held|target))\s*$")
MESSAGE = re.compile(r"^\s*(to_chat|act_message|visible_message)\(.*\)\s*$")
RETURN = re.compile(r"^\s*return(\s+(OP_PASS|OP_OK|TRUE|OP_COMMITTED))?\s*$")
OPTION_KEYS = ("on_fail", "fail_args", "check_proc", "check_args", "timed_action_flags", "busy", "max_distance", "target_zone", "interaction_key", "max_interact_count", "hidden", "progress", "icon", "iconstate")


def kwargs(args):
    pos, kw = [], {}
    for a in args:
        m = re.match(r"^(\w+)\s*=\s*(.*)$", a, re.S)
        if m:
            kw[m.group(1)] = m.group(2).strip()
        else:
            pos.append(a)
    return pos, kw


SPAN = re.compile(r'^((?:span_\w+\()*)"(.*)"(\)*)$', re.S)


def message_text(expr):
    """The template text of a literal message expression (span_x("...") with at most [src] interpolated), or None."""
    expr = expr.strip()
    for w in ("MSG_SELF", "MSG_OTHERS", "MSG_BLIND"):
        if expr.startswith(w + "(") and expr.endswith(")"):
            expr = expr[len(w) + 1:-1].strip()
    m = SPAN.match(expr)
    if not m or m.group(1).count("(") != m.group(3).count(")"):
        return None
    body = m.group(2).replace("\\the [src]", "%T%").replace("[src]", "%T%")
    if "[" in body or "]" in body:
        return None
    return m.group(1) + '"' + body + '"' + m.group(3)


def parse_start(stmt):
    """(self, others, blind) template expressions of a start-message statement, or None if it is not a literal one."""
    m = re.match(r"^\s*to_chat\(\s*user\s*,\s*(.*)\)\s*$", stmt, re.S)
    if m:
        t = message_text(m.group(1))
        return (t, None, None) if t else None
    m = re.match(r"^\s*act_message\(\s*user\s*,\s*src\s*,(.*)\)\s*$", stmt, re.S)
    if not m:
        return None
    pos, kw = kwargs(split_args(m.group(1)))
    vals = {"self": None, "others": None, "blind": None}
    for name, v in zip(("self", "others", "blind"), pos):
        vals[name] = v
    for k, v in kw.items():
        if k not in vals:
            return None
        vals[k] = v
    out = []
    for k in ("self", "others", "blind"):
        if vals[k] is None:
            out.append(None)
            continue
        t = message_text(vals[k])
        if not t:
            return None
        out.append(t)
    return tuple(out)


def main():
    sites = "--sites" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--files" in sys.argv:
        names = [a for a in args if a.endswith(".dm")]  # explicit files: the selftest and a hand run
    else:
        names = subprocess.check_output(["git", "ls-files", "-z", "*.dm"]).decode("utf-8", "surrogateescape").split("\0")
        names = [n for n in names if n and not n.startswith(SKIP)]
        if "--dirs" in sys.argv:
            dirs = tuple(a.rstrip("/") + "/" for a in args)
            names = [n for n in names if n.startswith(dirs)]
    residue = defaultdict(list)
    converted = 0
    apply_ = "--apply" in sys.argv
    queue = list(names)
    while queue:
        rel = queue.pop(0)
        file_residue = defaultdict(list)
        converted_here = False
        try:
            raw = open(rel, encoding="utf-8", errors="surrogateescape", newline="").read()
        except OSError:
            continue
        if "task_timed(" not in raw and "task_start(" not in raw:
            continue
        f = File(rel)
        lines = f.lines
        text = "\n".join(l for l in lines if l is not None)
        for i, line in enumerate(list(lines)):
            if line is None:
                continue
            m = CALL.match(line)
            if not m:
                continue
            tag = "%s:%d" % (rel, i + 1)
            # the enclosing proc
            j = i
            while j >= 0 and not (lines[j] and re.match(r"^/[\w/]*proc/\w+\(", lines[j])):
                j -= 1
            if j < 0:
                file_residue["not_in_proc"].append(tag)
                continue
            sig = re.match(r"^(/[\w/]*?)/proc/(\w+)\((.*)\)", lines[j])
            ptype, pname = sig.group(1), sig.group(2)
            if m.group(1) == "task_start":
                file_residue["named_task"].append(tag)
                continue
            op_refs = re.findall(r"then\(PROC_REF\(%s\)\)" % re.escape(pname), text)
            if not op_refs or "datum/act/op" not in sig.group(3):
                file_residue["not_op_handler"].append(tag)
                continue
            first, last = body_range(lines, j)
            body = [(k, lines[k]) for k in range(first, last + 1) if lines[k] and lines[k].strip() and not lines[k].strip().startswith("//")]
            others = [(k, l) for (k, l) in body if k != i]
            aliases, pre, starts = {}, False, []
            for (k, l) in others:
                if ALIAS.match(l):
                    am = ALIAS.match(l)
                    aliases[am.group(1)] = am.group(2)
                elif MESSAGE.match(l) and k < i:
                    starts.append(l)
                elif RETURN.match(l) and k > i:
                    pass
                else:
                    pre = True
            if pre:
                file_residue["prechecks"].append(tag)
                continue
            parsed = [parse_start(x) for x in starts]
            if any(x is None for x in parsed) or len(parsed) > 1:
                file_residue["start_message"].append(tag)
                continue
            pos, kw = kwargs(split_args(m.group(2)))
            if len(pos) < 2 or any(k in kw for k in OPTION_KEYS):
                file_residue["options"].append(tag)
                continue
            user, dur = pos[0], pos[1]
            if not DUR.match(dur):
                file_residue["dynamic_duration"].append(tag)
                continue
            target = (pos[2] if len(pos) > 2 else kw.get("target", "")).strip()
            if target not in ("src", "A.target"):
                file_residue["other_target"].append(tag)
                continue
            done = re.match(r"^PROC_REF\((\w+)\)$", kw.get("on_done", ""))
            recv = kw.get("receiver", "")
            if not done or recv != "src":
                file_residue["options"].append(tag)
                continue
            claims = kw.get("claims", "FALSE") == "TRUE"
            dargs = []
            if "done_args" in kw:
                dm = re.match(r"^list\((.*)\)$", kw["done_args"], re.S)
                if not dm:
                    file_residue["done_args_state"].append(tag)
                    continue
                dargs = split_args(dm.group(1))
            if any(a != user and a not in aliases for a in dargs):
                file_residue["done_args_state"].append(tag)
                continue
            dname = done.group(1)
            dsig_i = next((k for k, l in enumerate(lines) if l and re.match(r"^%s/proc/%s\(" % (re.escape(ptype), re.escape(dname)), l)), None)
            if dsig_i is None or len(re.findall(r"\b%s\b" % re.escape(dname), text)) != 2 or len(re.findall(r"\b%s\b" % re.escape(pname), text)) != 2:
                file_residue["shared_proc"].append(tag)
                continue
            dparams = [p.strip() for p in split_args(re.match(r"^[^(]*\((.*)\)", lines[dsig_i]).group(1))] if re.match(r"^[^(]*\((.*)\)", lines[dsig_i]).group(1).strip() else []
            if len(dparams) != len(dargs):
                file_residue["done_args_state"].append(tag)
                continue
            # build the new done handler header
            decl = []
            for a, p in zip(dargs, dparams):
                pname_only = p.split("/")[-1].split("=")[0].strip()
                ptypepath = "/".join(p.split("=")[0].strip().split("/")[:-1])
                src_expr = "A.actor" if a == user else aliases[a]
                decl.append("\tvar/%s%s = %s" % ((ptypepath + "/") if ptypepath else "", pname_only, src_expr))
            if not decl:
                decl = []
            # op line
            op_i = next((k for k, l in enumerate(lines) if l and re.search(r"then\(PROC_REF\(%s\)\)" % re.escape(pname), l)), None)
            if op_i is None:
                file_residue["not_op_handler"].append(tag)
                continue
            if re.match(r"^\d+$", dur):  # raw deciseconds become a time define
                dur = "%g SECONDS" % (int(dur) / 10.0) if int(dur) else "0"
            begins = ""
            msg_def = None
            if parsed:
                opkey = re.search(r'op\("(\w+)"', lines[op_i])
                leaf = ptype.rstrip("/").split("/")[-1]
                mname = "%s/%s_begins" % (leaf, opkey.group(1) if opkey else pname)
                self_t, others_t, blind_t = parsed[0]
                if others_t is None and blind_t is None:
                    msg_def = "MSG_DEF_SELF(%s, %s)" % (mname, self_t)
                else:
                    msg_def = "MSG_DEF(%s, %s, %s)" % (mname, self_t or "null", others_t or "null")
                begins = "begins(MSG(%s)%s), " % (mname, (", blind = " + blind_t) if blind_t else "")
            wait = "wait(%s)" % dur
            if claims:
                wait = "claims(), " + wait
            wait = begins + wait
            lines[op_i] = re.sub(r"then\(PROC_REF\(%s\)\)" % re.escape(pname), "%s, then(PROC_REF(%s))" % (wait, dname), lines[op_i])
            if msg_def:
                ci = op_i
                while ci >= 0 and not (lines[ci] and lines[ci].startswith("CAPABILITIES(")):
                    ci -= 1
                lines.insert(ci if ci >= 0 else op_i, msg_def + "\n")
                if ci >= 0:
                    op_i += 1
                    if dsig_i >= ci:
                        dsig_i += 1
                    if j >= ci:
                        j += 1
            # the done proc gets the op act
            lines[dsig_i] = re.sub(r"\(.*\)", "(datum/act/op/A)", lines[dsig_i], count=1)
            for d in reversed(decl):
                lines.insert(dsig_i + 1, d)
            # delete P (its lines and one trailing blank), indices shifted by the inserts when after dsig_i
            shift = len(decl) if dsig_i < j else 0
            pj = j + shift
            pf, pl = body_range(lines, pj)
            for k in range(pj, pl + 1):
                lines[k] = None
            # also delete a doc comment directly above P
            k = pj - 1
            while k >= 0 and lines[k] is not None and lines[k].startswith("///"):
                lines[k] = None
                k -= 1
            f.dirty = True
            converted += 1
            converted_here = True
            break  # indices moved: save, then look at the file again
        if f.dirty:
            f.save()
        if converted_here and apply_:
            queue.insert(0, rel)
            continue
        for code, ts in file_residue.items():
            residue[code].extend(ts)
    print("timed_task: %d handlers converted; residue %d" % (converted, sum(len(v) for v in residue.values())))
    for code, ts in sorted(residue.items(), key=lambda kv: -len(kv[1])):
        print("    %-16s %4d" % (code, len(ts)))
        if sites:
            for t in sorted(ts):
                print("        " + t)
    return 0


if __name__ == "__main__":
    sys.exit(main())
