//! Composition of the four existing base_vars rules over one captured owner.
//! The candidate pipeline performs raw/typed ALLOW acquisition once, then the
//! shared hot classifier and existing native record rule append in legacy order.
//! This backend is not whole-workspace admission or a production IPC cutover.
use crate::{
    captured_base_var_candidates::BorrowedBaseVarCandidates,
    captured_raw_policy::{CapturedRawPolicy, Configuration, RawRun, MAX_FIXTURE_SITES},
    lint::Site,
};
use dm_analysis::policy_inputs::PolicyInputs;
use std::{
    panic::{catch_unwind, AssertUnwindSafe},
    path::Path,
};

pub struct CapturedBaseVarsPolicy<'a> {
    raw: CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
impl<'a> CapturedBaseVarsPolicy<'a> {
    pub fn capture(
        root: &Path,
        inputs: &'a PolicyInputs,
        configuration: Configuration<'_>,
    ) -> Result<Self, String> {
        Ok(Self {
            raw: CapturedRawPolicy::capture(root, inputs, configuration)?,
            inputs,
        })
    }
    pub fn scan(&self, checkpoint: impl FnMut() -> Result<(), String>) -> Result<RawRun, String> {
        BorrowedBaseVarsPolicy::capture(&self.raw, self.inputs)?.scan(checkpoint)
    }
}
/// Host can retain/reuse its captured raw-policy source owner and scopes.
pub struct BorrowedBaseVarsPolicy<'a> {
    raw: &'a CapturedRawPolicy,
    inputs: &'a PolicyInputs,
    candidates: BorrowedBaseVarCandidates<'a>,
}
impl<'a> BorrowedBaseVarsPolicy<'a> {
    pub fn capture(raw: &'a CapturedRawPolicy, inputs: &'a PolicyInputs) -> Result<Self, String> {
        Ok(Self {
            raw,
            inputs,
            candidates: BorrowedBaseVarCandidates::capture(raw, inputs)?,
        })
    }
    pub fn scan(
        &self,
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<RawRun, String> {
        let previous = crate::dm::sys::take_recorded();
        let result = catch_unwind(AssertUnwindSafe(|| {
            let mut run = self.candidates.scan_for_composition(&mut checkpoint)?;
            let scope = self.raw.scopes.for_lint("base_vars", "");
            checkpoint()?;
            let records = dm_analysis::records_data_only::findings(
                self.inputs,
                &self.raw.tree.root,
                scope.list("record_accessor_prefixes"),
            )
            .map_err(|error| error.0)?;
            for finding in records {
                checkpoint()?;
                run.run.sites.push(Site {
                    rule: finding.rule,
                    rel: finding.rel,
                    line: finding.line,
                    msg: finding.msg,
                    key: finding.key,
                    ident: finding.ident,
                });
                if run.run.sites.len() > MAX_FIXTURE_SITES {
                    return Err("base-vars fixture exceeds finding admission".into());
                }
            }
            if let Some(error) = self.raw.tree.captured_violation() {
                return Err(error);
            }
            checkpoint()?;
            Ok(run)
        }));
        let _ = crate::dm::sys::take_recorded();
        crate::dm::sys::restore_recorded(previous);
        match result {
            Ok(result) => result,
            Err(_) => Err(self.raw.tree.captured_violation().unwrap_or_else(|| {
                "captured base-vars policy panicked; findings discarded".into()
            })),
        }
    }
}
#[cfg(test)]
#[path = "captured_base_vars_policy_tests.rs"]
mod tests;
