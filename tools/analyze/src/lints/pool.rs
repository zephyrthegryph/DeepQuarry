//! Port of `tools/ci/pool_lint.py`: pool take/release (code/datums/lifecycle/pool.dm).
//!
//! A pooled type (a subtype of `/datum/pooled`, or declared with `POOL_DECLARE`) is taken with
//! `take(type)` and given back with `.release()`, never built with `new`. Fails when `new` builds a
//! pooled type outside the exempt files, or a file calls `take()` / `pool_take()` but never
//! releases anything. A straight-line factory may instead return its acquired local to the caller.
//!
//! Quirks kept: a line containing the literal text `ALLOW(pool)` is skipped wholesale (even inside a
//! comment, and it is not an `allowed()` call: no comment-line-above form, and it also hides a
//! `.release()` on that line); `current` (the enclosing type for `parent_type`) persists past any
//! non-type line; `POOL_DECLARE` is searched on the raw line, comments included.

use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};

use crate::incr;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat;
use crate::scopes::LintScope;
use crate::tree::{SourceFile, CODE_DM};
use crate::util::{before_slashes, starts_with_any};

static META: Meta = Meta {
    name: "pool",
    group: "",
    label: "pool",
    legacy: "tools/ci/pool_lint.py",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "new_pooled", hint: "take it with take(type) and give it back with .release()" },
        RuleMeta { name: "take_leak", hint: "release what the file takes (a leak by construction)" },
    ],
    allow: &[], // the Python never lists `pool` in allow_annotations.LINTS, so ALLOW(pool) stays unknown
    lists: &["exempt_prefixes"],
};

struct Pool;

fn strip(line: &str) -> String {
    pat!(r#""[^"]*""#).replace_all(before_slashes(line), "\"\"")
}

const NEW_POOLED: u8 = 0;
const TAKE_LEAK: u8 = 1;
const RULE_NAMES: [&str; 2] = ["new_pooled", "take_leak"];

/// One file's contribution to the pooled-type index: the types it declares pooled (sorted, unique).
#[derive(Serialize, Deserialize, Default, PartialEq)]
struct Facts {
    pooled: Vec<String>,
}

fn facts_of(f: &SourceFile) -> Facts {
    let mut pooled: BTreeSet<String> = BTreeSet::new();
    let mut current: Option<String> = None;
    for line in f.raw().lines() {
        if let Some(m) = pat!(r"^(/datum/[A-Za-z0-9_/]+)\s*$").captures(line) {
            current = Some(m.s(1).to_string());
        }
        if let Some(m) = pat!(r"^\s+parent_type\s*=\s*(/datum/pooled\b[A-Za-z0-9_/]*|/datum/[A-Za-z0-9_/]+)").captures(line) {
            if let Some(cur) = &current {
                if m.s(1).starts_with("/datum/pooled") {
                    pooled.insert(cur.clone());
                }
            }
        }
        for d in pat!(r"POOL_DECLARE\((/datum/[A-Za-z0-9_/]+)\)").captures_iter(line) {
            pooled.insert(d.s(1).to_string());
        }
    }
    Facts { pooled: pooled.into_iter().collect() }
}

/// A factory transfers the acquired object only when an unconditionally assigned local is
/// returned unchanged at the same top-level indentation, within the same proc. Conditional
/// returns, reassignment and other earlier returns do not establish this contract.
fn returned_acquisition(lines: &[&str], at: usize) -> bool {
    let declaration = strip(lines[at]);
    let Some(local) = pat!(r"^\tvar/(?:[A-Za-z0-9_]+/)+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:pool_take|take)\(/datum/[A-Za-z0-9_/]+\)\s*$").captures(&declaration) else {
        return false;
    };
    let name = local.s(1);
    for raw in &lines[at + 1..] {
        let line = strip(raw);
        if !line.trim().is_empty() && !line.starts_with('\t') && !line.starts_with(' ') {
            break;
        }
        let trimmed = line.trim();
        if trimmed.starts_with("return") {
            return line == format!("\treturn {}", name);
        }
        // Writes to members initialize the packet; writes to the local change its identity.
        if let Some(write) = pat!(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?:=|\+=|-=|\*=|/=)").captures(&line) {
            if write.s(1) == name {
                return false;
            }
        }
    }
    false
}

/// The sites of one file given the pooled-type index: `(rule, line, message)` in emission order.
fn judge(f: &SourceFile, pooled: &BTreeSet<String>, exempt_prefixes: &[String]) -> Vec<(u8, u32, String)> {
    let mut out: Vec<(u8, u32, String)> = Vec::new();
    let exempt = starts_with_any(&f.rel, exempt_prefixes);
    let mut takes: Vec<(usize, String)> = Vec::new();
    let mut releases = false;
    let lines: Vec<&str> = f.raw().lines().collect();
    for (number, raw) in f.raw().numbered() {
        if raw.contains("ALLOW(pool)") {
            continue;
        }
        let line = strip(raw);
        if pat!(r"\.release\(\)|\bpool_release\(|\brelease\(\)").is_match(&line) {
            releases = true;
        }
        for t in pat!(r"\b(?:pool_take|take)\((/datum/[A-Za-z0-9_/]+)").captures_iter(&line) {
            if !returned_acquisition(&lines, number - 1) {
                takes.push((number, t.s(1).to_string()));
            }
        }
        if exempt {
            continue;
        }
        for t in pat!(r"\bnew\s+(/datum/[A-Za-z0-9_/]+)").captures_iter(&line) {
            let t = t.s(1);
            if pooled.iter().any(|p| t == p || (t.starts_with(p.as_str()) && t.as_bytes().get(p.len()) == Some(&b'/'))) {
                out.push((NEW_POOLED, number as u32, format!("new {}: a pooled type is taken with take(), not built", t)));
            }
        }
    }
    if !takes.is_empty() && !releases && !exempt {
        let (number, t) = &takes[0];
        out.push((TAKE_LEAK, *number as u32, format!("take({}) but the file never releases: give it back with .release()", t)));
    }
    out
}

/// Uncached whole-tree check (the selftest's entry).
fn check(files: &[&SourceFile], exempt_prefixes: &[String], out: &mut Sink) {
    let mut pooled: BTreeSet<String> = BTreeSet::new();
    for f in files {
        pooled.extend(facts_of(f).pooled);
    }
    for f in files {
        for (rule, line, msg) in judge(f, &pooled, exempt_prefixes) {
            out.site_in_msg(RULE_NAMES[rule as usize], &f.rel, line as usize, msg);
        }
    }
}

/// The same check through the per-file caches: facts by content, judgements by (content, index).
fn check_incr(files: &[&SourceFile], exempt_prefixes: &[String], out: &mut Sink) {
    let facts = incr::facts("pool-facts", files, facts_of);
    let mut pooled: BTreeSet<String> = BTreeSet::new();
    for fa in &facts {
        pooled.extend(fa.pooled.iter().cloned());
    }
    let key = incr::ctx_key(&(&pooled, exempt_prefixes));
    let results = incr::keyed("pool-judge", key, files, |f| judge(f, &pooled, exempt_prefixes));
    for (f, res) in files.iter().zip(results) {
        for (rule, line, msg) in res {
            out.site_in_msg(RULE_NAMES[rule as usize], &f.rel, line as usize, msg);
        }
    }
}

impl Lint for Pool {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let files = cx.files();
        check_incr(&files, cx.list("exempt_prefixes"), out);
        let n = out.sites.len();
        out.note(format!("pool_lint: {} problem(s)", n));
    }

    fn selftest(&self) -> Result<String, String> {
        let mut scope = LintScope::default();
        scope.lists.insert("exempt_prefixes".into(), vec!["code/modules/unit_tests/".into(), "code/datums/lifecycle/pool.dm".into()]);
        let run = |files: Vec<(&str, &str)>| -> usize {
            let fs: Vec<SourceFile> = files.iter().map(|(r, t)| SourceFile::from_text(r, t)).collect();
            let refs: Vec<&SourceFile> = fs.iter().collect();
            let mut out = Sink::new();
            check(&refs, scope.list("exempt_prefixes"), &mut out);
            out.sites.len()
        };
        let good = "/datum/foo\n\tparent_type = /datum/pooled\n\n/proc/f()\n\tvar/datum/foo/F = take(/datum/foo)\n\tF.release()\n";
        let factory = "/datum/foo\n\tparent_type = /datum/pooled\n\n/proc/factory()\n\tvar/datum/foo/packet = take(/datum/foo)\n\tpacket.zone = 1\n\treturn packet\n";
        let reassigned = factory.replace("\tpacket.zone = 1", "\tpacket = null");
        let conditional = factory.replace("\treturn packet", "\tif(ok)\n\t\treturn packet");
        let multiple = factory.replace("\tpacket.zone = 1", "\tvar/datum/foo/other = take(/datum/foo)");
        if run(vec![("factory.dm", factory)]) != 0
            || run(vec![("reassigned.dm", &reassigned)]) == 0
            || run(vec![("conditional.dm", &conditional)]) == 0
            || run(vec![("multiple.dm", &multiple)]) == 0
        {
            return Err("factory return contract misclassified".into());
        }
        let bad_new = "/proc/g()\n\tvar/datum/foo/F = new /datum/foo\n";
        let bad_leak = [("a.dm", "/datum/foo\n\tparent_type = /datum/pooled\n"), ("c.dm", "/proc/h()\n\treturn take(/datum/foo)\n")];
        if run(vec![("a.dm", good)]) != 0 {
            return Err("clean input flagged".into());
        }
        if run(vec![("a.dm", good), ("b.dm", bad_new)]) == 0 || run(bad_leak.to_vec()) == 0 {
            return Err("a violation went unflagged".into());
        }
        Ok(String::new())
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/pool_lint.py"],
            old_raw: &[&["tools/ci/pool_lint.py"]],
            blank: &[],
            parse: ParseKind::FileLine,
            update: None,
            seed: None,
            files: &[],
            selftest: Some(&["tools/ci/pool_lint.py", "--selftest"]),
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Pool);
}
