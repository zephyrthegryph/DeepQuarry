//! Opt-in test observation, NEVER an input/admission/cache identity.
//! Debug addresses are process-local evidence only and never enter wire pins.
use dm_tree::frontend::{ColdFrontend, RetainedSemanticTree};
use std::sync::Arc;
pub(super) fn emit(
    phase: &str,
    frontend: &ColdFrontend,
    queries: &crate::query_db::QueryDb,
    state: &RetainedSemanticTree,
) {
    if std::env::var_os("DMB_UNIFIED_TEST_OWNER_TRACE").as_deref()
        != Some(std::ffi::OsStr::new("1"))
    {
        return;
    }
    let archive = frontend.body_archive();
    let count = archive.as_ref().map_or(0, |archive| archive.len());
    let mut issued_observed = 0usize;
    let mut owners = Vec::new();
    if let Some(archive) = archive.as_ref() {
        for ordinal in 0..count {
            // Observation must not mint Code/Input owners or run a query.
            // A busy sparse slot may conservatively be omitted.
            if let Some(input) = archive.peek_syntax_input(ordinal) {
                issued_observed += 1;
                if owners.len() < 512 {
                    owners.push(serde_json::json!({"key":input.key(),"address":Arc::as_ptr(&input)as usize,"ordinal":ordinal}));
                }
            }
        }
    }
    let row = serde_json::json!({
        "observation":"native-original-program-owner-test-v1","phase":phase,
        "tree":Arc::as_ptr(&frontend.snapshot.tree)as usize,
        "declaration_syntax":Arc::as_ptr(&frontend.syntax)as usize,
        "query_db":queries as *const crate::query_db::QueryDb as usize,
        "source_mapping":frontend.source_export_mapping().map(|mapping|Arc::as_ptr(mapping)as usize),
        "body_inputs_total":count,"body_inputs_issued_observed":issued_observed,
        "body_inputs_complete":issued_observed==count&&count<=512,"body_inputs":owners,
        "body_inputs_observation":"already-issued owners only; unissued or concurrently borrowed slots omitted",
        "body_parser_computed":queries.db().stats(dm_query::Kind(4)).computed,
        "native_rebuilds":state.rebuilds(),
        "declaration_parsing_seconds":frontend.timings.declaration_parsing.as_secs_f64(),
        "tree_resolution_seconds":frontend.timings.tree_resolution.as_secs_f64(),
        "claim":"process-local owner observation only; not a semantic model or cache/admission key"
    });
    crate::daemon_eprintln!("native owner observation: {row}");
}
