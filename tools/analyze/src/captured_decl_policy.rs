//! Decl's unchanged policy over captured source and native lifecycle headers.
//! Complete decl rule set, explicit captured-file scope only. No baseline or
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
pub struct CapturedDeclPolicy<'a> {
    raw: CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
#[cfg(test)]
#[path = "captured_decl_policy_tests.rs"]
mod tests;
impl<'a> CapturedDeclPolicy<'a> {
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
    pub fn scan(
        &self,
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<RawRun, String> {
        checkpoint()?;
        // Compact report rows only. All text/tree/syntax owners remain issued
        // native owners. Definition selection is never reparsed from DM text.
        let rows = lifecycle_definitions(
            self.inputs.archive(),
            LifecyclePolicy::Decl,
            &self.raw.tree.root,
        )
        .map_err(|e| e.0)?;
        let mut headers = Vec::with_capacity(rows.len());
        for row in rows {
            checkpoint()?;
            let captured = self
                .inputs
                .file(row.source.path.as_path())
                .ok_or("native decl origin is outside captured policy inputs")?;
            if !captured.is_compiled() {
                return Err("native decl origin is not an issued compiled input".into());
            }
            let rel = dm_preprocess::regions::relative_filesystem_path(
                row.source.path.as_path(),
                &self.raw.tree.root,
            )
            .ok_or("native decl origin is outside policy root")?
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
                .ok_or("native decl source has no captured raw view")?;
            if line == 0 || line > file.raw().num_lines() {
                return Err(
                    "native decl header cannot be projected into captured raw source".into(),
                );
            }
            let name = self
                .inputs
                .archive()
                .tree()
                .symbols()
                .text(row.name)
                .ok_or("native decl name is unavailable")?;
            headers.push((
                rel,
                u32::try_from(line).map_err(|_| "native decl line overflow")?,
                name.to_string(),
                row.lifecycle,
            ));
        }
        let meta = crate::lints::decl::captured_metadata();
        let scope = self.raw.scopes.for_lint(meta.name, meta.group);
        let cx = Cx {
            tree: &self.raw.tree,
            meta,
            scope: &scope,
        };
        let mut sink = Sink::new();
        let result = catch_unwind(AssertUnwindSafe(|| {
            crate::lints::decl::scan_captured(&cx, &mut sink, &headers)
        }));
        if result.is_err() {
            return Err(self
                .raw
                .tree
                .captured_violation()
                .unwrap_or_else(|| "captured decl policy panicked; findings discarded".into()));
        }
        if let Some(error) = self.raw.tree.captured_violation() {
            return Err(error);
        }
        checkpoint()?;
        if sink.sites.len() > MAX_FIXTURE_SITES {
            return Err("captured decl fixture exceeds finding admission".into());
        }
        Ok(RawRun {
            name: "decl".into(),
            run: Run {
                sites: sink.sites,
                notes: sink.notes,
            },
            allow_used: sink.allow_used,
        })
    }
}
