"""Rewrites set_light(range, power, color, on) calls to set_glow(holder, GLOW(range, power, color)[, on]) (doc/rewrite/proposals/base_vars.md, "Light").

  python tools/dx/codemods/set_light_to_glow.py [--apply]

`X.set_light(...)` becomes `set_glow(X, GLOW(...))`, a bare `set_light(...)` inside a proc `set_glow(src, GLOW(...))`. Named arguments
(l_range =, l_power =, l_color =, l_on =) map by name; a missing part is null (kept). Calls it cannot parse are printed. Dry run unless --apply.
"""
import _guard  # noqa: F401  (must be first: --help, dry run, write scope)
import os
import re
import sys

APPLY = "--apply" in sys.argv
CALL = re.compile(r"(?<![\w/])((?:[A-Za-z_][\w]*(?:\(\))?(?:\??\.[A-Za-z_]\w*(?:\(\))?)*)\??\.)?set_light\(")
NAMES = ["l_range", "l_power", "l_color", "l_on"]


def split_args(s):
    out, depth, cur, q = [], 0, "", None
    for c in s:
        if q:
            cur += c
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
            out.append(cur.strip())
            cur = ""
            continue
        cur += c
    if cur.strip():
        out.append(cur.strip())
    return out


def rewrite(text, path, residue):
    out, pos = [], 0
    for m in CALL.finditer(text):
        if m.start() < pos:
            continue
        line_start = text.rfind("\n", 0, m.start()) + 1
        if re.match(r"\s*(/[\w/]*)?proc/set_light\(|/atom/proc/set_light", text[line_start:m.end()]) or "proc/set_light(" in text[line_start:m.end()]:
            continue  # the definition
        i, depth = m.end(), 1
        while i < len(text) and depth:
            if text[i] == "(":
                depth += 1
            elif text[i] == ")":
                depth -= 1
            elif text[i] == "\n":
                break
            i += 1
        if depth:
            residue.append("%s: %s" % (path, text[m.start():m.start() + 80]))
            continue
        args = split_args(text[m.end():i - 1])
        vals = [None, None, None, None]
        ok = True
        for k, a in enumerate(args):
            nm = re.match(r"^(l_range|l_power|l_color|l_on)\s*=\s*(.+)$", a)
            if nm:
                vals[NAMES.index(nm.group(1))] = nm.group(2)
            elif k < 4:
                vals[k] = a
            else:
                ok = False
        if not ok:
            residue.append("%s: %s" % (path, text[m.start():i]))
            continue
        holder = (m.group(1) or "").rstrip(".").rstrip("?") or "src"
        glow = "GLOW(%s, %s, %s)" % tuple(v if v is not None else "null" for v in vals[:3])
        repl = "set_glow(%s, %s%s)" % (holder, glow, (", " + vals[3]) if vals[3] is not None else "")
        out.append(text[pos:m.start()])
        out.append(repl)
        pos = i
    out.append(text[pos:])
    return "".join(out)


def main():
    residue, changed = [], 0
    for d, _, files in os.walk("code"):
        if "_generated" in d.replace("\\", "/"):
            continue
        for f in files:
            if not f.endswith(".dm"):
                continue
            p = os.path.join(d, f).replace("\\", "/")
            with open(p, encoding="utf-8", errors="surrogateescape", newline="") as fh:
                text = fh.read()
            if "set_light(" not in text:
                continue
            new = rewrite(text, p, residue)
            if new != text:
                changed += 1
                if APPLY:
                    with open(p, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
                        fh.write(new)
    print("set_light_to_glow: %d files %s" % (changed, "changed" if APPLY else "would change"))
    for r in residue:
        print("RESIDUE", r)


if __name__ == "__main__":
    main()
