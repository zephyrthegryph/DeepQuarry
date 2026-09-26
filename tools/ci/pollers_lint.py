#!/usr/bin/env python3
"""Polling ratchet (roadmap S3-S5, doc/rewrite/migration_plan.md track 1d).

Periodic work runs on object-model pipelines, stages, watches, clocks and parking
(doc/rewrite/object_model_core.md section 4.10, code/datums/om/periodic.dm,
code/game/machinery/machine_pipeline.dm). This lint counts the old polling constructs
per file and fails when a file has more than tools/ci/pollers_allowlist.txt allows:

    process      a `process()` proc definition (`/type/process(` at column 0, or an
                 indented `process(` / `proc/process(` under a type block)
    start        a START_PROCESSING( or START_MACHINE_PROCESSING( call

Core files are exempt: the MC and subsystem framework (code/controllers/), the object-model
core (code/datums/om/), the defines, and the external-I/O datums whose process() is not
gameplay polling (tgui windows, database queries).

It also checks that every type defining machine_step() is covered by the machine pipeline's
decl (so a stepping machine can't silently never run).

    python tools/ci/pollers_lint.py            # the CI check
    python tools/ci/pollers_lint.py --report   # totals
    python tools/ci/pollers_lint.py --update   # rewrite the allowlist to today's counts
"""
import glob
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
ALLOWLIST = os.path.join(ROOT, "tools", "ci", "pollers_allowlist.txt")

EXEMPT_PREFIXES = (
    "code/controllers/",
    "code/datums/om/",
    "code/__defines/",
    "code/modules/unit_tests/",
)
EXEMPT_FILES = {
    "code/modules/tgui/tgui.dm",
    "code/controllers/subsystems/dbcore.dm",
}

TOP_LEVEL = re.compile(r"^/[\w/]+?/(?:proc/)?process\(")
TYPE_BLOCK = re.compile(r"^/[\w/]+\s*(?://.*)?$")
NESTED = re.compile(r"^\t(?:proc/)?process\(")
START = re.compile(r"(?<![\w])START_(?:MACHINE_)?PROCESSING\(")
DEFINE = re.compile(r"^\s*#\s*define\b")

STEP_DEF = re.compile(r"^(/obj/machinery[\w/]*?)/machine_step\(")
PIPELINE_FILE = os.path.join(ROOT, "code", "game", "machinery", "machine_pipeline.dm")


def strip_comment(line):
    out = []
    in_str = False
    i = 0
    while i < len(line):
        c = line[i]
        if c == '"' and (i == 0 or line[i - 1] != "\\"):
            in_str = not in_str
        if not in_str and line.startswith("//", i):
            break
        out.append(c)
        i += 1
    return "".join(out)


def dm_files():
    for path in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True) + glob.glob(os.path.join(ROOT, "maps", "**", "*.dm"), recursive=True):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        yield path, rel


def exempt(rel):
    return rel in EXEMPT_FILES or rel.startswith(EXEMPT_PREFIXES)


def count_file(path):
    process = 0
    start = 0
    in_type = False
    in_block_comment = False
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.rstrip("\n").rstrip("\r")
            if in_block_comment:
                if "*/" in line:
                    in_block_comment = False
                continue
            if line.lstrip().startswith("/*") and "*/" not in line:
                in_block_comment = True
                continue
            code = strip_comment(line)
            if TOP_LEVEL.match(code):
                process += 1
            elif in_type and NESTED.match(code):
                process += 1
            if TYPE_BLOCK.match(code):
                in_type = True
            elif code and not code[0].isspace():
                in_type = False
            if not DEFINE.match(code):
                start += len(START.findall(code))
    return process, start


def counts():
    result = {}
    for path, rel in dm_files():
        if exempt(rel):
            continue
        p, s = count_file(path)
        if p or s:
            result[rel] = (p, s)
    return result


def read_allowlist():
    allowed = {}
    if not os.path.exists(ALLOWLIST):
        return allowed
    with open(ALLOWLIST, encoding="utf-8") as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            rel, p, s = line.rsplit(None, 2)
            allowed[rel] = (int(p), int(s))
    return allowed


def write_allowlist(result):
    total_p = sum(v[0] for v in result.values())
    total_s = sum(v[1] for v in result.values())
    with open(ALLOWLIST, "w", encoding="utf-8", newline="\n") as f:
        f.write("# Polling ratchet (tools/ci/pollers_lint.py): <file> <process() defs> <START_*PROCESSING calls>.\n")
        f.write("# A file may not exceed its counts; files not listed may have none. Lower it as types migrate:\n")
        f.write("# `python tools/ci/pollers_lint.py --update`.\n")
        f.write(f"# Totals: {total_p} process() definitions, {total_s} START_PROCESSING/START_MACHINE_PROCESSING calls.\n")
        for rel in sorted(result):
            p, s = result[rel]
            f.write(f"{rel} {p} {s}\n")


def machine_pipeline_roots():
    with open(PIPELINE_FILE, encoding="utf-8") as f:
        text = f.read()
    m = re.search(r"/datum/om/decl/pipeline_machines\s*\n\tof = list\((.*?)\n\t\)", text, re.S)
    if not m:
        return None
    roots = set(re.findall(r"(/obj/machinery[\w/]*)", m.group(1)))
    # Lazily joined types (the decl's `lazy` list): covered, they join on MACHINE_WAKE().
    lazy = re.search(r"var/list/lazy = list\((.*?)\n\t\)", text, re.S)
    if lazy:
        roots |= set(re.findall(r"(/obj/machinery[\w/]*)", re.sub(r"//[^\n]*", "", lazy.group(1))))
    return roots


def check_step_coverage():
    roots = machine_pipeline_roots()
    if roots is None:
        return ["could not find /datum/om/decl/pipeline_machines in machine_pipeline.dm"]
    errors = []
    for path, rel in dm_files():
        if rel.startswith("code/modules/unit_tests/"):
            continue  # test probes join lazily through MACHINE_WAKE()
        with open(path, encoding="utf-8", errors="replace") as f:
            for n, line in enumerate(f, 1):
                m = STEP_DEF.match(line)
                if not m:
                    continue
                t = m.group(1)
                if t in ("/obj/machinery", "/obj/machinery/atmospherics", "/obj/machinery/proc"):  # defaults, not work
                    continue
                parts = t.split("/")
                if not any("/".join(parts[:i]) in roots for i in range(3, len(parts) + 1)):
                    errors.append(f"{rel}:{n}: {t} defines machine_step() but is not under any type in /datum/om/decl/pipeline_machines")
    return errors


def main():
    result = counts()
    if "--update" in sys.argv:
        write_allowlist(result)
        print(f"wrote {ALLOWLIST}")
        return 0
    total_p = sum(v[0] for v in result.values())
    total_s = sum(v[1] for v in result.values())
    if "--report" in sys.argv:
        for rel in sorted(result):
            print(f"{rel} {result[rel][0]} {result[rel][1]}")
        print(f"total: {total_p} process() definitions, {total_s} START calls, {len(result)} files")
        return 0
    allowed = read_allowlist()
    errors = []
    for rel, (p, s) in sorted(result.items()):
        ap, as_ = allowed.get(rel, (0, 0))
        if p > ap:
            errors.append(f"{rel}: {p} process() definitions (allowed {ap}) -- put the work on a pipeline (code/datums/om/periodic.dm)")
        if s > as_:
            errors.append(f"{rel}: {s} START_*PROCESSING calls (allowed {as_}) -- use PERIODIC_START or a machine wake")
    errors += check_step_coverage()
    for e in errors:
        print(e)
    print(f"pollers: {total_p} process() definitions, {total_s} START calls outside core")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
