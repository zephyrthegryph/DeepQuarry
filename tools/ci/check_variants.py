#!/usr/bin/env python3
"""Variant families (code/content/variants/README.md): two checks, run by check_ratchets.sh.

1. Every `VARIANT(/parent, "key")` names a registered family and a key its table has (the compiler checks the path, this checks the key).
2. A converted family (a parent in the registry, code/content/variants/variant_tables.dm) gets no new data-only leaf subtype: a type
   directly under the parent that declares no proc, no new var and no CAPABILITIES entry and only sets var defaults is a row of the
   table, not a type. The rule is a hard ban: there is no baseline.

3. A map the build compiles in (`#include "x.dmm"`) names no collapsed type's old path: the compiler instances those maps itself, so
   the loader alias (code/content/variants/variant_alias.dm) never sees them. `--rewrite-maps` rewrites such a line to the parent type with
   a `variant = "key"` edit; every other map (templates, submaps, expedition sites) keeps the old path and loads through the alias.

  python3 tools/ci/check_variants.py
  python3 tools/ci/check_variants.py --rewrite-maps
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import variant_census as vc  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
REGISTRY = os.path.join(ROOT, "code", "content", "variants", "variant_tables.dm")
REG_LINE = re.compile(r'^\t(/[\w/]+) = "(dq_variants_\w+)",')
TABLE_START = re.compile(r"^GLOBAL_LIST_INIT\((dq_variants_\w+), *list\(")
ROW = re.compile(r'^\t"([^"]+)" = list\(')
REF = re.compile(r'\bVARIANT\(\s*(/[\w/]+)\s*,\s*"([^"]+)"\s*\)')


def dm_files():
    for dp, dn, fn in os.walk(os.path.join(ROOT, "code")):
        dn.sort()
        for f in sorted(fn):
            if f.endswith(".dm"):
                yield os.path.join(dp, f)


def load_registry():
    parents = {}
    for line in open(REGISTRY, encoding="utf-8"):
        m = REG_LINE.match(line)
        if m:
            parents[m.group(1)] = m.group(2)
    return parents


def load_tables(files):
    rows = {}
    for full in files:
        cur = None
        for line in open(full, encoding="utf-8", errors="replace"):
            m = TABLE_START.match(line)
            if m:
                cur = m.group(1)
                rows.setdefault(cur, set())
            elif cur and ROW.match(line):
                rows[cur].add(ROW.match(line).group(1))
            elif line.startswith("))"):
                cur = None
    return rows


def compiled_maps():
    """The .dmm files some .dm file includes: the build instances their atoms itself."""
    found = []
    inc = re.compile(r'^\s*#include\s+"([^"]+\.dmm)"')
    for dp, dn, fn in os.walk(os.path.join(ROOT, "maps")):
        dn.sort()
        for f in sorted(fn):
            if f.endswith(".dm"):
                for line in open(os.path.join(dp, f), encoding="utf-8", errors="replace"):
                    m = inc.match(line)
                    if m:
                        found.append(os.path.normpath(os.path.join(dp, m.group(1))))
    return found


def rewrite_map_text(text, aliases):
    """TGM text with each alias path line turned into parent + variant edit. Returns (text, count)."""
    out = []
    count = 0
    for line in text.split("\n"):
        m = re.match(r"^(/[\w/]+)(\{|,)(\r?)$", line)
        if m and m.group(1) in aliases:
            parent, key = aliases[m.group(1)]
            cr = m.group(3)
            if m.group(2) == "{":
                out.append("%s{%s" % (parent, cr))
                out.append('\tvariant = "%s";%s' % (key, cr))
            else:
                out.append("%s{%s" % (parent, cr))
                out.append('\tvariant = "%s"%s' % (key, cr))
                out.append("\t},%s" % cr)
            count += 1
        else:
            out.append(line)
    return "\n".join(out), count


def main():
    rewrite = "--rewrite-maps" in sys.argv
    problems = []
    parents = load_registry()
    files = list(dm_files())
    texts = {}
    for full in files:
        texts[full] = open(full, encoding="utf-8", errors="replace").read()
    rows = load_tables([f for f in files if "dq_variants_" in texts[f]])
    for p, name in sorted(parents.items()):
        if name not in rows:
            problems.append("%s: the registry names table %s, which no file defines" % (p, name))
    # 1. VARIANT() references
    for full, text in texts.items():
        if "VARIANT(" not in text:
            continue
        rel = os.path.relpath(full, ROOT).replace("\\", "/")
        for n, line in enumerate(text.split("\n"), 1):
            for m in REF.finditer(line):
                path, key = m.group(1), m.group(2)
                if path not in parents:
                    problems.append("%s:%d: VARIANT(%s, ...) names a type that is not a registered variant family" % (rel, n, path))
                elif key not in rows.get(parents[path], ()):
                    problems.append("%s:%d: VARIANT(%s, \"%s\"): the table %s has no row \"%s\"" % (rel, n, path, key, parents[path], key))
    # 2. no new data-only leaf under a converted parent
    needles = [p + "/" for p in parents]
    jobs = []
    for full, text in texts.items():
        rel = os.path.relpath(full, ROOT).replace("\\", "/")
        if rel.startswith(vc.SKIP_DIRS):
            continue
        if any(n in text for n in needles):
            jobs.append((full, rel))
    types = {}
    for job in jobs:
        for p, (procs, caps, newvars, overrides, files_) in vc.parse_file(job).items():
            t = types.get(p)
            if t is None:
                t = types[p] = vc.T(p)
            t.procs |= procs
            t.caps += caps
            t.newvars |= newvars
            for k, v in overrides.items():
                t.overrides.setdefault(k, v)
            t.files |= files_
    for p, t in types.items():
        for par in parents:
            if p.startswith(par + "/") and p.count("/") == par.count("/") + 1:
                # a data-only type is judged on its own declarations; children are counted over the whole tree below
                has_child = any(q.startswith(p + "/") for q in types)
                if not has_child and not t.procs and not t.caps and not t.newvars and t.overrides:
                    problems.append("%s (%s): a data-only leaf under the variant family %s; add a row to %s instead"
                                    % (p, sorted(t.files)[0], par, parents[par]))
    # 3. compiled-in maps
    aliases = {}
    for p, name in parents.items():
        for key in rows.get(name, ()):
            aliases[p + "/" + key] = (p, key)
    for full in compiled_maps():
        if not os.path.exists(full):
            continue
        text = open(full, encoding="utf-8", newline="").read()
        new, count = rewrite_map_text(text, aliases)
        if not count:
            continue
        rel = os.path.relpath(full, ROOT).replace("\\", "/")
        if rewrite:
            open(full, "w", encoding="utf-8", newline="").write(new)
            print("rewrote %d line(s) in %s" % (count, rel))
        else:
            problems.append("%s: %d line(s) name the old path of a collapsed type, and the build compiles this map in: python3 tools/ci/check_variants.py --rewrite-maps" % (rel, count))
    for pr in problems:
        print("[variants] " + pr)
    if problems:
        print("check_variants: %d problem(s)" % len(problems))
        return 1
    print("check_variants: %d families, %d references checked" % (len(parents), sum(len(REF.findall(t)) for t in texts.values())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
