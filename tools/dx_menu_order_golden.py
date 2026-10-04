#!/usr/bin/env python3
"""Regenerate code/modules/unit_tests/dx_menu_order_golden.dm from a capture run.

Capture: run the two tests with the tables empty:

    python tools/dx_menu_order_golden.py --empty          # empties both tables
    bash tools/dq_focused_test.sh dx_menu_order dx_menu_order_static   # both fail, logging DXORDER / DXSTATIC lines
    python tools/dx_menu_order_golden.py --write LOG... [--static-add=/type,...]   # writes the tables from the log(s)

`--diff LOG...` prints what moved against the committed tables (git HEAD) without writing. Keys keep their committed order; new ones are
appended.
"""
import re
import subprocess
import sys
from pathlib import Path

GOLDEN = Path(__file__).resolve().parent.parent / "code/modules/unit_tests/dx_menu_order_golden.dm"
HEADER = """// The orders dx_menu_order and dx_menu_order_static check, last captured when binding specificity (resolve.dm, op_binding_specificity)
// replaced the storage.put_in default anchor. Do not edit by hand: regenerate with tools/dx_menu_order_golden.py.
"""
ENTRY = re.compile(r'^\t\t"(.*)" = "(.*)",?$')


def read_tables(text):
    tables, cur = [{}, {}], -1
    for line in text.splitlines():
        if line.startswith("/proc/dx_menu_order_golden()"):
            cur = 0
        elif line.startswith("/proc/dx_menu_order_static_golden()"):
            cur = 1
        m = ENTRY.match(line)
        if m and cur >= 0:
            tables[cur][m.group(1)] = m.group(2)
    return tables


def render(tables):
    def body(t):
        rows = [f'\t\t"{k}" = "{v}"' for k, v in t.items()]
        return ",\n".join(rows)
    out = HEADER + "\n"
    out += '/// "target <- held" = "all | click | menu" (see dx_menu_order.dm).\n/proc/dx_menu_order_golden()\n\tvar/static/list/table = list(\n'
    out += body(tables[0]) + "\n\t)\n\treturn table\n\n"
    out += '/// "type" = the keys of its ops in click order, gates ignored.\n/proc/dx_menu_order_static_golden()\n\tvar/static/list/table = list(\n'
    out += body(tables[1]) + "\n\t)\n\treturn table\n"
    return out


def read_logs(paths):
    got = [{}, {}]
    for p in paths:
        for line in Path(p).read_text(encoding="utf-8", errors="replace").splitlines():
            for tag, i in (("DXORDER|", 0), ("DXSTATIC|", 1)):
                at = line.find(tag)
                if at >= 0:
                    parts = line[at + len(tag):].split("|", 1)
                    if len(parts) == 2:
                        got[i][parts[0]] = parts[1].rstrip("\r\n")  # a line can end in spaces (an empty menu)
    return got


def merge(old, new):
    out = {k: new[k] for k in old if k in new}
    out.update({k: v for k, v in new.items() if k not in out})
    return out


def main():
    mode, logs = sys.argv[1], [a for a in sys.argv[2:] if not a.startswith("--static-add=")]
    # the static table keeps its listed types (a capture logs every type the static order finds interesting); --static-add=T1,T2 lists more
    add = [t for a in sys.argv[2:] if a.startswith("--static-add=") for t in a.split("=", 1)[1].split(",")]
    if mode == "--empty":
        GOLDEN.write_text(render([{}, {}]), encoding="utf-8", newline="\n")
        return
    rel = GOLDEN.relative_to(GOLDEN.parents[3]).as_posix()
    old = read_tables(subprocess.run(["git", "show", f"HEAD:{rel}"], cwd=GOLDEN.parents[3], capture_output=True, text=True, encoding="utf-8", check=True).stdout)
    new = read_logs(logs)
    new[1] = {k: v for k, v in new[1].items() if k in old[1] or k in add}
    if not new[0] or not new[1]:
        sys.exit("no DXORDER or no DXSTATIC lines in the log(s)")
    if mode == "--diff" or mode == "--write":
        for i, name in ((0, "dx_menu_order"), (1, "dx_menu_order_static")):
            for k in sorted(set(old[i]) | set(new[i])):
                if old[i].get(k) != new[i].get(k):
                    print(f"{name} | {k}\n  was: {old[i].get(k)}\n  now: {new[i].get(k)}")
    if mode == "--write":
        GOLDEN.write_text(render([merge(old[0], new[0]), merge(old[1], new[1])]), encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
