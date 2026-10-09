#!/usr/bin/env python3
r"""MAP_RESOLVER / MAP_RESOLVER_VARS -> the map_resolver(...) entry of the type's CAPABILITIES block (code/library/maps/map_resolver_entry.dm).

    python tools/codemods/map_resolver.py [--check] [--paths code/game/objects/effects ...] [--list]

    MAP_RESOLVER(/obj/effect/gibspawner, GLOBAL_PROC_REF(resolve_gibspawner))
    MAP_RESOLVER_VARS(/obj/effect/gibspawner, "bloodcolor;fleshcolor")
        ->  CAPABILITIES(/obj/effect/gibspawner)
                map_resolver(GLOBAL_PROC_REF(resolve_gibspawner), vars = list("bloodcolor", "fleshcolor"))

A type under another resolver type (by path) changes what it inherits: configure(map_resolver(...)) naming only the proc and/or the vars it
declared (MAP_RESOLVER_VARS of a type with no MAP_RESOLVER of its own is configure(map_resolver(vars = list(...)))). The block is the type's
existing CAPABILITIES block (anywhere under code/) or a new one where the first macro of the type stood. A wave is closed under inheritance:
a type whose nearest resolver ancestor or descendant is not in the wave is converted with it, and the script says so.

    --paths P...   only the macros in these files or directories (default: every site)
    --check        print what would change; write nothing
    --list         print the declared types, one per line, and exit
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from capdecl import Blocks, File, all_files, call_args, normalise_ws, read_call, split_top, type_ancestors  # noqa: E402

LINE_LIMIT = 150


class Node:
    def __init__(self, path):
        self.path = path
        self.proc = None
        self.vars = None
        self.sites = []  # (file, start, end, comments)


def find_nodes(files):
    nodes = {}
    for r, f in files.items():
        for i, line in enumerate(f.lines):
            for name in ("MAP_RESOLVER", "MAP_RESOLVER_VARS"):
                if not line.startswith(name + "("):
                    continue
                j, text, comments = read_call(f.lines, i)
                call = call_args(normalise_ws(text))
                if not call or call[0] != name or len(call[1]) != 2:
                    print(f"residue: {r}:{i + 1} unreadable {name}")
                    continue
                path, arg = call[1]
                node = nodes.setdefault(path, Node(path))
                if name == "MAP_RESOLVER":
                    node.proc = arg
                else:
                    m = re.match(r'^"([^"]*)"$', arg)
                    if not m:
                        print(f"residue: {r}:{i + 1} MAP_RESOLVER_VARS names are not a string")
                        continue
                    node.vars = [v for v in m.group(1).split(";") if v]
                node.sites.append((f, i, j, comments))
    return nodes


def entry_lines(node, configure):
    parts = []
    if node.proc:
        parts.append(node.proc)
    if node.vars is not None:
        parts.append("vars = list(" + ", ".join('"' + v + '"' for v in node.vars) + ")")
    head = "configure(map_resolver(" if configure else "map_resolver("
    tail = "))" if configure else ")"
    one = "\t" + head + ", ".join(parts) + tail
    if len(one) <= LINE_LIMIT:
        return [one]
    out = ["\t" + head]
    for k, p in enumerate(parts):
        end = "," if k < len(parts) - 1 else tail
        if p.startswith("vars = list(") and len("\t\t" + p) > LINE_LIMIT:
            items = [", ".join('"' + v + '"' for v in node.vars[i:i + 4]) for i in range(0, len(node.vars), 4)]
            out.append("\t\tvars = list(")
            for n, chunk in enumerate(items):
                out.append("\t\t\t" + chunk + ("," if n < len(items) - 1 else ")") + (end if n == len(items) - 1 else ""))
        else:
            out.append("\t\t" + p + end)
    return out


def main(argv):
    check = "--check" in argv
    paths = []
    if "--paths" in argv:
        for a in argv[argv.index("--paths") + 1:]:
            if a.startswith("--"):
                break
            paths.append(a.rstrip("/"))
    files = {r: File(r) for r in all_files()}
    nodes = find_nodes(files)
    if "--list" in argv:
        for p in sorted(nodes):
            print(p)
        return 0

    def nearest_ancestor(path):
        for a in type_ancestors(path):
            if a in nodes:
                return a
        return None

    def in_paths(node):
        return not paths or any(f.rel == p or f.rel.startswith(p + "/") for f, _, _, _ in node.sites for p in paths)

    wave = {p for p, n in nodes.items() if in_paths(n)}
    changed = True
    while changed:
        changed = False
        for p in list(nodes):
            anc = nearest_ancestor(p)
            if p in wave and anc and anc not in wave:
                print(f"closure: {anc} is the resolver ancestor of {p}")
                wave.add(anc)
                changed = True
            if p not in wave and anc in wave:
                print(f"closure: {p} inherits from {anc}")
                wave.add(p)
                changed = True

    blocks = Blocks(files)
    ops = {}
    done, residue = 0, []
    for p in sorted(wave):
        node = nodes[p]
        anc = nearest_ancestor(p)
        configure = anc is not None
        if not node.proc and not configure:
            residue.append(f"{p}: MAP_RESOLVER_VARS with no resolver of its own or inherited")
            continue
        lines = entry_lines(node, configure)
        existing = blocks.by_type.get(p)
        first = sorted(node.sites, key=lambda s: (s[0].rel, s[1]))[0]
        comments = [c for _, _, _, cs in node.sites for c in cs]
        if existing and existing[2] != "block":
            residue.append(f"{p}: its CAPABILITIES is the legacy single-macro form ({existing[0].rel}:{existing[1] + 1})")
            continue
        for f, start, end, _ in node.sites:
            new = []
            if (f, start, end) == (first[0], first[1], first[2]):
                if existing:
                    bf, bi, _ = existing
                    ops.setdefault(bf.rel, []).append((blocks.block_end(bf, bi) + 1, blocks.block_end(bf, bi) + 1, lines))
                else:
                    new = ["CAPABILITIES(" + p + ")"] + lines
                    blocks.by_type[p] = (f, -1, "block")
            ops.setdefault(f.rel, []).append((start, end + 1, (comments if (f, start) == (first[0], first[1]) else []) + new))
        done += 1
    for r, file_ops in ops.items():
        f = files[r]
        for start, end, new in sorted(file_ops, key=lambda o: (o[0], o[1]), reverse=True):
            f.lines[start:end] = new
        f.dirty = True
    if not check:
        for f in files.values():
            f.save()
    print(f"{'would convert' if check else 'converted'} {done} resolver type(s) in {len(ops)} file(s)")
    for r in residue:
        print("residue:", r)
    return 1 if residue else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
