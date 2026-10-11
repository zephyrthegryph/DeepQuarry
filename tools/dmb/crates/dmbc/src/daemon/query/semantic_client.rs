//! Streaming traversal of revision-pinned retained semantic rosters.
//!
//! Start with an existing `QueryRequest` whose `expected_revision` is set (a
//! separate empty query may discover it). `visit_catalog` uses the SAME query
//! transport and validation as `execute`; it never starts a daemon or builds a
//! second model. Only the current page is retained. The callback must copy only
//! facts it needs and may stop at any row. Dense ordinals expire with the pin.
//!
//! Types expose parent links; authored members and captured intrinsics expose
//! selectors. Inherited effective lookup is a subsequent ordinary Resolver query,
//! not a generated type-by-member Cartesian catalog. A partial intrinsic catalog
//! cannot establish absence. `complete` remains false for total analysis coverage.
//!
//! Call `visit_catalog(&pinned_request, Catalog::Types, limits, checkpoint, visit)`
//! independently for each desired roster. A checkpoint can return Interrupted
//! when its caller cancels. Keep the same revision for subsequent Resolver queries;
//! a stale pin fails instead of silently restarting enumeration on another tree.
//! `visit_occurrences` additionally requires the current source revision pin and
//! streams only parser-issued occurrence facts. It does not parse or lower bodies.
#[path = "retained_export.rs"]
mod retained_export;
use super::{QueryRequest, SourceQuery};
pub use retained_export::run_export_file;
use std::{
    io,
    time::{Duration, Instant},
};
#[derive(Clone, Copy)]
pub enum Catalog {
    Types,
    Members,
    Intrinsics,
    /// Current issued source occurrences, requiring both revision pins.
    Occurrences,
    /// Source body envelopes and setting-context locations, without parsed syntax.
    BodyContexts,
}
#[derive(Clone, Copy)]
pub struct TraversalLimits {
    pub page_size: u32,
    pub max_pages: u32,
    pub max_items: u32,
    /// Checked before/after requests and callbacks. An already executing query
    /// has the existing transport's 20-second timeout, not a hard deadline here.
    pub elapsed: Duration,
}
impl Default for TraversalLimits {
    fn default() -> Self {
        Self {
            page_size: 128,
            max_pages: 4096,
            max_items: 524288,
            elapsed: Duration::from_secs(300),
        }
    }
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum VisitControl {
    Continue,
    Stop,
}
pub struct TraversalResult {
    pub revision: String,
    pub source_revision: Option<String>,
    pub pages: u32,
    pub visited: u32,
    pub total: u32,
    pub roster_finished: bool,
    pub stopped_by_consumer: bool,
    pub intrinsic_inventory_complete: bool,
    pub hierarchy_certified: bool,
    /// Roster enumeration does not prove complete executable/source analysis.
    pub complete: bool,
}
fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, message)
}
fn number(row: &serde_json::Value, key: &str) -> io::Result<u32> {
    row[key]
        .as_u64()
        .and_then(|value| value.try_into().ok())
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "invalid catalog page number"))
}
/// The template's other queries must be empty, preventing repeated side queries.
/// Cancellation/error propagates without returning a misleading finished result.
/// Callbacks and cancellation checks run only outside transport/session locks.
pub fn visit_catalog(
    template: &QueryRequest,
    catalog: Catalog,
    limits: TraversalLimits,
    checkpoint: impl FnMut() -> io::Result<()>,
    visit: impl FnMut(&serde_json::Value) -> io::Result<VisitControl>,
) -> Result<TraversalResult, Box<dyn std::error::Error>> {
    visit_catalog_with(template, catalog, limits, checkpoint, visit, super::execute)
}
/// Stream current source occurrences through the same validated query transport.
/// This does not issue executable body facts or certify complete provenance.
pub fn visit_occurrences(
    template: &QueryRequest,
    limits: TraversalLimits,
    checkpoint: impl FnMut() -> io::Result<()>,
    visit: impl FnMut(&serde_json::Value) -> io::Result<VisitControl>,
) -> Result<TraversalResult, Box<dyn std::error::Error>> {
    visit_catalog(template, Catalog::Occurrences, limits, checkpoint, visit)
}
fn visit_catalog_with(
    template: &QueryRequest,
    catalog: Catalog,
    limits: TraversalLimits,
    mut checkpoint: impl FnMut() -> io::Result<()>,
    mut visit: impl FnMut(&serde_json::Value) -> io::Result<VisitControl>,
    mut execute: impl FnMut(QueryRequest) -> Result<super::QueryReply, Box<dyn std::error::Error>>,
) -> Result<TraversalResult, Box<dyn std::error::Error>> {
    if template.expected_revision.is_none()
        || (matches!(catalog, Catalog::Occurrences | Catalog::BodyContexts)
            && template.expected_source_revision.is_none())
        || !template.queries.is_empty()
        || !template.source_queries.is_empty()
        || !(1..=128).contains(&limits.page_size)
        || !(1..=4096).contains(&limits.max_pages)
        || limits.max_items == 0
        || limits.max_items > 524288
        || limits.elapsed.is_zero()
        || limits.elapsed > Duration::from_secs(300)
    {
        return Err(invalid(
            "catalog traversal requires a pinned empty request and bounded limits",
        )
        .into());
    }
    template.validate()?;
    let began = Instant::now();
    let mut check = || {
        checkpoint()?;
        if began.elapsed() >= limits.elapsed {
            Err(io::Error::new(
                io::ErrorKind::TimedOut,
                "catalog traversal elapsed limit reached",
            ))
        } else {
            Ok(())
        }
    };
    let mut start = 0;
    let mut result = None;
    for page in 0..limits.max_pages {
        check()?;
        let mut request = template.clone();
        request.source_queries.push(match catalog {
            Catalog::Types => SourceQuery::SemanticTypesPage {
                start,
                limit: limits.page_size,
            },
            Catalog::Members => SourceQuery::SemanticMembersPage {
                start,
                limit: limits.page_size,
            },
            Catalog::Intrinsics => SourceQuery::SemanticIntrinsicMembersPage {
                start,
                limit: limits.page_size,
            },
            Catalog::Occurrences => SourceQuery::OccurrencesPage {
                start,
                limit: limits.page_size,
            },
            Catalog::BodyContexts => SourceQuery::BodyContextsPage {
                start,
                limit: limits.page_size,
            },
        });
        let reply = execute(request)?;
        check()?;
        // execute already validates exact request correspondence, pins, row
        // shape, cursor and bounded response size before exposing this page.
        let row: serde_json::Value = serde_json::from_str(reply.jsonl.trim())?;
        let total = number(&row, "total")?;
        let returned = number(&row, "returned")?;
        let (inventory, hierarchy) =
            if matches!(catalog, Catalog::Occurrences | Catalog::BodyContexts) {
                (false, false)
            } else {
                (
                    row["intrinsic_inventory_complete"]
                        .as_bool()
                        .ok_or_else(|| invalid("missing catalog completeness"))?,
                    row["hierarchy_certified"]
                        .as_bool()
                        .ok_or_else(|| invalid("missing hierarchy completeness"))?,
                )
            };
        let current = result.get_or_insert_with(|| TraversalResult {
            revision: reply.revision.clone(),
            source_revision: reply.source_revision.clone(),
            pages: 0,
            visited: 0,
            total,
            roster_finished: false,
            stopped_by_consumer: false,
            intrinsic_inventory_complete: inventory,
            hierarchy_certified: hierarchy,
            complete: false,
        });
        if current.revision != reply.revision
            || current.source_revision != reply.source_revision
            || current.total != total
            || current.intrinsic_inventory_complete != inventory
            || current.hierarchy_certified != hierarchy
        {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "pinned catalog changed during traversal",
            )
            .into());
        }
        current.pages = page + 1;
        for item in row["items"]
            .as_array()
            .ok_or_else(|| invalid("missing catalog items"))?
        {
            check()?;
            if current.visited >= limits.max_items {
                return Err(invalid("catalog traversal item limit reached").into());
            }
            current.visited += 1;
            let control = visit(item)?;
            check()?;
            if control == VisitControl::Stop {
                current.stopped_by_consumer = true;
                return Ok(result.expect("page result issued"));
            }
        }
        start = start
            .checked_add(returned)
            .ok_or_else(|| invalid("catalog cursor overflow"))?;
        if row["next_cursor"].is_null() {
            current.roster_finished = true;
            return Ok(result.expect("page result issued"));
        }
    }
    Err(invalid("catalog traversal page limit reached").into())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_unpinned_or_unbounded_traversal_before_transport() {
        let mut request = QueryRequest {
            timeout_seconds: None,
            project: "not-a-real-project.dme".into(),
            defines: Default::default(),
            engine_template: None,
            bootstrap_catalog: false,
            expected_revision: None,
            queries: Vec::new(),
            expected_source_revision: None,
            source_queries: Vec::new(),
        };
        let mut calls = 0;
        assert!(visit_catalog(
            &request,
            Catalog::Types,
            TraversalLimits::default(),
            || {
                calls += 1;
                Ok(())
            },
            |_| panic!("invalid request reached callback")
        )
        .is_err());
        assert_eq!(calls, 0);
        request.expected_revision = Some("00000000000000000000000000000001".into());
        for page_size in [0, 129] {
            let limits = TraversalLimits {
                page_size,
                ..Default::default()
            };
            assert!(visit_catalog(
                &request,
                Catalog::Types,
                limits,
                || panic!("invalid limits reached transport checkpoint"),
                |_| panic!("invalid limits reached callback")
            )
            .is_err());
        }
    }
    #[test]
    fn occurrence_traversal_uses_current_issued_pages_and_requires_both_pins() {
        use crate::runner_host::query_snapshot::{QueryAttempt, QueryState};
        use std::sync::{Arc, Mutex};
        struct Source;
        impl dm_preprocess::SourceProvider for Source {
            fn read(&self, _: &std::path::Path) -> Result<String, String> {
                Ok(
                    "/datum/example\n    var/value = 7\n    proc/read()\n        return value\n"
                        .into(),
                )
            }
        }
        let frontend = dm_tree::frontend::build_with_config(
            std::path::Path::new("fixture.dme"),
            &Source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
        )
        .unwrap();
        let state = Arc::new(Mutex::new(QueryState::default()));
        let mut attempt = QueryAttempt::new(Arc::clone(&state), true);
        attempt.capture(&frontend);
        attempt.finish_analyzed();
        drop(attempt);
        let mut request = QueryRequest {
            timeout_seconds: None,
            project: "fixture.dme".into(),
            defines: Default::default(),
            engine_template: None,
            bootstrap_catalog: false,
            expected_revision: Some(format!("{:032x}", frontend.snapshot.tree.identity())),
            expected_source_revision: None,
            queries: vec![],
            source_queries: vec![],
        };
        assert!(visit_occurrences(
            &request,
            Default::default(),
            || panic!("missing source pin reached transport"),
            |_| panic!("missing source pin reached consumer")
        )
        .is_err());
        request.expected_source_revision = Some(format!(
            "{:032x}",
            dm_analysis::tree_export::source_revision(&frontend)
        ));
        let mut ordinals = Vec::new();
        let result = visit_catalog_with(
            &request,
            Catalog::Occurrences,
            TraversalLimits {
                page_size: 1,
                ..Default::default()
            },
            || Ok(()),
            |item| {
                ordinals.push(item["occurrence"].as_u64().unwrap());
                Ok(VisitControl::Continue)
            },
            |page| {
                let reply = super::super::evaluate_snapshot(
                    &page,
                    &frontend.snapshot.tree,
                    &state.lock().unwrap(),
                )?;
                // Exercise the same reply preflight as the production transport.
                super::super::validate_reply(
                    &reply,
                    0,
                    1,
                    page.expected_revision.as_deref(),
                    page.expected_source_revision.as_deref(),
                )?;
                Ok(reply)
            },
        )
        .unwrap();
        assert!(result.roster_finished);
        assert!(result.total > 1);
        assert_eq!(result.pages, result.total);
        assert_eq!(ordinals, (0..u64::from(result.total)).collect::<Vec<_>>());
        assert_eq!(result.source_revision, request.expected_source_revision);
        assert!(!result.complete);
        assert!(!result.intrinsic_inventory_complete);
        assert!(!result.hierarchy_certified);
        request.expected_source_revision = Some("1".repeat(32));
        assert!(visit_catalog_with(
            &request,
            Catalog::Occurrences,
            Default::default(),
            || Ok(()),
            |_| panic!("stale source pin reached consumer"),
            |page| Ok(super::super::evaluate_snapshot(
                &page,
                &frontend.snapshot.tree,
                &state.lock().unwrap()
            )?)
        )
        .is_err());
    }
}
