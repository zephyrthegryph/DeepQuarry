#!/usr/bin/env python3
r"""DECLARE_UI / UI_ACT / UI_DATA rows -> interface() / op(ui_act()) entries (doc/rewrite/codemod_rules.md, "DECLARE_UI / UI_ACT").

    python tools/dx/codemods/ui_declare.py [--check] [--sites] [--only /type] [paths...]

One host type at a time: all of its legacy UI rows convert together or none does. A type that does not match the rules exactly is residue with a
code (listed with --sites). Idempotent: a converted type has no legacy rows left. Run `analyze gen` afterwards.
"""
import re
import subprocess
import sys
from collections import defaultdict

SKIP = ("code/__defines/", "code/modules/unit_tests/", "code/tests/", "tools/", "code/modules/tgs/")
ROW = re.compile(r"^(DECLARE_UI|DECLARE_UI_STATE|UI_[A-Z_]+)\((/[\w/]+)(.*)$")
OVERRIDES = ("ui_act_allowed", "tgui_data", "tgui_act", "ui_status", "tgui_interact", "ui_data", "ui_interact")
RESERVED = {"in", "as", "to", "step", "if", "else", "for", "while", "do", "set", "var", "new", "del", "null", "return", "src", "usr", "args", "list", "text", "num", "user", "A", "ui", "state", "action", "params"}
SETTINGS = ("EVENT_HANDLER", "SHOULD_", "PRIVATE_PROC", "PROTECTED_PROC", "RETURN_TYPE", "CAN_BE_REDEFINED")


def related(a, b):
    return a == b or a.startswith(b + "/") or b.startswith(a + "/")


def strip_code(s, keep=False):
    """The line without comments, string text blanked; the code inside a string's [..] interpolation is kept."""
    out = []
    stack = []  # "str" (inside string text), "expr" (inside a [..] of a string), "br" (a bracket inside that)
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        top = stack[-1] if stack else None
        if top == "str":
            if c == chr(92):
                out.append(c if keep else " ")
                if i + 1 < n:
                    out.append(s[i + 1] if keep else " ")
                i += 2
                continue
            if c == '"':
                stack.pop()
                out.append(c)
            elif c == "[":
                stack.append("expr")
                out.append(c)
            else:
                out.append(c if keep else " ")
        else:
            if c == '"':
                stack.append("str")
                out.append(c)
            elif c == "[" and top in ("expr", "br"):
                stack.append("br")
                out.append(c)
            elif c == "]" and top in ("expr", "br"):
                stack.pop()
                out.append(c)
            elif c == "/" and s[i : i + 2] == "//" and not stack:
                break
            else:
                out.append(c)
        i += 1
    return "".join(out)


def split_args(s):
    out, depth, cur, in_str, i = [], 0, "", False, 0
    while i < len(s):
        c = s[i]
        if in_str:
            cur += c
            if c == chr(92) and i + 1 < len(s):
                cur += s[i + 1]
                i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
            cur += c
        elif c in "([{":
            depth += 1
            cur += c
        elif c in ")]}":
            depth -= 1
            cur += c
        elif c == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += c
        i += 1
    if cur.strip() or out:
        out.append(cur.strip())
    return out


def inner_of_call(row_text, name):
    """The text between the outer parentheses of `NAME(...)` at the start of row_text, or None when unbalanced."""
    i = row_text.index("(")
    depth = 0
    in_str = False
    for k in range(i, len(row_text)):
        c = row_text[k]
        if in_str:
            if c == chr(92):
                continue
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return row_text[i + 1 : k]
    return None


class File:
    def __init__(self, rel):
        self.rel = rel
        with open(rel, encoding="utf-8", errors="surrogateescape", newline="") as fh:
            raw = fh.read()
        self.crlf = "\r\n" in raw
        self.lines = raw.replace("\r\n", "\n").split("\n")
        self.dirty = False

    def save(self):
        eol = "\r\n" if self.crlf else "\n"
        out = []
        prev_blank_before_none = None
        for l in self.lines:
            if l is None:
                if prev_blank_before_none is None:
                    prev_blank_before_none = (not out) or out[-1].strip() == ""
                continue
            if prev_blank_before_none and l.strip() == "":
                prev_blank_before_none = None
                continue  # a removed row between two blank lines takes one of them
            prev_blank_before_none = None
            out.append(l)
        text = eol.join(out)
        if self.crlf:
            text = text.replace("\r\n", "\n").replace("\n", "\r\n")
        with open(self.rel, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
            fh.write(text)


def body_range(lines, sig_idx):
    """Indices of the body lines under a column-0 signature line (blank lines included), and the index of the last non-blank one."""
    j = sig_idx + 1
    last = sig_idx
    while j < len(lines):
        l = lines[j]
        if l is None:
            j += 1
            continue
        if l.strip() == "":
            j += 1
            continue
        if l[0] in " \t":
            last = j
            j += 1
            continue
        break
    return sig_idx + 1, last


def words_in(text, name):
    return [m.start() for m in re.finditer(r"(?<![\w./])" + re.escape(name) + r"(?![\w])", text)]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check = "--check" in sys.argv
    sites = "--sites" in sys.argv
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1]
        args = [a for a in args if a != only]
    if "--files" in sys.argv:
        names = args  # exactly these files (the self-test)
    else:
        names = subprocess.check_output(["git", "ls-files", "-z", "*.dm"]).decode("utf-8", "surrogateescape").split("\0")
        names = [n for n in names if n and not n.startswith(SKIP)]
    files = {}
    rows = defaultdict(list)  # type -> [(kind, rel, idx, text)]
    code_text = {}
    for rel in names:
        try:
            f = File(rel)
        except OSError:
            continue
        files[rel] = f
        code_text[rel] = "\n".join(strip_code(l) for l in f.lines)
        for i, l in enumerate(f.lines):
            m = ROW.match(l)
            if m:
                rows[m.group(2)].append((m.group(1), rel, i, l))
    types = set(rows)
    residue = {}  # type -> reason
    plans = {}
    all_code = "\n".join(code_text.values())
    # Mentions that are neither a UI row nor a definition: calls, PROC_REFs, whatever could depend on a handler's signature.
    other_mentions = "\n".join(
        l for l in all_code.split("\n") if not re.match(r"^(UI_[A-Z_]+|DECLARE_UI\w*)\(", l) and not re.match(r"^/[\w/]+/(proc/)?\w+\(", l)
    )
    tree_text = "\n".join("\n".join(f.lines) for f in files.values())
    for t, rs in sorted(rows.items()):
        if only and t != only:
            continue
        kinds = [r[0] for r in rs]
        decl = [r for r in rs if r[0] == "DECLARE_UI"]
        if len(decl) != 1:
            residue[t] = "ui_forms"  # no declaration here (inherited), or several
            continue
        m = re.match(r'^DECLARE_UI\((/[\w/]+),\s*"([^"]*)"(?:,\s*UI_TITLE\("([^"]*)"\))?\)\s*(//.*)?$', decl[0][3])
        if not m:
            residue[t] = "ui_options"
            continue
        window, title = m.group(2), m.group(3)
        if any(k not in ("DECLARE_UI", "DECLARE_UI_STATE", "UI_ACT", "UI_ACT_PROC", "UI_DATA", "UI_DATA_REPLACE") for k in kinds):
            residue[t] = "ui_forms"
            continue
        if any(related(t, u) for u in types if u != t):
            residue[t] = "ui_related"
            continue
        tre = re.escape(t)
        ovr = re.compile(r"^" + tre + r"/(?:proc/)?(" + "|".join(OVERRIDES) + r")\(", re.M)
        if ovr.search(tree_text) or re.search(r"^CAPABILITIES\(" + tre + r"\)[^\n]*\n(?:[ \t][^\n]*\n)*?[ \t]+interface\(", tree_text, re.M):
            residue[t] = "ui_override"
            continue
        acts = []
        bad = None
        for k, rel, idx, text in rs:
            if k != "UI_ACT":
                continue
            inner = inner_of_call(text, "UI_ACT")
            if inner is None:
                bad = "ui_forms"
                break
            parts = split_args(inner)
            if len(parts) < 3 or parts[0] != t:
                bad = "ui_forms"
                break
            am = re.match(r'^"([A-Za-z0-9_-]+)"$', parts[1])
            if not am or not re.match(r"^[A-Za-z_]\w*$", parts[2]):
                bad = "act_name"
                break
            specs = []
            for sp in parts[3:]:
                sm = re.match(r'^UI_ARG_(NUM|INT|VALUE|TEXT)\(\s*"([A-Za-z_][A-Za-z0-9_]*)"\s*(?:,\s*(.*))?\)$', sp)
                if not sm or sm.group(2) in RESERVED:
                    bad = "arg_kind"
                    break
                bounds = split_args(sm.group(3)) if sm.group(3) else []
                if sm.group(1) == "VALUE" and bounds:
                    bad = "arg_kind"
                    break
                if sm.group(1) == "TEXT" and len(bounds) > 1:
                    bad = "arg_kind"
                    break
                if sm.group(1) in ("NUM", "INT") and len(bounds) not in (0, 2):
                    bad = "arg_kind"
                    break
                specs.append((sm.group(1), sm.group(2), bounds))
            if bad:
                break
            acts.append({"rel": rel, "idx": idx, "action": am.group(1), "proc": parts[2], "specs": specs})
        if bad:
            residue[t] = bad
            continue
        if len({a["action"] for a in acts}) != len(acts) or len({a["proc"] for a in acts}) != len(acts):
            residue[t] = "proc_shared"
            continue
        if not acts:
            residue[t] = "no_ops"  # a window with no buttons has nothing to type (ui_types) and nothing to gain
            continue
        data_rows = [r for r in rs if r[0] in ("UI_DATA", "UI_DATA_REPLACE")]
        data = None
        if len(data_rows) > 1:
            residue[t] = "data_rows"
            continue
        if data_rows:
            dinner = inner_of_call(data_rows[0][3], "UI_DATA")
            dparts = split_args(dinner) if dinner is not None else []
            if len(dparts) < 2 or dparts[0] != t:
                residue[t] = "data_rows"
                continue
            fields = []
            for dp in dparts[1:]:
                fm = re.match(r'^"([^"]*)"$', dp)
                if not fm:
                    fields = None
                    break
                txt = fm.group(1)
                mm = re.match(r"^merge:(\w+)(?:\{[^}]*\})?$", txt)
                if mm:
                    fields.append(("merge", mm.group(1), None))
                    continue
                key = None
                if "=" in txt:
                    key, txt = txt.split("=", 1)
                    if not re.match(r"^[A-Za-z_]\w*$", key):
                        fields = None
                        break
                kind = "var"
                if txt.startswith("proc:"):
                    kind = "proc"
                    txt = txt[5:]
                elif txt.startswith("slot:") or txt.startswith("merge:"):
                    fields = None
                    break
                name = txt.split(":", 1)[0]
                if not re.match(r"^[A-Za-z_]\w*$", name):
                    fields = None
                    break
                fields.append((kind, name, key or name))
            if not fields:
                residue[t] = "data_rows"
                continue
            data = {"row": data_rows[0], "fields": fields}
        plan = {"type": t, "window": window, "title": title, "acts": acts, "data": data, "rows": rs, "handlers": []}
        # ---- handlers
        for a in acts:
            pat = re.compile(r"^UI_ACT_PROC\(" + tre + r",\s*" + re.escape(a["proc"]) + r"\)\s*(//.*)?$")
            hit = None
            for rel in {r[1] for r in rs} | set(files):
                f = files[rel]
                for i, l in enumerate(f.lines):
                    if pat.match(l):
                        hit = (rel, i)
                        break
                if hit:
                    break
            if not hit:
                bad = "proc_missing"
                break
            rel, i = hit
            f = files[rel]
            first, last = body_range(f.lines, i)
            body_lines = f.lines[first : last + 1]
            body = "\n".join(strip_code(l) for l in body_lines)
            # references elsewhere: the row, the definition and nothing else
            occ = len(words_in(other_mentions, a["proc"]))
            if occ != 0:
                bad = "proc_shared"
                break
            for w in ("ui", "state", "action", "update_icon"):
                if words_in(body, w):
                    bad = "body_uses"
                    break
            if bad:
                break
            declared = [s[1] for s in a["specs"]]
            body_c = "\n".join(strip_code(l, keep=True) for l in body_lines)
            for m2 in re.finditer(r"\bparams\b(\s*\[\s*\"([A-Za-z_][A-Za-z0-9_]*)\"\s*\])?", body_c):
                if not m2.group(1) or m2.group(2) not in declared:
                    bad = "body_uses"
                    break
            if bad:
                break
            for w in words_in(body, "A"):
                bad = "name_clash"
                break
            if bad:
                break
            for d in declared:
                # a declared name must not already be a word of the body outside params["d"]
                stripped = re.sub(r"\bparams\s*\[\s*\"" + d + r"\"\s*\]", "", body_c)
                stripped = "\n".join(strip_code(x) for x in stripped.split("\n"))
                if words_in(stripped, d):
                    bad = "name_clash"
                    break
            if bad:
                break
            for bl in body.split("\n"):
                t2 = bl.strip()
                rm = re.match(r"^return\b\s*(.*)$", t2)
                if rm and rm.group(1).strip() not in ("", "TRUE", "FALSE", "1", "0", "null"):
                    bad = "body_uses"
                    break
                if re.match(r"^\.\s*[^\w\s=]", t2) or re.match(r"^\.\s*=\s*(?!(?:TRUE|FALSE|1|0|null)\s*$)\S", t2) or re.search(r"\.\.\(", t2):
                    bad = "body_uses"
                    break
            if bad:
                break
            plan["handlers"].append({"act": a, "rel": rel, "idx": i, "first": first, "last": last})
        if bad:
            residue[t] = bad
            continue
        # ---- the data proc
        if data:
            helper_bad = False
            helpers = {}
            for kind, name, key in data["fields"]:
                if kind not in ("merge", "proc"):
                    continue
                dpat = re.compile(r"^" + tre + r"/(?:proc/)?" + re.escape(name) + r"\(([^)]*)\)\s*(//.*)?$")
                hit = None
                for rel, f in files.items():
                    for i, l in enumerate(f.lines):
                        if dpat.match(l):
                            hit = (rel, i, dpat.match(l).group(1))
                            break
                    if hit:
                        break
                if not hit or len(words_in(other_mentions, name)) != 0 or name in helpers:
                    helper_bad = True
                    break
                rel, i, params = hit
                ps = [p.strip() for p in params.split(",")]
                if len(ps) != 3:
                    helper_bad = True
                    break
                un = ps[0].split("/")[-1]
                uin, stn = ps[1].split("/")[-1], ps[2].split("/")[-1]
                f = files[rel]
                first, last = body_range(f.lines, i)
                body = "\n".join(strip_code(l) for l in f.lines[first : last + 1])
                if words_in(body, uin) or words_in(body, stn) or words_in(body, "A") or re.search(r"\.\.\(", body):
                    helper_bad = True
                    break
                helpers[name] = {"rel": rel, "idx": i, "first": first, "last": last, "user": un, "uses_user": bool(words_in(body, un))}
            if helper_bad:
                residue[t] = "data_rows"
                continue
            data["helpers"] = helpers
            data["rename"] = len(data["fields"]) == 1 and data["fields"][0][0] == "merge"
        plans[t] = plan
    # ---- apply
    converted_acts = 0
    for t, plan in sorted(plans.items()):
        converted_acts += len(plan["acts"])
        if check:
            continue
        tre = re.escape(t)
        entries = []
        entries.append('interface("%s"%s)' % (plan["window"], (', title = "%s"' % plan["title"]) if plan["title"] is not None else ""))
        for a in plan["acts"]:
            parts = ['"%s"' % a["action"]]
            for kind, name, bounds in a["specs"]:
                if kind == "VALUE":
                    parts.append('arg("%s")' % name)
                elif kind == "TEXT":
                    parts.append('arg("%s", schema_text(%s))' % (name, bounds[0] if bounds else "4096"))
                else:
                    fn = "num" if kind == "NUM" else "int"
                    parts.append('arg("%s", %s(%s))' % (name, fn, ", ".join(bounds)))
            ui = 'ui_act("%s"%s)' % (a["action"], "".join(", " + p for p in parts[1:]))
            entries.append('op("%s", %s, then(PROC_REF(%s)))' % (a["action"], ui, a["proc"]))
        # handlers
        for h in plan["handlers"]:
            a = h["act"]
            f = files[h["rel"]]
            declared = [s[1] for s in a["specs"]]
            for k in range(h["first"], h["last"] + 1):
                l = f.lines[k]
                for d in declared:
                    l = re.sub(r"\bparams\s*\[\s*\"" + d + r"\"\s*\]", d, l)
                f.lines[k] = l
            body = "\n".join(strip_code(l) for l in f.lines[h["first"] : h["last"] + 1])
            sig = t + "/proc/" + a["proc"] + "(datum/act/op/A" + "".join(", " + d for d in declared) + ")"
            # insert `user` after the leading settings
            extra = ""
            if words_in(body, "user"):
                after = h["idx"]
                k = h["first"]
                while k <= h["last"]:
                    s = strip_code(f.lines[k]).strip()
                    if s == "":
                        k += 1
                        continue
                    if s.startswith(SETTINGS) and (("(" not in s) or s.endswith(")")):
                        after = k
                        k += 1
                        continue
                    break
                indent = "\t"
                for k2 in range(h["first"], h["last"] + 1):
                    if f.lines[k2].strip():
                        indent = re.match(r"^[ \t]*", f.lines[k2]).group(0)
                        break
                line = indent + "var/mob/user = A.actor"
                if after == h["idx"]:
                    extra = "\n" + line
                else:
                    f.lines[after] = f.lines[after] + "\n" + line
            f.lines[h["idx"]] = sig + extra
        # data proc
        d = plan["data"]
        if d and d["rename"]:
            # one merge proc and nothing else: the proc is the output (the SMES, afbbe2a3c8)
            h = d["helpers"][d["fields"][0][1]]
            f = files[h["rel"]]
            sig = t + "/ui_data(datum/act/eval/A)"
            extra = ""
            if h["uses_user"]:
                indent = "\t"
                for k2 in range(h["first"], h["last"] + 1):
                    if f.lines[k2].strip():
                        indent = re.match(r"^[ \t]*", f.lines[k2]).group(0)
                        break
                extra = "\n" + indent + "var/mob/%s = A.actor" % h["user"]
            f.lines[h["idx"]] = sig + extra
            f.dirty = True
        elif d:
            # fields and procs composed into one output, each helper kept as it is and called with the viewer
            out = [t + "/ui_data(datum/act/eval/A)", "\tvar/list/data = list()"]
            n = 0
            for kind, name, key in d["fields"]:
                if kind == "var":
                    out.append('\tdata["%s"] = %s' % (key, name))
                elif kind == "proc":
                    out.append('\tdata["%s"] = %s(A.actor, null, null)' % (key, name))
                else:
                    n += 1
                    out += ["\tvar/list/merged_%d = %s(A.actor, null, null)" % (n, name), "\tif(islist(merged_%d))" % n, "\t\tfor(var/merged_key_%d in merged_%d)" % (n, n), "\t\t\tdata[merged_key_%d] = merged_%d[merged_key_%d]" % (n, n, n)]
            out.append("\treturn data")
            # placed where the data row was
            drow = d["row"]
            files[drow[1]].lines[drow[2]] = "\n".join(out)
            files[drow[1]].dirty = True
        # delete the legacy rows; the declaration line becomes the block (or goes, when the type already has one)
        block_file = None
        for rel, f in files.items():
            for i, l in enumerate(f.lines):
                if l is not None and re.match(r"^CAPABILITIES\(" + tre + r"\)\s*(//.*)?$", l):
                    block_file = (rel, i)
        for kind, rel, idx, text in plan["rows"]:
            f = files[rel]
            if kind in ("UI_ACT_PROC", "DECLARE_UI_STATE"):
                continue  # the state row stays: it is its own legacy form, read by ui_open() whether or not a DECLARE_UI stands beside it
            if kind in ("UI_DATA", "UI_DATA_REPLACE") and d and not d["rename"]:
                continue  # the composed ui_data() stands where the row was
            if kind == "DECLARE_UI":
                if block_file:
                    f.lines[idx] = None
                else:
                    f.lines[idx] = "CAPABILITIES(%s)" % t + "".join("\n\t" + e for e in entries)
            else:
                f.lines[idx] = None
        if block_file:
            rel, i = block_file
            f = files[rel]
            first, last = body_range(f.lines, i)
            f.lines[last] = f.lines[last] + "".join("\n\t" + e for e in entries)
        for rel in {r[1] for r in plan["rows"]} | {h["rel"] for h in plan["handlers"]} | ({hp["rel"] for hp in d["helpers"].values()} if d else set()) | ({block_file[0]} if block_file else set()):
            files[rel].dirty = True
    if not check:
        for f in files.values():
            if f.dirty:
                f.save()
    if "--why" in sys.argv:
        for t, why in sorted(residue.items()):
            print("WHY	%s	%s	%s" % (why, t, ",".join(sorted({r[0] for r in rows[t]}))))
    by = defaultdict(list)
    for t, why in residue.items():
        by[why].append(t)
    print("ui_declare: %d types converted (%d ui_act ops)%s; residue %d types" % (len(plans), converted_acts, " (check)" if check else "", len(residue)))
    for why, ts in sorted(by.items(), key=lambda kv: -len(kv[1])):
        print("    %-14s %4d" % (why, len(ts)))
        if sites:
            for t in sorted(ts):
                print("        " + t)
    return 1 if (check and plans) else 0


if __name__ == "__main__":
    sys.exit(main())
