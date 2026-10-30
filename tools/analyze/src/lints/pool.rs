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

use crate::incr;
use crate::lint::{Cx, Lint, Meta, Registry, Sink};
use crate::parity::{Parity, ParseKind};
use crate::scopes::LintScope;
use crate::tree::SourceFile;

use crate::pool_policy::{Facts, META, RULE_NAMES};
struct Pool;
fn facts_of(f: &SourceFile) -> Facts {
    crate::pool_policy::facts_of(f, None, || Ok(()))
        .expect("legacy pool facts have no captured ceiling")
}
fn judge(
    f: &SourceFile,
    pooled: &BTreeSet<String>,
    exempt_prefixes: &[String],
) -> Vec<(u8, u32, String)> {
    let mut out = Vec::new();
    crate::pool_policy::judge(
        f,
        pooled,
        exempt_prefixes,
        None,
        || Ok(()),
        |r, l, m| {
            out.push((r, l, m.to_string()));
            Ok(())
        },
    )
    .expect("legacy pool judge has no captured ceiling");
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
    let results = incr::keyed("pool-judge", key, files, |f| {
        judge(f, &pooled, exempt_prefixes)
    });
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
        scope.lists.insert(
            "exempt_prefixes".into(),
            vec![
                "code/modules/unit_tests/".into(),
                "code/tests/unit_tests/".into(),
                "code/datums/lifecycle/pool.dm".into(),
            ],
        );
        let run = |files: Vec<(&str, &str)>| -> usize {
            let fs: Vec<SourceFile> = files
                .iter()
                .map(|(r, t)| SourceFile::from_text(r, t))
                .collect();
            let refs: Vec<&SourceFile> = fs.iter().collect();
            let mut out = Sink::new();
            check(&refs, scope.list("exempt_prefixes"), &mut out);
            out.sites.len()
        };
        let good = "/datum/foo\n\tparent_type = /datum/pooled\n\n/proc/f()\n\tvar/datum/foo/F = take(/datum/foo)\n\tF.release()\n";
        let factory = "/datum/foo\n\tparent_type = /datum/pooled\n\n/proc/factory()\n\tvar/datum/foo/packet = take(/datum/foo)\n\tpacket.zone = 1\n\treturn packet\n";
        let reassigned = factory.replace("\tpacket.zone = 1", "\tpacket = null");
        let conditional = factory.replace("\treturn packet", "\tif(ok)\n\t\treturn packet");
        let multiple = factory.replace(
            "\tpacket.zone = 1",
            "\tvar/datum/foo/other = take(/datum/foo)",
        );
        if run(vec![("factory.dm", factory)]) != 0
            || run(vec![("reassigned.dm", &reassigned)]) == 0
            || run(vec![("conditional.dm", &conditional)]) == 0
            || run(vec![("multiple.dm", &multiple)]) == 0
        {
            return Err("factory return contract misclassified".into());
        }
        let bad_new = "/proc/g()\n\tvar/datum/foo/F = new /datum/foo\n";
        let bad_leak = [
            ("a.dm", "/datum/foo\n\tparent_type = /datum/pooled\n"),
            ("c.dm", "/proc/h()\n\treturn take(/datum/foo)\n"),
        ];
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
