//! Current source query projection: shared issued occurrences, paths, and revision only.
//! Immutable issued source owners are shared; no full frontend revision is retained.
#[path = "runner_query_control_batch.rs"]
mod control_batch;
#[path = "runner_query_source_admission.rs"]
mod source_admission;
pub(crate) use source_admission::SourceFrameCapture;
#[path = "runner_query_named_policy.rs"]
mod named_policy;
#[path = "runner_query_native_policy.rs"]
mod native_policy;
#[path = "runner_query_occurrence_pages.rs"]
mod occurrence_pages;
#[cfg(test)]
#[path = "runner_query_policy_capture_tests.rs"]
mod policy_capture_tests;
#[path = "runner_query_raw_policy.rs"]
mod raw_policy;
#[path = "runner_query_resolved.rs"]
mod resolved;
#[path = "runner_query_selected.rs"]
mod selected;
#[path = "runner_query_variable_visibility.rs"]
mod variable_visibility;
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
    diagnostic_declarations:
        Option<Arc<dm_tree::diagnostic_declarations::DiagnosticDeclarationReceipt>>,
    semantic_sources: Option<Arc<crate::input_snapshot::SemanticSourceEvidence>>,
    tree: Arc<dm_tree::SemanticTree>,
    pub(crate) source_revision: u128,
    pub(crate) policy_revision: Option<u128>,
    pub(crate) outcome: &'static str,
    occurrences: Arc<dm_tree::OccurrenceTable>,
    /// Same immutable current producer owner; no parsed syntax or source arena.
    bodies: Option<Arc<[dm_tree::frontend::BodyOccurrence]>>,
    body_archive: Option<Arc<dm_tree::frontend::BodyArchive>>,
    native_policy_inputs: Option<Arc<crate::runner_host::policy_capture::CapturedPolicyInputs>>,
    native_workspace: Option<Arc<crate::runner_host::workspace_capture::WorkspaceCapture>>,
    source_mapping: Option<Arc<dm_tree::frontend::SourceExportMapping>>,
    paths: BTreeMap<dm_ir::FileId, Arc<PathBuf>>,
    selected: selected::SelectedRows,
    resolved: Option<resolved::ResolvedContext>,
    replay_proof: Option<ReplayProof>,
    native_schema_markers: Result<dm_analysis::value_schemas::Schemas, String>,
    native_value_input: Option<Arc<dm_analysis::value_query::ArchiveValueInput>>,
    native_value_queries: Option<Arc<dyn dm_analysis::value_query::ArchiveValueQueries>>,
    native_raw_queries: Option<Arc<crate::query_db::QueryDb>>,
}
struct ReplayProof {
    inputs: crate::input_snapshot::InputSnapshot,
    configuration: crate::session::Configuration,
    engine_bytes: Arc<[u8]>,
}
impl ReplayProof {
    fn admits(
        &self,
        inputs: &crate::input_snapshot::InputSnapshot,
        configuration: &crate::session::Configuration,
        engine_bytes: &[u8],
    ) -> bool {
        self.configuration == *configuration
            && self.engine_bytes.as_ref() == engine_bytes
            && self.inputs.same_recorded_facts(inputs)
    }
}
impl SourceSnapshot {
    /// Always run before semantic findings/proof/cache access. Source revisions
    /// and BodySyntax identities deliberately do not prove original decoding.
    pub(crate) fn require_semantic_source_encoding(&self) -> std::io::Result<()> {
        let evidence = self
            .semantic_sources
            .as_ref()
            .ok_or_else(|| std::io::Error::other("semantic source original encoding unproven"))?;
        let mapping = self
            .source_mapping
            .as_ref()
            .ok_or_else(|| std::io::Error::other("current semantic source mapping unavailable"))?;
        evidence.check(mapping)
    }
    /// Partial migration endpoint: findings only, never a model round-trip.
    pub(crate) fn write_native_checker(
        &self,
        ordinal: u32,
        severity: &str,
        tree: &dm_tree::SemanticTree,
        output: &mut impl std::io::Write,
    ) -> std::io::Result<()> {
        use dm_analysis::checks::Severity;
        use std::io;
        crate::daemon::control::checkpoint()?;
        self.require_semantic_source_encoding()?;
        let archive = self
            .body_archive
            .as_ref()
            .filter(|archive| archive.matches_tree(tree))
            .ok_or_else(|| {
                io::Error::new(io::ErrorKind::NotFound, "current body archive unavailable")
            })?;
        if ordinal as usize >= archive.len() {
            return Err(io::Error::other("body ordinal unavailable"));
        }
        let policy = match severity {
            "disabled" => Severity::Disabled,
            "warning" => Severity::Warning,
            "error" => Severity::Error,
            _ => return Err(io::Error::other("unknown native checker fixture policy")),
        };
        let mut rows = Vec::new();
        if policy != Severity::Disabled {
            let body = archive
                .parse(ordinal as usize)
                .map_err(|error| io::Error::other(error.message))?;
            let diagnostics = dm_analysis::checks::archived_ambiguous_not_bitwise(&body, policy)
                .map_err(io::Error::other)?;
            for diagnostic in diagnostics {
                crate::daemon::control::checkpoint()?;
                let origin = body
                    .location(diagnostic.span.start)
                    .ok_or_else(|| io::Error::other("checker origin unavailable"))?;
                let original = archive
                    .source_note_point(diagnostic.span.start)
                    .map_err(io::Error::other)?;
                rows.push(serde_json::json!({
                    "family": diagnostic.family, "severity": severity,
                    "expanded_span": [diagnostic.span.start, diagnostic.span.end],
                    "expression_span": [diagnostic.expression_span.start, diagnostic.expression_span.end],
                    "file": original.path, "line": original.line,
                    "include_occurrence": origin.include_occurrence,
                    "include_chain": origin.include_chain,
                    "message": diagnostic.message,
                    "notes": diagnostic.notes.iter().map(|note| note.legacy_text()).collect::<Vec<_>>(),
                }));
            }
        }
        serde_json::to_writer(
            &mut *output,
            &serde_json::json!({
                "row": "source_native_checker_fixture", "schema": "dm-session-source-query-v1",
                "source_revision": format!("{:032x}", self.source_revision),
                "semantic_revision": format!("{:032x}", tree.identity()),
                "ordinal": ordinal, "family": "ambiguous_not_bitwise", "policy": severity,
                "full_checker_parity": false, "diagnostics": rows,
            }),
        )
        .map_err(io::Error::other)?;
        output.write_all(b"\n")
    }

    /// Detach optional heavy source/selection owners under idle pressure.
    /// Existing request handles remain immutable; pinned lightweight rows survive.
    pub(crate) fn release_body_queries(&mut self) {
        if let Some(queries) = self.native_raw_queries.take() {
            queries.release_raw_policy_cache();
        }
        self.body_archive = None;
        self.native_policy_inputs = None;
        self.native_workspace = None;
        self.diagnostic_declarations = None;
        self.native_value_input = None;
        self.native_value_queries = None;
        self.resolved = None;
    }
    pub(super) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        // Only Arc handles are cloned for the common graph visitor. No source
        // rows, paths, metadata, or semantic payloads are materialized.
        census.snapshot(&dm_tree::TreeSnapshot {
            tree: Arc::clone(&self.tree),
            occurrences: Arc::clone(&self.occurrences),
        });
        if let Some(bodies) = &self.bodies {
            census.body_occurrences("query_snapshot.bodies", bodies);
        }
        if let Some(archive) = &self.body_archive {
            census.body_archive(archive);
        }
        if let Some(receipt) = &self.diagnostic_declarations {
            if census.arc_object("query_snapshot.diagnostic_receipt", receipt) {
                receipt.visit_error_storage(|address, logical, capacity| {
                    census.exposed_buffer(
                        "query_snapshot.diagnostic_receipt.errors",
                        address,
                        logical,
                        capacity,
                    );
                });
            }
        }
        if let Some(evidence) = &self.semantic_sources {
            census.semantic_source_evidence(evidence);
        }
        if let Some(queries) = &self.native_raw_queries {
            let stats = queries.raw_policy_cache_stats();
            census.unknown("query_snapshot.native_raw_query_cache",&format!(
                "{} nodes; input/params estimate {} bytes; derived estimate {} bytes; cache admission estimates only, private common source-view/config/result allocations not counted exactly",
                stats.nodes,stats.input_and_param_estimate,stats.derived_estimate));
        }
        if let Some(policy) = &self.native_policy_inputs {
            census.policy_capture(policy);
        }
        if let Some(workspace) = &self.native_workspace {
            workspace.census(census);
        }
        if let Some(mapping) = &self.source_mapping {
            census.source_export_mapping(mapping);
        }
        self.selected.census(census);
        if let Some(resolved) = &self.resolved {
            resolved.census(census);
        }
        match &self.native_schema_markers {
            Ok(schemas) => schemas.visit_storage(|entries| {
                census.collection_entries::<(
                    (dm_ir::SymbolId, dm_ir::SymbolId),
                    dm_analysis::value_schemas::Kind,
                )>(
                    "query_snapshot.native_schema_markers",
                    entries as *const _ as usize,
                    entries.len(),
                );
                for kind in entries.values() {
                    if let dm_analysis::value_schemas::Kind::Path(path) = kind {
                        census.string("query_snapshot.native_schema_markers", path);
                    }
                }
            }),
            Err(error) => census.string("query_snapshot.native_schema_markers.error", error),
        }
        if let Some(proof) = &self.replay_proof {
            census.policy_directory_facts(&proof.inputs);
            proof
                .inputs
                .visit_recorded_storage(|files, folders, negative, generated| {
                    census.collection_entries::<(PathBuf, crate::input_snapshot::FileInput)>(
                        "query_snapshot.replay_inputs.files",
                        files as *const _ as usize,
                        files.len(),
                    );
                    for (path, file) in files {
                        census.path("query_snapshot.replay_inputs.files", path);
                        census.path("query_snapshot.replay_inputs.files", &file.path);
                    }
                    census.collection_entries::<(PathBuf, crate::input_snapshot::FolderListing)>(
                        "query_snapshot.replay_inputs.folders",
                        folders as *const _ as usize,
                        folders.len(),
                    );
                    for (path, listing) in folders {
                        census.path("query_snapshot.replay_inputs.folders", path);
                        if let crate::input_snapshot::FolderListing::Present(names) = listing {
                            census.vec_payload("query_snapshot.replay_inputs.folders", names);
                            for name in names {
                                census.string("query_snapshot.replay_inputs.folders", name);
                            }
                        }
                    }
                    for (name, paths) in [
                        ("query_snapshot.replay_inputs.negative", negative),
                        ("query_snapshot.replay_inputs.generated", generated),
                    ] {
                        census.collection_entries::<PathBuf>(
                            name,
                            paths as *const _ as usize,
                            paths.len(),
                        );
                        for path in paths {
                            census.path(name, path);
                        }
                    }
                });
            census.slice("query_snapshot.replay_engine", &proof.engine_bytes, true);
            census.path(
                "query_snapshot.replay_config",
                &proof.configuration.worktree,
            );
            census.path(
                "query_snapshot.replay_config",
                &proof.configuration.manifest,
            );
            census.observe_items(
                "query_snapshot.replay_config.defines",
                proof.configuration.defines.len(),
            );
            census.unknown(
                "query_snapshot.replay_config.defines",
                "BTreeMap node backing is not exposed",
            );
            for (name, value) in &proof.configuration.defines {
                census.string("query_snapshot.replay_config.defines", name);
                census.string("query_snapshot.replay_config.defines", value);
            }
        }
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
        Self::capture_policy(frontend, None)
    }
    fn capture_policy(
        frontend: &ColdFrontend,
        policy: Option<Arc<crate::runner_host::policy_capture::CapturedPolicyInputs>>,
    ) -> Self {
        let revision_timer = dm_profile::detail_timer("query_capture.source_revision");
        let source_revision = dm_analysis::tree_export::source_revision(frontend);
        drop(revision_timer);
        let _timer = dm_profile::detail_timer("query_capture.rest");
        // The captured policy and body/value consumers share one issuance.
        // Do not create and immediately discard another archive or rescan the
        // compiled marker sources when a policy capture already supplies them.
        let body_archive = match &policy {
            Some(policy) => Some(Arc::clone(policy.policy().archive())),
            None => frontend.body_archive(),
        };
        let native_schema_markers = match &policy {
            Some(policy) => native_policy::capture_policy_schemas(policy.policy()),
            None => native_policy::capture_schemas(frontend),
        };
        let native_value_input = body_archive.as_ref().map(|archive| {
            dm_analysis::value_query::ArchiveValueInput::new(Arc::clone(archive), &[])
        });
        Self {
            diagnostic_declarations: None,
            semantic_sources: policy
                .as_ref()
                .map(|policy| Arc::clone(policy.semantic_source_evidence())),
            tree: Arc::clone(&frontend.snapshot.tree),
            source_revision,
            policy_revision: policy
                .as_ref()
                .and_then(|capture| capture.policy_revision()),
            outcome: "frontend_analyzed",
            source_mapping: frontend.source_export_mapping().cloned(),
            selected: Default::default(),
            resolved: None,
            replay_proof: None,
            native_schema_markers,
            native_value_input,
            native_value_queries: None,
            native_raw_queries: None,
            occurrences: Arc::clone(&frontend.snapshot.occurrences),
            body_archive,
            native_policy_inputs: policy,
            native_workspace: None,
            bodies: frontend
                .callable_roster()
                .ok()
                .map(|_| Arc::clone(&frontend.bodies)),
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
        if self.selected.contains(ordinal) {
            return self.selected.write(ordinal, self.source_revision, output);
        }
        let context = self.resolved.as_ref().ok_or_else(|| {
            std::io::Error::new(
                std::io::ErrorKind::NotFound,
                "current resolved host unavailable or evicted",
            )
        })?;
        let archive = self.body_archive.as_ref().ok_or_else(|| {
            std::io::Error::new(
                std::io::ErrorKind::NotFound,
                "current body archive unavailable or evicted",
            )
        })?;
        let current = context.query(archive, ordinal)?;
        selected::SelectedRows::write_current(&current, self.source_revision, output)
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
        if occurrence.provenance.expansion_stack.len() > 1024 {
            return Err(Error::new(
                ErrorKind::InvalidData,
                "source provenance exceeds bounded definition-origin depth",
            ));
        }
        let mapping = self.source_mapping.as_ref().ok_or_else(|| {
            Error::new(
                ErrorKind::NotFound,
                "current issued source mapping unavailable",
            )
        })?;
        let mut row = dm_analysis::tree_export::source_occurrence_row(
            tree,
            occurrence,
            ordinal,
            |file| {
                self.paths
                    .get(&file)
                    .map(|path| path.to_string_lossy().into_owned())
            },
            mapping.location(dm_tree::OccurrenceId(ordinal)),
        )
        .map_err(Error::other)?;
        let target_key = row["target"].take();
        row["target_key"] = target_key;
        row["target"] = target;
        row["schema"] = "dm-session-source-query-v1".into();
        row["row"] = "source_occurrence".into();
        row["source_revision"] = format!("{:032x}", self.source_revision).into();
        row["provenance_complete"] = false.into();
        Ok(row)
    }
}
pub(crate) struct QueryAttempt {
    state: Arc<Mutex<QueryState>>,
    captured: bool,
    enabled: bool,
    finished: bool,
    configuration: Option<crate::session::Configuration>,
    pending_diagnostic: Option<SourceSnapshot>,
    pending_source: Option<(SourceSnapshot, Arc<SourceFrameCapture>)>,
    pending_workspace: Option<(
        Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,
        Arc<crate::query_db::QueryDb>,
    )>,
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
            configuration: None,
            pending_workspace: None,
            pending_diagnostic: None,
            pending_source: None,
            enabled,
        }
    }
    pub(crate) fn pending_workspace(
        &self,
    ) -> Option<Arc<crate::runner_host::workspace_capture::WorkspaceCapture>> {
        self.pending_workspace
            .as_ref()
            .map(|(capture, _)| Arc::clone(capture))
    }
    pub(crate) fn admit_workspace_policy(
        &mut self,
        admission: crate::request_runner::runner_freshness::WorkspacePolicyAdmission,
    ) -> std::io::Result<()> {
        let (capture, queries) = self
            .pending_workspace
            .as_ref()
            .ok_or_else(|| std::io::Error::other("no staged workspace frame"))?;
        if !Arc::ptr_eq(capture, admission.capture()) {
            return Err(std::io::Error::other(
                "workspace admission belongs to another capture",
            ));
        }
        crate::daemon::control::checkpoint()?;
        let (snapshot, frame) = self
            .pending_source
            .as_mut()
            .ok_or_else(|| std::io::Error::other("workspace source frame unavailable"))?;
        frame.require_snapshot(snapshot)?;
        let mapping = snapshot
            .source_mapping
            .as_ref()
            .ok_or_else(|| std::io::Error::other("workspace source map unavailable"))?;
        if !capture.matches_source(mapping, snapshot.source_revision)
            || snapshot
                .native_raw_queries
                .as_ref()
                .is_none_or(|current| !Arc::ptr_eq(current, queries))
        {
            return Err(std::io::Error::other(
                "workspace admission source/Db frame differs",
            ));
        }
        snapshot.policy_revision = Some(capture.policy_revision());
        snapshot.native_workspace = Some(Arc::clone(capture));
        let (snapshot, _) = self
            .pending_source
            .take()
            .expect("validated staged workspace");
        self.state
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .snapshot = Some(snapshot);
        self.captured = true;
        self.pending_workspace = None;
        Ok(())
    }
    pub(crate) fn capture_with_workspace_recorded_sources<
        P: crate::input_snapshot::SnapshotProvider,
    >(
        &mut self,
        frontend: &ColdFrontend,
        queries: Arc<crate::query_db::QueryDb>,
        workspace: Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,
        request: &crate::policy_request::WorkspacePolicyRequest,
        inputs: &crate::input_snapshot::RecordingInputs<P>,
    ) -> std::io::Result<()> {
        if !workspace.matches_frontend(frontend)
            || !workspace.matches_request(request)
            || !workspace.is_recorded_in(&inputs.snapshot()?)
        {
            return Err(std::io::Error::other(
                "workspace policy capture differs from current original request",
            ));
        }
        if !self.enabled {
            return Ok(());
        }
        let evidence = inputs.semantic_source_evidence(frontend)?;
        let mut snapshot = SourceSnapshot::capture(frontend);
        let mapping = snapshot
            .source_mapping
            .as_ref()
            .ok_or_else(|| std::io::Error::other("workspace source mapping unavailable"))?;
        // Raw policy needs original byte ownership, not semantic UTF8. A later
        // AST question must still independently check evidence.check(mapping).
        evidence.require_mapping(mapping)?;
        snapshot.semantic_sources = Some(evidence);
        self.pending_workspace = Some((workspace, Arc::clone(&queries)));
        snapshot.native_raw_queries = Some(Arc::clone(&queries));
        snapshot.native_value_queries = Some(queries);
        self.pending_diagnostic = None;
        self.stage_source_snapshot(snapshot, inputs.snapshot()?)?;
        Ok(())
    }
    pub(crate) fn capture_with_recorded_sources<P: crate::input_snapshot::SnapshotProvider>(
        &mut self,
        frontend: &ColdFrontend,
        queries: Arc<crate::query_db::QueryDb>,
        policy: Option<Arc<crate::runner_host::policy_capture::CapturedPolicyInputs>>,
        inputs: &crate::input_snapshot::RecordingInputs<P>,
    ) -> std::io::Result<()> {
        self.pending_workspace = None;
        self.pending_diagnostic = None;
        self.pending_source = None;
        if !self.enabled {
            return Ok(());
        }
        if policy.as_ref().is_some_and(|policy| {
            policy.policy_revision().is_none() || !policy.policy().matches_frontend(frontend)
        }) {
            return Err(std::io::Error::other(
                "recorded policy differs from current bound compiler issuance",
            ));
        }
        let evidence = inputs.semantic_source_evidence(frontend)?;
        let mut snapshot = SourceSnapshot::capture_policy(frontend, policy);
        let mapping = snapshot
            .source_mapping
            .as_ref()
            .ok_or_else(|| std::io::Error::other("semantic source mapping unavailable"))?;
        // This binds original bytes even when a later semantic AST query must
        // decline incompatible encoding. Raw policy/Compile remain meaningful.
        evidence.require_mapping(mapping)?;
        snapshot.semantic_sources = Some(evidence);
        snapshot.native_raw_queries = Some(Arc::clone(&queries));
        snapshot.native_value_queries = Some(queries);
        self.stage_source_snapshot(snapshot, inputs.snapshot()?)
    }
    // Deliberate fixture scaffolding: production publication always stages and
    // consumes the existing complete captured-input freshness receipt.
    #[cfg(test)]
    pub(crate) fn capture_with_queries(
        &mut self,
        frontend: &ColdFrontend,
        queries: Arc<crate::query_db::QueryDb>,
        policy: Option<Arc<crate::runner_host::policy_capture::CapturedPolicyInputs>>,
    ) -> std::io::Result<()> {
        self.pending_source = None;
        self.pending_workspace = None;
        self.pending_diagnostic = None;
        if policy
            .as_ref()
            .is_some_and(|policy| policy.policy_revision().is_none())
        {
            return Err(std::io::Error::other(
                "raw policy capture has no admitted request binding",
            ));
        }
        if !self.enabled {
            return Ok(());
        }
        if let Some(policy) = &policy {
            if !policy.policy().matches_frontend(frontend) {
                return Err(std::io::Error::other(
                    "raw policy capture differs from current compiler issuance",
                ));
            }
        }
        let mut snapshot = SourceSnapshot::capture_policy(frontend, policy);
        snapshot.native_raw_queries = Some(Arc::clone(&queries));
        snapshot.native_value_queries = Some(queries);
        self.state
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .snapshot = Some(snapshot);
        self.captured = true;
        Ok(())
    }
    #[cfg(test)]
    pub(crate) fn capture(&mut self, frontend: &ColdFrontend) {
        self.pending_source = None;
        self.pending_workspace = None;
        self.pending_diagnostic = None;
        if !self.enabled {
            return;
        }
        let snapshot = SourceSnapshot::capture(frontend);
        let _timer = dm_profile::detail_timer("query_capture.replace");
        self.state
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .snapshot = Some(snapshot);
        self.captured = true;
    }
    pub(crate) fn capture_resolved_host(
        &mut self,
        frontend: &ColdFrontend,
        resolver: resolved::CapturedResolver,
        abi: Arc<crate::driver_facts::PreparedAbiUnits>,
        startup: Arc<crate::startup::StartupFacts>,
    ) -> std::io::Result<()> {
        if !self.enabled {
            return Ok(());
        }
        self.capture_resolved_context(
            frontend,
            resolved::ResolvedContext::new(resolver, abi, startup),
        )
    }
    pub(crate) fn capture_analysis_host(
        &mut self,
        frontend: &ColdFrontend,
        resolver: resolved::ScalarResolver,
        abi: Arc<crate::driver_facts::PreparedAbiUnits>,
        startup: Arc<crate::startup::StartupFacts>,
    ) -> std::io::Result<()> {
        if !self.enabled {
            return Ok(());
        }
        self.capture_resolved_context(
            frontend,
            resolved::ResolvedContext::for_analysis(resolver, abi, startup),
        )
    }
    fn capture_resolved_context(
        &mut self,
        frontend: &ColdFrontend,
        context: resolved::ResolvedContext,
    ) -> std::io::Result<()> {
        if !self.enabled {
            return Ok(());
        }
        self.with_current_source(|snapshot| {
            if !snapshot.matches_tree(&frontend.snapshot.tree) {
                return Err(std::io::Error::other(
                    "current resolved capture differs from query source",
                ));
            }
            if !Arc::ptr_eq(&snapshot.occurrences, &frontend.snapshot.occurrences)
                || snapshot
                    .bodies
                    .as_ref()
                    .is_none_or(|bodies| !Arc::ptr_eq(bodies, &frontend.bodies))
                || !context.matches_current(frontend)
            {
                return Err(std::io::Error::other(
                    "resolved capture current source owners differ",
                ));
            }
            snapshot.resolved = Some(context);
            Ok(())
        })
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
        self.with_current_source(|snapshot| {
            if !snapshot.matches_tree(&frontend.snapshot.tree)
                || !Arc::ptr_eq(&snapshot.occurrences, &frontend.snapshot.occurrences)
            {
                return Err(std::io::Error::other(
                    "selected capture source snapshot mismatch",
                ));
            }
            snapshot.selected.capture(current);
            Ok(())
        })
    }
    /// Issued only after this captured frontend's successful publication inputs
    /// passed the same post-publication restat used for the session record.
    pub(crate) fn policy_revision(&self) -> Option<u128> {
        if self.pending_source.is_some() || self.pending_diagnostic.is_some() {
            return None;
        }
        self.state
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .snapshot
            .as_ref()
            .and_then(|snapshot| snapshot.policy_revision)
    }
    pub(crate) fn configure(&mut self, configuration: crate::session::Configuration) {
        self.configuration = Some(configuration);
    }
    pub(crate) fn bind_publication_proof(
        &mut self,
        inputs: &crate::input_snapshot::InputSnapshot,
        engine_bytes: &Arc<[u8]>,
    ) {
        if !self.enabled || !self.captured {
            return;
        }
        let Some(configuration) = &self.configuration else {
            return;
        };
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        if let Some(snapshot) = &mut state.snapshot {
            // Resources may extend this request ledger, but cannot omit policy
            // absence/folder facts. Text revision equality is not replay proof.
            if snapshot
                .native_workspace
                .as_ref()
                .is_some_and(|capture| !capture.is_recorded_in(inputs))
            {
                snapshot.replay_proof = None;
                crate::daemon_eprintln!("native workspace replay proof refused: capture facts absent from completed ledger");
                return;
            }
            if snapshot
                .native_policy_inputs
                .as_ref()
                .is_some_and(|policy| !policy.is_recorded_in(inputs))
            {
                snapshot.replay_proof = None;
                crate::daemon_eprintln!("native policy replay proof refused: captured facts absent from completed ledger");
                return;
            }
            snapshot.replay_proof = Some(ReplayProof {
                inputs: inputs.clone(),
                configuration: configuration.clone(),
                engine_bytes: Arc::clone(engine_bytes),
            });
        }
    }
    /// The caller has already authenticated these current session inputs and
    /// engine bytes. Neither pair identity nor a source revision hash is proof.
    pub(crate) fn admit_published_replay(
        &mut self,
        inputs: &crate::input_snapshot::InputSnapshot,
        engine_bytes: &[u8],
        current_tree: Option<&Arc<dm_tree::SemanticTree>>,
    ) -> bool {
        if !self.enabled {
            return false;
        }
        let Some(configuration) = &self.configuration else {
            return false;
        };
        let state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        let admitted = state.snapshot.as_ref().is_some_and(|snapshot| {
            current_tree.is_some_and(|tree| Arc::ptr_eq(tree, &snapshot.tree))
                && snapshot
                    .replay_proof
                    .as_ref()
                    .is_some_and(|proof| proof.admits(inputs, configuration, engine_bytes))
        });
        self.captured = admitted;
        admitted
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
                    // Pending workspace owners never enter this snapshot.
                    // A previously freshness-admitted frontend policy may stay
                    // valid when only later backend/publication work failed.
                }
            }
        }
    }
}

#[cfg(test)]
#[path = "runner_query_body_context_tests.rs"]
mod body_context_tests;

impl SourceSnapshot {
    pub(crate) fn write_body_model(
        &self,
        ordinal: u32,
        tree: &dm_tree::SemanticTree,
        output: &mut impl std::io::Write,
    ) -> std::io::Result<()> {
        use std::io::{self, Write};
        crate::daemon::control::checkpoint()?;
        let archive = self
            .body_archive
            .as_ref()
            .filter(|archive| archive.matches_tree(tree))
            .ok_or_else(|| {
                io::Error::new(io::ErrorKind::NotFound, "current body archive unavailable")
            })?;
        let body = archive
            .parse(ordinal as usize)
            .map_err(|error| io::Error::other(error.message))?;
        crate::daemon::control::checkpoint()?;
        struct Bounded(Vec<u8>);
        impl Write for Bounded {
            fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
                crate::daemon::control::checkpoint()?;
                if self.0.len().saturating_add(bytes.len()) > 192 * 1024 {
                    return Err(io::Error::other("body model query exceeds output budget"));
                }
                self.0.extend_from_slice(bytes);
                Ok(bytes.len())
            }
            fn flush(&mut self) -> io::Result<()> {
                Ok(())
            }
        }
        let mut syntax = Bounded(Vec::new());
        dm_analysis::typed_body_jsonl::write_archived_jsonl(&body, &mut syntax)
            .map_err(io::Error::other)?;
        let lexical = dm_analysis::typed_body::lexical::analyze_archived(&body, None)
            .map_err(io::Error::other)?;
        let mut bindings = Bounded(Vec::new());
        dm_analysis::typed_body::lexical::jsonl::write_jsonl(&lexical, &mut bindings)
            .map_err(io::Error::other)?;
        serde_json::to_writer(&mut *output, &serde_json::json!({
            "row":"source_body_model", "schema":"dm-session-source-query-v1",
            "source_revision":format!("{:032x}",self.source_revision), "ordinal":ordinal,
            "member":body.occurrence().member.0,"declaration":body.occurrence().declaration.0,
            "typed_jsonl":String::from_utf8(syntax.0).map_err(io::Error::other)?,
            "lexical_jsonl":String::from_utf8(bindings.0).map_err(io::Error::other)?,
            "semantic_resolution_complete":false,
            "coverage":"current typed syntax and lexical bindings; nonlocal resolved selections require compiler host facts"
        })).map_err(io::Error::other)?;
        output.write_all(b"\n")
    }
}

#[path = "runner_query_analyze_policy.rs"]
mod analyze_policy;

#[cfg(test)]
#[path = "runner_query_semantic_admission_tests.rs"]
mod semantic_admission_tests;

impl SourceSnapshot {
    pub(crate) fn write_resolved_queries(
        &self,
        queries: &[crate::daemon::query::QueryItem],
        tree: &dm_tree::SemanticTree,
        output: &mut impl std::io::Write,
    ) -> std::io::Result<()> {
        use std::io::{self, Write};
        if !self.matches_tree(tree) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "current compiler host tree differs",
            ));
        }
        let context = self.resolved.as_ref().ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::NotFound,
                "current compiler resolver unavailable or pressure-evicted",
            )
        })?;
        struct Bounded(Vec<u8>);
        impl Write for Bounded {
            fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
                crate::daemon::control::checkpoint()?;
                if bytes.len() > (192usize * 1024).saturating_sub(self.0.len()) {
                    return Err(io::Error::other("resolved query rows exceed output budget"));
                }
                self.0.extend_from_slice(bytes);
                Ok(bytes.len())
            }
            fn flush(&mut self) -> io::Result<()> {
                Ok(())
            }
        }
        let mut rows = Bounded(Vec::new());
        context.write_queries(queries, &mut rows)?;
        serde_json::to_writer(&mut *output, &serde_json::json!({
            "row":"source_resolved_queries", "schema":"dm-session-source-query-v1",
            "source_revision":format!("{:032x}",self.source_revision),
            "semantic_revision":format!("{:032x}",tree.identity()), "complete":false,
            "query_count":queries.len(), "captured_jsonl":String::from_utf8(rows.0).map_err(io::Error::other)?
        })).map_err(io::Error::other)?;
        output.write_all(b"\n")
    }
}

#[cfg(test)]
#[path = "runner_query_acquisition_release_tests.rs"]
mod acquisition_release_tests;

#[path = "runner_query_workspace_native_guard.rs"]
pub(crate) mod workspace_native_guard;
#[cfg(test)]
#[path = "runner_query_workspace_raw_tests.rs"]
mod workspace_raw_tests;

#[path = "runner_query_workspace_policy.rs"]
mod workspace_policy;

impl SourceSnapshot {
    fn capture_diagnostic(
        frontend: &dm_tree::frontend::DiagnosticSourceView<'_>,
        queries: Arc<crate::query_db::QueryDb>,
        policy: Arc<crate::runner_host::policy_capture::CapturedPolicyInputs>,
    ) -> std::io::Result<Self> {
        let archive = frontend.archive();
        if !frontend.receipt().authenticates(frontend.tree())
            || !Arc::ptr_eq(archive, policy.policy().archive())
            || policy.policy_revision().is_none()
            || !archive.uses_body_queries(queries.as_ref())
        {
            return Err(std::io::Error::other(
                "diagnostic original graph/policy/Db issuance differs",
            ));
        }
        policy
            .semantic_source_evidence()
            .check(frontend.mapping())?;
        Ok(Self {
            diagnostic_declarations: Some(Arc::clone(frontend.receipt())),
            semantic_sources: Some(Arc::clone(policy.semantic_source_evidence())),
            tree: Arc::clone(frontend.tree()),
            source_revision: frontend.source_revision(),
            policy_revision: policy.policy_revision(),
            outcome: "diagnostic_frontend_admitted",
            occurrences: Arc::clone(frontend.occurrences()),
            bodies: Some(Arc::clone(frontend.bodies())),
            body_archive: Some(Arc::clone(archive)),
            native_policy_inputs: Some(policy),
            native_workspace: None,
            source_mapping: Some(Arc::clone(frontend.mapping())),
            paths: frontend
                .files()
                .iter()
                .map(|file| (file.id, Arc::clone(&file.path)))
                .collect(),
            selected: Default::default(),
            resolved: None,
            replay_proof: None,
            native_schema_markers: Err(
                "diagnostic-only source has no runtime value-schema admission".into(),
            ),
            native_value_input: None,
            native_value_queries: None,
            native_raw_queries: Some(queries),
        })
    }
    /// Only the current published diagnostic frame supplies this owner; no
    /// equal-hash sibling or old executable patch-base tree is substituted.
    /// Choose the exact current prepared original owner. A valid consuming
    /// diagnostic-to-ordinary transfer need not rebuild RetainedSemanticTree's
    /// older executable patch-base entry merely to serve read-only queries.
    pub(crate) fn prepared_query_tree(&self) -> Option<&Arc<dm_tree::SemanticTree>> {
        if let Some(tree) = self.diagnostic_tree() {
            return Some(tree);
        }
        self.resolved.as_ref()?.checker_resolver(&self.tree).ok()?;
        Some(&self.tree)
    }
    pub(crate) fn diagnostic_tree(&self) -> Option<&Arc<dm_tree::SemanticTree>> {
        self.diagnostic_declarations
            .as_ref()
            .filter(|receipt| receipt.authenticates(&self.tree))
            .map(|_| &self.tree)
    }
}
impl QueryAttempt {
    pub(crate) fn stage_diagnostic(
        &mut self,
        frontend: &dm_tree::frontend::DiagnosticSourceView<'_>,
        queries: Arc<crate::query_db::QueryDb>,
        policy: Arc<crate::runner_host::policy_capture::CapturedPolicyInputs>,
    ) -> std::io::Result<()> {
        if !self.enabled {
            return Err(std::io::Error::other(
                "diagnostic queries require the existing query owner",
            ));
        }
        self.pending_source = None;
        self.pending_workspace = None;
        self.pending_diagnostic = Some(SourceSnapshot::capture_diagnostic(
            frontend, queries, policy,
        )?);
        Ok(())
    }
    pub(crate) fn pending_diagnostic_policy(
        &self,
    ) -> Option<Arc<crate::runner_host::policy_capture::CapturedPolicyInputs>> {
        self.pending_diagnostic
            .as_ref()
            .and_then(|snapshot| snapshot.native_policy_inputs.as_ref().map(Arc::clone))
    }
    pub(crate) fn admit_diagnostic_policy(
        &mut self,
        admission: crate::request_runner::runner_freshness::DiagnosticPolicyAdmission,
    ) -> std::io::Result<()> {
        let snapshot = self
            .pending_diagnostic
            .as_ref()
            .ok_or_else(|| std::io::Error::other("no staged diagnostic original frame"))?;
        let policy = snapshot
            .native_policy_inputs
            .as_ref()
            .ok_or_else(|| std::io::Error::other("staged diagnostic capture missing"))?;
        if !Arc::ptr_eq(policy, admission.capture())
            || snapshot.diagnostic_tree().is_none()
            || !snapshot.body_archive.as_ref().is_some_and(|archive| {
                snapshot
                    .native_raw_queries
                    .as_ref()
                    .is_some_and(|db| archive.uses_body_queries(db.as_ref()))
            })
        {
            return Err(std::io::Error::other(
                "diagnostic freshness proof belongs to another original frame",
            ));
        }
        snapshot.require_semantic_source_encoding()?;
        let snapshot = self
            .pending_diagnostic
            .take()
            .expect("validated staged original");
        self.state
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .snapshot = Some(snapshot);
        self.captured = true;
        Ok(())
    }
}

#[cfg(test)]
#[path = "runner_query_diagnostic_tests.rs"]
mod diagnostic_tests;
