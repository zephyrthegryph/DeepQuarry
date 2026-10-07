#!/usr/bin/env python3
r"""DECLARE_VERB* -> verb_entry(), om_grant / om_revoke(GRANT_VERB) -> grant / revoke(granted_verb())
(doc/rewrite/codemod_rules.md, "DECLARE_VERB and GRANT_VERB -> verb_entry() and granted_verb()").

    python tools/dx/codemods/verb_decl.py [--check] [--sites] [--files paths...]

Part 1, per declaration: DECLARE_VERB(T, V), DECLARE_LOGIN_VERB(T, V), DECLARE_VERB_IF(T, V, "var") and DECLARE_VERB_HIDE(T, V) on an /atom type become verb_entry() entries in
T's CAPABILITIES block. Part 2, per statement: `om_grant(E, GRANT_VERB, path, source)` / `om_revoke(...)` become `grant(E, granted_verb(path), source)` / `revoke(...)`, for
a path every site of which converts (a verb granted one way and revoked another would leave the activation behind). The rest is residue with a code (--sites lists it).
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

SKIP = ("code/__defines/", "code/modules/unit_tests/", "code/tests/", "tools/", "code/modules/tgs/", "code/datums/om/", "code/engine/", "code/datums/reactions/")
ATOM_ROOTS = ("/obj", "/turf", "/mob", "/area", "/atom")
HEAD = re.compile(r"^(DECLARE_VERB_IF|DECLARE_VERB_HIDE|DECLARE_LOGIN_VERB|DECLARE_VERB)\((.*)\)\s*(//.*)?$")
GRANT = re.compile(r"^(\s*)(om_grant|om_revoke)\((.*)\)\s*(//.*)?$")
GRANT_ANY = re.compile(r"\b(om_grant|om_revoke|om_grant_each|om_revoke_each|om_revoke_all_of|om_grant_for|om_apply)\s*\([^)]*GRANT_VERB\b")
NAMED = re.compile(r"^VERB_NAMED\((.*)\)$")


def is_path(text):
    return bool(re.match(r"^/[\w/]+$", text))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check = "--check" in sys.argv
    sites = "--sites" in sys.argv
    if "--files" in sys.argv:
        names = args
    else:
        names = subprocess.check_output(["git", "ls-files", "-z", "*.dm"]).decode("utf-8", "surrogateescape").split("\0")
        names = [n for n in names if n and not n.startswith(SKIP)]
    files = {}
    for rel in names:
        try:
            files[rel] = File(rel)
        except OSError:
            continue

    capblock = {}
    decls = []  # (kind, type, rel, line, parts, comment)
    grant_sites = []  # (rel, idx, verb, target, path, source, indent, comment)
    other_sites = []  # (rel, idx) GRANT_VERB uses this codemod does not convert
    for rel, f in files.items():
        for i, l in enumerate(f.lines):
            if l is None:
                continue
            m = re.match(r"^CAPABILITIES\((/[\w/]+)\)\s*(//.*)?$", l)
            if m:
                capblock[m.group(1)] = (rel, i)
                continue
            m = HEAD.match(l)
            if m:
                decls.append((m.group(1), "", rel, i, split_args(m.group(2)), m.group(3) or ""))
                continue
            if "GRANT_VERB" in l and not l.lstrip().startswith("//"):
                m = GRANT.match(l)
                parts = split_args(m.group(3)) if m else None
                if m and parts and len(parts) == 4 and parts[1] == "GRANT_VERB":
                    grant_sites.append((rel, i, m.group(2), parts[0], parts[2], parts[3], m.group(1), m.group(4) or ""))
                elif GRANT_ANY.search(l) or re.search(r"\bGRANT_VERB\b", l):
                    other_sites.append((rel, i))

    residue = []  # (code, tag)
    entries = defaultdict(list)  # type -> [entry text]
    done_lines = []  # (rel, idx)
    converted_decls = 0
    for kind, _t, rel, i, parts, comment in decls:
        if len(parts) < 2 or not parts[0].startswith("/") or not is_path(parts[0]):
            residue.append(("decl_form", "%s:%d" % (rel, i + 1)))
            continue
        t, verb = parts[0], parts[1]
        tag = "%s %s %s" % (kind, t, verb)
        if not t.startswith(ATOM_ROOTS):
            residue.append(("non_atom", tag))
            continue
        if not is_path(verb):
            residue.append(("verb_expr", tag))
            continue
        if kind == "DECLARE_VERB_IF":
            m = re.match(r'^"(\w+)"$', parts[2]) if len(parts) == 3 else None
            if not m:
                residue.append(("decl_form", tag))
                continue
            entry = "verb_entry(%s, when = nameof(%s))" % (verb, m.group(1))
        elif kind == "DECLARE_LOGIN_VERB":
            entry = "verb_entry(%s, login = TRUE)" % verb
        elif kind == "DECLARE_VERB_HIDE":
            entry = "verb_entry(%s, hidden = TRUE)" % verb
        else:
            entry = "verb_entry(%s)" % verb
        if len(parts) != (3 if kind == "DECLARE_VERB_IF" else 2):
            residue.append(("decl_form", tag))
            continue
        if comment:
            entry += " " + comment
        entries[t].append((rel, i, entry))
        converted_decls += 1

    # ---- grants: a path converts only when every site that names it converts
    by_path = defaultdict(list)
    for s in grant_sites:
        by_path[s[4]].append(s)
    bad_paths = set()
    other_files = {rel for (rel, _i) in other_sites}
    for path, ss in by_path.items():
        for (rel, i, fn, target, p, source, indent, comment) in ss:
            if re.match(r'^"', source) or source in ("null", "0"):
                bad_paths.add(path)
            m = NAMED.match(p)
            if m and len(split_args(m.group(1))) != 3:
                bad_paths.add(path)
        if any(rel in other_files for (rel, *_r) in ss):
            bad_paths.add(path)
    converted_grants = 0
    grant_edits = []
    for path, ss in by_path.items():
        for (rel, i, fn, target, p, source, indent, comment) in ss:
            tag = "%s:%d %s" % (rel, i + 1, path)
            if path in bad_paths:
                residue.append(("grant_shared", tag))
                continue
            m = NAMED.match(p)
            if m:
                a = split_args(m.group(1))
                what = "granted_verb(%s, verb_name = %s, verb_desc = %s)" % (a[0], a[1], a[2])
            else:
                what = "granted_verb(%s)" % p
            new = "%s%s(%s, %s, %s)%s" % (indent, "grant" if fn == "om_grant" else "revoke", target, what, source, (" " + comment) if comment else "")
            grant_edits.append((rel, i, new))
            converted_grants += 1
    for (rel, i) in other_sites:
        residue.append(("grant_form", "%s:%d" % (rel, i + 1)))

    if not check:
        for t, items in entries.items():
            block = capblock.get(t)
            for (rel, i, _e) in items:
                files[rel].lines[i] = None
                files[rel].dirty = True
            lines = "".join("\n\t" + e for (_r, _i, e) in items)
            if block:
                r, bi = block
                f = files[r]
                fb, lb = body_range(f.lines, bi)
                f.lines[lb] = f.lines[lb] + lines
                f.dirty = True
            else:
                rel, i, _e = items[0]
                files[rel].lines[i] = "CAPABILITIES(%s)" % t + lines
        for (rel, i, new) in grant_edits:
            files[rel].lines[i] = new
            files[rel].dirty = True
        for f in files.values():
            if f.dirty:
                f.save()
    by = defaultdict(list)
    for code, tag in residue:
        by[code].append(tag)
    print("verb_decl: %d declarations and %d grant statements converted%s; residue %d" % (converted_decls, converted_grants, " (check)" if check else "", len(residue)))
    for code, ts in sorted(by.items(), key=lambda kv: -len(kv[1])):
        print("    %-14s %4d" % (code, len(ts)))
        if sites:
            for tag in sorted(ts):
                print("        " + tag)
    return 1 if (check and (converted_decls or converted_grants)) else 0


if __name__ == "__main__":
    sys.exit(main())
