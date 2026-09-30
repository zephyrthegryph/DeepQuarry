#!/usr/bin/env python3
"""Rename icon states to the look naming convention (code/__defines/look_names.dm).

Renames a state in an icon's `.dmi.toml` (the editable source; the PNG sheet needs no change because
states are addressed by order) and rewrites the exact quoted string references to it in code and maps.

    python tools/dq_icons/rename_states.py icons/obj/power.dmi.toml \\
        --map apc_frame=frame --map apcox-0=power-off  [--refs code/modules/power] [--apply]

Without --apply it only reports what it would change (a dry run). A rename is refused when the new
name already exists in the icon, or when the old name is missing.

References: every `"old"` string literal in the .dm / .dmm / .dme files under --refs (default `code` and
`maps`) that ALSO mentions the icon file's path or (with --anywhere) any file at all. Interpolated names
("old[x]") cannot be renamed mechanically: they are listed under "interpolated" for a hand edit.
A file that names the icon is the safe scope; use --anywhere only for a state name unique to the tree.

    --map-file FILE     one `old new` pair per line ('#' comments) instead of / besides --map
    --check             list states that do not follow the convention (lowercase, dash separated)
    --standard          derive the renames from the legacy names in the icon (no --map needed):
                          panel_open, cover_open ...  -> panel-open, cover-open   (standard part, dashed)
                          apco<0-2>-<mode>            -> channel-<0-2>-<mode>   (the equipment/lighting/environ channels)
                          apco3-<n>                   -> charge-<n>             (apco3 is the charge lamp, not a channel)
                          apc<0-2>-nocover / -b-nocover, apcmaint -> apc0-cover-removed[-broken][-cell], maintenance
                          <base>-panel                -> <base>-panel-open
                        A legacy name whose standard name already exists is reported and skipped.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STATE_NAME = re.compile(r'^(name\s*=\s*)"((?:[^"\\]|\\.)*)"\s*$')
CONVENTION = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
REF_SUFFIXES = (".dm", ".dmm", ".dme")


def read_toml_states(lines: list[str]) -> list[tuple[int, str]]:
    """(line index, name) for each [[state]] name line."""
    found: list[tuple[int, str]] = []
    in_state = False
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped == "[[state]]":
            in_state = True
            continue
        if stripped.startswith("[") and stripped != "[[state]]":
            in_state = False
        if in_state:
            m = STATE_NAME.match(stripped)
            if m:
                found.append((index, m.group(2)))
                in_state = False
    return found


STANDARD_TOKENS = {"panel", "cover", "broken", "locked", "wires", "dark", "lid", "cell", "bolts", "welded",
                   "emergency", "power", "charge", "channel"}
APC_CHANNEL = re.compile(r"^apco([0-2])-(\d+)$")
APC_CHARGE = re.compile(r"^apco3-(\d+)$")
APC_COVERLESS = re.compile(r"^apc([12])(-b)?-nocover$")
BASE_PANEL = re.compile(r"^(.+)-panel$")


def standard_name(name: str) -> str | None:
    """The standard name for a legacy state name, or None when it needs no rename."""
    m = APC_CHARGE.match(name)
    if m:
        return "charge-%s" % m.group(1)
    m = APC_CHANNEL.match(name)
    if m:
        return "channel-%s-%s" % (m.group(1), m.group(2))
    m = APC_COVERLESS.match(name)
    if m:
        # apc1 has no cell in it, apc2 has one; "-b-" is the broken frame. Variants chain on the apc0 base.
        return "apc0-cover-removed%s%s" % ("-broken" if m.group(2) else "", "-cell" if m.group(1) == "2" else "")
    if name == "apcmaint":
        return "maintenance"
    m = BASE_PANEL.match(name)
    if m:
        return "%s-panel-open" % m.group(1)
    parts = re.split(r"[_-]", name)
    if parts and parts[0].lower() in STANDARD_TOKENS:
        new = "-".join(p.lower() for p in parts)
        return new if new != name else None
    return None


def standard_pairs(toml_path: Path) -> tuple[dict[str, str], list[str]]:
    """old -> new for every legacy state in the icon, and the ones skipped (target taken)."""
    names = [n for _, n in read_toml_states(toml_path.read_text(encoding="utf-8").splitlines())]
    taken = set(names)
    pairs: dict[str, str] = {}
    skipped: list[str] = []
    for name in names:
        new = standard_name(name)
        if not new:
            continue
        if new in taken or new in pairs.values():
            skipped.append("%s -> %s (target exists)" % (name, new))
            continue
        pairs[name] = new
    return pairs, skipped


def parse_pairs(map_args: list[str], map_file: str | None) -> dict[str, str]:
    pairs: dict[str, str] = {}
    for item in map_args:
        if "=" not in item:
            sys.exit("bad --map %r: expected old=new" % item)
        old, new = item.split("=", 1)
        pairs[old] = new
    if map_file:
        for raw in Path(map_file).read_text(encoding="utf-8").splitlines():
            raw = raw.split("#", 1)[0].strip()
            if not raw:
                continue
            parts = raw.split()
            if len(parts) != 2:
                sys.exit("bad map line %r: expected `old new`" % raw)
            pairs[parts[0]] = parts[1]
    return pairs


def plan_toml(toml_path: Path, pairs: dict[str, str]) -> tuple[list[str], list[str]]:
    """The new toml lines and the problems found."""
    lines = toml_path.read_text(encoding="utf-8").splitlines(keepends=True)
    states = read_toml_states([l.rstrip("\r\n") for l in lines])
    names = {name for _, name in states}
    problems: list[str] = []
    for old, new in pairs.items():
        if old not in names:
            problems.append("%s has no state %r" % (toml_path, old))
        elif new in names and new != old:
            problems.append("%s already has a state %r" % (toml_path, new))
    if problems:
        return lines, problems
    for index, name in states:
        if name in pairs:
            eol = "\r\n" if lines[index].endswith("\r\n") else "\n"
            lead = re.match(r"^(\s*name\s*=\s*)", lines[index]).group(1)
            lines[index] = '%s"%s"%s' % (lead, pairs[name], eol)
    return lines, problems


def icon_mentions(toml_path: Path) -> list[str]:
    """Path spellings code uses for this icon: 'icons/obj/power.dmi'."""
    rel = toml_path.resolve().relative_to(ROOT).as_posix()
    if rel.endswith(".toml"):
        rel = rel[: -len(".toml")]
    return [rel, rel.replace("/", "\\")]


def scan_refs(roots: list[Path], pairs: dict[str, str], mentions: list[str], anywhere: bool):
    """[(path, new text, count)] and the interpolated hits."""
    changes = []
    interpolated: list[str] = []
    olds = "|".join(re.escape(o) for o in sorted(pairs, key=len, reverse=True))
    exact = re.compile(r'"(%s)"' % olds)
    interp = re.compile(r'"(%s)\[' % olds)
    for root in roots:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*")):
            if path.suffix not in REF_SUFFIXES or not path.is_file():
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            if not anywhere and not any(m in text for m in mentions):
                continue
            count = 0

            def sub(m):
                nonlocal count
                count += 1
                return '"%s"' % pairs[m.group(1)]

            new_text = exact.sub(sub, text)
            for m in interp.finditer(text):
                line = text.count("\n", 0, m.start()) + 1
                interpolated.append("%s:%d: %s" % (path.relative_to(ROOT).as_posix(), line, m.group(0)))
            if count:
                changes.append((path, new_text, count))
    return changes, interpolated


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("toml", type=Path, help="the icon's .dmi.toml")
    ap.add_argument("--map", action="append", default=[], help="old=new (repeatable)")
    ap.add_argument("--map-file")
    ap.add_argument("--refs", action="append", default=[], help="directory or file to rewrite references in")
    ap.add_argument("--anywhere", action="store_true", help="rewrite in files that do not mention the icon")
    ap.add_argument("--apply", action="store_true", help="write the changes (default: dry run)")
    ap.add_argument("--standard", action="store_true", help="derive renames from legacy names (see above)")
    ap.add_argument("--check", action="store_true", help="list states off the naming convention and exit")
    args = ap.parse_args(argv)

    toml_path = args.toml if args.toml.is_absolute() else (ROOT / args.toml)
    if args.check:
        lines = toml_path.read_text(encoding="utf-8").splitlines()
        off = [n for _, n in read_toml_states(lines) if not CONVENTION.match(n)]
        for name in off:
            print(name)
        print("%d state(s) off the convention" % len(off))
        return 0

    pairs = parse_pairs(args.map, args.map_file)
    if args.standard:
        derived, skipped = standard_pairs(toml_path)
        for note in skipped:
            print("skipped: " + note)
        for old, new in derived.items():
            pairs.setdefault(old, new)
    if not pairs:
        ap.error("nothing to rename: give --map old=new or --map-file")
    new_lines, problems = plan_toml(toml_path, pairs)
    if problems:
        for p in problems:
            print("error: " + p)
        return 1
    roots = [Path(r) if Path(r).is_absolute() else ROOT / r for r in (args.refs or ["code", "maps"])]
    changes, interpolated = scan_refs(roots, pairs, icon_mentions(toml_path), args.anywhere)

    print("%s: %d state(s) renamed" % (toml_path.relative_to(ROOT).as_posix(), len(pairs)))
    for path, _, count in changes:
        print("  %s: %d reference(s)" % (path.relative_to(ROOT).as_posix(), count))
    if interpolated:
        print("interpolated references to edit by hand:")
        for line in interpolated:
            print("  " + line)
    if not args.apply:
        print("dry run: pass --apply to write")
        return 0
    toml_path.write_text("".join(new_lines), encoding="utf-8", newline="")
    for path, text, _ in changes:
        path.write_text(text, encoding="utf-8", newline="")
    print("applied; rebuild icons/gen with tools/dq_icons/repack.py (the build does it)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
