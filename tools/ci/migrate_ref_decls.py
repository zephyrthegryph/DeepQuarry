"""One-shot migration: the per-kind REF_<KIND>(PATH, NAMES) / REF_VAR forms and the
hand-written declared_*_vars() overrides -> the single DECLARE_REF(PATH, "var", KIND, OPT)
form (code/__defines/lifecycle.dm). Kept for reference; running it twice is a no-op.

    python tools/ci/migrate_ref_decls.py [--dry]
"""
import glob
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

NAME_KINDS = {"OWNED", "OWNED_LIST", "OWNED_VALUES", "SPILL", "SPILL_LIST", "HELD", "DROP",
              "KEEP", "DEF", "STATIC", "WEAK_LIST", "TRANSIENT"}
ASSOC_KINDS = {"PAIR", "BACKLIST", "BACKLIST_HANDLE", "BACK_HANDLE", "BACK_VIA", "LIST_BACK",
               "BACK", "QUEUE_MEMBER"}
# REF_QUEUE_MEMBER is spelled QUEUE in the new form.
NEW_KIND = {"QUEUE_MEMBER": "QUEUE"}
ALL = sorted(NAME_KINDS | ASSOC_KINDS, key=len, reverse=True)
LINE = re.compile(r"^REF_(" + "|".join(ALL) + r")\((.*)\)\s*(//.*)?$")
VAR_LINE = re.compile(r"^REF_VAR\(\s*(/[\w/]+)\s*,\s*(\w+)\s*,\s*(/[\w/]+)\s*,\s*(\w+)\s*\)\s*(//.*)?$")
PVAR_LINE = re.compile(r"^REF_(PAIR|BACKLIST)_VAR\(\s*(/[\w/]+)\s*,\s*(/[\w/]+)\s*,\s*(\w+)\s*,\s*(\"\w+\")\s*\)\s*(//.*)?$")

# Hand-written overrides: proc name -> kind.
PROC_KIND = {
    "declared_owned_vars": "OWNED", "declared_owned_list_vars": "OWNED_LIST",
    "declared_owned_value_vars": "OWNED_VALUES", "declared_pair_vars": "PAIR",
    "declared_backlist_vars": "BACKLIST",
}


def split_top(s, sep=","):
    out, depth, cur, q = [], 0, "", False
    i = 0
    while i < len(s):
        c = s[i]
        if q:
            cur += c
            if c == "\\":
                cur += s[i + 1]
                i += 1
            elif c == '"':
                q = False
        elif c == '"':
            q = True
            cur += c
        elif c in "([{":
            depth += 1
            cur += c
        elif c in ")]}":
            depth -= 1
            cur += c
        elif c == sep and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += c
        i += 1
    if cur.strip():
        out.append(cur.strip())
    return out


def split_assoc(entry):
    parts = split_top(entry, "=")
    if len(parts) != 2:
        raise ValueError("not an assoc entry: " + entry)
    key, val = parts
    if re.fullmatch(r"[a-z_]\w*", key):
        key = '"%s"' % key
    return key, val


def entries(kind, spec):
    """[(var_expr, opt_expr)] for one old declaration."""
    spec = spec.strip()
    m = re.fullmatch(r"list\((.*)\)", spec, re.S)
    items = split_top(m.group(1)) if m else [spec]
    out = []
    for it in items:
        if kind in NAME_KINDS:
            if not re.fullmatch(r'"[^"]*"', it):
                raise ValueError("non-literal name: " + it)
            out.append((it, "null"))
        else:
            out.append(split_assoc(it))
    return out


def emit(path, kind, pairs, comment):
    tail = ("\t" + comment) if comment else ""
    nk = NEW_KIND.get(kind, kind)
    return ["DECLARE_REF(%s, %s, %s, %s)%s" % (path, var, nk, opt, tail) for var, opt in pairs]


def migrate_text(text, rel, stats):
    lines = text.split("\n")
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        s = line.rstrip("\r")
        m = LINE.match(s)
        if m:
            kind = m.group(1)
            args = split_top(m.group(2))
            if len(args) != 2:
                raise ValueError("%s:%d: bad args %s" % (rel, i + 1, s))
            new = emit(args[0], kind, entries(kind, args[1]), m.group(3))
            out.extend(new)
            stats["old"] += 1
            stats["new"] += len(new)
            i += 1
            continue
        m = VAR_LINE.match(s)
        if m:
            path, kind, vtype, name, com = m.groups()
            out.append("%s/var%s/%s" % (path, vtype, name))
            out.extend(emit(path, kind, [('"%s"' % name, "null")], com))
            stats["old"] += 1
            stats["new"] += 1
            i += 1
            continue
        m = PVAR_LINE.match(s)
        if m:
            kind, path, vtype, name, other, com = m.groups()
            out.append("%s/var%s/%s" % (path, vtype, name))
            out.extend(emit(path, kind, [('"%s"' % name, other)], com))
            stats["old"] += 1
            stats["new"] += 1
            i += 1
            continue
        # Hand-written override: header + body until the next indent-0 line.
        hm = re.match(r"^(/[\w/]*?)/(" + "|".join(PROC_KIND) + r")\(\)\s*$", s)
        if hm and not rel.endswith("datums/lifecycle/links.dm"):
            body = []
            j = i + 1
            while j < len(lines) and (lines[j].startswith("\t") or not lines[j].strip()):
                if lines[j].strip():
                    body.append(lines[j].strip())
                j += 1
            joined = " ".join(body)
            kind = PROC_KIND[hm.group(2)]
            lm = re.search(r"list\((.*)\)", joined)
            pm = re.search(r'\+\s*(".*?")\s*$', joined)
            if pm:
                spec = pm.group(1)
            elif lm:
                spec = "list(%s)" % lm.group(1)
            else:
                raise ValueError("%s:%d: can't read override %s" % (rel, i + 1, joined))
            out.extend(emit(hm.group(1), kind, entries(kind, spec), None))
            out.append("")
            stats["old"] += 1
            stats["procs"] += 1
            i = j
            continue
        out.append(line)
        i += 1
    return "\n".join(out)


def main(argv):
    dry = "--dry" in argv
    stats = {"old": 0, "new": 0, "procs": 0, "files": 0}
    errors = []
    skip = ("code/__defines/lifecycle.dm",)
    for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True) + \
            glob.glob(os.path.join(ROOT, "maps", "**", "*.dm"), recursive=True):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        if rel in skip:
            continue
        with open(path, encoding="latin-1", newline="") as h:
            text = h.read()
        if "REF_" not in text and "declared_" not in text:
            continue
        before = dict(stats)
        try:
            new = migrate_text(text, rel, stats)
        except ValueError as e:
            errors.append(str(e) if rel in str(e) else rel + ": " + str(e))
            stats.update(before)
            continue
        if new != text:
            stats["files"] += 1
            if not dry:
                with open(path, "w", encoding="latin-1", newline="") as h:
                    h.write(new)
    print(stats)
    for e in errors:
        print("ERROR", e)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
