#!/usr/bin/env python3
"""A bare `dir` write on an atom becomes set_dir(), so a drawn type redraws when its dir changes (final_api section 7/13).

    X.dir = V   ->  X.set_dir(V)        dir = V / src.dir = V  ->  set_dir(V)        X.dir |= V  ->  X.set_dir(X.dir | V)

Sites come from the `tracked` lint (SETTER(/atom, dir) makes every write outside set_dir() a finding), plus the dotted writes
whose holder is a name known to be an atom (ATOM_HOLDERS) that the lint cannot type. code/game/machinery and code/modules/power
are never written: their counts are printed. Dry run by default; --apply writes.

    python tools/dx/codemods/dir_to_set_dir.py [--analyze PATH] [--apply]
"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
SKIP = ("code/game/machinery/", "code/modules/power/", "code/modules/unit_tests/")
ATOM_HOLDERS = {"mob", "user", "host", "H", "AM", "shadekin", "result", "new_pad", "plant", "frame", "WD", "bottom", "gargoyle", "P2", "door_bottom", "placement", "new_holder"}
WRITE = re.compile(r"^(?P<ind>\s*)(?:(?P<holder>[A-Za-z_][\w\.]*)\.)?dir\s*(?P<op>\|=|&=|\^=|\+=|-=|=)\s*(?P<val>[^=].*?)\s*(?P<cmt>//.*)?$")


def sites_from_lint(binary):
    out = subprocess.run([binary, "check", "--lint", "tracked"], cwd=ROOT, capture_output=True, text=True).stdout
    found = set()
    for line in out.splitlines():
        m = re.match(r"(code/\S+?):(\d+): \[tracked/outside_setter\] (?:\w+\.)?dir written", line)
        if m:
            found.add((m.group(1), int(m.group(2))))
    return found


def rewrite(line):
    m = WRITE.match(line)
    if not m:
        return None
    holder, op, val = m.group("holder"), m.group("op"), m.group("val")
    if holder == "src":
        holder = None
    target = "%s." % holder if holder else ""
    cur = "%sdir" % target
    if op != "=":
        val = "%s %s %s" % (cur, op[:-1], val)
    out = "%s%sset_dir(%s)" % (m.group("ind"), target, val)
    if m.group("cmt"):
        out += " " + m.group("cmt")
    return out


def main():
    args = sys.argv[1:]
    binary = str(ROOT / "tools/analyze/target/release/analyze.exe")
    if "--analyze" in args:
        binary = args[args.index("--analyze") + 1]
    sites = sites_from_lint(binary)
    for path in ROOT.joinpath("code").rglob("*.dm"):
        rel = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding="utf-8", errors="surrogateescape")
        for i, line in enumerate(text.split("\n"), 1):
            m = WRITE.match(line.rstrip("\r"))
            if m and m.group("holder") in ATOM_HOLDERS:
                sites.add((rel, i))
    by_file = {}
    skipped = {}
    for rel, n in sorted(sites):
        if rel.startswith(SKIP):
            skipped[rel] = skipped.get(rel, 0) + 1
            continue
        by_file.setdefault(rel, []).append(n)
    changed = 0
    for rel, nums in by_file.items():
        path = ROOT / rel
        raw = path.read_bytes().decode("utf-8", errors="surrogateescape")
        crlf = "\r\n" in raw
        lines = raw.replace("\r\n", "\n").split("\n")
        for n in nums:
            new = rewrite(lines[n - 1])
            if new is None:
                print("unhandled %s:%d: %s" % (rel, n, lines[n - 1].strip()))
                continue
            lines[n - 1] = new
            changed += 1
            print("%s:%d -> %s" % (rel, n, new.strip()))
        out = "\n".join(lines)
        if crlf:
            out = out.replace("\n", "\r\n")
        path.write_bytes(out.encode("utf-8", errors="surrogateescape"))
    print("rewrote %d site(s); skipped (machinery/power/tests): %s" % (changed, sum(skipped.values())))
    for rel, c in sorted(skipped.items()):
        print("  skipped %s: %d" % (rel, c))


main()
