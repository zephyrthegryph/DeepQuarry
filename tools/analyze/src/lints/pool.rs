//! Port of `tools/ci/pool_lint.py`: pool take/release (code/datums/lifecycle/pool.dm).
//!
//! A pooled type (a subtype of `/datum/pooled`, or declared with `POOL_DECLARE`) is taken with
//! `take(type)` and given back with `.release()`, never built with `new`. Fails when `new` builds a
//! pooled type outside the exempt files, or a file calls `take()` / `pool_take()` but never
//! releases anything.
//!
//! Quirks kept: a line containing the literal text `ALLOW(pool)` is skipped wholesale (even inside a
//! comment, and it is not an `allowed()` call: no comment-line-above form, and it also hides a
//! `.release()` on that line); `current` (the enclosing type for `parent_type`) persists past any
//! non-type line; `POOL_DECLARE` is searched on the raw line, comments included.

use std::collections::HashSet;

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
    allow: &["pool"],
    lists: &["exempt_prefixes"],
};

struct Pool;

fn strip(line: &str) -> String {
    pat!(r#""[^"]*""#).replace_all(before_slashes(line), "\"\"")
}

fn check(files: &[&SourceFile], exempt_prefixes: &[String], out: &mut Sink) {
    let mut pooled: HashSet<String> = HashSet::new();
    for f in files {
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
    }
    for f in files {
        let exempt = starts_with_any(&f.rel, exempt_prefixes);
        let mut takes: Vec<(usize, String)> = Vec::new();
        let mut releases = false;
        for (number, raw) in f.raw().numbered() {
            if raw.contains("ALLOW(pool)") {
                continue;
            }
            let line = strip(raw);
            if pat!(r"\.release\(\)|\bpool_release\(|\brelease\(\)").is_match(&line) {
                releases = true;
            }
            for t in pat!(r"\b(?:pool_take|take)\((/datum/[A-Za-z0-9_/]+)").captures_iter(&line) {
                takes.push((number, t.s(1).to_string()));
            }
            if exempt {
                continue;
            }
            for t in pat!(r"\bnew\s+(/datum/[A-Za-z0-9_/]+)").captures_iter(&line) {
                let t = t.s(1);
                if pooled.iter().any(|p| t == p || (t.starts_with(p.as_str()) && t.as_bytes().get(p.len()) == Some(&b'/'))) {
                    out.site_in_msg("new_pooled", &f.rel, number, format!("new {}: a pooled type is taken with take(), not built", t));
                }
            }
        }
        if !takes.is_empty() && !releases && !exempt {
            let (number, t) = &takes[0];
            out.site_in_msg(
                "take_leak",
                &f.rel,
                *number,
                format!("take({}) but the file never releases: give it back with .release()", t),
            );
        }
    }
}

impl Lint for Pool {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let files = cx.files();
        check(&files, cx.list("exempt_prefixes"), out);
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
