//! Init's unchanged policy over captured source and native lifecycle headers.
//! Complete init rule set, explicit captured-file scope only. No baseline or
//! generator runs, no filesystem discovery, model construction, or raw reread.
use crate::{
    captured_raw_policy::{CapturedRawPolicy, Configuration, RawRun, MAX_FIXTURE_SITES},
    lint::{Cx, Run, Sink},
};
use dm_analysis::{
    lifecycle_declarations::{lifecycle_definitions, LifecyclePolicy},
    policy_inputs::PolicyInputs,
};
use std::{
    panic::{catch_unwind, AssertUnwindSafe},
    path::Path,
};
pub struct CapturedInitPolicy<'a> {
    raw: CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
#[cfg(test)]
#[path = "captured_init_policy_tests.rs"]
mod tests;
impl<'a> CapturedInitPolicy<'a> {
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
        BorrowedInitPolicy::capture(&self.raw, self.inputs)?.scan(checkpoint)
    }
}
/// Reuse the host's same cross-file owner without acquiring another model.
pub struct BorrowedInitPolicy<'a> {
    raw: &'a CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
impl<'a> BorrowedInitPolicy<'a> {
    pub fn capture(raw: &'a CapturedRawPolicy, inputs: &'a PolicyInputs) -> Result<Self, String> {
        raw.validate_current_raw_roster(inputs)?;
        Ok(Self { raw, inputs })
    }
    pub fn scan(&self, checkpoint: impl FnMut() -> Result<(), String>) -> Result<RawRun, String> {
        let previous = crate::dm::sys::take_recorded();
        let result = catch_unwind(AssertUnwindSafe(|| self.scan_inner(checkpoint)));
        let _ = crate::dm::sys::take_recorded();
        crate::dm::sys::restore_recorded(previous);
        match result {
            Ok(result) => result,
            Err(_) => Err("captured init policy panicked; findings discarded".into()),
        }
    }
    fn scan_inner(
        &self,
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<RawRun, String> {
        checkpoint()?;
        // Compact report rows only. All text/tree/syntax owners remain issued
        // native owners. Definition selection is never reparsed from DM text.
        let rows = lifecycle_definitions(
            self.inputs.archive(),
            LifecyclePolicy::Init,
            &self.raw.tree.root,
        )
        .map_err(|e| e.0)?;
        let mut headers = Vec::with_capacity(rows.len());
        for row in rows {
            checkpoint()?;
            let captured = self
                .inputs
                .file(row.source.path.as_path())
                .ok_or("native init origin is outside captured policy inputs")?;
            if !captured.is_compiled() {
                return Err("native init origin is not an issued compiled input".into());
            }
            let rel = dm_preprocess::regions::relative_filesystem_path(
                row.source.path.as_path(),
                &self.raw.tree.root,
            )
            .ok_or("native init origin is outside policy root")?
            .to_string_lossy()
            .replace('\\', "/");
            let line = captured
                .analyze_display_line(row.source.line)
                .map_err(|e| e.to_string())?;
            let file = self
                .raw
                .tree
                .files
                .iter()
                .find(|file| file.rel == rel)
                .ok_or("native init source has no captured raw view")?;
            if line == 0 || line > file.raw().num_lines() {
                return Err(
                    "native init header cannot be projected into captured raw source".into(),
                );
            }
            let name = self
                .inputs
                .archive()
                .tree()
                .symbols()
                .text(row.name)
                .ok_or("native init name is unavailable")?;
            let owner = self
                .inputs
                .archive()
                .tree()
                .symbols()
                .text(row.owner)
                .ok_or("native init owner is unavailable")?;
            headers.push((
                rel,
                u32::try_from(line).map_err(|_| "native init line overflow")?,
                owner.to_string(),
                name.to_string(),
            ));
        }
        let meta = crate::lints::init::captured_metadata();
        let scope = self.raw.scopes.for_lint(meta.name, meta.group);
        let cx = Cx { fixture:None,
            tree: &self.raw.tree,
            meta,
            scope: &scope,
        };
        let mut sink = Sink::new();
        let result = catch_unwind(AssertUnwindSafe(|| {
            crate::lints::init::scan_captured(&cx, &mut sink, &headers)
        }));
        if result.is_err() {
            return Err(self
                .raw
                .tree
                .captured_violation()
                .unwrap_or_else(|| "captured init policy panicked; findings discarded".into()));
        }
        if let Some(error) = self.raw.tree.captured_violation() {
            return Err(error);
        }
        checkpoint()?;
        if sink.sites.len() > MAX_FIXTURE_SITES {
            return Err("captured init fixture exceeds finding admission".into());
        }
        Ok(RawRun {
            name: "init".into(),
            run: Run {
                sites: sink.sites,
                notes: sink.notes,
            },
            allow_used: sink.allow_used,
        })
    }
}
