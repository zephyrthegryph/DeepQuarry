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

use std::borrow::Cow;
use std::collections::HashSet;

use serde::{Deserialize, Serialize};

use crate::incr;

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat;
use crate::pat_match;
use crate::tree::{SourceFile, CODE_MAPS_DM};
use crate::util::{is_py_space, py_lstrip, starts_with_any};

static META: Meta = Meta {
    name: "pollers",
    group: "",
    label: "pollers",
    legacy: "tools/ci/pollers_lint.py",
    select: CODE_MAPS_DM,
    scan: ScanKind::Both,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "process", hint: "put the work on a pipeline (code/datums/om/periodic.dm)" },
        RuleMeta { name: "start", hint: "use om_task_periodic() or a machine wake" },
        RuleMeta { name: "step_coverage", hint: "" },
    ],
    allow: &["pollers"],
    lists: &["step_exempt_prefixes"],
};

#[derive(Serialize, Deserialize, Default, PartialEq)]
struct Steps {
    steps: Vec<(u32, String)>,
}

struct Pollers;

/// `strip_comment`: drops a trailing `//` comment outside double quotes (a `"` after a backslash
/// does not toggle).
fn strip_comment(line: &str) -> Cow<'_, str> {
    if !line.contains("//") {
        return Cow::Borrowed(line); // nothing to cut: the loop below would copy the line
    }
    let chars: Vec<char> = line.chars().collect();
    let mut out = String::new();
    let mut in_str = false;
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '"' && (i == 0 || chars[i - 1] != '\\') {
            in_str = !in_str;
        }
        if !in_str && c == '/' && chars.get(i + 1) == Some(&'/') {
            break;
        }
        out.push(c);
        i += 1;
    }
    Cow::Owned(out)
}

impl Lint for Pollers {
    fn meta(&self) -> &Meta {
        &META
    }

    /// `count_file`: process() definitions and START_*PROCESSING calls not kept by ALLOW(pollers).
    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        let mut in_type = false;
        let mut in_block_comment = false;
        for (number, raw) in f.raw().numbered() {
            let line = raw.trim_end_matches('\r');
            if in_block_comment {
                if line.contains("*/") {
                    in_block_comment = false;
                }
                continue;
            }
            if py_lstrip(line).starts_with("/*") && !line.contains("*/") {
                in_block_comment = true;
                continue;
            }
            let code = strip_comment(line);
            let is_process = pat_match!(r"^/[\w/]+?/(?:proc/)?process\(").is_match(&code) || (in_type && pat_match!(r"^\t(?:proc/)?process\(").is_match(&code));
            let is_start = !pat_match!(r"^\s*#\s*define\b").is_match(&code) && pat!(r"(?<![\w])START_(?:MACHINE_)?PROCESSING\(").is_match(&code);
            // Asked only about a line that would otherwise count.
            let kept = (is_process || is_start) && out.allowed(f, number, "pollers");
            if is_process && !kept {
                out.site_msg("process", number, "process() definition");
            }
            if pat_match!(r"^/[\w/]+\s*(?://.*)?$").is_match(&code) {
                in_type = true;
            } else if code.chars().next().map(|c| !is_py_space(c)).unwrap_or(false) {
                in_type = false;
            }
            if is_start && !kept {
                out.site_msg("start", number, "START_*PROCESSING call");
            }
        }
    }

    /// `check_step_coverage`: no machine defines `machine_step()` (the machine pipeline was deleted; its work is
    /// `started_work()`). The heads of a file are cached by content.
    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let all = cx.all_files();
        let heads = incr::facts("pollers-steps", &all, |f| {
            let mut steps = Vec::new();
            if f.text().contains("machine_step(") {
                for (n, line) in f.raw().numbered() {
                    if let Some(m) = pat_match!(r"^(/obj/machinery[\w/]*?)/machine_step\(").captures(line) {
                        steps.push((n as u32, m.s(1).to_string()));
                    }
                }
            }
            Steps { steps }
        });
        for (f, fa) in all.iter().zip(&heads) {
            // Test probes join lazily through MACHINE_WAKE().
            if fa.steps.is_empty() || starts_with_any(&f.rel, cx.list("step_exempt_prefixes")) {
                continue;
            }
            for (n, t) in &fa.steps {
                out.site_in_msg("step_coverage", &f.rel, *n as usize, format!("{} defines machine_step(): machine work is started_work()", t));
            }
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

    fn scan(text: &str) -> Sink {
        let tree = Tree::from_files(vec![]);
        let scope = LintScope::default();
        let cx = Cx { tree: &tree, meta: &META, scope: &scope };
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
