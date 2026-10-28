//! Port of `tools/ci/sys_rules/expiry.py` (doc/rewrite/systems.md section 17): hand-rolled expiry and
//! elapsed state read against `world.time`. The old expiry macros are retired: an end time is a COOLDOWN var
//! (`COOLDOWN_DECLARE`), a start time a STAMP var.
//!
//! `world_time_expiry` counts a `world.time` compare that `cooldown_lint.py` does NOT count as a
//! cooldown, plus elapsed compares; `world_time_write` a stored time written as `x = world.time`
//! (or through `TIME_NOW` on a member); `expiry_undeclared` a var read or written by a `COOLDOWN_*`
//! macro that has no `COOLDOWN_DECLARE`.
//!
//! The Python imports `cooldown_lint` (its COMPARE/CONST_CMP/TIME_NAME patterns and
//! `timestamp_names()`); the parts expiry uses are inlined here. Not a cooldown lint port.
//!
//! The Python module redefines `scan` three times (compares, then writes, then `TIME_NOW` writes);
//! sites are emitted in the same pass order (all compares, then writes, then undeclared, then
//! `TIME_NOW` writes), which only matters for the order inside `world_time_write`.
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
use crate::tree::{SourceFile, Tree};
use crate::util::{before_slashes, py_lstrip, py_strip};

const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "world_time_expiry",
        hint: "COOLDOWN_DECLARE/COOLDOWN_START/COOLDOWN_RUNNING/COOLDOWN_TIMELEFT for an end time, STAMP/ELAPSED for a start (code/__defines/cooldowns.dm, code/__defines/sys_expiry.dm)",
    },
    RuleMeta {
        name: "world_time_write",
        hint: "a stored time is written with COOLDOWN_START/COOLDOWN_EXTEND/STAMP (or TIME_NOW for list slots/records), never `x = world.time (+ N)`",
    },
    RuleMeta {
        name: "expiry_undeclared",
        hint: "a var read/written by COOLDOWN_EXTEND/RUNNING/LAPSED or an _OWN cooldown macro is declared with COOLDOWN_DECLARE (a base type uses a cooldowns() name and cooldown_*)",
    },
];

const SKIP: &[&str] = &["code/datums/om/", "code/controllers/master.dm", "code/controllers/failsafe.dm"];
/// `cooldown_lint.SKIP_DIRS`.
const COOLDOWN_SKIP_DIRS: &[&str] = &["code/modules/unit_tests/", "code/tests/unit_tests/", "code/controllers/", "code/datums/om/"];

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
    (rel.starts_with("code/modules/reagents/") || rel.starts_with("code/content/reagents/")) && pat!(r"(?<![\w.])data\b").is_match(line)
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
        if line.contains("COOLDOWN_") {
            for c in pat!(r"\b(?:STATIC_)?COOLDOWN_(?:TMP_)?DECLARE\(\s*(\w+)\s*\)").captures_iter(line) {
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
        if code.contains("COOLDOWN_") {
            for c in pat!(r"\b(?:COOLDOWN_(?:EXTEND|RUNNING|LAPSED)(?:_OWN)?|COOLDOWN_(?:START|FINISHED|TIMELEFT)_OWN)\(\s*[^,()]+(?:\([^()]*\))?\s*,\s*(\w+)").captures_iter(code) {
                w.uses.push((number, c.s(1).to_string()));
            }
        }
    }
    w
}

fn pass_at_writes(f: &SourceFile) -> Vec<usize> {
    let mut out = Vec::new();
    if skipped(&f.rel) || !f.raw().text.contains("TIME_NOW(") {
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
        let Some(m) = pat!(r"\A(?:\s*((?:\w+\.)*)(\w+)\s*=\s*TIME_NOW\()").captures(code) else { continue };
        if py_lstrip(code).starts_with("var/") {
            continue;
        }
        let (mut owner, name) = (m.s(1), m.s(2));
        if owner.starts_with("GLOB.") {
            owner = &owner[5..];
            if owner.is_empty() {
                continue; // a GLOBAL_VAR cannot be COOLDOWN_DECLAREd
            }
        }
        if !owner.is_empty() || !local.contains(name) {
            out.push(number);
        }
    }
    out
}

fn files_scan(_tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    // The declared-name index is gone with the old declaration macro: a raw compare against a cooldown var is the cooldown lint's.
    let names: BTreeSet<String> = BTreeSet::new();
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
