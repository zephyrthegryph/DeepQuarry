//! Current source query projection: shared issued occurrences, paths, and revision only.
//! No executable syntax, source text, or old frontend issuance is retained.
#[path = "runner_query_selected.rs"]
mod selected;
use dm_tree::frontend::ColdFrontend;
use std::{
    collections::BTreeMap,
    path::PathBuf,
    sync::{Arc, Mutex},
};
pub(crate) struct QueryState {
    pub(crate) snapshot: Option<SourceSnapshot>,
    pub(crate) last_request_outcome: &'static str,
    pub(crate) publication_pair: Option<String>,
}
impl Default for QueryState {
    fn default() -> Self {
        Self {
            snapshot: None,
            last_request_outcome: "never_started",
            publication_pair: None,
        }
    }
}
pub(crate) struct SourceSnapshot {
    tree: Arc<dm_tree::SemanticTree>,
    pub(crate) source_revision: u128,
    pub(crate) outcome: &'static str,
    occurrences: Arc<dm_tree::OccurrenceTable>,
    paths: BTreeMap<dm_ir::FileId, Arc<PathBuf>>,
    selected: selected::SelectedRows,
}
impl SourceSnapshot {
    pub(super) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        // Only Arc handles are cloned for the common graph visitor. No source
        // rows, paths, metadata, or semantic payloads are materialized.
        census.snapshot(&dm_tree::TreeSnapshot {
            tree: Arc::clone(&self.tree),
            occurrences: Arc::clone(&self.occurrences),
        });
        self.selected.census(census);
        census.observe_items("query_snapshot.paths", self.paths.len());
        census.unknown("query_snapshot.paths", "BTreeMap node capacity and allocator overhead are not exposed; logical path roster count is not allocated bytes");
        for path in self.paths.values() {
            census.arc_path("query_snapshot.paths", path);
        }
    }
    pub(crate) fn matches_tree(&self, tree: &dm_tree::SemanticTree) -> bool {
        std::ptr::eq(self.tree.as_ref(), tree)
    }
    fn capture(frontend: &ColdFrontend) -> Self {
        Self {
            tree: Arc::clone(&frontend.snapshot.tree),
            source_revision: dm_analysis::tree_export::source_revision(frontend),
            outcome: "frontend_analyzed",
            selected: Default::default(),
            occurrences: Arc::clone(&frontend.snapshot.occurrences),
            paths: frontend
                .files
                .iter()
                .map(|file| (file.id, Arc::clone(&file.path)))
                .collect(),
        }
    }
    pub(crate) fn write_selected(
        &self,
        ordinal: u32,
        output: &mut impl std::io::Write,
    ) -> std::io::Result<()> {
        self.selected.write(ordinal, self.source_revision, output)
    }
    pub(crate) fn occurrence(
        &self,
        ordinal: u32,
        tree: &dm_tree::SemanticTree,
    ) -> std::io::Result<serde_json::Value> {
        use std::io::{Error, ErrorKind};
        if !self.matches_tree(tree) {
            return Err(Error::other(
                "source query tree differs from admitted snapshot",
            ));
        }
        let occurrence = self
            .occurrences
            .get(dm_tree::OccurrenceId(ordinal))
            .ok_or_else(|| {
                Error::new(ErrorKind::InvalidInput, "unknown current source occurrence")
            })?;
        let target = match occurrence.target {
            dm_tree::Target::Type(id) => {
                serde_json::json!({"kind":"type", "symbol":tree.type_node(id).ok_or_else(|| Error::other("unknown occurrence type"))?.path.bits()})
            }
            dm_tree::Target::Member(id) => {
                let member = tree
                    .member(id)
                    .ok_or_else(|| Error::other("unknown occurrence member"))?;
                serde_json::json!({"kind":format!("{:?}",member.kind),"owner":tree.type_node(member.owner).ok_or_else(|| Error::other("unknown occurrence owner"))?.path.bits(),
                    "name":member.name.bits(),"override_depth":tree.member_occurrence(id)})
            }
        };
        let provenance = &occurrence.provenance;
        let path = |file| {
            self.paths
                .get(&file)
                .map(|path| path.to_string_lossy().into_owned())
                .ok_or_else(|| Error::other("unknown occurrence source path"))
        };
        if provenance.expansion_stack.len() > 1024 {
            return Err(Error::new(
                ErrorKind::InvalidData,
                "source provenance exceeds bounded definition-origin depth",
            ));
        }
        let definitions = provenance
            .expansion_stack
            .iter()
            .map(|span| {
                Ok(serde_json::json!({"path":path(span.file)?,"start":span.start,"end":span.end}))
            })
            .collect::<std::io::Result<Vec<_>>>()?;
        Ok(
            serde_json::json!({"schema":"dm-session-source-query-v1","row":"source_occurrence",
            "source_revision":format!("{:032x}",self.source_revision),"occurrence":ordinal,"target":target,
            "path":path(provenance.span.file)?,"start":provenance.span.start,"end":provenance.span.end,
            "include_occurrence":provenance.include_occurrence,"region":format!("{:032x}",provenance.region),
            "definition_origins":definitions,"provenance_complete":false}),
        )
    }
}
pub(crate) struct QueryAttempt {
    state: Arc<Mutex<QueryState>>,
    captured: bool,
    enabled: bool,
    finished: bool,
}
impl QueryAttempt {
    pub(crate) fn new(state: Arc<Mutex<QueryState>>, enabled: bool) -> Self {
        {
            let mut current = state.lock().unwrap_or_else(|error| error.into_inner());
            current.last_request_outcome = "building";
            current.publication_pair = None;
        }
        Self {
            state,
            captured: false,
            finished: false,
            enabled,
        }
    }
    pub(crate) fn capture(&mut self, frontend: &ColdFrontend) {
        if !self.enabled {
            return;
        }
        let snapshot = SourceSnapshot::capture(frontend);
        self.state
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .snapshot = Some(snapshot);
        self.captured = true;
    }
    pub(crate) fn capture_selected(
        &mut self,
        frontend: &ColdFrontend,
        current: &crate::selected_query::CurrentProcedureReferences,
    ) -> std::io::Result<()> {
        if !self.enabled {
            return Ok(());
        }
        frontend
            .body_input(current.occurrence())
            .map_err(|diagnostic| std::io::Error::other(diagnostic.message))?;
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        let snapshot = state.snapshot.as_mut().ok_or_else(|| {
            std::io::Error::other("selected capture lacks current source snapshot")
        })?;
        if !snapshot.matches_tree(&frontend.snapshot.tree)
            || !Arc::ptr_eq(&snapshot.occurrences, &frontend.snapshot.occurrences)
        {
            return Err(std::io::Error::other(
                "selected capture source snapshot mismatch",
            ));
        }
        snapshot.selected.capture(current);
        Ok(())
    }
    pub(crate) fn finish_published(&mut self, pair: &crate::publish::OutputPair) {
        self.finish(Some(pair.name()));
    }
    pub(crate) fn finish_analyzed(&mut self) {
        self.finish(None);
    }
    fn finish(&mut self, publication_pair: Option<String>) {
        let published = publication_pair.is_some();
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        state.publication_pair = publication_pair;
        state.last_request_outcome = if published { "published" } else { "analyzed" };
        if let Some(snapshot) = &mut state.snapshot {
            if self.captured {
                snapshot.outcome = if published { "published" } else { "analyzed" };
            }
        }
        if published && !self.captured {
            // Output-only replay does not issue a fresh source-query projection.
            state.snapshot = None;
        }
        self.finished = true;
    }
}
impl Drop for QueryAttempt {
    fn drop(&mut self) {
        if !self.finished {
            let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
            state.last_request_outcome = "failed";
            if self.captured {
                if let Some(snapshot) = &mut state.snapshot {
                    snapshot.outcome = "frontend_analyzed_build_failed";
                }
            }
        }
    }
}
