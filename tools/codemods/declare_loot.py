#!/usr/bin/env python3
r"""DECLARE_LOOT -> the loot(...) entry of the type's CAPABILITIES block (code/library/loot/loot_entries.dm).

    python tools/codemods/declare_loot.py [--check] [--tests] [--paths code/game/objects/random ...] [--list]

    DECLARE_LOOT(/obj/random/x, LOOT_TABLE(/a = 3, LOOT_SET(1, /b, /c)), LOOT_COUNT(2))
        ->  CAPABILITIES(/obj/random/x)
                loot(table = list(/a = 3, loot_set(1, /b, /c)), count = 2)

The rows keep their order and text (LOOT_REF(P) is P: a pure table is the abstract type /loot/...). A declaration whose type has an ancestor that
declares loot is written configure(loot(...)): it changes the rows it names. The block is the type's existing CAPABILITIES block (found anywhere
under code/) or a new one where the macro stood. A wave is closed under inheritance: a site whose nearest declaring ancestor or descendant is not in
the wave is converted with it (the legacy and the entry forms do not inherit from one another), and the script says so.

    --paths P...   only the DECLARE_LOOT sites in these files or directories (default: every site)
    --tests        include code/modules/unit_tests/ (left alone by default)
    --check        print what would change; write nothing
    --list         print the declared types, one per line, and exit (the owners of snapshots/loot/owners.txt)

Residue (left as it is, printed): a LOOT_ macro this table does not know, a comment inside the macro, a type whose block is the legacy
CAPABILITIES(T, entries...) form.
"""
import re
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0] if "/" in __file__ else ".")
import os  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from capdecl import (  # noqa: E402
    ROOT, Blocks, File, all_files, call_args, normalise_ws, read_call, rel, split_top, type_ancestors,
)

ROW_MACROS = ("LOOT_SET", "LOOT_SUB", "LOOT_STACK", "LOOT_TYPES")
LINE_LIMIT = 150


def convert_rows(text):
    """The text of a table's rows with the row macros as constructors, innermost first; LOOT_REF(P) is P.

    LOOT_SET(W, a, b) / LOOT_SUB(W, a, b) become loot_set(W, list(a, b)) / loot_sub(W, list(a, b)) (a variadic proc loses `/path = weight`
    arguments, a list keeps them); LOOT_STACK and LOOT_TYPES keep their arguments."""
    prev = None
    while prev != text:
        prev = text
        text = re.sub(r"\bLOOT_REF\(\s*(/[\w/]+)\s*\)", r"\1", text)
    out = []
    i, n = 0, len(text)
    while i < n:
        m = re.compile(r"\b(" + "|".join(ROW_MACROS) + r")\s*\(").match(text, i)
        if m and (i == 0 or not (text[i - 1].isalnum() or text[i - 1] == "_")):
            open_at = m.end() - 1
            depth, k, in_str = 0, open_at, False
            while k < n:
                c = text[k]
                if in_str:
                    if c == "\\":
                        k += 1
                    elif c == '"':
                        in_str = False
                elif c == '"':
                    in_str = True
                elif c == "(":
                    depth += 1
                elif c == ")":
                    depth -= 1
                    if depth == 0:
                        break
                k += 1
            args = [convert_rows(x) for x in split_top(text[open_at + 1:k])]
            name = m.group(1)
            if name in ("LOOT_SET", "LOOT_SUB"):
                out.append(name.lower() + "(" + args[0] + ", list(" + ", ".join(args[1:]) + "))")
            else:
                out.append(name.lower() + "(" + ", ".join(args) + ")")
            i = k + 1
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def convert_spec(spec):
    """One LOOT_* spec of a DECLARE_LOOT as (param, value text), or None."""
    spec = spec.strip()
    if spec == "LOOT_PER_ROUND":
        return ("per_round", "TRUE")
    if spec == "LOOT_REPEAT_SEARCH":
        return ("repeat_search", "TRUE")
    call = call_args(spec)
    if not call:
        return None
    name, args = call
    rows = lambda a: convert_rows(", ".join(a))  # noqa: E731
    if name == "LOOT_TABLE":
        return ("table", "list(" + rows(args) + ")")
    if name == "LOOT_COUNT" and len(args) == 1:
        return ("count", args[0])
    if name == "LOOT_CHANCE" and len(args) == 1:
        return ("chance", args[0])
    if name == "LOOT_ALL":
        return ("all", "list(" + rows(args) + ")")
    if name == "LOOT_HOOK" and len(args) == 1:
        return ("hook", args[0])
    if name == "LOOT_UNLUCKY":
        return ("unlucky", "list(" + rows(args) + ")")
    if name == "LOOT_UNCOMMON" and len(args) >= 2:
        return ("uncommon", "loot_tier(" + args[0] + ", list(" + rows(args[1:]) + "))")
    if name == "LOOT_RARE" and len(args) >= 2:
        return ("rare", "loot_tier(" + args[0] + ", list(" + rows(args[1:]) + "))")
    if name == "LOOT_GAMMA" and len(args) == 1:
        return ("gamma_chance", args[0])
    if name == "LOOT_DEPLETION" and len(args) == 2:
        return ("depletion", "loot_depletion(" + args[0] + ", " + args[1] + ")")
    return None


def param_lines(key, value, depth):
    """`key = value` as lines at tab depth `depth`; a long list(...) / loot_tier(...) is broken one row per line."""
    pad = "\t" * depth
    one = pad + key + " = " + value
    if len(one) <= LINE_LIMIT:
        return [one]
    call = call_args(value)
    if call and call[0] in ("list", "loot_tier"):
        name, items = call
        out = [pad + key + " = " + name + "("]
        for k, item in enumerate(items):
            tail = "," if k < len(items) - 1 else ")"
            out.append(pad + "\t" + item + tail)
        return out
    return [one]


def entry_lines(params, configure):
    """The entry as block lines (one tab deep)."""
    head = "configure(loot(" if configure else "loot("
    tail = "))" if configure else ")"
    one = "\t" + head + ", ".join(k + " = " + v for k, v in params) + tail
    if len(one) <= LINE_LIMIT:
        return [one]
    out = ["\t" + head]
    for idx, (k, v) in enumerate(params):
        lines = param_lines(k, v, 2)
        end = "," if idx < len(params) - 1 else tail
        lines[-1] += end
        out += lines
    return out


class Site:
    def __init__(self, f, start, end, path, specs, comments):
        self.f, self.start, self.end, self.path, self.specs, self.comments = f, start, end, path, specs, comments


def find_sites(files, include_tests):
    sites = []
    for r, f in files.items():
        if not include_tests and r.startswith("code/modules/unit_tests/"):
            continue
        for i, line in enumerate(f.lines):
            if not line.startswith("DECLARE_LOOT("):
                continue
            j, text, comments = read_call(f.lines, i)
            call = call_args(normalise_ws(text))
            if not call or call[0] != "DECLARE_LOOT" or not call[1]:
                print(f"residue: {r}:{i + 1} unreadable DECLARE_LOOT")
                continue
            sites.append(Site(f, i, j, call[1][0], call[1][1:], comments))
    return sites


def main(argv):
    check = "--check" in argv
    include_tests = "--tests" in argv
    paths = []
    if "--paths" in argv:
        for a in argv[argv.index("--paths") + 1:]:
            if a.startswith("--"):
                break
            paths.append(a.rstrip("/"))
    files = {r: File(r) for r in all_files()}
    sites = find_sites(files, include_tests)
    if "--list" in argv:
        for s in sorted(sites, key=lambda s: s.path):
            print(s.path)
        return 0
    by_path = {s.path: s for s in sites}

    def nearest_ancestor(path):
        for a in type_ancestors(path):
            if a in by_path:
                return a
        return None

    def selected_by_paths(s):
        return not paths or any(s.f.rel == p or s.f.rel.startswith(p + "/") for p in paths)

    wave = {s.path for s in sites if selected_by_paths(s)}
    # Close the wave under inheritance: the nearest declaring ancestor, and every site whose nearest declaring ancestor is in the wave.
    changed = True
    while changed:
        changed = False
        for s in sites:
            anc = nearest_ancestor(s.path)
            if s.path in wave and anc and anc not in wave:
                print(f"closure: {anc} ({by_path[anc].f.rel}) is the declaring ancestor of {s.path}")
                wave.add(anc)
                changed = True
            if s.path not in wave and anc in wave:
                print(f"closure: {s.path} ({s.f.rel}) inherits from {anc}")
                wave.add(s.path)
                changed = True

    if "--wave-owners" in argv:
        # The wave's declarations and the ones whose tables name them (a nested table or spawner): what the roll pin's subset test proves for the wave.
        names = set(wave)
        for s in sites:
            text = " ".join(s.specs)
            if any(re.search(re.escape(p) + r"(?![\w/])", text) for p in wave):
                names.add(s.path)
        out_path = os.path.join(ROOT, "data", "loot_pin_subset.txt")
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "w", newline="\n") as fh:
            fh.write("\n".join(sorted(names)) + "\n")
        print(f"wave owners: {len(wave)} declared + {len(names) - len(wave)} nesting them -> data/loot_pin_subset.txt")
    # A converted pure table is a type: every LOOT_REF(P) of it, wherever it stands, is P.
    converted_tables = {p for p in wave if p.startswith("/loot/")}
    ref_edits = 0
    if converted_tables:
        ref_re = re.compile(r"\bLOOT_REF\(\s*(/loot/[\w/]+)\s*\)")
        for f in files.values():
            for k, line in enumerate(f.lines):
                if "LOOT_REF(" not in line:
                    continue
                new_line = ref_re.sub(lambda m: m.group(1) if m.group(1) in converted_tables else m.group(0), line)
                if new_line != line:
                    f.lines[k] = new_line
                    f.dirty = True
                    ref_edits += 1

    blocks = Blocks(files)
    ops = {}  # file rel -> list of (start, end_exclusive, new lines)
    done, residue = 0, []
    for s in sorted(sites, key=lambda s: (s.f.rel, s.start)):
        if s.path not in wave:
            continue
        params = []
        bad = None
        for spec in s.specs:
            conv = convert_spec(normalise_ws(spec))
            if not conv:
                bad = spec
                break
            params.append(conv)
        if bad is not None or "LOOT_" in " ".join(v for _, v in params):
            residue.append(f"{s.f.rel}:{s.start + 1} {s.path}: unknown spec {bad or ''}")
            continue
        if s.comments and any(not c.startswith("//") for c in s.comments):
            residue.append(f"{s.f.rel}:{s.start + 1} {s.path}: comment inside the macro")
            continue
        configure = nearest_ancestor(s.path) is not None
        lines = entry_lines(params, configure)
        existing = blocks.by_type.get(s.path)
        file_ops = ops.setdefault(s.f.rel, [])
        comment_lines = list(s.comments)
        if existing:
            bf, bi, form = existing
            if form != "block":
                residue.append(f"{s.f.rel}:{s.start + 1} {s.path}: its CAPABILITIES is the legacy single-macro form ({bf.rel}:{bi + 1})")
                continue
            end = blocks.block_end(bf, bi)
            ops.setdefault(bf.rel, []).append((end + 1, end + 1, lines))
            new = comment_lines  # the macro's comments stay where the macro was
            file_ops.append((s.start, s.end + 1, new))
        else:
            file_ops.append((s.start, s.end + 1, comment_lines + ["CAPABILITIES(" + s.path + ")"] + lines))
            blocks.by_type[s.path] = (s.f, -1, "block")
        done += 1
    for r, file_ops in ops.items():
        f = files[r]
        for start, end, new in sorted(file_ops, key=lambda o: (o[0], o[1]), reverse=True):
            f.lines[start:end] = new
        f.dirty = True
    if not check:
        for f in files.values():
            f.save()
    print(f"{'would convert' if check else 'converted'} {done} DECLARE_LOOT site(s) in {len(ops)} file(s); {ref_edits} LOOT_REF line(s) of converted tables")
    for r in residue:
        print("residue:", r)
    return 1 if residue else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
