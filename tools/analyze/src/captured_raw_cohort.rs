//! Whole-cohort raw policy over the existing captured owners. This is explicit
//! bounded fixture coverage, not RAW_FILE27 or whole-workspace admission.
use crate::{captured_generator_budget::Budget, captured_raw_policy::{self, CapturedRawPolicy, RawRun},
    lint::{Cx, Run, ScanKind, Sink}, scopes::LintScope};
use dm_analysis::policy_inputs::PolicyInputs;
use std::{panic::{catch_unwind, AssertUnwindSafe}, sync::Arc};
pub const FULL_WORKSPACE_COVERAGE: bool = false;
pub const LINTS: &[&str] = &crate::native_policy_roster::RAW_COHORT_LINT_NAMES;
pub struct BorrowedRawCohort<'a> { raw: &'a CapturedRawPolicy, inputs: &'a PolicyInputs }
fn denied(budget: &Budget, message: &'static str) -> String { budget.deny(); message.into() }
fn intact(raw: &CapturedRawPolicy, budget: &Budget) -> Result<(), String> {
    raw.tree.captured_violation().map_or(Ok(()), |error| { budget.deny(); Err(error) })
}
/// All quantities are obtained by borrowing admitted input; no token/parser or
/// semantic index is constructed for this resource census. Policy-owned facts,
/// maps, transformations and message temporaries remain under this peak reserve.
/// Existing regex-engine internals/global matcher caches are not an RSS claim.
fn admit_temporaries(name: &str, raw: &CapturedRawPolicy, scope: &LintScope, budget: &Budget,
    checkpoint: &mut impl FnMut() -> Result<(), String>) -> Result<(), String> {
    let mut units = 1usize;
    let mut width = 1usize;
    for file in &raw.tree.files {
        checkpoint()?;
        let text = file.raw().text.as_str();
        units = units.checked_add(text.len()).and_then(|n| n.checked_add(file.rel.len()))
            .ok_or_else(|| denied(budget, "raw-cohort input census overflow"))?;
        width = width.max(file.rel.len());
        for (_, line) in file.raw().numbered() { width = width.max(line.len()); }
    }
    for values in scope.lists.values() {
        for value in values {
            units = units.checked_add(value.len()).and_then(|n| n.checked_add(1))
                .ok_or_else(|| denied(budget, "raw-cohort configuration census overflow"))?;
            width = width.max(value.len());
        }
    }
    // Per-policy simultaneous owned-string families are enumerated in the
    // accompanying resource audit. Four capacity/old-new-overlap units per
    // string family cover geometric String/Vec construction and short messages.
    // Metadata terms cover vector growth, hash buckets, BTree nodes and TLS
    // annotation coordination concurrently. These are reservations, not RSS.
    let (string_families, metadata_per_unit): (usize, usize) = match name {
        "cooldown" => (4, 2048),
        "declaration_block" => (4, 4096),
        "duplicate_input_key" => (12, 8192),
        "entry_slots" => (2, 2048),
        "interactions" => (12, 8192),
        "latent" => (12, 8192),
        "pollers" => (4, 4096),
        "read_back" => (8, 8192),
        "cap_bits" => (8, 4096),
        _ => return Err("unadmitted raw-cohort resource recipe".into()),
    };
    let bytes = width.checked_add(256)
        .and_then(|n| n.checked_mul(string_families))
        .and_then(|n| n.checked_mul(4))
        .and_then(|n| n.checked_add(metadata_per_unit))
        .and_then(|n| n.checked_mul(units))
        .and_then(|n| n.checked_add(raw.tree.files.len().checked_mul(4096)?))
        .and_then(|n| n.checked_add(8192))
        .ok_or_else(|| denied(budget, "raw-cohort temporary envelope overflow"))?;
    budget.charge(bytes)
}
impl<'a> BorrowedRawCohort<'a> {
    /// This wrapper grants nothing: scan authenticates the complete original
    /// roster before entering the no-IO policy scope or calling any matcher.
    pub fn capture(raw: &'a CapturedRawPolicy, inputs: &'a PolicyInputs) -> Self { Self { raw, inputs } }
    pub fn scan(&self, name: &str, budget: Arc<Budget>, remaining_bytes: usize,
        remaining_sites: usize, mut checkpoint: impl FnMut() -> Result<(), String>) -> Result<RawRun, String> {
        checkpoint()?; budget.require()?; intact(self.raw, &budget)?;
        if !LINTS.contains(&name) { return Err("policy is not in the whole raw cohort".into()); }
        // BTreeSet roster validation itself has coordination storage; reserve
        // before the exact original authority checker allocates it.
        let roster = self.raw.tree.files.len().checked_mul(512).and_then(|n| n.checked_add(4096))
            .ok_or_else(|| denied(&budget, "raw-cohort roster coordination overflow"))?;
        budget.charge(roster)?;
        if self.raw.tree.files.len() > 128 { return Err("raw-cohort exceeds existing128-file fixture admission".into()); }
        self.raw.validate_current_raw_roster(self.inputs)?;
        let lint = captured_raw_policy::registry().find(name).ok_or("raw-cohort module absent")?;
        let meta = lint.meta();
        let empty = LintScope::default();
        let scope = self.raw.scopes.borrowed_for_lint(meta.name, meta.group).unwrap_or(&empty);
        admit_temporaries(name, self.raw, scope, &budget, &mut checkpoint)?;
        // The existing Kind10 final view census allocates after this function
        // returns while these rows remain retained. Reserve its coordination
        // headroom BEFORE the sink can retain rows; its own later budget charge
        // is intentionally conservative, preserving the existing pool path.
        let final_census = self.raw.tree.files.len().checked_mul(64 * 256)
            .and_then(|n| n.checked_add(4096))
            .ok_or_else(|| denied(&budget, "raw-cohort final census overlap overflow"))?;
        budget.charge(final_census)?;
        let headroom = remaining_bytes.saturating_sub(budget.used());
        if headroom < 1024 { return Err(denied(&budget, "raw-cohort result metadata denied")); }
        let mut sink = Sink::bounded(remaining_sites.min(captured_raw_policy::MAX_FIXTURE_SITES), headroom);
        let cx = Cx { tree: &self.raw.tree, meta, scope };
        // This TLS scope disables only old disk caches, after actual roster
        // admission. It does not manufacture input/current-source authority.
        let no_io = crate::incr::captured_compute_scope();
        let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
            if matches!(meta.scan, ScanKind::File | ScanKind::Both) {
                for file in cx.files() {
                    checkpoint()?; intact(self.raw, &budget)?;
                    sink.begin_captured_phase(&file.rel);
                    lint.scan_file(&cx, file, &mut sink);
                    intact(self.raw, &budget)?;
                    if let Some(error) = sink.admission_error() { budget.deny(); return Err(error); }
                }
            }
            if matches!(meta.scan, ScanKind::Tree | ScanKind::Both) {
                checkpoint()?; intact(self.raw, &budget)?;
                sink.begin_captured_phase("");
                lint.scan_tree(&cx, &mut sink);
            }
            Ok(())
        }));
        // Check latches on error and panic too: no operational denial can be
        // laundered as a cached deterministic String failure or empty finding.
        intact(self.raw, &budget)?;
        no_io.require().map_err(|e| { budget.deny(); e })?;
        if let Some(error) = sink.admission_error() { budget.deny(); return Err(error); }
        budget.require()?;
        match result {
            Ok(result) => result?,
            Err(_) => return Err(denied(&budget, "raw-cohort policy panicked; complete findings discarded")),
        }
        checkpoint()?;
        Ok(RawRun { name: name.to_owned(), run: Run { sites: sink.sites, notes: sink.notes }, allow_used: sink.allow_used })
    }
}
