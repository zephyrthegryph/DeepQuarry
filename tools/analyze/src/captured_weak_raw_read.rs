//! Existing full weak_raw_read policy over explicit captured native/raw inputs.
//! Baseline/workspace discovery remain host responsibilities; no model is built.
use crate::{
    captured_raw_policy::{CapturedRawPolicy, Configuration, RawRun, MAX_FIXTURE_SITES},
    lint::{Run, Sink},
};
use dm_analysis::policy_inputs::PolicyInputs;
use std::path::Path;
pub struct CapturedWeakRawRead<'a> {
    raw: CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
impl<'a> CapturedWeakRawRead<'a> {
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
        BorrowedWeakRawRead::capture(&self.raw, self.inputs)?.scan(checkpoint)
    }
}
pub struct BorrowedWeakRawRead<'a> {
    raw: &'a CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
impl<'a> BorrowedWeakRawRead<'a> {
    pub fn capture(raw: &'a CapturedRawPolicy, inputs: &'a PolicyInputs) -> Result<Self, String> {
        raw.validate_current_raw_roster(inputs)?;
        Ok(Self { raw, inputs })
    }
    pub fn scan(&self, checkpoint: impl FnMut() -> Result<(), String>) -> Result<RawRun, String> {
        let scope = self.raw.scopes.for_lint("weak_raw_read", "");
        let meta = crate::weak_relation_policy::metadata();
        let cx = crate::lint::Cx {
            tree: &self.raw.tree,
            meta,
            scope: &scope,
        };
        let weak = crate::weak_relation_policy::declarations(cx.files());
        let rows = dm_analysis::weak_raw_read_native::findings(
            self.inputs,
            &self.raw.tree.root,
            &weak,
            |f| scope.exempt(f),
            checkpoint,
        )
        .map_err(|e| e.0)?;
        if rows.len() > MAX_FIXTURE_SITES {
            return Err("weak_raw_read exceeds fixture finding admission".into());
        }
        let mut sink = Sink::new();
        for row in rows {
            sink.site_in_msg(
                "raw",
                &row.rel,
                row.line,
                format!(
                    "`{}` of {} is a weak relation read raw; use {}()",
                    row.var, row.holder, row.var
                ),
            );
        }
        Ok(RawRun {
            name: "weak_raw_read".into(),
            run: Run {
                sites: sink.sites,
                notes: sink.notes,
            },
            allow_used: sink.allow_used,
        })
    }
}
#[cfg(test)]
#[path = "captured_weak_raw_read_tests.rs"]
mod tests;
