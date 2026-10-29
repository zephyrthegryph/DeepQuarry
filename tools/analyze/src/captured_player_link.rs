//! Existing full player_link policy over explicit captured native/raw inputs.
//! Baseline/workspace discovery remain host responsibilities; no model is built.
use crate::{
    captured_raw_policy::{CapturedRawPolicy, Configuration, RawRun, MAX_FIXTURE_SITES},
    lint::{Run, Sink},
};
use dm_analysis::policy_inputs::PolicyInputs;
use std::path::Path;
pub struct CapturedPlayerLink<'a> {
    raw: CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
impl<'a> CapturedPlayerLink<'a> {
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
        BorrowedPlayerLink::capture(&self.raw, self.inputs)?.scan(checkpoint)
    }
}
pub struct BorrowedPlayerLink<'a> {
    raw: &'a CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
impl<'a> BorrowedPlayerLink<'a> {
    pub fn capture(raw: &'a CapturedRawPolicy, inputs: &'a PolicyInputs) -> Result<Self, String> {
        raw.validate_current_raw_roster(inputs)?;
        Ok(Self { raw, inputs })
    }
    pub fn scan(&self, checkpoint: impl FnMut() -> Result<(), String>) -> Result<RawRun, String> {
        let scope = self.raw.scopes.for_lint("player_link", "");
        let rows = dm_analysis::player_link_native::findings(
            self.inputs,
            &self.raw.tree.root,
            |f| scope.exempt(f),
            checkpoint,
        )
        .map_err(|e| e.0)?;
        if rows.len() > MAX_FIXTURE_SITES {
            return Err("player_link exceeds fixture finding admission".into());
        }
        let mut sink = Sink::new();
        for row in rows {
            sink.site_in_msg(
                "raw_key",
                &row.rel,
                row.line,
                crate::player_link_policy::MESSAGE,
            );
        }
        Ok(RawRun {
            name: "player_link".into(),
            run: Run {
                sites: sink.sites,
                notes: sink.notes,
            },
            allow_used: sink.allow_used,
        })
    }
}
#[cfg(test)]
#[path = "captured_player_link_tests.rs"]
mod tests;
