//! Port of `tools/ci/pollers_lint.py`: the polling ratchet (roadmap S3-S5,
//! doc/rewrite/migration_plan.md track 1d).
//!
//! Periodic work runs on object-model pipelines, stages, watches and parking, not on the old polling
//! constructs this counts, each failing unless kept by `// ALLOW(pollers): <reason>`:
//!   * `process`: a `process()` proc definition (`/type/process(` at column 0, or an indented
//!     `process(` / `proc/process(` under a type block);
//!   * `start`: a `START_PROCESSING(` / `START_MACHINE_PROCESSING(` call.
//! Core files (the MC, the OM core, the defines, the external-I/O datums) are exempt by
//! `lint_scopes.toml`. It also checks (`step_coverage`, a whole-tree scan) that no machine defines
//! `machine_step()`: the machine pipeline is gone, a machine's work is `started_work()`.
//!
//! Quirks kept: no `exempt_path()` here (benchmarks and the TGS DMAPI are counted); the scan reads
//! the raw text with its own `//` stripper (strings are not stripped, only a `//` outside quotes, with
//! `\"` not toggling) and its own `/*` block tracking (a block comment line is skipped outright, type
//! state included); `in_type` survives every indented or blank line; the ALLOW question is asked once
//! per line that would count, and the one answer covers both a process and a start on that line;
//! the step-coverage check reads every file, exempt ones included, except the unit-test probes.


use serde::{Deserialize, Serialize};

use crate::incr;

use crate::lint::{Cx,Lint,Meta,Registry,Sink};
use crate::parity::{ParseKind, Parity};
use crate::tree::SourceFile;
use crate::util::starts_with_any;

use crate::raw_tree_pollers_policy as policy;
use policy::META;

#[derive(Serialize, Deserialize, Default, PartialEq)]
struct Steps {
    steps: Vec<(u32, String)>,
}

struct Pollers;

impl Lint for Pollers {
    fn meta(&self) -> &Meta {
        &META
    }

    /// `count_file`: process() definitions and START_*PROCESSING calls not kept by ALLOW(pollers).
    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        policy::scan_file(f,out);
    }

    /// `check_step_coverage`: no machine defines `machine_step()` (the machine pipeline was deleted; its work is
    /// `started_work()`). The heads of a file are cached by content.
    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let all = cx.all_files();
        let heads=incr::facts("pollers-steps",&all,|f|Steps{steps:policy::steps(f)});
        for (f, fa) in all.iter().zip(&heads) {
            // Test probes join lazily through MACHINE_WAKE().
            if fa.steps.is_empty() || starts_with_any(&f.rel, cx.list("step_exempt_prefixes")) {
                continue;
            }
            policy::report_steps(&f.rel,&fa.steps,out);
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/pollers_lint.py"],
            old_raw: &[],
            blank: &[],
            // `file:line: message`, and some paths hold spaces.
            parse: ParseKind::FileLineAny,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Pollers);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scopes::LintScope;
    use crate::tree::Tree;

    fn scan(text: &str) -> Sink<'static> {
        let tree = Tree::from_files(vec![]);
        let scope = LintScope::default();
        let cx = Cx { fixture:None, tree: &tree, meta: &META, scope: &scope };
        let f = SourceFile::from_text("code/modules/x.dm", text);
        let mut out = Sink::new();
        out.cur = f.rel.clone();
        Pollers.scan_file(&cx, &f, &mut out);
        out
    }

    #[test]
    fn allow_is_asked_only_for_a_line_that_would_count() {
        let out = scan("/obj/a\n\tprocess() // ALLOW(pollers): the legacy pump has no pipeline yet\n\tvar/x = 1 // ALLOW(pollers): nothing here polls\n");
        assert!(out.sites.is_empty(), "{:?}", out.sites);
        assert_eq!(out.allow_used.len(), 1);
        assert_eq!(out.allow_used[0].line, 2);
    }

    #[test]
    fn one_answer_covers_process_and_start_on_a_line() {
        let out = scan("/obj/a\n\tprocess() START_PROCESSING(SSobj, src)\n");
        let rules: Vec<&str> = out.sites.iter().map(|s| s.rule.as_str()).collect();
        assert_eq!(rules, vec!["process", "start"]);
    }
}
