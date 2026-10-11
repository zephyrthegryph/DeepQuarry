//! Shadow execution only: exact normal admission remains the sole reuse authority.
use super::*;
use std::collections::BTreeMap;
fn ledger(
    reads: &[ResolverRead],
) -> Option<BTreeMap<dm_ir::ResolveQuery, (dm_ir::ReadDomain, Vec<u8>)>> {
    let mut result = BTreeMap::new();
    for read in reads {
        let value = (read.domain, read.answer.canonical_bytes());
        if result
            .insert(read.query, value.clone())
            .is_some_and(|old| old != value)
        {
            return None;
        }
    }
    Some(result)
}
fn same_projection(old: &Projection, new: &Projection) -> bool {
    old.dimensions == new.dimensions
        && old.grid == new.grid
        && old.objects == new.objects
        && old.instances.len() == new.instances.len()
        && old
            .instances
            .iter()
            .zip(new.instances.iter())
            .all(|(old, new)| {
                old.kind == new.kind && old.atom == new.atom && old.origin == new.origin
            })
}
impl MapMemo {
    fn mismatch(&self, detail: &str) -> String {
        self.verification_failed.store(true, Ordering::Relaxed);
        self.verification.mismatches.fetch_add(1, Ordering::Relaxed);
        format!("DMBD_VERIFY map hit mismatch: {detail}")
    }
    pub(super) fn verify_parse(
        &self,
        captured: &CapturedMap,
        cached: &MapPlan,
    ) -> Result<(), MapDiagnostic> {
        self.verification.checked.fetch_add(1, Ordering::Relaxed);
        let fresh = dm_tree::maps::plan(captured.clone());
        let valid = fresh.as_ref().is_ok_and(|fresh| {
            cached.model == fresh.model
                && cached.symbols.ordered() == fresh.symbols.ordered()
                && cached.template_origins == fresh.template_origins
                && cached.block_origins == fresh.block_origins
        });
        if valid {
            return Ok(());
        }
        Err(MapDiagnostic {
            kind: dm_tree::maps::DiagnosticKind::Internal,
            span: dm_syntax::Span::new(0, 0),
            message: self.mismatch("parse output/current origins"),
        })
    }
    pub(super) fn verify_geometry<R: Resolver>(
        &self,
        maps: &[MapPlan],
        defaults: WorldDefaults,
        host: &R,
        cached: &Projection,
        original: &[ResolverRead],
    ) -> Result<(), crate::map_projection::Error> {
        self.verification.checked.fetch_add(1, Ordering::Relaxed);
        let recorder = RecordingResolver::new(host);
        let fresh = crate::map_projection::project(
            maps,
            defaults,
            &crate::map_projection::ResolverClassifier(&recorder),
        );
        let fresh_reads = recorder.reads();
        let valid_output = fresh
            .as_ref()
            .is_ok_and(|fresh| same_projection(cached, fresh));
        let old = ledger(original);
        let current = ledger(&fresh_reads);
        if valid_output && old.is_some() && old == current {
            return Ok(());
        }
        let detail = if !valid_output {
            "geometry output"
        } else {
            "geometry original query/domain/answer ledger"
        };
        Err(crate::map_projection::Error::Verification(
            self.mismatch(detail),
        ))
    }
    /// Current request only; map outputs/per-unit emission are outside this scope.
    pub fn map_verification_counts(&self) -> (u64, u64) {
        (
            self.verification.checked.load(Ordering::Relaxed),
            self.verification.mismatches.load(Ordering::Relaxed),
        )
    }
}
#[cfg(test)]
#[path = "map_memo_verify_tests.rs"]
mod tests;
