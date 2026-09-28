#!/usr/bin/env python3
"""Polling ratchet (roadmap S3-S5, doc/rewrite/migration_plan.md track 1d).

Periodic work runs on object-model pipelines, stages, watches, clocks and parking
(doc/rewrite/object_model_core.md section 4.10, code/datums/om/periodic.dm,
code/game/machinery/machine_pipeline.dm). This lint counts the old polling constructs
and fails on any site not marked `// ALLOW(pollers): <reason>` on its line or the
comment line above it (tools/ci/allow_annotations.py):

    process      a `process()` proc definition (`/type/process(` at column 0, or an
                 indented `process(` / `proc/process(` under a type block)
    start        a START_PROCESSING( or START_MACHINE_PROCESSING( call

Core files are exempt: the MC and subsystem framework (code/controllers/), the object-model
core (code/datums/om/), the defines, and the external-I/O datums whose process() is not
gameplay polling (tgui windows, database queries).

It also checks that every type defining machine_step() is covered by the machine pipeline's
decl (so a stepping machine can't silently never run).

    python tools/ci/pollers_lint.py            # the CI check
    python tools/ci/pollers_lint.py --report   # every site
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from allow_annotations import allowed  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

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
    """(process() definition lines, START_*PROCESSING call lines) not kept by ALLOW(pollers)."""
    process = []
    start = []
    in_type = False
    in_block_comment = False
    with open(path, encoding="utf-8", errors="replace") as f:
        raw_lines = f.read().split("\n")
    for number, raw in enumerate(raw_lines, 1):
        line = raw.rstrip("\r")
        if in_block_comment:
            if "*/" in line:
                in_block_comment = False
            continue
        if line.lstrip().startswith("/*") and "*/" not in line:
            in_block_comment = True
            continue
        code = strip_comment(line)
        kept = allowed(raw_lines, number, "pollers")
        if (TOP_LEVEL.match(code) or (in_type and NESTED.match(code))) and not kept:
            process.append(number)
        if TYPE_BLOCK.match(code):
            in_type = True
        elif code and not code[0].isspace():
            in_type = False
        if not DEFINE.match(code) and not kept and START.search(code):
            start.append(number)
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
    total_p = sum(len(v[0]) for v in result.values())
    total_s = sum(len(v[1]) for v in result.values())
    errors = []
    for rel, (p, st) in sorted(result.items()):
        for n in p:
            errors.append(f"{rel}:{n}: process() definition -- put the work on a pipeline (code/datums/om/periodic.dm)")
        for n in st:
            errors.append(f"{rel}:{n}: START_*PROCESSING call -- use om_task_periodic() or a machine wake")
    if "--report" in sys.argv:
        for e in errors:
            print(e)
        print(f"total: {total_p} process() definitions, {total_s} START calls, {len(result)} files")
        return 0
    errors += check_step_coverage()
    for e in errors:
        print(e)
    print(f"pollers: {total_p} process() definitions, {total_s} START calls outside core")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
