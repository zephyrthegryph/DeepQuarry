#!/usr/bin/env python3
"""Census of data-only leaf types: the types a variant collapse (code/content/variants/README.md) can remove.

A data-only leaf is a type nothing inherits from that declares no proc, no new var and no CAPABILITIES entry, and only sets var defaults.
Each such type costs BYOND a per-(type, proc) table (about 12.5 KB for an /atom subtype, much less for a plain /datum), so a family of them
is one parent type plus a row table.

  python3 tools/ci/variant_census.py            # rewrite doc/rewrite/variant_census.md
  python3 tools/ci/variant_census.py --check    # fail when the committed census is stale
  python3 tools/ci/variant_census.py --json     # machine-readable census (family -> leaf -> overrides) on stdout
  python3 tools/ci/variant_census.py --list PARENT   # the data-only leaves directly under PARENT, with their overrides

The scan is textual: comments and string contents are blanked and an indentation-aware path stack names each statement's type. It reads
code/ only; the unit tests (code/tests/) are left out.
"""
import os
import re
import sys

MEMBER_KW = {"var", "proc", "verb", "static", "global", "const", "tmp"}
ATOM_ROOTS = ("/obj", "/mob", "/turf", "/area", "/atom")
ROOTS = ATOM_ROOTS + ("/datum",)
# Model constants, not measurements: the memory report puts an /atom subtype at about 12.5 KB; a /datum subtype carries a much shorter proc table.
KB_ATOM = 12.5
KB_DATUM = 4.0
SKIP_DIRS = ("code/tests/",)
MACRO_ROOT = re.compile(r"^([A-Z_][A-Z0-9_]*)\s*\(\s*(/[\w/]+)")
HEAD_OK = re.compile(r"^/?[\w.]+(/[\w.]+)*$")


def clean(text):
    """Blank comments; replace string and file literals by empty ones. Newlines are kept."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        two = text[i:i + 2]
        if two == "//":
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if two == "/*":
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("\n" * text.count("\n", i, j))
            i = j
            continue
        if two == '{"':
            j = text.find('"}', i + 2)
            j = n if j < 0 else j + 2
            out.append('""' + "\n" * text.count("\n", i, j))
            i = j
            continue
        if c == '"':
            j = i + 1
            depth = 0
            while j < n:
                d = text[j]
                if d == "\\":
                    j += 2
                    continue
                if d == "[":
                    depth += 1
                elif d == "]" and depth:
                    depth -= 1
                elif d == '"' and depth == 0:
                    break
                elif d == "\n" and depth == 0:
                    break
                j += 1
            out.append('""')
            i = j + 1
            continue
        if c == "'":
            j = text.find("'", i + 1)
            if j < 0 or "\n" in text[i:j]:
                out.append(c)
                i += 1
                continue
            out.append("''")
            i = j + 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def statements(text):
    """Yield (indent, statement): lines joined while a bracket is open or after a trailing backslash."""
    buf = None
    indent = 0
    for ln in text.split("\n"):
        if buf is None:
            if not ln.strip():
                continue
            stripped = ln.lstrip("\t ")
            if stripped.startswith("#"):
                continue
            lead = ln[: len(ln) - len(stripped)]
            indent = lead.count("\t") + lead.count(" ") // 4
            buf = stripped
        else:
            buf += " " + ln.strip()
        depth = sum(buf.count(c) for c in "([{") - sum(buf.count(c) for c in ")]}")
        if buf.endswith("\\"):
            buf = buf[:-1]
            continue
        if depth > 0:
            continue
        yield indent, buf.strip()
        buf = None
    if buf:
        yield indent, buf.strip()


def split_assign(s):
    depth = 0
    for i, c in enumerate(s):
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "=" and depth == 0:
            nxt = s[i + 1:i + 2]
            prv = s[i - 1:i]
            if nxt == "=" or prv in ("!", "<", ">", "="):
                continue
            return s[:i].strip(), s[i + 1:].strip()
    return s, None


class T:
    def __init__(self, path):
        self.path = path
        self.procs = set()
        self.caps = 0
        self.newvars = set()
        self.overrides = {}
        self.files = set()
        self.children = 0


def parse_one(text, rel, get):
    stack = []  # (indent, type path, kind)
    for indent, st in statements(text):
        while stack and stack[-1][0] >= indent:
            stack.pop()
        top = stack[-1] if stack else None
        if top and top[2] in ("caps", "caps_in"):
            get(top[1]).caps += 1
            stack.append((indent, top[1], "caps_in"))
            continue
        if top and top[2] in ("member", "body", "other"):
            # inside a proc body or under a var: nothing here declares a type
            if top[2] == "other" and not top[1]:
                pass
            else:
                stack.append((indent, top[1], "body"))
                continue
        base = top[1] if top else ""
        m = MACRO_ROOT.match(st)
        if m and not top:
            t = get(m.group(2))
            t.files.add(rel)
            if m.group(1) == "CAPABILITIES":
                stack.append((indent, m.group(2), "caps"))
            else:
                t.caps += 1
            continue
        if not top and re.match(r"^[A-Z_][A-Z0-9_]*\s*\(", st):
            continue
        left, val = split_assign(st)
        paren = left.find("(")
        head = (left[:paren] if paren >= 0 else left).strip().replace(" ", "")
        if not head or not HEAD_OK.match(head):
            stack.append((indent, base, "other"))
            continue
        segs = [s for s in head.split("/") if s]
        absolute = head.startswith("/")
        prefix = [] if (absolute or not base) else [p for p in base.split("/") if p]
        mi = None
        for i, s in enumerate(segs):
            if s in MEMBER_KW:
                mi = i
                break
        if mi is not None:
            tp = prefix + segs[:mi]
            if not tp:
                stack.append((indent, base, "other"))
                continue
            tpath = "/" + "/".join(tp)
            t = get(tpath)
            t.files.add(rel)
            if segs[mi] in ("proc", "verb"):
                t.procs.add(segs[-1])
            else:
                t.newvars.add(segs[-1])
            stack.append((indent, tpath, "member"))
            continue
        if paren >= 0:
            tp = prefix + segs[:-1]
            if not tp:
                stack.append((indent, base, "other"))
                continue
            tpath = "/" + "/".join(tp)
            t = get(tpath)
            t.files.add(rel)
            t.procs.add(segs[-1])
            stack.append((indent, tpath, "member"))
            continue
        if val is not None:
            tp = prefix + segs[:-1]
            if not tp:
                stack.append((indent, base, "other"))
                continue
            tpath = "/" + "/".join(tp)
            t = get(tpath)
            t.files.add(rel)
            t.overrides[segs[-1]] = val
            stack.append((indent, tpath, "member"))
            continue
        tpath = "/" + "/".join(prefix + segs)
        t = get(tpath)
        t.files.add(rel)
        stack.append((indent, tpath, "type"))


def parse_file(args):
    full, rel = args
    types = {}

    def get(p):
        t = types.get(p)
        if t is None:
            t = types[p] = T(p)
        return t

    with open(full, encoding="utf-8", errors="replace") as fh:
        parse_one(clean(fh.read()), rel, get)
    return {p: (t.procs, t.caps, t.newvars, t.overrides, t.files) for p, t in types.items()}


def analyse(root):
    """Scans root/code; returns {type path: T}."""
    # A worker that dies (a full temp drive once made every Windows worker fail at start) raises BrokenProcessPool here;
    # multiprocessing.Pool waited forever on it instead.
    from concurrent.futures import ProcessPoolExecutor
    jobs = []
    for dp, dn, fn in os.walk(os.path.join(root, "code")):
        dn.sort()
        for f in sorted(fn):
            if f.endswith(".dm"):
                full = os.path.join(dp, f)
                rel = os.path.relpath(full, root).replace("\\", "/")
                if not rel.startswith(SKIP_DIRS):
                    jobs.append((full, rel))
    types = {}
    with ProcessPoolExecutor(max(1, min(8, os.cpu_count() or 2))) as pool:
        for part in pool.map(parse_file, jobs, chunksize=64):
            for p, (procs, caps, newvars, overrides, files) in part.items():
                t = types.get(p)
                if t is None:
                    t = types[p] = T(p)
                t.procs |= procs
                t.caps += caps
                t.newvars |= newvars
                for k, v in overrides.items():
                    t.overrides.setdefault(k, v)
                t.files |= files
    for p in types:
        parts = p.strip("/").split("/")
        for k in range(len(parts) - 1, 0, -1):
            par = "/" + "/".join(parts[:k])
            if par in types:
                types[par].children += 1
                break
    return types


def is_data_only(t):
    return t.children == 0 and not t.procs and not t.caps and not t.newvars and bool(t.overrides)


def root_of(path):
    return "/" + path.strip("/").split("/")[0]


def kb(path):
    return KB_ATOM if path.startswith(ATOM_ROOTS) else KB_DATUM


def census(root):
    types = analyse(root)
    rooted = {p: t for p, t in types.items() if p.startswith(ROOTS)}
    leaves = {p: t for p, t in rooted.items() if is_data_only(t)}
    fam = {}
    for p, t in leaves.items():
        fam.setdefault(p.rsplit("/", 1)[0], []).append(t)
    return rooted, leaves, fam


def render(rooted, leaves, fam):
    by_root = {}
    for p in rooted:
        by_root.setdefault(root_of(p), [0, 0])[0] += 1
    for p in leaves:
        by_root[root_of(p)][1] += 1
    out = []
    w = out.append
    w("# Variant census")
    w("")
    w("Generated by `python3 tools/ci/variant_census.py`; do not edit by hand. A data-only leaf is a type nothing inherits from that declares")
    w("no proc, no new var and no CAPABILITIES entry and only sets var defaults (the tool's docstring has the rule). A family is the leaves'")
    w("direct parent. The sizes are a model (12.5 KB per /atom subtype from the memory report, 4 KB per /datum subtype), not a measurement;")
    w("the rule in `code/content/variants/README.md` still decides each family (no behaviour, no use of the type as an identity).")
    w("")
    w("## Totals")
    w("")
    w("| Root | Declared types | Data-only leaves |")
    w("|---|---:|---:|")
    for r in sorted(by_root):
        w("| `%s` | %d | %d |" % (r, by_root[r][0], by_root[r][1]))
    w("| **all** | **%d** | **%d** |" % (len(rooted), len(leaves)))
    w("")
    w("Declared types are the paths the source names (a type that exists only as a parent of a declared one is not counted, and types made")
    w("by macros or by the build's generated files are not seen). The compiled type count is higher; the memory report has it.")
    w("")
    atom_leaf = sum(1 for p in leaves if p.startswith(ATOM_ROOTS))
    datum_leaf = len(leaves) - atom_leaf
    w("%d leaves are /atom types (%.0f MB modelled) and %d are /datum types (%.0f MB modelled), in %d families." % (
        atom_leaf, atom_leaf * KB_ATOM / 1024.0, datum_leaf, datum_leaf * KB_DATUM / 1024.0, len(fam)))
    w("")
    # What has been converted, and what is deliberately kept as types.
    try:
        import check_variants as cv
        parents = cv.load_registry()
        tables = cv.load_tables([f for f in cv.dm_files() if "dq_variants_" in open(f, encoding="utf-8", errors="replace").read()])
    except ImportError:
        parents, tables = {}, {}
    w("## Converted")
    w("")
    w("%d families are a parent type and a row table (`code/content/variants/`); the leaves below are what is left. `python3 tools/ci/check_variants.py` keeps"
      % len(parents))
    w("a new data-only leaf out of them.")
    w("")
    w("| Rows | Parent |")
    w("|---:|---|")
    for par in sorted(parents, key=lambda q: (-len(tables.get(parents[q], ())), q)):
        w("| %d | `%s` |" % (len(tables.get(parents[par], ())), par))
    w("")
    kept = (
        ("Techweb designs and nodes", ("/datum/design_techweb", "/datum/techweb_node")),
        ("Sprite accessories (hair, markings, ears, tails, wings)", ("/datum/sprite_accessory",)),
        ("Alternate job titles", ("/datum/alt_title",)),
        ("Perks", ("/datum/perk",)),
        ("Areas", ("/area",)),
    )
    w("## Deliberately kept as types")
    w("")
    w("These families are not converted, by decision: a /datum subtype carries a far shorter proc table than an atom, the type path is the identity")
    w("the registries, saves and templates use, and areas are looked up and templated by type. They stay in the lists below.")
    w("")
    w("| Family | Data-only leaves |")
    w("|---|---:|")
    for label, prefixes in kept:
        n = sum(len(ts) for par, ts in fam.items() if par.startswith(prefixes))
        w("| %s | %d |" % (label, n))
    w("")
    ranked = sorted(fam.items(), key=lambda kv: (-len(kv[1]) * kb(kv[0]), kv[0]))
    for title, atoms in (("/atom families (collapse first)", True), ("/datum families", False)):
        rows = [(p, ts) for p, ts in ranked if p.startswith(ATOM_ROOTS) == atoms]
        big = [(p, ts) for p, ts in rows if len(ts) >= 5]
        w("## %s" % title)
        w("")
        w("| Leaves | ~MB | Parent | Vars the leaves set (most common) |")
        w("|---:|---:|---|---|")
        for p, ts in big:
            cnt = {}
            for t in ts:
                for k in t.overrides:
                    cnt[k] = cnt.get(k, 0) + 1
            top = ", ".join("`%s`" % k for k, _ in sorted(cnt.items(), key=lambda kv: (-kv[1], kv[0]))[:6])
            w("| %d | %.2f | `%s` | %s |" % (len(ts), len(ts) * kb(p) / 1024.0, p, top))
        w("")
        w("%d further families have fewer than 5 leaves and are not listed." % (len(rows) - len(big)))
        w("")
    return "\n".join(out)


def main(argv):
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    rooted, leaves, fam = census(root)
    doc = os.path.join(root, "doc", "rewrite", "variant_census.md")
    if "--json" in argv:
        import json
        json.dump({p: {t.path: t.overrides for t in sorted(ts, key=lambda x: x.path)} for p, ts in sorted(fam.items())}, sys.stdout, indent=1, sort_keys=True)
        return 0
    if "--list" in argv:
        parent = argv[argv.index("--list") + 1]
        for t in sorted(fam.get(parent, []), key=lambda x: x.path):
            print(t.path, t.overrides)
        return 0
    text = render(rooted, leaves, fam)
    if "--check" in argv:
        have = open(doc, encoding="utf-8").read() if os.path.exists(doc) else ""
        if have != text:
            print("variant census is stale: run python3 tools/ci/variant_census.py")
            return 1
        return 0
    with open(doc, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    print("wrote", doc, "(%d data-only leaves in %d families)" % (len(leaves), len(fam)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
