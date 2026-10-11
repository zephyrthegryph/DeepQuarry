"""Moves base-type vars into a per-instance table (cooldown table or sparse slots), driven by the compiler's "undefined var" errors.

  python tools/dx/codemods/var_to_table.py <cooldown|sparse|stat:STAT_X:setter|expr|READ|WRITE> <compile log> <name> [<name> ...] [--apply] [--files ...] [--dirs ...]

Run after the vars were deleted (and declared with cooldowns() / sparse()) and the tree compiled once: every
`file:line:error: <expr>: undefined var` whose last name is one of <name>s is rewritten on that line.
  cooldown:  `X.n = v` -> `cooldown_set_end(X, n, v)`, `X.n += v` -> `cooldown_set_end(X, n, cooldown_end(X, n) + (v))`,
             any other `X.n` -> `cooldown_end(X, n)`;
  sparse:    `X.n = v` -> `sparse_set(X, n, v)`, `X.n += v` -> `sparse_set(X, n, sparse_get(X, n) + (v))`, other reads -> `sparse_get(X, n)`.
A bare `n` is src's. Lines it cannot rewrite are printed as residue. Dry run unless --apply.
"""
import _guard  # noqa: F401  (must be first: --help, dry run, write scope)
import re
import sys

REF = r"[A-Za-z_]\w*(?:\(\))?(?:(?:\?\.|\.)[A-Za-z_]\w*(?:\(\))?)*"
ERR = re.compile(r"^(?P<file>[^:]+\.dm):(?P<line>\d+):error: (?P<expr>.*?): undefined var")

args = [a for a in sys.argv[1:] if not a.startswith("--")]
MODE, LOG, NAMES = args[0], args[1], set(args[2:])
TEMPLATES = None
if MODE == "cooldown":
    GET, SET = "cooldown_end", "cooldown_set_end"
elif MODE == "sparse":
    GET, SET = "sparse_get", "sparse_set"
elif MODE.startswith("stat:"):
    # stat:STAT_X:setter -- reads stat_value(X, STAT_X), writes setter(X, v)
    _, STAT_ID, SETTER = MODE.split(":")
    GET, SET = None, None
    TEMPLATES = ("stat_value({h}, %s)" % STAT_ID, SETTER + "({h}, {v})")
else:
    # expr|<read template>|<write template>, with {h} the holder and {v} the value: expr|nutrition_of({h})|{h}.set_nutrition({v})
    _, READ_T, WRITE_T = MODE.split("|")
    GET, SET = None, None
    TEMPLATES = (READ_T, WRITE_T)


def get(h, n):
    return TEMPLATES[0].format(h=h) if TEMPLATES else "%s(%s, %s)" % (GET, h, n)


def put(h, n, v):
    return TEMPLATES[1].format(h=h, v=v) if TEMPLATES else "%s(%s, %s, %s)" % (SET, h, n, v)


def rewrite(line, n):
    orig = line
    # a statement write: [X.]n op= v
    m = re.match(r"^(\s*)(?:(" + REF + r")\??\.)?" + n + r"\s*([-+]?)=(?!=)\s*(.+?)\s*(//.*)?$", line)
    if m:
        indent, ref, op, value, comment = m.groups()
        ref = ref or "src"
        value = re.sub(r"(?<![\w.:/])(" + REF + r")\??\." + n + r"\b(?!\s*\()", lambda x: get(x.group(1), n), value)
        if op:
            value = "%s %s (%s)" % (get(ref, n), op, value)
        return "%s%s%s" % (indent, put(ref, n, value), (" " + comment) if comment else "")
    line = re.sub(r"(?<![\w.:/])(" + REF + r")\??\." + n + r"\b(?!\s*\()", lambda x: get(x.group(1), n), line)
    # bare reads (src's): skip the name where it already sits inside a table call (`cooldown_end(X, n)`)
    keep = re.compile(r"(?:cooldown_\w+|sparse_\w+|stat_value)\([^()]*?,\s*" + n + r"\b")
    spans = [m.span() for m in keep.finditer(line)]
    out, pos = [], 0
    for m in re.finditer(r"(?<![\w.:/?#])\b" + n + r"\b(?!\s*[(:])", line):
        if any(a <= m.start() < b for a, b in spans):
            continue
        out.append(line[pos:m.start()])
        out.append(get("src", n))
        pos = m.end()
    out.append(line[pos:])
    line = "".join(out)
    return line if line != orig else None


def main():
    sites = {}
    lines_of_log = open(LOG, encoding="utf-8", errors="replace").read().split("\n")
    # DreamChecker: "file, line N, column C:" then "error: undefined field: \"n\" on /type"
    for i, raw in enumerate(lines_of_log[:-1]):
        loc = re.match(r"^(.+\.dm), line (\d+), column \d+:", raw.strip())
        err = re.match(r'^error: undefined field: "(\w+)"', lines_of_log[i + 1].strip())
        if loc and err and err.group(1) in NAMES:
            sites.setdefault(loc.group(1).replace("\\", "/"), {}).setdefault(int(loc.group(2)), set()).add(err.group(1))
    for raw in lines_of_log:
        m = ERR.match(raw.strip())
        if not m:
            continue
        n = re.split(r"\??\.", m.group("expr").strip())[-1]
        if n in NAMES:
            sites.setdefault(m.group("file").replace("\\", "/"), {}).setdefault(int(m.group("line")), set()).add(n)
    residue = []
    for path, at in sites.items():
        with open(path, encoding="utf-8", errors="surrogateescape", newline="") as fh:
            lines = fh.read().split("\n")
        for ln, ns in at.items():
            text = lines[ln - 1]
            for n in sorted(ns):
                r = rewrite(text, n)
                if r is None:
                    residue.append("%s:%d: %s: %s" % (path, ln, n, lines[ln - 1].strip()))
                else:
                    text = r
            lines[ln - 1] = text
        with open(path, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
            fh.write("\n".join(lines))
    for r in residue:
        print("residue " + r)
    print("var_to_table %s: %d files, %d lines, %d residue" % (MODE, len(sites), sum(len(x) for x in sites.values()), len(residue)))


if __name__ == "__main__":
    main()
