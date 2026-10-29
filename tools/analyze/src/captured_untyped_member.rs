//! Existing untyped_member messages/scopes over native declared receiver facts.
use crate::{
    captured_raw_policy::{CapturedRawPolicy, Configuration, RawRun, MAX_FIXTURE_SITES},
    lint::{Run, Sink},
};
use dm_analysis::policy_inputs::PolicyInputs;
use std::path::Path;
pub struct CapturedUntypedMember<'a> {
    raw: CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
impl<'a> CapturedUntypedMember<'a> {
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
        BorrowedUntypedMember::capture(&self.raw, self.inputs)?.scan(checkpoint)
    }
}
pub struct BorrowedUntypedMember<'a> {
    raw: &'a CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
impl<'a> BorrowedUntypedMember<'a> {
    pub fn capture(raw: &'a CapturedRawPolicy, inputs: &'a PolicyInputs) -> Result<Self, String> {
        raw.validate_current_raw_roster(inputs)?;
        Ok(Self { raw, inputs })
    }
    pub fn scan(&self, checkpoint: impl FnMut() -> Result<(), String>) -> Result<RawRun, String> {
        let scope = self.raw.scopes.for_lint("untyped_member", "");
        let rows = dm_analysis::untyped_member_native::findings(
            self.inputs,
            &self.raw.tree.root,
            |file| scope.exempt(file),
            checkpoint,
        )
        .map_err(|e| e.0)?;
        if rows.len() > MAX_FIXTURE_SITES {
            return Err("untyped_member exceeds fixture admission".into());
        }
        let mut sink = Sink::new();
        for row in rows {
            sink.site_in_msg(
                "static_member",
                &row.rel,
                row.line as usize,
                crate::untyped_member_policy::message(&row.name),
            );
        }
        Ok(RawRun {
            name: "untyped_member".into(),
            run: Run {
                sites: sink.sites,
                notes: sink.notes,
            },
            allow_used: sink.allow_used,
        })
    }
}

#[cfg(test)]
#[path = "captured_untyped_member_tests.rs"]
mod tests;
