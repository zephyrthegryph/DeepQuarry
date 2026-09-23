#!/usr/bin/env python3
"""Body-time lint (doc/medical_frameworks.md §1.13).

Nothing time-based in the body rewrite's areas runs on process(), START_PROCESSING or addtimer.
There are two ways to run on time: the holder ticks it (life_tick(ctx) with ctx.body_seconds),
or it is clocked (on_settle() plus clock events; code/datums/clocks/). Rules:

  timer     START_PROCESSING / STOP_PROCESSING / addtimer( in code/modules/{body,organs,medical,
            surgery}/**, code/modules/reagents/reagents/** and code/modules/mob/living/**.
  process   A process() proc on /obj/item/organ, /obj/item/implant, /datum/affliction or
            /datum/reagent subtypes. Holder-ticked work is life_tick().
  stasis    The identifiers inStasisNow, stasis_paused, advance_stasis and preserved, anywhere
            in code/.
  settle    world.time inside an on_settle() or life_tick() body (use the clock or ctx). No
            allowlist.
  prob      prob( inside a life_tick() body without PROB_OVER.

Existing sites are listed in tools/ci/body_time_allowlist.txt as `rule<TAB>file<TAB>count`.
The list is a ratchet: a file may not gain sites, and an entry whose count is higher than what
is left fails too, so the list only shrinks as slices K2-K5 convert their files.

    python3 tools/ci/check_body_time.py            # the CI check
    python3 tools/ci/check_body_time.py --list     # print every finding
    python3 tools/ci/check_body_time.py --update   # rewrite the allowlist to the current counts
"""
import os
import re
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ALLOWLIST = os.path.join(ROOT, "tools", "ci", "body_time_allowlist.txt")

TIMER_DIRS = [
    "code/modules/body",
    "code/modules/organs",
    "code/modules/medical",
    "code/modules/surgery",
    "code/modules/reagents/reagents",
    "code/modules/mob/living",
]
TIMER = re.compile(r"\b(?:START_PROCESSING|STOP_PROCESSING)\b|\baddtimer\(")
PROCESS_TYPES = r"/(?:obj/item/organ|obj/item/implant|datum/affliction|datum/reagent)(?:/[\w/]*)?"
PROCESS_TOP = re.compile(r"^(" + PROCESS_TYPES + r")/(?:proc/)?process\(")
TYPE_BLOCK = re.compile(r"^(/[\w/]+)\s*(?://.*)?$")
NESTED_PROCESS = re.compile(r"^\t(?:proc/)?process\(")
PROCESS_TYPE_RE = re.compile("^" + PROCESS_TYPES + "$")
STASIS = re.compile(r"\b(?:inStasisNow|stasis_paused|advance_stasis|preserved)\b")
BODY_START_TOP = re.compile(r"^/[\w/]+?/(?:proc/)?(on_settle|life_tick)\(")
BODY_START_NESTED = re.compile(r"^\t(?:proc/)?(on_settle|life_tick)\(")
WORLD_TIME = re.compile(r"\bworld\.time\b")
PROB = re.compile(r"(?<![\w.])prob\(")

# Rules without an allowlist: any finding fails.
STRICT = {"settle"}


def strip_comment_and_strings(line):
    out = []
    in_str = False
    i = 0
    while i < len(line):
        c = line[i]
        if c == '"' and (i == 0 or line[i - 1] != "\\"):
            in_str = not in_str
            out.append(c)
            i += 1
            continue
        if not in_str and line.startswith("//", i):
            break
        out.append(" " if in_str else c)
        i += 1
    return "".join(out)


def dm_files(base):
    for dirpath, _, names in os.walk(os.path.join(ROOT, base)):
        for name in names:
            if name.endswith(".dm"):
                full = os.path.join(dirpath, name)
                yield os.path.relpath(full, ROOT).replace(os.sep, "/"), full


def read_lines(full):
    with open(full, encoding="utf-8", errors="ignore") as f:
        return [strip_comment_and_strings(l.rstrip("\r")) for l in f.read().split("\n")]


def indent_of(line):
    return len(line) - len(line.lstrip("\t"))


def proc_bodies(lines, starts_top, starts_nested):
    """Yields (line_index, line) for every line inside a matching proc body."""
    current_type_block = False
    i = 0
    while i < len(lines):
        line = lines[i]
        body_indent = None
        if starts_top.match(line):
            body_indent = 1
        elif TYPE_BLOCK.match(line):
            current_type_block = True
        elif current_type_block and starts_nested.match(line):
            body_indent = 2
        elif line and not line.startswith("\t"):
            current_type_block = False
        if body_indent is None:
            i += 1
            continue
        i += 1
        while i < len(lines):
            body = lines[i]
            if body.strip() and indent_of(body) < body_indent:
                break
            yield i, body
            i += 1


def scan():
    """Returns a list of (rule, file, line_number, text)."""
    findings = []
    for base in TIMER_DIRS:
        for rel, full in dm_files(base):
            for n, line in enumerate(read_lines(full), 1):
                if TIMER.search(line):
                    findings.append(("timer", rel, n, line.strip()))
    for rel, full in dm_files("code"):
        lines = read_lines(full)
        current_type = None
        for n, line in enumerate(lines, 1):
            if STASIS.search(line):
                findings.append(("stasis", rel, n, line.strip()))
            m = PROCESS_TOP.match(line)
            if m:
                findings.append(("process", rel, n, line.strip()))
                continue
            tb = TYPE_BLOCK.match(line)
            if tb:
                current_type = tb.group(1)
            elif line and not line.startswith("\t"):
                current_type = None
            elif current_type and NESTED_PROCESS.match(line) and PROCESS_TYPE_RE.match(current_type):
                findings.append(("process", rel, n, current_type + ": " + line.strip()))
        for idx, body in proc_bodies(lines, BODY_START_TOP, BODY_START_NESTED):
            if WORLD_TIME.search(body):
                findings.append(("settle", rel, idx + 1, body.strip()))
        life_tick_top = re.compile(r"^/[\w/]+?/(?:proc/)?life_tick\(")
        life_tick_nested = re.compile(r"^\t(?:proc/)?life_tick\(")
        for idx, body in proc_bodies(lines, life_tick_top, life_tick_nested):
            if PROB.search(body) and "PROB_OVER" not in body:
                findings.append(("prob", rel, idx + 1, body.strip()))
    return findings


def load_allowlist():
    allowed = {}
    if not os.path.exists(ALLOWLIST):
        return allowed
    with open(ALLOWLIST, encoding="utf-8") as f:
        for raw in f:
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            rule, path, count = line.split("\t")
            allowed[(rule, path)] = int(count)
    return allowed


def write_allowlist(counts):
    with open(ALLOWLIST, "w", encoding="utf-8", newline="\n") as f:
        f.write("# Body-time lint ratchet (tools/ci/check_body_time.py, doc/medical_frameworks.md §1.13).\n")
        f.write("# rule<TAB>file<TAB>sites. A file may not gain sites; lower a count (or drop the line)\n")
        f.write("# when a K2-K5 slice converts sites, or the check fails as stale.\n")
        for (rule, path), count in sorted(counts.items()):
            f.write(f"{rule}\t{path}\t{count}\n")


def main():
    findings = scan()
    counts = Counter((rule, path) for rule, path, _, _ in findings if rule not in STRICT)
    if "--list" in sys.argv:
        for rule, path, n, text in findings:
            print(f"{rule}\t{path}:{n}\t{text}")
        return 0
    if "--update" in sys.argv:
        write_allowlist(counts)
        print(f"body_time_allowlist.txt: {len(counts)} entries, {sum(counts.values())} sites")
        return 0
    allowed = load_allowlist()
    failed = False
    for rule, path, n, text in findings:
        if rule in STRICT:
            print(f"{path}:{n}: [{rule}] {text}  (world.time inside on_settle()/life_tick(): use the clock or ctx)")
            failed = True
    for key, count in sorted(counts.items()):
        limit = allowed.get(key, 0)
        if count > limit:
            rule, path = key
            print(f"{path}: [{rule}] {count} sites, allowlist has {limit}. New body-time sites must be clocked or holder-ticked (doc/medical_frameworks.md §1.2):")
            for r, p, n, text in findings:
                if r == rule and p == path:
                    print(f"    {p}:{n}: {text}")
            failed = True
    for key, limit in sorted(allowed.items()):
        if counts.get(key, 0) < limit:
            rule, path = key
            print(f"{path}: [{rule}] stale allowlist entry: {counts.get(key, 0)} sites left, allowlist has {limit}. Lower it.")
            failed = True
    if failed:
        print("Body-time lint failed. Run with --list to see every site.")
        return 1
    print(f"Body-time lint: {sum(counts.values())} allowlisted sites in {len(counts)} entries, no new ones.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
