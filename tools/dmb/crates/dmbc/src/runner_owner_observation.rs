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
    let inputs = archive.as_ref().and_then(|archive| archive.syntax_inputs());
    let count = inputs.map_or(0, |inputs| inputs.len());
    let owners = inputs
        .into_iter()
        .flatten()
        .take(512)
        .map(|input| serde_json::json!({"key":input.key(),"address":Arc::as_ptr(input)as usize}))
        .collect::<Vec<_>>();
    let row = serde_json::json!({
        "observation":"native-original-program-owner-test-v1","phase":phase,
        "tree":Arc::as_ptr(&frontend.snapshot.tree)as usize,
        "declaration_syntax":Arc::as_ptr(&frontend.syntax)as usize,
        "query_db":queries as *const crate::query_db::QueryDb as usize,
        "source_mapping":frontend.source_export_mapping().map(|mapping|Arc::as_ptr(mapping)as usize),
        "body_inputs_total":count,"body_inputs_complete":count<=512,"body_inputs":owners,
        "body_parser_computed":queries.db().stats(dm_query::Kind(4)).computed,
        "native_rebuilds":state.rebuilds(),
        "declaration_parsing_seconds":frontend.timings.declaration_parsing.as_secs_f64(),
        "tree_resolution_seconds":frontend.timings.tree_resolution.as_secs_f64(),
        "claim":"process-local owner observation only; not a semantic model or cache/admission key"
    });
    crate::daemon_eprintln!("native owner observation: {row}");
}
