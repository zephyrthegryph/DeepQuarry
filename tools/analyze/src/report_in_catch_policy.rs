//! Original authored CODE-view catch range scanner shared by both report facades.
use crate::{
    key_policy_control::Control,
    lint::{Meta, Policy, RuleMeta, ScanKind},
    pat::Pat,
    tree::{View, CODE_DM},
};

const HINT: &str = "stack_trace()/CRASH() throw again from inside a catch and skip what follows it under any outer try: use dq_report_caught(e, \"context\"), or throw to re-raise";

pub(crate) static META: Meta = Meta {
    name: crate::allow_registry_fields::report_in_catch::SCOPE_META_0.name,
    group: crate::allow_registry_fields::report_in_catch::SCOPE_META_0.group,
    label: "report_in_catch",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: RULE, hint: HINT }],
    allow: crate::allow_registry_fields::report_in_catch::ALLOW_0,
    lists: crate::allow_registry_fields::report_in_catch::SCOPE_META_0.lists,
};

pub(crate) const RULE: &str = "throwing_report";
pub(crate) const MESSAGE: &str = "stack_trace()/CRASH() inside a catch block";

pub(crate) fn excluded(relative: &str) -> bool {
    relative.starts_with("code/tests/") || relative.contains("/_generated/")
}

pub(crate) struct Patterns {
    catch_head: Pat,
    throwing: Pat,
}

impl Patterns {
    pub(crate) fn new() -> Self {
        Self {
            catch_head: Pat::new(r"^\s*catch\b"),
            throwing: Pat::new(r"\b(?:stack_trace|CRASH)\("),
        }
    }

    pub(crate) fn scan<C: Control>(
        &self,
        code: &View,
        control: &mut C,
        mut emit: impl FnMut(usize) -> Result<(), C::Error>,
    ) -> Result<(), C::Error> {
        let mut active = None;
        for (number, text) in code.numbered() {
            control.checkpoint()?;
            if text.trim().is_empty() {
                continue;
            }
            let indent = text.len() - text.trim_start_matches('\t').len();
            if active.is_some_and(|block| indent > block) {
                // A nested catch range ends no later than its outer range, so
                // the outer scan already covers every possible nested finding.
                if self.throwing.is_match(text) {
                    emit(number)?;
                }
                continue;
            }
            active = self.catch_head.is_match(text).then_some(indent);
        }
        control.checkpoint()
    }
}
