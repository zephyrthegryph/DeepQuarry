//! Port of `tools/ci/sys_rules/expiry.py` (doc/rewrite/systems.md section 17): hand-rolled expiry and
//! elapsed state read against `world.time`.
//!
//! `world_time_expiry` counts a `world.time` compare that `cooldown_lint.py` does NOT count as a
//! cooldown, plus elapsed compares; `world_time_write` a stored time written as `x = world.time`
//! (or through `EXPIRY_AT` on a member); `expiry_undeclared` a var read or written by an `EXPIRY_*`
//! macro that has no `EXPIRY_DECLARE`.
//!
//! The Python imports `cooldown_lint` (its COMPARE/CONST_CMP/TIME_NAME patterns and
//! `timestamp_names()`); the parts expiry uses are inlined here. Not a cooldown lint port.
//!
//! The Python module redefines `scan` three times (compares, then writes, then `EXPIRY_AT` writes);
//! sites are emitted in the same pass order (all compares, then writes, then undeclared, then
//! `EXPIRY_AT` writes), which only matters for the order inside `world_time_write`.
//!
//! Quirk kept: `ALLOW(cooldown)` inside this module is checked with the engine's `allow::kept`
//! directly (the module has no Sink there), so that use is not recorded for the unused-ALLOW check.

use std::collections::BTreeSet;

use std::sync::OnceLock;

use serde::{Deserialize, Serialize};

use crate::dm::sys::{register_module, SysModule};
use crate::incr;
use crate::lint::{Registry, RuleMeta};
use crate::pat::Pat;
use crate::pat;
use crate::tree::{SourceFile, Tree, CODE_DM};
use crate::util::{before_slashes, py_lstrip, py_strip};

const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "world_time_expiry",
        hint: "EXPIRY_DECLARE/EXPIRY_SET/EXPIRY_ACTIVE/EXPIRY_LEFT/ELAPSED (code/__defines/sys_expiry.dm, doc/rewrite/systems.md section 17)",
    },
    RuleMeta {
        name: "world_time_write",
        hint: "a stored time is written with EXPIRY_SET/EXPIRY_EXTEND/EXPIRY_STAMP (or EXPIRY_AT for list slots/records), never `x = world.time (+ N)`",
    },
    RuleMeta {
        name: "expiry_undeclared",
        hint: "a var read/written by EXPIRY_*/ELAPSED is declared with EXPIRY_DECLARE/EXPIRY_TMP_DECLARE",
    },
];

const SKIP: &[&str] = &["code/datums/om/", "code/controllers/master.dm", "code/controllers/failsafe.dm"];
/// `cooldown_lint.SKIP_DIRS`.
const COOLDOWN_SKIP_DIRS: &[&str] = &["code/modules/unit_tests/", "code/controllers/", "code/datums/om/"];

/// `CMP` of both modules (a compare operator that is not a shift, `==`, `!=` or `>>`).
macro_rules! cmp {
    () => {
        r"(?:>=|<=|(?<![<>=!])>(?![>=])|(?<![<>=])<(?![<=]))"
    };
}

fn skipped(rel: &str) -> bool {
    SKIP.iter().any(|p| rel.starts_with(p))
}

fn compare() -> &'static Pat {
    pat!(concat!(r"(?<![\w.])world\.time\s*", cmp!(), r"|", cmp!(), r"\s*world\.time(?![\w])"))
}

fn const_cmp() -> &'static Pat {
    pat!(concat!(
        r"world\.time\s*",
        cmp!(),
        r"\s*\d+(?:\.\d+)?(?:\s+(?:SECONDS?|MINUTES?|HOURS?|DECISECONDS?))?\s*(?:\)|$|&&|\|\|)|(?:^|\(|&&|\|\|)\s*\d+(?:\.\d+)?(?:\s+(?:SECONDS?|MINUTES?|HOURS?|DECISECONDS?))?\s*",
        cmp!(),
        r"\s*world\.time"
    ))
}

fn elapsed() -> &'static Pat {
    pat!(concat!(
        r#"(?<![\w.])world\.time\s*-\s*[\w.\[\]\"]+(?:\s*\))?\s*"#,
        cmp!(),
        r"|",
        cmp!(),
        r"\s*\(?\s*world\.time\s*-\s*\w"
    ))
}

/// `cooldown_lint.not_a_cooldown`: the compare reads a recorded time kept as data.
fn not_a_cooldown(rel: &str, line: &str, stamp: Option<&Pat>) -> bool {
    if pat!(r"\b\w*(?:_at|_until|_since|deadline|expires|expires_at|expiry|timestamp|timeofdeath)\b").is_match(line)
        || pat!(r#"\[\s*(?:""|\d+)\s*\]"#).is_match(line)
        || const_cmp().is_match(py_strip(line))
    {
        return true;
    }
    if let Some(s) = stamp {
        if s.is_match(line) {
            return true;
        }
    }
    rel.starts_with("code/modules/reagents/") && pat!(r"(?<![\w.])data\b").is_match(line)
}

/// `cooldown_lint.timestamp_names()`: every `EXPIRY_DECLARE`d name in `code/`.
fn timestamp_names(tree: &Tree) -> BTreeSet<String> {
    let files = tree.select(&CODE_DM);
    let per: Vec<Vec<String>> = incr::facts("sys-expiry-names", &files, |f| {
        let text = &f.raw().text;
        if !text.contains("EXPIRY") {
            return Vec::new();
        }
        pat!(r"\b(?:STATIC_)?EXPIRY(?:_TMP)?_DECLARE\(\s*(\w+)\s*\)").captures_iter(text).into_iter().map(|c| c.s(1).to_string()).collect()
    });
    let mut names: BTreeSet<String> = per.into_iter().flatten().collect();
    names.remove("name");
    names.remove("time"); // would match every `world.time`
    names
}

fn pass_compares(f: &SourceFile, stamp: Option<&Pat>) -> Vec<usize> {
    let mut out = Vec::new();
    let rel = f.rel.as_str();
    if skipped(rel) || !f.raw().text.contains("world.time") {
        return out;
    }
    for (number, line) in f.raw().numbered() {
        let code = before_slashes(line);
        if !code.contains("world.time") || py_lstrip(code).starts_with('#') {
            continue;
        }
        let mut hit = false;
        if compare().is_match(code) && !const_cmp().is_match(py_strip(code)) {
            // A compare cooldown_lint counts (not a recorded time) belongs to that lint.
            if not_a_cooldown(rel, code, stamp) || !rel.starts_with("code/") {
                hit = !crate::dm::sys::kept_recorded(f, number, "cooldown");
            } else if COOLDOWN_SKIP_DIRS.iter().any(|p| rel.starts_with(p)) {
                hit = true;
            }
        }
        if !hit && elapsed().is_match(code) {
            hit = true;
        }
        if hit {
            out.push(number);
        }
    }
    out
}

#[derive(Serialize, Deserialize, Default, PartialEq)]
struct Writes {
    declared: Vec<String>,
    writes: Vec<usize>,
    uses: Vec<(usize, String)>,
}

fn pass_writes(f: &SourceFile) -> Writes {
    let mut w = Writes { declared: Vec::new(), writes: Vec::new(), uses: Vec::new() };
    let skip = skipped(&f.rel);
    for (number, line) in f.raw().numbered() {
        if line.contains("EXPIRY") {
            for c in pat!(r"\b(?:STATIC_)?EXPIRY(?:_TMP)?_DECLARE\(\s*(\w+)\s*\)").captures_iter(line) {
                w.declared.push(c.s(1).to_string());
            }
        }
        if skip {
            continue;
        }
        let code = before_slashes(line);
        if py_lstrip(code).starts_with('#') {
            continue;
        }
        if code.contains("world.time")
            && pat!(r"(?<![=!<>])=(?!=)\s*\(?\s*world\.time\b(?!\s*[-*/%])").is_match(code)
            && !pat!(r"\A(?:\s*var/(?!static))").is_match(code)
        {
            w.writes.push(number);
        }
        if code.contains("EXPIRY_") || code.contains("ELAPSED(") {
            for c in pat!(r"\b(?:EXPIRY_(?:SET|EXTEND|CLEAR|ACTIVE|EXPIRED|LEFT|STAMP)|ELAPSED)\(\s*[^,()]+(?:\([^()]*\))?\s*,\s*(\w+)").captures_iter(code) {
                w.uses.push((number, c.s(1).to_string()));
            }
        }
    }
    w
}

fn pass_at_writes(f: &SourceFile) -> Vec<usize> {
    let mut out = Vec::new();
    if skipped(&f.rel) || !f.raw().text.contains("EXPIRY_AT(") {
        return out;
    }
    let mut local: BTreeSet<String> = BTreeSet::new();
    for (number, line) in f.raw().numbered() {
        if let Some(ch) = line.chars().next() {
            if !crate::util::is_py_space(ch) {
                local.clear();
                if let Some(head) = pat!(r"\A(?:/[\w/]*\(([^)]*)\))").captures(line) {
                    let params = head.s(1);
                    for c in pat!(r"\bvar/(?:[\w]+/)*(\w+)").captures_iter(params) {
                        local.insert(c.s(1).to_string());
                    }
                    for w in params.split(',') {
                        local.insert(py_strip(w.split('=').next().unwrap_or("")).to_string());
                    }
                }
                continue;
            }
        }
        let code = before_slashes(line);
        for c in pat!(r"\bvar/(?:[\w]+/)*(\w+)").captures_iter(code) {
            local.insert(c.s(1).to_string());
        }
        let Some(m) = pat!(r"\A(?:\s*((?:\w+\.)*)(\w+)\s*=\s*EXPIRY_AT\()").captures(code) else { continue };
        if py_lstrip(code).starts_with("var/") {
            continue;
        }
        let (mut owner, name) = (m.s(1), m.s(2));
        if owner.starts_with("GLOB.") {
            owner = &owner[5..];
            if owner.is_empty() {
                continue; // a GLOBAL_VAR cannot be EXPIRY_DECLAREd
            }
        }
        if !owner.is_empty() || !local.contains(name) {
            out.push(number);
        }
    }
    out
}

fn files_scan(tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let names = timestamp_names(tree);
    let stamp: OnceLock<Option<Pat>> = OnceLock::new();
    let p1: Vec<Vec<u32>> = incr::keyed("sys-expiry-compares", incr::ctx_key(&names), files, |f| {
        let stamp = stamp
            .get_or_init(|| {
                if names.is_empty() {
                    None
                } else {
                    Some(Pat::new(&format!(r"(?<![\w])(?:{})\b", names.iter().map(|s| s.as_str()).collect::<Vec<_>>().join("|"))))
                }
            })
            .as_ref();
        pass_compares(f, stamp).into_iter().map(|l| l as u32).collect()
    });
    let p2: Vec<Writes> = incr::facts("sys-expiry-writes", files, pass_writes);
    let p3: Vec<Vec<u32>> = incr::facts("sys-expiry-at", files, |f| pass_at_writes(f).into_iter().map(|l| l as u32).collect());
    let mut out: Vec<(&'static str, String, usize)> = Vec::new();
    for (f, lines) in files.iter().zip(&p1) {
        for &l in lines {
            out.push(("world_time_expiry", f.rel.clone(), l as usize));
        }
    }
    let mut declared: BTreeSet<&str> = BTreeSet::new();
    for w in &p2 {
        for d in &w.declared {
            declared.insert(d.as_str());
        }
    }
    for (f, w) in files.iter().zip(&p2) {
        for &l in &w.writes {
            out.push(("world_time_write", f.rel.clone(), l));
        }
    }
    for (f, w) in files.iter().zip(&p2) {
        for (l, name) in &w.uses {
            if !declared.contains(name.as_str()) {
                out.push(("expiry_undeclared", f.rel.clone(), *l));
            }
        }
    }
    for (f, lines) in files.iter().zip(&p3) {
        for &l in lines {
            out.push(("world_time_write", f.rel.clone(), l as usize));
        }
    }
    out
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: "expiry", rules: RULES, files_scan: Some(files_scan), ..SysModule::DEFAULT });
}
