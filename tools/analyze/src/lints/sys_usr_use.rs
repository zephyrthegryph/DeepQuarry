//! Port of `tools/ci/sys_rules/usr_use.py`: `usr` outside a verb (AGENTS.md section 3a, "Avoid `usr`
//! outside verb procs").
//!
//! `usr_outside_verb`: the word `usr` in code that is not a verb's body. A verb body is any proc that
//! carries `set name`/`set category`/`set src`/`set desc`/`set hidden`/`set popup_menu`/`set instant`,
//! anything under `/verb/`, and the body of an `ADMIN_VERB(...)` or `DECLARE_VERB...` macro.
//! Preprocessor lines and the macro library (`code/__defines/`: `[lint."sys/usr_use"]` in
//! `tools/ci/lint_scopes.toml`) are skipped. Text inside a string is ignored; an embedded `[usr]` is
//! code and counts.
//!
//! Static limits kept from the Python: a proc that is a verb only because `DECLARE_VERB` grants it, and
//! has no `set` line, is seen as an ordinary proc; macro-generated procs other than the verb macros
//! are scanned as loose code. A verb proc's range runs from its head line through its last body line
//! (the head line itself is exempt), and a verb macro's from its own line through the indented or
//! blank lines under it.

use crate::raw_fixture_policy::PatternApi as _;
use std::collections::HashSet;

use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat::Pat;
use crate::pat_match;
use crate::tree::SourceFile;
use crate::util::{py_lstrip, py_strip};

use crate::allow_registry_fields::sys_usr_use::RULES;

/// `verb_lines`: the set of 1-based line numbers that belong to a verb's body (or a verb macro's).
fn verb_lines_using(f:&SourceFile,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<HashSet<usize>,String>{
    fixture.check()?;
    let set_stmt = fixture.pattern(r"^\s*set\s+(?:name|category|src|desc|hidden|popup_menu|instant)\b",crate::raw_fixture_policy::PatternMode::Match,||crate::pat_match!(r"^\s*set\s+(?:name|category|src|desc|hidden|popup_menu|instant)\b"));
    let verb_macro = fixture.pattern(r"^(?:ADMIN_VERB\w*|DECLARE_\w*VERB\w*)\(",crate::raw_fixture_policy::PatternMode::Match,||crate::pat_match!(r"^(?:ADMIN_VERB\w*|DECLARE_\w*VERB\w*)\("));
    let clean = f.clean();
    let mut out = HashSet::new();
    for proc in fixture.procs(f)? {
        let end = proc.body_start + proc.body_len - 1;
        let head = clean.line(proc.line);
        let verb = head.split('(').next().unwrap_or("").contains("/verb/")
            || (0..proc.body_len).any(|k| set_stmt.is_match(clean.line(proc.body_start + k)));
        if verb {
            for line in proc.line..=end{fixture.set_insert(&mut out,line)?;}
        }
    }
    // A macro-defined verb: `ADMIN_VERB(` at column 0 and the indented body under it.
    let n = clean.num_lines();
    let mut i = 0usize; // 0-based
    while i < n {
        if verb_macro.is_match(clean.line(i + 1)) {
            let mut j = i + 1;
            while j < n && (py_strip(clean.line(j + 1)).is_empty() || clean.line(j + 1).starts_with([' ', '\t'])) {
                j += 1;
            }
            for line in i+1..=j{fixture.set_insert(&mut out,line)?;}
            i = j;
            continue;
        }
        i += 1;
    }
    Ok(out)
}

/// `scan_lines`: `usr` in sanitized code, not on a preprocessor line and not in a verb.
fn scan_lines(f:&SourceFile,out:&mut Vec<(&'static str,usize)>){scan_lines_using(f,out,&crate::raw_fixture_policy::Fixture::legacy()).expect("legacy scanner has no admission refusal")}
fn scan_lines_using(f:&SourceFile,out:&mut Vec<(&'static str,usize)>,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<(),String>{
    fixture.check()?;
    let usr=fixture.pattern(r"(?<![\w.])usr(?!\w)",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"(?<![\w.])usr(?!\w)"));
    let hits: Vec<usize> =
        fixture.collect(f.clean().numbered().filter(|(_, code)| usr.is_match(code) && !py_lstrip(code).starts_with('#')).map(|(n, _)| n))?;
    if hits.is_empty() {
        return Ok(());
    }
    let verb = verb_lines_using(f,fixture)?;
    for n in hits {
        if !verb.contains(&n) {
            fixture.push(out,("usr_outside_verb", n))?;
        }
    }
    Ok(())
}

fn scan_file(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    if !f.raw().text.contains("usr") {
        return;
    }
    scan_lines(f, out);
}

fn selftest() -> Result<String, String> {
    selftest_with_fixture(&crate::raw_fixture_policy::Fixture::legacy())
}

fn selftest_with_fixture(fixture: &crate::raw_fixture_policy::Fixture<'_>) -> Result<String, String> {
    let fixture_lines = [
        "/mob/proc/plain()",                             // 1
        "\tvar/mob/M = usr",                             // 2 bad
        "\tto_chat(usr, \"the usr word in text\")",      // 3 bad (the call), not the text
        "/mob/proc/ability()",                           // 4
        "\tset name = \"Ability\"",                      // 5
        "\tset category = \"Abilities\"",                // 6
        "\tvar/mob/M = usr",                             // 7 ok: a verb body
        "/mob/verb/shout()",                             // 8
        "\tto_chat(usr, \"hi\")",                        // 9 ok: under /verb/
        "ADMIN_VERB(smite, R_FUN, \"Smite\", \"x\", y)", // 10
        "\tlog_admin(\"[key_name(usr)]\")",              // 11 ok: a verb macro body
        "/proc/helper(x)",                               // 12
        "\tvar/t = \"usr\"",                             // 13 ok: text only
        "\tlog_admin(\"[usr]\")",                        // 14 bad: an embedded expression
        "#define WHO usr",                               // 15 ok: preprocessor
        "\t// usr is mentioned in a comment",            // 16 ok: a comment
        "\tvar/x = src.usr_count",                       // 17 ok: another identifier
    ];
    let f = fixture.file("x.dm", &fixture.join(&fixture_lines,"\n")?)?;
    let mut v = Vec::new();
    scan_lines_using(&f,&mut v,fixture)?;
    let got: Vec<usize> = fixture.collect(v.into_iter().map(|(_, n)| n))?;
    if got != [2, 3, 14] {
        return Err(fixture.detail(format_args!("usr_use selftest: got {:?}", got))?);
    }
    Ok(fixture.own("usr_use")?)
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: crate::allow_registry_fields::sys_usr_use::SCOPE_MODULE_NAME, rules: RULES, file_scan: Some(scan_file), fixture_file_scan:Some(scan_lines_using), selftest: Some(selftest), fixture_selftest: Some(selftest_with_fixture), py_selftest: true, ..SysModule::DEFAULT },
    );
}
