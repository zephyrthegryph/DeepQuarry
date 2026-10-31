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

use std::collections::HashSet;

use crate::dm::dx::procs_in;
use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat::Pat;
use crate::pat_match;
use crate::tree::SourceFile;
use crate::util::{py_lstrip, py_strip};

const RULES: &[RuleMeta] = &[RuleMeta {
    name: "usr_outside_verb",
    hint: "take the acting mob as a `user` argument (or use `src`); `usr` is only meaningful at the top of a verb (AGENTS.md 3a)",
}];

/// `verb_lines`: the set of 1-based line numbers that belong to a verb's body (or a verb macro's).
fn verb_lines(f: &SourceFile) -> HashSet<usize> {
    let set_stmt = pat_match!(r"^\s*set\s+(?:name|category|src|desc|hidden|popup_menu|instant)\b");
    let verb_macro = pat_match!(r"^(?:ADMIN_VERB\w*|DECLARE_\w*VERB\w*)\(");
    let clean = f.clean();
    let mut out = HashSet::new();
    for proc in procs_in(f) {
        let end = proc.body_start + proc.body_len - 1;
        let head = clean.line(proc.line);
        let verb = head.split('(').next().unwrap_or("").contains("/verb/")
            || (0..proc.body_len).any(|k| set_stmt.is_match(clean.line(proc.body_start + k)));
        if verb {
            out.extend(proc.line..=end);
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
            out.extend(i + 1..=j);
            i = j;
            continue;
        }
        i += 1;
    }
    out
}

/// `scan_lines`: `usr` in sanitized code, not on a preprocessor line and not in a verb.
fn scan_lines(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    let usr: &Pat = crate::pat!(r"(?<![\w.])usr(?!\w)");
    let hits: Vec<usize> =
        f.clean().numbered().filter(|(_, code)| usr.is_match(code) && !py_lstrip(code).starts_with('#')).map(|(n, _)| n).collect();
    if hits.is_empty() {
        return;
    }
    let verb = verb_lines(f);
    for n in hits {
        if !verb.contains(&n) {
            out.push(("usr_outside_verb", n));
        }
    }
}

fn scan_file(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    if !f.raw().text.contains("usr") {
        return;
    }
    scan_lines(f, out);
}

fn selftest() -> Result<String, String> {
    let fixture = [
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
    let f = SourceFile::from_text("x.dm", &fixture.join("\n"));
    let mut v = Vec::new();
    scan_lines(&f, &mut v);
    let got: Vec<usize> = v.into_iter().map(|(_, n)| n).collect();
    if got != vec![2, 3, 14] {
        return Err(format!("usr_use selftest: got {:?}", got));
    }
    Ok("usr_use".to_string())
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: "usr_use", rules: RULES, file_scan: Some(scan_file), selftest: Some(selftest), py_selftest: true, ..SysModule::DEFAULT },
    );
}
