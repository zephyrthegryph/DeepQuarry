//! Full requirement_bool policy over explicit captured raw/native inputs.
//! Reuses original union/classifier. It is not workspace inventory, baseline
//! judgement, or proof that every primary grammar form is supported.
use crate::{
    captured_raw_policy::{CapturedRawPolicy, Configuration, RawRun, MAX_FIXTURE_SITES},
    lint::{Cx, Run, Sink},
};
use dm_analysis::policy_inputs::PolicyInputs;
use std::{
    panic::{catch_unwind, AssertUnwindSafe},
    path::Path,
};
pub struct CapturedRequirementBool<'a> {
    raw: CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
impl<'a> CapturedRequirementBool<'a> {
    pub fn capture(
        root: &Path,
        inputs: &'a PolicyInputs,
        config: Configuration<'_>,
    ) -> Result<Self, String> {
        Ok(Self {
            raw: CapturedRawPolicy::capture(root, inputs, config)?,
            inputs,
        })
    }
    pub fn scan(&self, checkpoint: impl FnMut() -> Result<(), String>) -> Result<RawRun, String> {
        BorrowedRequirementBool::capture(&self.raw, self.inputs)?.scan(checkpoint)
    }
}
pub struct BorrowedRequirementBool<'a> {
    raw: &'a CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
impl<'a> BorrowedRequirementBool<'a> {
    pub fn capture(raw: &'a CapturedRawPolicy, inputs: &'a PolicyInputs) -> Result<Self, String> {
        // Shared roster/current-AnalyzeRaw-owner validation only; no base-var
        // policy runs and no fabricated semantic context is constructed.
        crate::captured_base_var_hot_policy::NativeBaseVarFacts::capture(raw, inputs)?;
        Ok(Self { raw, inputs })
    }
    pub fn scan(&self, checkpoint: impl FnMut() -> Result<(), String>) -> Result<RawRun, String> {
        self.scan_with::<dm_analysis::policy_body_demand::Compatibility>(checkpoint)
            .map_err(|e| e.0)
    }
    pub fn scan_checked(
        &self,
        checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<RawRun, dm_analysis::policy_body_demand::PolicyFailure> {
        self.scan_with::<dm_analysis::policy_body_demand::Checked>(checkpoint)
    }
    fn scan_with<D: dm_analysis::policy_body_demand::Demand>(
        &self,
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<RawRun, D::Error> {
        checkpoint()?;
        let typed = dm_analysis::analyze_call_sites::named_with::<D>(
            self.inputs,
            &self.raw.tree.root,
            &["req_bool"],
            &mut checkpoint,
        )?;
        let meta = crate::lints::requirement_bool::captured_metadata();
        let scope = self.raw.scopes.for_lint(meta.name, meta.group);
        let cx = Cx {
            tree: &self.raw.tree,
            meta,
            scope: &scope,
        };
        let mut sink = Sink::new();
        let previous = crate::dm::sys::take_recorded();
        let result = catch_unwind(AssertUnwindSafe(|| {
            crate::lints::requirement_bool::scan_captured(&cx, &mut sink, typed)
        }));
        let _ = crate::dm::sys::take_recorded();
        crate::dm::sys::restore_recorded(previous);
        if result.is_err() {
            return Err("requirement_bool policy panicked; findings discarded".into());
        }
        if let Some(error) = self.raw.tree.captured_violation() {
            return Err(error.into());
        }
        checkpoint()?;
        if sink.sites.len() > MAX_FIXTURE_SITES {
            return Err("requirement_bool exceeds fixture finding admission".into());
        }
        Ok(RawRun {
            name: meta.name.into(),
            run: Run {
                sites: sink.sites,
                notes: sink.notes,
            },
            allow_used: sink.allow_used,
        })
    }
}

#[cfg(test)]
#[path = "captured_requirement_bool_tests.rs"]
mod tests;
