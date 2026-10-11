//! Small owned telemetry snapshots independent of compiler source owners.
use crate as dmbc;
pub(super) fn replay_warnings(warnings: &[String]) -> std::io::Result<()> {
    use std::io::Write;
    let mut output = dmbc::daemon::stderr_writer();
    for warning in warnings {
        output.write_all(warning.as_bytes())?;
    }
    Ok(())
}
pub(super) fn memo_statistics(
    memo: &dmbc::lowering_memo::ProcedureMemo,
    retention_status: &serde_json::Value,
) -> serde_json::Value {
    use std::sync::atomic::Ordering::Relaxed;
    let (verification_checked, verification_mismatches) = memo.procedure_verification_counts();
    serde_json::json!({
        "policy":format!("{:032x}",memo.policy),
        "host":retention_status,
        "disk_hits":memo.counts.disk_hits.load(Relaxed),
        "compact_disk_hits":memo.counts.compact_disk_hits.load(Relaxed),
        "compact_disk_encoded":memo.counts.compact_disk_encoded.load(Relaxed),
        "compact_fallback_encoding":memo.counts.compact_fallback_encoding.load(Relaxed),
        "compact_fallback_ineligible":memo.counts.compact_fallback_ineligible.load(Relaxed),
        "resident_hits":memo.counts.resident_hits.load(Relaxed),
        "resident_dropped":memo.counts.resident_dropped.load(Relaxed),
        "resident_retention":format!("{:?}",memo.resident_retention()),
        "symbolic_declines":memo.symbolic.as_ref().map(|store| store.decline_stats()),
        "procedure_verification": {
            "scope": "current_request_procedure_memo_hits_only",
            "checked": verification_checked,
            "mismatches": verification_mismatches
        },
        "link_assignments":memo.link_bindings.as_ref().map(|store| serde_json::json!({
            "scope":"process_local_cumulative",
            "reuses":store.assignment_reuses()
        })),
        "required_type_ancestry":memo.required_types.as_ref().map(|store| serde_json::json!({
            "scope":"process_local_cumulative",
            "hits":store.hits.load(Relaxed),
            "recomputed":store.recomputed.load(Relaxed)
        })),
        "issued_preparations":memo.counts.issued_preparations.load(Relaxed),
        "parsed_preparations":memo.counts.parsed_preparations.load(Relaxed),
        "recomputed":memo.counts.recomputed.load(Relaxed),
        "pending_dropped":memo.counts.pending_dropped.load(Relaxed),
        "staged_records":memo.counts.staged_records.load(Relaxed),
        "staging_failed":memo.counts.staging_failed.load(Relaxed),
        "key_preparation_seconds":memo.counts.key_preparation_ns.load(Relaxed) as f64 / 1e9,
        "lookup_seconds":memo.counts.lookup_ns.load(Relaxed) as f64 / 1e9,
        "occurrence_reads_seconds":memo.counts.occurrence_reads_ns.load(Relaxed) as f64 / 1e9,
        "explanation_seconds":memo.counts.explanation_ns.load(Relaxed) as f64 / 1e9,
        "encode_seconds":memo.counts.encode_ns.load(Relaxed) as f64 / 1e9,
        "staging_wall_seconds":memo.counts.staging_ns.load(Relaxed) as f64 / 1e9,
        "staging_errors":memo.staging_errors()
    })
}
pub(super) struct FrontendReport {
    pub frontend_seconds: f64,
    pub declaration_reuse: serde_json::Value,
    pub frontend_stage_wall_seconds: serde_json::Value,
    pub metadata_resolution: serde_json::Value,
}
impl FrontendReport {
    pub fn capture(frontend: &dm_tree::frontend::ColdFrontend) -> Self {
        let d = &frontend.timings.declaration_reuse;
        Self {
            frontend_seconds: frontend.timings.total.as_secs_f64(),
            frontend_stage_wall_seconds: frontend_stage_wall_seconds(&frontend.timings),
            metadata_resolution: serde_json::Value::Null,
            declaration_reuse: serde_json::json!({"duration_scope":"stage_wall_and_summed_worker_wall","worker_duration_scope":"sum_of_worker_elapsed_not_cpu_or_critical_wall","chunks":d.chunks,"region_hits":d.region_hits,"independent_hits":d.independent_hits,"facts_hits":d.facts_hits,"parsed_chunks":d.parsed_chunks,"descriptor_scan_seconds":d.descriptor_scan.as_secs_f64(),"worker_lookup_decode_and_parse_seconds":d.worker_lookup_decode_and_parse.as_secs_f64(),"worker_fresh_facts_seconds":d.worker_fresh_facts.as_secs_f64(),"ordered_merge_seconds":d.ordered_merge.as_secs_f64()}),
        }
    }
    pub fn capture_metadata(&mut self, state: Option<&dm_tree::frontend::RetainedSemanticTree>) {
        self.metadata_resolution = state.map_or(serde_json::Value::Null, |state| {
            let counts = state.metadata_resolution_stats();
            serde_json::json!({
                "scope": "retained_metadata_owner_cumulative_artifact_stage",
                "excludes": "separate_unchanged_roster_updates",
                "common_resolved_members": counts.common_resolved_members,
                "structurally_reused_members": counts.structurally_reused_members,
                "structurally_dirty_members": counts.structurally_dirty_members,
                "symbol_only_rebinds": state.symbol_only_rebinds(),
            })
        });
    }
}
/// Existing stage timers only; these values are elapsed wall durations.
/// Expansion includes the joined arena; no independent join timer is available.
fn frontend_stage_wall_seconds(t: &dm_tree::frontend::FrontendTimings) -> serde_json::Value {
    serde_json::json!({
        "scope": "existing_frontend_stage_elapsed_wall",
        "directive_planning": t.directive_planning.as_secs_f64(),
        "expansion_including_join": t.expansion.as_secs_f64(),
        "declaration_parsing": t.declaration_parsing.as_secs_f64(),
        "tree_resolution": t.tree_resolution.as_secs_f64(),
        "provenance_and_body_indexing": t.provenance_and_body_indexing.as_secs_f64(),
        "total": t.total.as_secs_f64(),
    })
}
#[cfg(test)]
mod frontend_timing_tests {
    #[test]
    fn existing_stage_durations_are_exported_as_wall_without_worker_sum() {
        use std::time::Duration;
        let timings = dm_tree::frontend::FrontendTimings {
            directive_planning: Duration::from_millis(125),
            expansion: Duration::from_millis(250),
            declaration_parsing: Duration::from_millis(375),
            tree_resolution: Duration::from_millis(500),
            provenance_and_body_indexing: Duration::from_millis(625),
            total: Duration::from_secs(2),
            declaration_reuse: dm_tree::frontend::DeclarationReuseStats {
                worker_fresh_facts: Duration::from_secs(99),
                ..Default::default()
            },
        };
        let value = super::frontend_stage_wall_seconds(&timings);
        assert_eq!(value["directive_planning"], 0.125);
        assert_eq!(value["expansion_including_join"], 0.25);
        assert_eq!(value["declaration_parsing"], 0.375);
        assert_eq!(value["tree_resolution"], 0.5);
        assert_eq!(value["provenance_and_body_indexing"], 0.625);
        assert_eq!(value["total"], 2.0);
        assert_eq!(value["scope"], "existing_frontend_stage_elapsed_wall");
    }
}
pub(super) fn explanations(
    frontend: &dm_tree::frontend::ColdFrontend,
    memo: Option<&dmbc::lowering_memo::ProcedureMemo>,
) -> Vec<serde_json::Value> {
    let symbols = frontend.snapshot.tree.symbols();
    memo.map(|memo| memo.explain()).unwrap_or_default().into_iter().map(|entry| {
        let owner = symbols.text(entry.identity.owner).unwrap_or("<unknown>");
        let name = symbols.text(entry.identity.name).unwrap_or("<unknown>");
        let namespace = if entry.identity.verb { "verb" } else { "proc" };
        let path = format!("{}/{namespace}/{name}", owner.trim_end_matches('/'));
        serde_json::json!({"path":path,"occurrence":entry.identity.occurrence,"outcome":format!("{:?}",entry.outcome),"reason":entry.reason.map(|reason|format!("{reason:?}")),"changed_query":entry.changed_query})
    }).collect()
}

pub(super) fn initializer_totals(
    memo: Option<&dmbc::lowering_memo::ProcedureMemo>,
) -> Option<serde_json::Value> {
    use std::sync::atomic::Ordering::Relaxed;
    memo.and_then(|memo| memo.initializers.as_ref())
        .map(|store| {
            let (modifier_hits, modifier_recomputed) = store.modifier_reuse_counts();
            let (token_roster_hits, token_roster_recomputed) = store.token_roster_reuse_counts();
            serde_json::json!({
                "scope": "current_request",
                "hits": store.hits.load(Relaxed),
                "recomputed": store.recomputed.load(Relaxed),
                "declined": store.declined.load(Relaxed),
                "modifier_hits": modifier_hits,
                "modifier_recomputed": modifier_recomputed,
                "token_roster_hits": token_roster_hits,
                "token_roster_recomputed": token_roster_recomputed,
            })
        })
}

pub(super) fn startup_totals(
    memo: Option<&dmbc::lowering_memo::ProcedureMemo>,
) -> Option<serde_json::Value> {
    use std::sync::atomic::Ordering::Relaxed;
    memo.and_then(|memo| memo.startup.as_ref()).map(|store| {
        serde_json::json!({
            "scope": "current_request",
            "hits": store.hits.load(Relaxed),
            "recomputed": store.recomputed.load(Relaxed),
        })
    })
}

pub(super) fn abi_totals(
    memo: Option<&dmbc::lowering_memo::ProcedureMemo>,
) -> Option<serde_json::Value> {
    memo.and_then(|memo| memo.abi.as_ref()).map(|store| {
        let (hits, recomputed) = store.totals();
        serde_json::json!({
            "scope": "retained_session_total",
            "hits": hits,
            "recomputed": recomputed,
        })
    })
}

pub(super) fn initializer_fragment_totals(
    memo: Option<&dmbc::lowering_memo::ProcedureMemo>,
) -> Option<serde_json::Value> {
    use std::sync::atomic::Ordering::Relaxed;
    memo.and_then(|memo| memo.initializer_fragments.as_ref())
        .map(|store| {
            serde_json::json!({
                "scope": "current_request",
                "hits": store.hits.load(Relaxed),
                "recomputed": store.recomputed.load(Relaxed),
                "declined": store.declined.load(Relaxed),
            })
        })
}
