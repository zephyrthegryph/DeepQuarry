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

use crate::raw_fixture_policy::PatternApi as _;
use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::SourceFile;

use crate::allow_registry_fields::sys_sync_sql::RULES;

/// `scan_lines`: one site per sanitized line with a call on a query that does not name sqlite.
fn scan_lines(f:&SourceFile,out:&mut Vec<(&'static str,usize)>){
    scan_lines_using(f,out,&crate::raw_fixture_policy::Fixture::legacy()).expect("legacy scanner has no admission refusal")
}
fn scan_lines_using(f:&SourceFile,out:&mut Vec<(&'static str,usize)>,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<(),String>{
    fixture.check()?;
    let call = fixture.pattern(r"(?<![\w])[\w\]\)]+\s*\.\s*(?:warn_execute|Execute)\s*\(",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"(?<![\w])[\w\]\)]+\s*\.\s*(?:warn_execute|Execute)\s*\("));
    for (number, code) in f.clean().numbered() {
        let Some(m) = call.find(code) else { continue };
        let args = fixture.args(code,m.end-1)?.unwrap_or_default();
        let mut sqlite=false;for arg in &args{if fixture.lower(arg)?.contains("sqlite"){sqlite=true;break}}
        if sqlite {
            continue;
        }
        fixture.push(out,("sync_sql", number))?;
    }
    Ok(())
}


/// `scan_legacy`: one site per sanitized line naming the deleted database query API.
fn scan_legacy(f:&SourceFile,out:&mut Vec<(&'static str,usize)>){
    scan_legacy_using(f,out,&crate::raw_fixture_policy::Fixture::legacy()).expect("legacy scanner has no admission refusal")
}
fn scan_legacy_using(f:&SourceFile,out:&mut Vec<(&'static str,usize)>,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<(),String>{
    fixture.check()?;
    let legacy = fixture.pattern(r"\bNewQuery\s*\(|/datum/db_query\b|\brun_query_sync\b|\bqueue_query\b|\bqueries_(?:active|standby)\b",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"\bNewQuery\s*\(|/datum/db_query\b|\brun_query_sync\b|\bqueue_query\b|\bqueries_(?:active|standby)\b"));
    for (number, code) in f.clean().numbered() {
        if legacy.find(code).is_some() {
            fixture.push(out,("legacy_db_api", number))?;
        }
    }
    Ok(())
}


fn scan_file(f:&SourceFile,out:&mut Vec<(&'static str,usize)>){
    scan_file_using(f,out,&crate::raw_fixture_policy::Fixture::legacy()).expect("legacy scanner has no admission refusal")
}
fn scan_file_using(f:&SourceFile,out:&mut Vec<(&'static str,usize)>,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<(),String>{
    fixture.check()?;
    scan_legacy_using(f,out,fixture)?;
    if !f.raw().text.contains("xecute(") {
        return Ok(());
    }
    scan_lines_using(f,out,fixture)?;
    Ok(())
}


fn selftest() -> Result<String, String> {
    selftest_with_fixture(&crate::raw_fixture_policy::Fixture::legacy())
}

fn selftest_with_fixture(fixture: &crate::raw_fixture_policy::Fixture<'_>) -> Result<String, String> {
    let fixture_lines = [
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
    let f = fixture.file("x.dm", &fixture.join(&fixture_lines,"\n")?)?;
    let mut v = Vec::new();
    scan_lines_using(&f,&mut v,fixture)?;
    let got: Vec<usize> = fixture.collect(v.into_iter().map(|(_, n)| n))?;
    if got != [1, 2, 3, 9] {
        return Err(fixture.detail(format_args!("sync_sql selftest: got {:?}", got))?);
    }
    let legacy = [
        "var/datum/db_query/q = SSdbcore.NewQuery(\"SELECT 1\")", // 1 bad (twice on the line: one site)
        "SSdbcore.run_query_sync(q)",                              // 2 bad
        "// SSdbcore.NewQuery(sql)",                               // 3 ok: a comment
        "var/list/rows = sql_ask(src, \"SELECT 1\", null, PROC_REF(x))", // 4 ok
    ];
    let g = fixture.file("y.dm", &fixture.join(&legacy,"\n")?)?;
    let mut w = Vec::new();
    scan_legacy_using(&g,&mut w,fixture)?;
    let got: Vec<usize> = fixture.collect(w.into_iter().map(|(_, n)| n))?;
    if got != [1, 2] {
        return Err(fixture.detail(format_args!("legacy_db_api selftest: got {:?}", got))?);
    }
    Ok(fixture.own("sync_sql")?)
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: crate::allow_registry_fields::sys_sync_sql::SCOPE_MODULE_NAME, rules: RULES, file_scan: Some(scan_file), fixture_file_scan:Some(scan_file_using), selftest: Some(selftest), fixture_selftest: Some(selftest_with_fixture), py_selftest: true, ..SysModule::DEFAULT },
    );
}
