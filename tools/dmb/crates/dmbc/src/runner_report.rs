//! Small owned telemetry snapshots independent of compiler source owners.
use crate as dmbc;
pub(super) struct FrontendReport {
    pub frontend_seconds: f64,
    pub declaration_reuse: serde_json::Value,
}
impl FrontendReport {
    pub fn capture(frontend: &dm_tree::frontend::ColdFrontend) -> Self {
        let d = &frontend.timings.declaration_reuse;
        Self {
            frontend_seconds: frontend.timings.total.as_secs_f64(),
            declaration_reuse: serde_json::json!({"chunks":d.chunks,"region_hits":d.region_hits,"independent_hits":d.independent_hits,"facts_hits":d.facts_hits,"parsed_chunks":d.parsed_chunks,"descriptor_scan_seconds":d.descriptor_scan.as_secs_f64(),"worker_lookup_decode_and_parse_seconds":d.worker_lookup_decode_and_parse.as_secs_f64(),"worker_fresh_facts_seconds":d.worker_fresh_facts.as_secs_f64(),"ordered_merge_seconds":d.ordered_merge.as_secs_f64()}),
        }
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
            serde_json::json!({
                "scope": "retained_session_total",
                "hits": store.hits.load(Relaxed),
                "recomputed": store.recomputed.load(Relaxed),
                "declined": store.declined.load(Relaxed),
                "modifier_hits": modifier_hits,
                "modifier_recomputed": modifier_recomputed,
            })
        })
}

pub(super) fn startup_totals(
    memo: Option<&dmbc::lowering_memo::ProcedureMemo>,
) -> Option<serde_json::Value> {
    use std::sync::atomic::Ordering::Relaxed;
    memo.and_then(|memo| memo.startup.as_ref()).map(|store| {
        serde_json::json!({
            "scope": "retained_session_total",
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
                "scope": "retained_session_total",
                "hits": store.hits.load(Relaxed),
                "recomputed": store.recomputed.load(Relaxed),
                "declined": store.declined.load(Relaxed),
            })
        })
}
