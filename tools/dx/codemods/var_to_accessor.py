"""Replaces deleted base-type reference vars with their accessor and setter procs, driven by the compiler's errors.

  python tools/dx/codemods/var_to_accessor.py <compile log> [--apply] [--files ...] [--dirs ...]

Run after the vars in SPECS were deleted (their links declared, the accessors written) and the tree compiled once. On every line the
compiler (`file:line:error: <expr>: undefined var`, or `nameof: requires a var`) or DreamChecker (`undefined field: "v"`) reports:
  * `rel_set(H, nameof(v), x)` (also `nameof(H.v)`, `nameof(/type::v)`) -> the setter `set_x(H, x)`; `rel_clear(H, nameof(v))` -> `set_x(H, null)`;
  * a statement `[X.]v = x` -> the setter; any other `X.v` -> the reader `x_of(X)` (a bare `v` is src's).
Lines it cannot rewrite exactly are printed as residue. Dry run unless --apply.
"""
import _guard  # noqa: F401  (must be first: --help, dry run, write scope)
import re
import sys

SPECS = {
    "master": ("item_master({h})", "set_item_master({h}, {v})"),
    "vore_selected": ("vore_selected_of({h})", "set_vore_selected({h}, {v})"),
    "spont_belly_front": ("spont_belly_of({h}, LK_SPONT_FRONT)", "set_spont_belly({h}, LK_SPONT_FRONT, {v})"),
    "spont_belly_rear": ("spont_belly_of({h}, LK_SPONT_REAR)", "set_spont_belly({h}, LK_SPONT_REAR, {v})"),
    "spont_belly_left": ("spont_belly_of({h}, LK_SPONT_LEFT)", "set_spont_belly({h}, LK_SPONT_LEFT, {v})"),
    "spont_belly_right": ("spont_belly_of({h}, LK_SPONT_RIGHT)", "set_spont_belly({h}, LK_SPONT_RIGHT, {v})"),
    "tf_form": ("tf_form_of({h})", "set_tf_form({h}, {v})"),
    "tf_form_mind": ("tf_form_mind_of({h})", "set_tf_form_mind({h}, {v})"),
    "nest": ("nest_of({h})", "set_nest({h}, {v})"),
}
REF = r"[A-Za-z_]\w*(?:\(\))?(?:(?:\?\.|\.)[A-Za-z_]\w*(?:\(\))?)*"
ERR = re.compile(r"^(?P<file>[^:]+\.dm):(?P<line>\d+):error: (?P<expr>.*?): (?:undefined var|requires a var)")


def get(n, h):
    return SPECS[n][0].format(h=h)


def put(n, h, v):
    return SPECS[n][1].format(h=h, v=v)


def args_of(text, start):
    """The comma-split top-level arguments of the call whose '(' is at text[start - 1], and the index after its ')'."""
    depth, cur, out, i = 0, "", [], start
    while i < len(text):
        c = text[i]
        if c in "([":
            depth += 1
        elif c in ")]":
            if depth == 0:
                out.append(cur)
                return out, i + 1
            depth -= 1
        if c == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += c
        i += 1
    return None, None


def rewrite(line, n):
    orig = line
    pos = 0
    while True:
        m = re.compile(r"\b(rel_set|rel_clear)\(").search(line, pos)
        if not m:
            break
        pos = m.end()
        args, end = args_of(line, m.end())
        if args and len(args) > 1 and re.search(r"nameof\(\s*(?:[\w./:]*?(?:\.|::))?" + n + r"\s*\)", args[1]):
            holder = args[0].strip()
            inner = re.search(r"nameof\(\s*(" + REF + r")\." + n + r"\s*\)", args[1])
            if inner:
                holder = inner.group(1)
            value = args[2].strip() if m.group(1) == "rel_set" and len(args) > 2 else "null"
            repl = put(n, holder, value)
            line = line[:m.start()] + repl + line[end:]
            pos = m.start() + len(repl)
    if line != orig:
        return line
    w = re.match(r"^(\s*)(?:(" + REF + r")\??\.)?" + n + r"\s*=(?!=)\s*(.+?)\s*(//.*)?$", line)
    if w:
        indent, ref, value, comment = w.groups()
        return indent + put(n, ref or "src", value) + ((" " + comment) if comment else "")
    line = re.sub(r"(?<![\w.:/])(" + REF + r")\??\." + n + r"\b(?!\s*\()", lambda x: get(n, x.group(1)), line)
    protected = [x.span() for x in re.finditer(r"\b\w+_of\([^()]*\)|nameof\([^()]*\)|LK_\w+", line)]
    out, pos = [], 0
    for x in re.finditer(r"(?<![\w.:/?#])\b" + n + r"\b(?!\s*[(:=])", line):
        if any(a <= x.start() < b for a, b in protected):
            continue
        out.append(line[pos:x.start()])
        out.append(get(n, "src"))
        pos = x.end()
    out.append(line[pos:])
    line = "".join(out)
    return line if line != orig else None


def main():
    log = [a for a in sys.argv[1:] if not a.startswith("--")][0]
    text = open(log, encoding="utf-8", errors="replace").read().split("\n")
    sites = {}
    for i, raw in enumerate(text):
        m = ERR.match(raw.strip())
        if m:
            path = m.group("file").replace("\\", "/")
            names = [x.replace("()", "") for x in re.split(r"\??\.", m.group("expr").strip())]
            hit = [x for x in names if x in SPECS]
            if m.group("expr").strip() == "nameof":
                src = open(path, encoding="utf-8", errors="replace").read().split("\n")[int(m.group("line")) - 1]
                hit = [x for x in SPECS if re.search(r"nameof\([^)]*\b" + x + r"\)", src)]
            for x in hit[:1]:
                sites.setdefault(path, {}).setdefault(int(m.group("line")), set()).add(x)
        loc = re.match(r"^(.+\.dm), line (\d+), column \d+:", raw.strip())
        if loc and i + 1 < len(text):
            err = re.match(r'^error: undefined field: "(\w+)"', text[i + 1].strip())
            if err and err.group(1) in SPECS:
                sites.setdefault(loc.group(1).replace("\\", "/"), {}).setdefault(int(loc.group(2)), set()).add(err.group(1))
    residue = []
    for path, at in sites.items():
        with open(path, encoding="utf-8", errors="surrogateescape", newline="") as fh:
            lines = fh.read().split("\n")
        for ln, ns in at.items():
            cur = lines[ln - 1]
            for n in sorted(ns):
                r = rewrite(cur, n)
                if r is None:
                    residue.append("%s:%d: %s: %s" % (path, ln, n, cur.strip()))
                else:
                    cur = r
            lines[ln - 1] = cur
        with open(path, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
            fh.write("\n".join(lines))
    for r in residue:
        print("residue " + r)
    print("var_to_accessor: %d files, %d lines, %d residue" % (len(sites), sum(len(x) for x in sites.values()), len(residue)))


if __name__ == "__main__":
    main()
