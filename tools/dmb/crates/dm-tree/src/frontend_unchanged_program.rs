//! Reissue current source authority around ONE retained native program owner.
//! Current planning/expansion already refreshed the original input ledger.
use super::*;
impl ColdFrontend {
    pub(super) fn reissue_unchanged_program(
        previous: &ColdFrontend,
        plan: DirectivePlan,
        expanded: ExpandedRegions,
        files: Vec<SourceFile>,
        by_path: Arc<HashMap<PathBuf, FileId>>,
        timings: FrontendTimings,
        primary_headers: bool,
    ) -> Result<
        Self,
        (
            DirectivePlan,
            ExpandedRegions,
            Vec<SourceFile>,
            Arc<HashMap<PathBuf, FileId>>,
            FrontendTimings,
        ),
    > {
        let reject = || false;
        let admitted = previous.source_export_mapping().is_some()
            && previous.body_archive().is_some()
            && (!primary_headers
                || previous
                    .source_export_mapping
                    .declaration_compatibility_issued())
            && dm_preprocess::regions::plans_equal(&plan, &previous.plan).is_ok()
            && plan.source_acquisitions.len() == plan.occurrences.len()
            && plan.occurrences.iter().enumerate().all(|(index, _)| {
                match (
                    plan.source_acquisitions.get(&index),
                    previous.plan.source_acquisitions.get(&index),
                ) {
                    (Some(now), Some(old)) => now.same_original_acquisition(old),
                    _ => reject(),
                }
            })
            && files.len() == previous.files.len()
            && files.iter().zip(previous.files.iter()).all(|(now, old)| {
                now.id == old.id
                    && now.path == old.path
                    && now.captured == old.captured
                    && now.text.same_view(&old.text)
                    && now.line_starts == old.line_starts
            })
            && *by_path == *previous.source_by_path
            && expanded.diagnostics.is_empty()
            && expanded.text.as_str() == previous.expanded.text.as_str()
            && expanded.origins.len() == previous.expanded.origins.len()
            && expanded
                .origins
                .iter()
                .zip(previous.expanded.origins.iter())
                .all(|(now, old)| {
                    now.origin == old.origin
                        && now.output_span == old.output_span
                        && now.source_span == old.source_span
                        && now.region == old.region
                        && now.macro_expansions == old.macro_expansions
                })
            && expanded.emission_regions == previous.expanded.emission_regions
            && expanded.receipts.len() == previous.expanded.receipts.len()
            && expanded
                .receipts
                .iter()
                .zip(previous.expanded.receipts.iter())
                .all(|(now, old)| {
                    now.region() == old.region()
                        && now.output_span() == old.output_span()
                        && now.origin_row_count() == old.origin_row_count()
                });
        if !admitted {
            return Err((plan, expanded, files, by_path, timings));
        }
        let issued_arena = expanded.text.clone();
        let mut current = Self {
            timings,
            engine: previous.engine.clone(),
            plan,
            expanded,
            syntax: Arc::clone(&previous.syntax),
            allocation_ledger: Arc::clone(&previous.allocation_ledger),
            snapshot: previous.snapshot.clone(),
            files: files.into(),
            source_by_path: by_path,
            bodies: Arc::clone(&previous.bodies),
            callable_roster: Arc::clone(&previous.callable_roster),
            abi_settings_complete: previous.abi_settings_complete,
            body_by_declaration: Arc::clone(&previous.body_by_declaration),
            issued_bodies: Arc::clone(&previous.issued_bodies),
            issued_body_codes: Arc::clone(&previous.issued_body_codes),
            issued_settings: Arc::clone(&previous.issued_settings),
            issued_syntax: Arc::clone(&previous.issued_syntax),
            issued_arena,
            emission_order: Arc::clone(&previous.emission_order),
            source_export_mapping: Arc::clone(&previous.source_export_mapping),
            body_queries: previous.body_queries.clone(),
            reused_body_queries: false,
            setting_expression_queries: previous.setting_expression_queries.clone(),
        };
        current.source_export_mapping =
            Arc::new(previous.source_export_mapping.reissue_unchanged(&current));
        current.reused_body_queries = current.body_queries.is_some();
        crate::change_set::record_outcome("frontend original-program reuse: current acquisitions/plan/mapping; same tree, declaration AST and body query graph; declaration parse=0 normalization=0".into());
        Ok(current)
    }
}

#[cfg(test)]
#[path = "frontend_unchanged_program_tests.rs"]
mod tests;
