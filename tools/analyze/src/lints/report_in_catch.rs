//! `report_in_catch`: `stack_trace()` or `CRASH()` inside a catch block.
//!
//! Both raise a new exception. Under any outer try (a delivery, safe_call(), a test) it leaves the catch at once: the rest of the catch, the loop around it and
//! any state restored after it are skipped, and the original fault is replaced. Report with `dq_report_caught(e, "context")`, which never throws, or re-raise
//! on purpose with `throw`. Test code is exempt: it reads faults directly. The block is found by indentation, as DM defines it.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::pat::Pat;
use crate::tree::CODE_DM;

const HINT: &str = "stack_trace()/CRASH() throw again from inside a catch and skip what follows it under any outer try: use dq_report_caught(e, \"context\"), or throw to re-raise";

static META: Meta = Meta {
    name: "report_in_catch",
    group: "",
    label: "report_in_catch",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "throwing_report", hint: HINT }],
    allow: &[],
    lists: &[],
};

struct ReportInCatch {
    catch_head: Pat,
    throwing: Pat,
}

fn indent(text: &str) -> usize {
    text.len() - text.trim_start_matches('\t').len()
}

impl Lint for ReportInCatch {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        for f in cx.files() {
            if f.rel.starts_with("code/tests/") || f.rel.contains("/_generated/") {
                continue;
            }
            let lines: Vec<(usize, &str)> = f.code().numbered().collect();
            let mut reported: Vec<usize> = Vec::new();
            for (i, &(_, head)) in lines.iter().enumerate() {
                if !self.catch_head.is_match(head) {
                    continue;
                }
                let block = indent(head);
                for &(n, text) in &lines[i + 1..] {
                    if text.trim().is_empty() {
                        continue;
                    }
                    if indent(text) <= block {
                        break;
                    }
                    if self.throwing.is_match(text) && !reported.contains(&n) {
                        reported.push(n);
                        out.site_in_msg("throwing_report", &f.rel, n, "stack_trace()/CRASH() inside a catch block".to_string());
                    }
                }
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(ReportInCatch { catch_head: Pat::new(r"^\s*catch\b"), throwing: Pat::new(r"\b(?:stack_trace|CRASH)\(") });
}
