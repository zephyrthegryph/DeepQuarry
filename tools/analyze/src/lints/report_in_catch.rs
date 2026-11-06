//! `report_in_catch`: `stack_trace()` or `CRASH()` inside a catch block.
//!
//! Both raise a new exception. Under any outer try (a delivery, safe_call(), a test) it leaves the catch at once: the rest of the catch, the loop around it and
//! any state restored after it are skipped, and the original fault is replaced. Report with `dq_report_caught(e, "context")`, which never throws, or re-raise
//! on purpose with `throw`. Test code is exempt: it reads faults directly. The block is found by indentation, as DM defines it.

use crate::{
    key_policy_control::Compatibility,
    lint::{Cx, Lint, Meta, Registry, Sink},
    report_in_catch_policy::{self as policy, Patterns, META},
};

struct ReportInCatch(Patterns);

impl Lint for ReportInCatch {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        for file in cx.files() {
            if policy::excluded(&file.rel) {
                continue;
            }
            self.0.scan(file.code(), &mut Compatibility, |line| {
                out.site_in_msg(policy::RULE, &file.rel, line, policy::MESSAGE);
                Ok(())
            }).unwrap();
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(ReportInCatch(Patterns::new()));
}
