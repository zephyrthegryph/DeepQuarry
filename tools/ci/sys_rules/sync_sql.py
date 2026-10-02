"""sys_lint module: synchronous SQL (AGENTS.md section 3f: "nothing waits on I/O"; the SQL part of
doc/rewrite/final_api.html section 2, the io host system).

Rule:
  sync_sql   a call to `<query>.Execute(` or `<query>.warn_execute(` on a database query.

A MySQL `Execute()` outside a prompt flow either blocks the tick on the connection
(`async = FALSE`, and the boot-time default) or is refused outright once the kernel runs
(code/controllers/subsystems/dbcore.dm: "Execute(async) outside a prompt flow"). The caller
should start the query with `om_io(E, /datum/om/io/sql, ...)` and take the rows in a callback, or
run as a prompt flow (code/datums/om/flow_io.dm).

Not counted: the database layer itself, `dbcore.dm` (boot and shutdown queries; it is the one place
that may block), `flow_io.dm` (the flow wrapper), the local SQLite database (`sqlite.dm`, and any
call whose arguments name `sqlite`), and `world/IsBanned`. A boot-only caller elsewhere is kept with
`// ALLOW(sys_sync_sql): <reason>`.

The baseline (tools/ci/sys_baseline/sync_sql.txt) holds the legacy sites; target 0. Unit tests and
benchmarks are skipped by sys_lint itself.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _dx_dm as dm  # noqa: E402

RULES = {
    "sync_sql": "start the query with om_io(E, /datum/om/io/sql, ...) and read the rows in a callback, or run the caller as a prompt flow (code/datums/om/flow_io.dm)",
}

EXEMPT_FILES = (
    "code/controllers/subsystems/dbcore.dm",
    "code/controllers/subsystems/sqlite.dm",
    "code/datums/om/flow_io.dm",
    "code/modules/admin/IsBanned.dm",
)

CALL = re.compile(r"(?<![\w])[\w\]\)]+\s*\.\s*(?:warn_execute|Execute)\s*\(")


def scan_lines(rel, clean):
    found = []
    for number, code in enumerate(clean, 1):
        m = CALL.search(code)
        if not m:
            continue
        args = dm.call_args(code, m.end() - 1) or []
        if any("sqlite" in a.lower() for a in args):
            continue
        found.append((rel, number))
    return found


def scan(files):
    out = {"sync_sql": []}
    tree = dm.tree(files)
    for rel, _lines in files:
        if rel in EXEMPT_FILES:
            continue
        if "xecute(" not in tree.raw_text(rel):
            continue
        out["sync_sql"].extend(scan_lines(rel, tree.clean[rel]))
    return out


def selftest():
    fixture = [
        "if(!query.Execute())",                                   # 1 bad
        "query.Execute(async = FALSE)",                           # 2 bad
        "if(!query_admin_in_db.warn_execute())",                  # 3 bad
        "query.Execute(SSsqlite.sqlite_db)",                      # 4 ok: the local SQLite database
        "Execute(found)",                                         # 5 ok: not a call on a query
        "/datum/SDQL2_query/proc/Execute(list/found)",            # 6 ok: a definition
        "// query.Execute()",                                     # 7 ok: a comment
        "var/x = \"query.Execute()\"",                            # 8 ok: text
        "SSdbcore.NewQuery(\"SELECT 1\").Execute()",              # 9 bad: a call on a call
    ]
    got = [n for _rel, n in scan_lines("x.dm", dm.sanitize(fixture))]
    assert got == [1, 2, 3, 9], got
    return "sync_sql"
