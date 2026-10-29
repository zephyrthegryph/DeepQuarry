//! Reuse unchanged, audited raw-only policy over compiler-owned source views.
//! This is explicit captured-file coverage, never a whole-workspace proof.
//! No Engine::new, filesystem discovery, legacy semantic model, generator,
//! baseline mutation or second DM parser runs at this boundary.
use crate::{
    lint::{AllowUse, Cx, Registry, Run, ScanKind, Sink},
    scopes::Scopes,
    tree::{SourceFile, Tree},
};
use dm_analysis::policy_inputs::{PolicyInputs, PolicyRole, TextView};
use std::{
    panic::{catch_unwind, AssertUnwindSafe},
    path::Path,
};

/// Explicit migration fixture admission; not lint ceilings or CPU/RSS guarantees.
pub const MAX_FIXTURE_FILE_BYTES: usize = 256 * 1024;
pub const MAX_FIXTURE_TOTAL_BYTES: usize = 8 * 1024 * 1024;
pub const MAX_FIXTURE_SITES: usize = 10_000;
pub const RAW_FILE_LINTS: &[&str] = &crate::native_policy_roster::LINT_NAMES;
fn registry() -> &'static Registry {
    static REGISTRY:std::sync::OnceLock<Registry>=std::sync::OnceLock::new();
    REGISTRY.get_or_init(|| {
        let mut reg=Registry::default();
        include!(concat!(env!("OUT_DIR"),"/native_policy_registry_gen.rs"));
        reg
    })
}
/// Original policy metadata, reused for strict finding admission and later
/// host-owned ratchet judgment. No semantic model is queried.
pub fn metadata(name: &str) -> Option<&'static crate::lint::Meta> {
    registry().find(name).map(|lint| lint.meta())
}
/// Host authenticates exact bytes or absence through the native request ledger.
/// This enum does not itself prove a filesystem observation or full config closure.
#[derive(Clone, Copy)]
pub enum Configuration<'a> {
    Captured(&'a [u8]),
    ProvenMissing,
}
pub struct RawRun {
    pub name: String,
    pub run: Run,
    pub allow_used: Vec<AllowUse>,
}
pub struct CapturedRawPolicy {
    tree: Tree,
    scopes: Scopes,
}
impl CapturedRawPolicy {
    pub fn capture(
        root: &Path,
        inputs: &PolicyInputs,
        configuration: Configuration<'_>,
    ) -> Result<Self, String> {
        if !root.is_absolute() {
            return Err("raw policy root must be absolute".into());
        }
        let root = dm_preprocess::regions::canonical_path(root);
        let mut files = Vec::new();
        let mut total_bytes = match configuration {
            Configuration::Captured(bytes) => bytes.len(),
            Configuration::ProvenMissing => 0,
        };
        if total_bytes > MAX_FIXTURE_FILE_BYTES {
            return Err("raw-policy fixture configuration exceeds per-file admission".into());
        }
        for file in inputs
            .files()
            .filter(|file| file.role() == PolicyRole::DmSource)
        {
            let absolute = dm_preprocess::regions::canonical_path(file.path().as_ref());
            // Containment/report projection only: preserve the captured provider
            // key, including its original safe DOS-verbatim spelling.
            let relative = dm_preprocess::regions::relative_filesystem_path(&absolute, &root)
                .ok_or("captured raw source lies outside policy root")?;
            let rel = relative.to_string_lossy().replace('\\', "/");
            let raw = file
                .view(TextView::AnalyzeRaw)
                .map_err(|error| error.to_string())?
                .clone();
            if raw.len() > MAX_FIXTURE_FILE_BYTES {
                return Err("raw-policy fixture source exceeds per-file admission".into());
            }
            total_bytes = total_bytes
                .checked_add(raw.len())
                .ok_or("raw-policy fixture byte accounting overflow")?;
            if total_bytes > MAX_FIXTURE_TOTAL_BYTES {
                return Err("raw-policy fixture sources exceed total admission".into());
            }
            files.push(SourceFile::from_shared_text(&rel, absolute, raw));
        }
        let scopes = match configuration {
            Configuration::Captured(bytes) => match std::str::from_utf8(bytes) {
                Ok(text) => Scopes::parse(text)?,
                // Existing Scopes::load read_to_string treats invalid UTF8 as
                // an IO error and returns default scopes; preserve that branch.
                Err(_) => Scopes::default(),
            },
            Configuration::ProvenMissing => Scopes::default(),
        };
        Ok(Self {
            tree: Tree::from_captured_files(root, files),
            scopes,
        })
    }
    /// These are raw findings and consumed ALLOW records only. The host retains
    /// baseline/ceiling judgment, unused-ALLOW aggregation and unique generators.
    /// Every selected policy must complete; any unsupported access discards all.
    pub fn scan(
        &self,
        names: &[String],
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Vec<RawRun>, String> {
        if let Some(error) = self.tree.captured_violation() {
            return Err(error);
        }
        if names.is_empty() {
            return Err("explicit raw-policy lint list required".into());
        }
        for name in names {
            if !RAW_FILE_LINTS.contains(&name.as_str()) {
                return Err(format!(
                    "lint {name} has not been admitted as raw-file-only"
                ));
            }
        }
        let registry = registry();
        let mut runs = Vec::new();
        let mut completed_sites = 0usize;
        let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
            for lint in registry
                .lints
                .iter()
                .filter(|lint| names.iter().any(|name| name == lint.meta().name))
            {
                checkpoint()?;
                let meta = lint.meta();
                if meta.scan != ScanKind::File {
                    return Err(format!(
                        "raw-only lint {} changed its scan contract",
                        meta.name
                    ));
                }
                let scope = self.scopes.for_lint(meta.name, meta.group);
                let cx = Cx {
                    tree: &self.tree,
                    meta,
                    scope: &scope,
                };
                let mut sink = Sink::new();
                for file in cx.files() {
                    checkpoint()?;
                    sink.cur = file.rel.clone();
                    lint.scan_file(&cx, file, &mut sink);
                    // A legacy per-file scan finishes before this admission
                    // check. Reject the complete batch; never truncate sites.
                    if completed_sites.saturating_add(sink.sites.len()) > MAX_FIXTURE_SITES {
                        return Err("raw-policy fixture exceeds finding admission".into());
                    }
                    if let Some(error) = self.tree.captured_violation() {
                        return Err(error);
                    }
                }
                completed_sites = completed_sites.saturating_add(sink.sites.len());
                runs.push(RawRun {
                    name: meta.name.into(),
                    run: Run {
                        sites: sink.sites,
                        notes: sink.notes,
                    },
                    allow_used: sink.allow_used,
                });
            }
            Ok(())
        }));
        match result {
            Ok(Ok(())) => Ok(runs),
            Ok(Err(error)) => Err(error),
            Err(_) => Err(self
                .tree
                .captured_violation()
                .unwrap_or_else(|| "raw policy panicked; findings discarded".into())),
        }
    }
}
#[cfg(test)]
#[path = "captured_raw_policy_tests.rs"]
mod tests;
