//! Port of `tools/ci/sys_rules/sync_sql.py`: synchronous SQL (AGENTS.md section 3f, "nothing waits
//! on I/O"; the SQL part of doc/rewrite/final_api.html section 2, the io host system).
//!
//! `sync_sql`: a call to `<query>.Execute(` or `<query>.warn_execute(` on a database query. A MySQL
//! `Execute()` outside a prompt flow either blocks the tick on the connection or is refused once the
//! kernel runs; the caller should start the query with `om_io(E, /datum/om/io/sql, ...)` or run as a
//! prompt flow. Not counted: the database layer itself (`dbcore.dm`, `sqlite.dm`, `flow_io.dm`,
//! `IsBanned.dm`: `[lint."sys/sync_sql"]` in `tools/ci/lint_scopes.toml`) and any call whose arguments
//! name `sqlite`. A boot-only caller elsewhere is kept with `// ALLOW(sys_sync_sql): <reason>`.
//!
//! Quirks kept from the Python:
//! * the file prefilter is the raw text containing `xecute(`, so a file whose only calls are
//!   `.Execute (` (a space before the parenthesis, which the pattern allows) is skipped;
//! * only the first call on a line is looked at, and its arguments are read off that one sanitized
//!   line: a string literal's text is blanked (so `Execute("sqlite")` still counts), and a call whose
//!   parenthesis closes on a later line has no arguments to inspect (it counts).

use crate::dm::dx::call_args;
use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::SourceFile;

const RULES: &[RuleMeta] = &[RuleMeta {
    name: "sync_sql",
    hint: "start the query with om_io(E, /datum/om/io/sql, ...) and read the rows in a callback, or run the caller as a prompt flow (code/datums/om/flow_io.dm)",
}];

/// `scan_lines`: one site per sanitized line with a call on a query that does not name sqlite.
fn scan_lines(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    let call = pat!(r"(?<![\w])[\w\]\)]+\s*\.\s*(?:warn_execute|Execute)\s*\(");
    for (number, code) in f.clean().numbered() {
        let Some(m) = call.find(code) else { continue };
        let args = call_args(code, m.end - 1).unwrap_or_default();
        if args.iter().any(|a| a.to_lowercase().contains("sqlite")) {
            continue;
        }
        out.push(("sync_sql", number));
    }
}

fn scan_file(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    if !f.raw().text.contains("xecute(") {
        return;
    }
    scan_lines(f, out);
}

fn selftest() -> Result<String, String> {
    let fixture = [
        "if(!query.Execute())",                         // 1 bad
        "query.Execute(async = FALSE)",                 // 2 bad
        "if(!query_admin_in_db.warn_execute())",        // 3 bad
        "query.Execute(SSsqlite.sqlite_db)",            // 4 ok: the local SQLite database
        "Execute(found)",                               // 5 ok: not a call on a query
        "/datum/SDQL2_query/proc/Execute(list/found)",  // 6 ok: a definition
        "// query.Execute()",                           // 7 ok: a comment
        "var/x = \"query.Execute()\"",                  // 8 ok: text
        "SSdbcore.NewQuery(\"SELECT 1\").Execute()",    // 9 bad: a call on a call
    ];
    let f = SourceFile::from_text("x.dm", &fixture.join("\n"));
    let mut v = Vec::new();
    scan_lines(&f, &mut v);
    let got: Vec<usize> = v.into_iter().map(|(_, n)| n).collect();
    if got != vec![1, 2, 3, 9] {
        return Err(format!("sync_sql selftest: got {:?}", got));
    }
    Ok("sync_sql".to_string())
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: "sync_sql", rules: RULES, file_scan: Some(scan_file), selftest: Some(selftest), py_selftest: true, ..SysModule::DEFAULT },
    );
}
