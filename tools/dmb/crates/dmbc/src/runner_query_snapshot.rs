//! Current source query projection: shared issued occurrences, paths, and revision only.
//! Immutable issued source owners are shared; no full frontend revision is retained.
#[path = "runner_query_control_batch.rs"]
mod control_batch;
#[path = "runner_query_source_admission.rs"]
mod source_admission;
pub(crate) use source_admission::{SourceAnswerPublication, SourceAnswersMode, SourceFrameCapture};
#[path = "runner_query_named_policy.rs"]
mod named_policy;
#[path = "runner_query_native_policy.rs"]
mod native_policy;
#[path = "runner_query_occurrence_pages.rs"]
mod occurrence_pages;
#[cfg(test)]
#[path = "runner_query_policy_capture_tests.rs"]
mod policy_capture_tests;
#[path = "runner_query_purity.rs"]
mod purity;
#[path = "runner_query_raw_policy.rs"]
mod raw_policy;
#[path = "runner_query_resolved.rs"]
mod resolved;
#[path = "runner_query_selected.rs"]
mod selected;
#[path = "runner_query_source_context.rs"]
mod source_context;
#[path = "runner_query_variable_visibility.rs"]
mod variable_visibility;
// Keep actual operation status out of diagnostic/string adapters. A genuine
// parser rejection keeps its original location owner and legacy Other kind.
fn body_syntax_io(error: dm_tree::frontend::BodySyntaxFailure) -> std::io::Error {
    match error {
        dm_tree::frontend::BodySyntaxFailure::Operational(error) => error,
        error @ dm_tree::frontend::BodySyntaxFailure::Syntax(_) => std::io::Error::other(error),
    }
}
use dm_tree::frontend::ColdFrontend;
pub(crate) use purity::PurityScope;
use std::{
    collections::BTreeMap,
    path::PathBuf,
    sync::{Arc, Mutex},
};
#[path="runner_query_raw_workspace.rs"]mod raw_workspace;
pub(crate) use raw_workspace::RawWorkspaceSnapshot;
#[path="runner_query_handlers.rs"]mod handlers;
pub(crate) use handlers::HandlerWorkspaceSnapshot;
#[cfg(test)]
impl SourceSnapshot {
    pub(crate) fn original_body_census_archive(&self) -> std::io::Result<&dm_tree::frontend::BodyArchive> {
        self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalChecker0290))?;
        let archive = self.body_archive.as_deref().ok_or_else(|| std::io::Error::other("actual Original BODY archive missing"))?;
        if !archive.matches_tree(&self.tree)
            || !self.source_mapping.as_ref().is_some_and(|mapping| Arc::ptr_eq(mapping, archive.source_mapping()))
        {
            return Err(std::io::Error::other("census archive differs from actual captured tree and source mapping"));
        }
        Ok(archive)
    }
}

pub(crate) struct QueryState {
    pub(crate) raw_snapshot:Option<RawWorkspaceSnapshot>,
    pub(crate) handlers_snapshot:Option<HandlerWorkspaceSnapshot>,
    pub(crate) snapshot: Option<SourceSnapshot>,
    pub(crate) last_request_outcome: &'static str,
    pub(crate) publication_pair: Option<String>,
}
impl Default for QueryState {
    fn default() -> Self {
        Self {
            snapshot: None,raw_snapshot:None,handlers_snapshot:None,
            last_request_outcome: "never_started",
            publication_pair: None,
        }
    }
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum SnapshotPolicyRole { ExplicitSubset, WorkspaceGeneratorChild, WorkspaceSemanticChild }
#[derive(Clone, Copy)]
enum WorkspaceSnapshotRole<'a> { RawPolicy, Generator(&'a crate::policy_request::AdmittedPolicyRequest) }
#[derive(Clone, Copy, PartialEq, Eq)]
struct WorkspaceGeneratorSelection{names:[Option<crate::GeneratorName>;13]}
impl WorkspaceGeneratorSelection{
 fn from_admitted(intent:&crate::policy_request::AdmittedPolicyRequest,workspace:&crate::runner_host::workspace_capture::WorkspaceCapture)->std::io::Result<Self>{
  if intent.workspace().is_none_or(|request|!workspace.matches_request(request))||intent.workspace_generators().is_empty()||intent.workspace_generators().len()>13{return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"generator intent differs from actual workspace request"))}
  let mut selected=Self{names:[None;13]};for(slot,name)in selected.names.iter_mut().zip(intent.workspace_generators()){*slot=Some(*name);}Ok(selected)
 }
 fn permits(&self,name:crate::GeneratorName)->bool{self.names.iter().flatten().any(|candidate|*candidate==name)}
}
#[derive(Clone,Copy,PartialEq,Eq)]
struct WorkspaceSemanticSelection{names:[Option<crate::policy_request::WorkspaceAuxiliaryQuestion>;crate::policy_request::WorkspaceAuxiliaryQuestion::SEMANTIC.len()]}
impl WorkspaceSemanticSelection{
 fn from_admitted(intent:&crate::policy_request::AdmittedPolicyRequest,workspace:&crate::runner_host::workspace_capture::WorkspaceCapture)->std::io::Result<Option<Self>>{
  use crate::policy_request::AnalysisContext;
  if intent.workspace().is_none_or(|request|!workspace.matches_request(request))||!workspace.matches_auxiliary_questions(intent.workspace_auxiliary()){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"semantic intent differs from actual workspace request"))}
  let mut selected=Self{names:[None;crate::policy_request::WorkspaceAuxiliaryQuestion::SEMANTIC.len()]};let mut count=0;for name in intent.workspace_auxiliary().iter().copied().filter(|name|name.is_semantic()){if intent.analysis_context().is_none()||count==selected.names.len(){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"semantic selection has no issued original context"))}selected.names[count]=Some(name);count+=1;}Ok((count!=0).then_some(selected))
 }
 fn permits(&self,name:crate::policy_request::WorkspaceAuxiliaryQuestion)->bool{name.is_semantic()&&self.names.iter().flatten().any(|candidate|*candidate==name)}
}
enum OriginalNoticeReplay{Ordinary,Retained(dm_tree::frontend::OriginalPreprocessNoticeOwner),Released}
pub(crate) struct SourceSnapshot {
    original_notice_replay:OriginalNoticeReplay,
    model_preparation:Option<dm_tree::frontend::DiagnosticPreparationPurpose>,
    analysis_subject:Option<Arc<crate::input_snapshot::OriginalAnalysisSubject>>,
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
    image_dir_proof: Option<dm_tree::frontend::CleanOriginalImageDirProof>,
    body_archive: Option<Arc<dm_tree::frontend::BodyArchive>>,
    native_policy_inputs: Option<Arc<crate::runner_host::policy_capture::CapturedPolicyInputs>>,
    policy_role: SnapshotPolicyRole,
    workspace_generator_selection: Option<WorkspaceGeneratorSelection>,
    workspace_semantic_selection: Option<WorkspaceSemanticSelection>,
    native_workspace: Option<Arc<crate::runner_host::workspace_capture::WorkspaceCapture>>,
    generation_inputs: Option<crate::request_runner::runner_freshness::GenerationInputClosure>,
    source_mapping: Option<Arc<dm_tree::frontend::SourceExportMapping>>,
    paths: BTreeMap<dm_ir::FileId, Arc<PathBuf>>,
    selected: selected::SelectedRows,
    resolved: Option<resolved::ResolvedContext>,
    replay_proof: Option<ReplayProof>,
    native_schema_markers: Result<dm_analysis::value_schemas::Schemas, String>,
    native_value_input: Option<Arc<dm_analysis::value_query::ArchiveValueInput>>,
    native_value_queries: Option<Arc<dyn dm_analysis::value_query::ArchiveValueQueries>>,
    native_raw_queries: Option<Arc<crate::query_db::QueryDb>>,
    native_effect_request_input: std::sync::OnceLock<purity::EffectRequestInput>,
    source_answers: Option<crate::query_db::SourceAnswerScopeOwner>,
    source_question_role: bool,
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
    pub(crate) fn matches_original_analysis_subject(&self,path:&std::path::Path)->bool{self.analysis_subject.as_ref().is_some_and(|subject|subject.matches_request_project(path))}
    pub(crate) fn require_analysis_context(&self,context:Option<crate::policy_request::AnalysisContext>)->std::io::Result<()> {
        use dm_tree::frontend::DiagnosticPreparationPurpose as P;
        let analyze=context==Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290);
        if analyze&&!matches!(self.model_preparation,Some(P::OriginalSharedComplete|P::OriginalAnalyzePrefix))||!analyze&&self.model_preparation==Some(P::OriginalAnalyzePrefix){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"query role differs from actual complete/prefix native preparation"))}

        if context==Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290){let subject=self.analysis_subject.as_ref().ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidInput,"query lacks actual full Analyze subject receipt"))?;subject.require_bound_mapping(self.source_mapping.as_ref().ok_or_else(||std::io::Error::other("analysis subject mapping absent"))?)?;}
        let expected=context.map_or(dm_preprocess::InitialEnvironment::Native5161687,|context|context.initial_environment());
        if self.source_mapping.as_ref().map(|mapping|mapping.initial_environment()).is_some_and(|actual|actual!=expected) || (context.is_some()&&self.source_mapping.is_none()){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"query analysis context differs from its actual current source mapping"))}Ok(())
    }
    /// A diagnostic-only analysis frame can lend its separately completed
    /// workspace source capture to these exact source report operations. This
    /// does not admit ordinary compiler/ABI/model questions; each report still
    /// authenticates its actual capture, source guard, QueryDb and typed EOF.
    pub(crate) fn admits_original_analysis_workspace_question(&self,question:&crate::daemon::query::SourceQuery)->bool {
        self.native_workspace.is_some()
            && self.source_mapping.as_ref().is_some_and(|mapping|mapping.initial_environment()==dm_preprocess::InitialEnvironment::OriginalChecker0290)
            && matches!(question,crate::daemon::query::SourceQuery::NativeWorkspaceRawReportPage{..}|crate::daemon::query::SourceQuery::NativeWorkspaceHygieneReportPage{..}|crate::daemon::query::SourceQuery::NativeWorkspaceSysReportPage{..}|crate::daemon::query::SourceQuery::NativeWorkspaceSemanticReportPage{..}|crate::daemon::query::SourceQuery::NativeWorkspaceRawTreeReportPage{..}|crate::daemon::query::SourceQuery::NativeWorkspacePolicyReportPage{..}|crate::daemon::query::SourceQuery::NativeWorkspaceKeysReportPage{..}|crate::daemon::query::SourceQuery::NativeDeadlinePollingEvidence{..}|crate::daemon::query::SourceQuery::NativeWorkspaceCheckGrepReportPage{..}|crate::daemon::query::SourceQuery::NativeWorkspaceCheckGrepBaselineReportPage{..})
    }
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
    /// Narrow source structural family on the compiler's original Answers table.
    /// Every request checks exact source/profile/binding before ANY cached read.
    pub(crate) fn source_answer_hash(
        &self,
        tree: &dm_tree::SemanticTree,
        question: dm_ir::ResolveQuery,
    ) -> std::io::Result<u128> {
        if !std::ptr::eq(tree, self.tree.as_ref()) {
            return Err(std::io::Error::other("source Answers tree is foreign"));
        }
        let scope = self
            .source_answers
            .as_ref()
            .ok_or(std::io::ErrorKind::Unsupported)?;
        self.require_semantic_source_encoding()?;
        let queries = self
            .native_raw_queries
            .as_ref()
            .ok_or_else(|| std::io::Error::other("source Answers compiler Db unavailable"))?;
        queries.source_answer_hash(
            scope,
            tree,
            self.source_mapping
                .as_deref()
                .ok_or_else(|| std::io::Error::other("source Answers map unavailable"))?,
            self.body_archive
                .as_deref()
                .ok_or_else(|| std::io::Error::other("source Answers archive unavailable"))?,
            question,
        )
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
                .parse_checked(ordinal as usize)
                .map_err(body_syntax_io)?;
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
        if matches!(self.original_notice_replay,OriginalNoticeReplay::Retained(_)){self.original_notice_replay=OriginalNoticeReplay::Released;}
        drop(self.native_effect_request_input.take());
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
        if let Some(scope) = &self.source_answers {
            scope.census(census);
        }
        if let Some(input)=self.native_effect_request_input.get(){input.census(census);}
        if let Some(queries) = &self.native_raw_queries {
            queries.purity_census(census);
            queries.value_rejection_census(census);
            queries.answer_storage_census(census);
            let stats = queries.raw_policy_cache_stats();
            census.unknown("query_snapshot.native_raw_query_cache",&format!(
                "{} nodes; input/params estimate {} bytes; derived estimate {} bytes; cache admission estimates only, private common source-view/config/result allocations not counted exactly",
                stats.nodes,stats.input_and_param_estimate,stats.derived_estimate));
        }
        if let OriginalNoticeReplay::Retained(owner)=&self.original_notice_replay{
            use dm_tree::frontend::OriginalPreprocessNoticeStorage as N;use dm_preprocess::regions::OriginalDiagnosticStorage as S;
            owner.visit_storage(|row|match row{
                N::Metadata(S::Owner{address,bytes})=>{census.exposed_buffer("query_snapshot.original_notices.owner",address,bytes,bytes);},
                N::Metadata(S::Buffer{address,logical,capacity})=>{census.exposed_buffer("query_snapshot.original_notices.buffer",address,logical,capacity);},
                N::Metadata(S::Opaque(reason))=>census.unknown("query_snapshot.original_notices",reason),
                N::Mapping(mapping)=>census.source_export_mapping(mapping),N::Acquisition(source)=>census.source_acquisition(source),N::Path(path)=>census.arc_path("query_snapshot.original_notices.path",path),

            });
        }
        if let Some(subject)=&self.analysis_subject{subject.census(census);}
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
        Self::capture_policy_role(frontend, policy, SnapshotPolicyRole::ExplicitSubset)
    }
    fn capture_policy_role(
        frontend: &ColdFrontend,
        policy: Option<Arc<crate::runner_host::policy_capture::CapturedPolicyInputs>>,
        role: SnapshotPolicyRole,
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
            Some(policy) if matches!(role, SnapshotPolicyRole::ExplicitSubset) => native_policy::capture_policy_schemas(policy.policy()),
            Some(_) => native_policy::capture_schemas(frontend),
            None => native_policy::capture_schemas(frontend),
        };
        let native_value_input = body_archive.as_ref().map(|archive| {
            dm_analysis::value_query::ArchiveValueInput::new(Arc::clone(archive), &[])
        });
        Self {
            analysis_subject:None,
            diagnostic_declarations: None,
            image_dir_proof: None,
            original_notice_replay:OriginalNoticeReplay::Ordinary,
            model_preparation:None,
            semantic_sources: policy
                .as_ref()
                .map(|policy| Arc::clone(policy.semantic_source_evidence())),
            tree: Arc::clone(&frontend.snapshot.tree),
            source_revision,
            policy_revision: match role {
                SnapshotPolicyRole::ExplicitSubset => policy.as_ref().and_then(|capture| capture.policy_revision()),
                // Only admit_workspace_policy may install the published full
                // workspace revision. The child keeps its own subset intent.
                SnapshotPolicyRole::WorkspaceGeneratorChild | SnapshotPolicyRole::WorkspaceSemanticChild => None,
            },
            outcome: "frontend_analyzed",
            source_mapping: frontend.source_export_mapping().cloned(),
            selected: Default::default(),
            resolved: None,
            replay_proof: None,
            native_schema_markers,
            native_value_input,
            native_value_queries: None,
            native_raw_queries: None,
            native_effect_request_input: Default::default(),
            source_answers: None,
            source_question_role: false,
            occurrences: Arc::clone(&frontend.snapshot.occurrences),
            body_archive,
            native_policy_inputs: policy,
            policy_role: role,
            workspace_generator_selection: None,
            workspace_semantic_selection: None,
            native_workspace: None,
            generation_inputs: None,
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
    /// Borrow the genuine generator subset retained by this published workspace.
    /// This is not full policy authority: callers still need the actual current
    /// workspace scope and both completed traversal witnesses in QueryDb.
    pub(crate) fn workspace_generator_inputs(&self,name:crate::GeneratorName) -> std::io::Result<&Arc<crate::runner_host::policy_capture::CapturedPolicyInputs>> {
        if self.workspace_generator_selection.as_ref().is_none_or(|selection|!selection.permits(name)){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"generator was not selected by snapshot preparation"))}
        let guard = self.workspace_native_read()?;
        self.native_workspace.as_ref().ok_or_else(|| std::io::Error::other("workspace capture unavailable"))?.require_scope(&guard)?;
        let child = self.native_policy_inputs.as_ref().ok_or_else(|| std::io::Error::other("workspace generator child unavailable"))?;
        if child.policy_revision().is_none()
            || !self.body_archive.as_ref().is_some_and(|archive| Arc::ptr_eq(archive, child.policy().archive()))
            || !self.source_mapping.as_ref().is_some_and(|mapping| Arc::ptr_eq(mapping, child.policy().mapping()))
        { return Err(std::io::Error::other("workspace generator child belongs to another original frame")); }
        child.semantic_source_evidence().require_mapping(child.policy().mapping())?;
        Ok(child)
    }
    /// Exact semantic child selected during genuine diagnostic workspace preparation.
    /// The caller still owes its own current reader scope and completed file domain.
    pub(crate) fn workspace_semantic_inputs(&self,name:crate::policy_request::WorkspaceAuxiliaryQuestion)->std::io::Result<&Arc<crate::runner_host::policy_capture::CapturedPolicyInputs>>{
        let guard=self.workspace_native_read()?;
        self.workspace_semantic_inputs_with_guard(name,&guard)
    }
    fn workspace_semantic_inputs_with_guard(&self,name:crate::policy_request::WorkspaceAuxiliaryQuestion,guard:&workspace_native_guard::NativeReadGuard<'_>)->std::io::Result<&Arc<crate::runner_host::policy_capture::CapturedPolicyInputs>>{
        if self.policy_role!=SnapshotPolicyRole::WorkspaceSemanticChild || self.workspace_semantic_selection.as_ref().is_none_or(|selection|!selection.permits(name)){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"semantic question was not selected by actual workspace preparation"))}
        self.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalChecker0290))?;
        let workspace=self.native_workspace.as_ref().ok_or_else(||std::io::Error::other("semantic workspace capture unavailable"))?;workspace.require_scope(guard)?;
        let child=self.native_policy_inputs.as_ref().ok_or_else(||std::io::Error::other("semantic original child unavailable"))?;
        if child.policy_revision().is_none() || !self.body_archive.as_ref().is_some_and(|archive|Arc::ptr_eq(archive,child.policy().archive())) || !self.source_mapping.as_ref().is_some_and(|mapping|Arc::ptr_eq(mapping,child.policy().mapping())){return Err(std::io::Error::other("semantic child belongs to another original source owner"))}
        child.semantic_source_evidence().check(child.policy().mapping())?;Ok(child)
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
    // Move the prior metadata; a variant switch restores this exact old state.
    // No pair String is cloned or new query owner constructed.
    prior_state: Option<(&'static str,Option<String>)>,
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
        let prior_state={
            let mut current = state.lock().unwrap_or_else(|error| error.into_inner());
            let prior=(current.last_request_outcome,current.publication_pair.take());
            current.last_request_outcome = "building";
            prior
        };
        Self {
            state,
            prior_state:Some(prior_state),
            captured: false,
            finished: false,
            configuration: None,
            pending_workspace: None,
            pending_diagnostic: None,
            pending_source: None,
            enabled,
        }
    }
    /// Bind the actual selected BuildHost variant before any source capture.
    /// Early cached publication stays on its existing path; a real engine
    /// switch must not publish into the now-stashed previous variant.
    pub(crate) fn bind_current_variant(&mut self,state:Arc<Mutex<QueryState>>)->std::io::Result<()>{
        if Arc::ptr_eq(&self.state,&state){return Ok(())}
        if self.finished||self.captured||self.pending_workspace.is_some()||self.pending_diagnostic.is_some()||self.pending_source.is_some(){return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"query variant changed after source capture"))}
        let prior=self.prior_state.take().ok_or_else(||std::io::Error::other("query attempt prior variant metadata unavailable"))?;
        {let mut previous=self.state.lock().unwrap_or_else(|error|error.into_inner());previous.last_request_outcome=prior.0;previous.publication_pair=prior.1;}
        let prior={let mut current=state.lock().unwrap_or_else(|error|error.into_inner());let prior=(current.last_request_outcome,current.publication_pair.take());current.last_request_outcome="building";prior};
        self.state=state;self.prior_state=Some(prior);Ok(())
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
        let generation_inputs=admission.take_generation_inputs();
        if generation_inputs.as_ref().is_some_and(|inputs|snapshot.workspace_generator_selection.as_ref().is_none_or(|selection|!inputs.matches_names(&selection.names))){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"generation admission questions differ from this exact staged frame"));}
        snapshot.generation_inputs=generation_inputs;
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
        self.state.lock().unwrap_or_else(|e|e.into_inner()).raw_snapshot=None;self.state.lock().unwrap_or_else(|e|e.into_inner()).handlers_snapshot=None;
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
        self.capture_workspace_snapshot(frontend,queries,workspace,request,inputs,WorkspaceSnapshotRole::RawPolicy)
    }
    pub(crate) fn capture_with_workspace_generator_recorded_sources<
        P: crate::input_snapshot::SnapshotProvider,
    >(
        &mut self,
        frontend: &ColdFrontend,
        queries: Arc<crate::query_db::QueryDb>,
        workspace: Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,
        request: &crate::policy_request::WorkspacePolicyRequest,
        inputs: &crate::input_snapshot::RecordingInputs<P>,
        intent: &crate::policy_request::AdmittedPolicyRequest,
    ) -> std::io::Result<()> {
        self.capture_workspace_snapshot(frontend,queries,workspace,request,inputs,WorkspaceSnapshotRole::Generator(intent))
    }
    fn capture_workspace_snapshot<
        P: crate::input_snapshot::SnapshotProvider,
    >(
        &mut self,
        frontend: &ColdFrontend,
        queries: Arc<crate::query_db::QueryDb>,
        workspace: Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,
        request: &crate::policy_request::WorkspacePolicyRequest,
        inputs: &crate::input_snapshot::RecordingInputs<P>,
        role: WorkspaceSnapshotRole<'_>,
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
        let (mut snapshot, evidence) = match role {
            // Preserve the raw-only workspace path: no generator capture or
            // semantic-encoding admission is introduced for unrelated queries.
            WorkspaceSnapshotRole::RawPolicy => {
                let evidence = inputs.semantic_source_evidence(frontend)?;
                (SourceSnapshot::capture(frontend), evidence)
            },
            WorkspaceSnapshotRole::Generator(intent) => {
                let selected=WorkspaceGeneratorSelection::from_admitted(intent,&workspace)?;
                let child = Arc::new(crate::runner_host::policy_capture::capture_workspace_generator(frontend, inputs, workspace.configuration().0)?);
                let evidence = Arc::clone(child.semantic_source_evidence());
                {let mut snapshot=SourceSnapshot::capture_policy_role(frontend,Some(child),SnapshotPolicyRole::WorkspaceGeneratorChild);snapshot.workspace_generator_selection=Some(selected);(snapshot,evidence)}
            }
        };
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
        self.state.lock().unwrap_or_else(|e|e.into_inner()).raw_snapshot=None;self.state.lock().unwrap_or_else(|e|e.into_inner()).handlers_snapshot=None;
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
        self.state.lock().unwrap_or_else(|e|e.into_inner()).raw_snapshot=None;self.state.lock().unwrap_or_else(|e|e.into_inner()).handlers_snapshot=None;
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
        let state=self.state.lock().unwrap_or_else(|e|e.into_inner());
        state.snapshot.as_ref().and_then(|snapshot|snapshot.policy_revision).or_else(||state.raw_snapshot.as_ref().map(|raw|raw.policy_revision()))
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
            state.snapshot = None;state.raw_snapshot=None;state.handlers_snapshot=None;
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
        use std::io;
        crate::daemon::control::checkpoint()?;
        let archive = self
            .body_archive
            .as_ref()
            .filter(|archive| archive.matches_tree(tree))
            .ok_or_else(|| {
                io::Error::new(io::ErrorKind::NotFound, "current body archive unavailable")
            })?;
        let body = archive
            .parse_checked(ordinal as usize)
            .map_err(body_syntax_io)?;
        crate::daemon::control::checkpoint()?;
        let mut syntax =
            bounded_json_writer::Bounded::new(192 * 1024, "body model query exceeds output budget");
        let exported = dm_analysis::typed_body_jsonl::write_archived_jsonl(&body, &mut syntax)
            .map_err(io::Error::other);
        syntax.restore(exported)?;
        let lexical = dm_analysis::typed_body::lexical::analyze_archived(&body, None)
            .map_err(io::Error::other)?;
        let mut bindings =
            bounded_json_writer::Bounded::new(192 * 1024, "body model query exceeds output budget");
        let exported =
            dm_analysis::typed_body::lexical::jsonl::write_jsonl(&lexical, &mut bindings)
                .map_err(io::Error::other);
        bindings.restore(exported)?;
        bounded_json_writer::write_json_line(
            &serde_json::json!({
                "row":"source_body_model", "schema":"dm-session-source-query-v1",
                "source_revision":format!("{:032x}",self.source_revision), "ordinal":ordinal,
                "member":body.occurrence().member.0,"declaration":body.occurrence().declaration.0,
                "typed_jsonl":String::from_utf8(syntax.bytes).map_err(io::Error::other)?,
                "lexical_jsonl":String::from_utf8(bindings.bytes).map_err(io::Error::other)?,
                "semantic_resolution_complete":false,
                "coverage":"current typed syntax and lexical bindings; nonlocal resolved selections require compiler host facts"
            }),
            output,
        )
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
        use std::io;
        if !self.matches_tree(tree) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "current compiler host tree differs",
            ));
        }
        if self.source_question_role {
            return self.write_source_questions(queries, tree, output);
        }
        let context = self.resolved.as_ref().ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::NotFound,
                "current compiler resolver unavailable or pressure-evicted",
            )
        })?;
        let mut rows = bounded_json_writer::Bounded::new(
            192 * 1024,
            "resolved query rows exceed output budget",
        );
        let exported = context.write_queries(queries, &mut rows);
        rows.restore(exported)?;
        bounded_json_writer::write_json_line(
            &serde_json::json!({
                "row":"source_resolved_queries", "schema":"dm-session-source-query-v1",
                "source_revision":format!("{:032x}",self.source_revision),
                "semantic_revision":format!("{:032x}",tree.identity()), "complete":false,
                "query_count":queries.len(), "captured_jsonl":String::from_utf8(rows.bytes).map_err(io::Error::other)?
            }),
            output,
        )
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
#[path = "runner_query_check_grep.rs"]
mod check_grep;

/// Ephemeral checker sibling of one selected Analyze capture. The checker
/// configuration is never substituted for the workspace policy or published as
/// a second resident QueryState.
pub(crate) struct CombinedCheckerFrame {
    snapshot: SourceSnapshot,
}
impl CombinedCheckerFrame {
    pub(crate) fn stage(
        frontend:&dm_tree::frontend::DiagnosticSourceView<'_>, queries:Arc<crate::query_db::QueryDb>,
        policy:Arc<crate::runner_host::policy_capture::CapturedPolicyInputs>,
        workspace:&crate::runner_host::workspace_capture::WorkspaceCapture,
    )->std::io::Result<Self>{
        use dm_tree::frontend::DiagnosticPreparationPurpose::OriginalSharedComplete;
        if frontend.preparation_purpose()!=OriginalSharedComplete ||
            !workspace.matches_source(frontend.mapping(),frontend.source_revision()) ||
            !Arc::ptr_eq(frontend.mapping(),policy.policy().mapping()) {
            return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"combined checker and Analyze require one complete current Original source"));
        }
        Ok(Self{snapshot:SourceSnapshot::capture_diagnostic(frontend,queries,policy)?})
    }
    pub(crate) fn write(
        self, admission:crate::request_runner::runner_freshness::DiagnosticPolicyAdmission,
        environment:&std::path::Path, compact_cache:Option<&std::path::Path>, output:&mut impl std::io::Write,
    )->std::io::Result<crate::request_runner::PreparedCheckerTranscript>{
        if self.snapshot.native_policy_inputs.as_ref().is_none_or(|current|!Arc::ptr_eq(current,admission.capture())){
            return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"combined checker scope differs from its actual admitted capture"));
        }
        self.snapshot.require_analysis_context(Some(crate::policy_request::AnalysisContext::OriginalChecker0290))?;
        let clean = match compact_cache {
            Some(cache)=>self.snapshot.write_compact_original_ordered_checker(environment,&self.snapshot.tree,cache,output)?,
            None=>self.snapshot.write_original_ordered_checker(environment,None,&self.snapshot.tree,output)?,
        };
        use dq_analyze::selected_exclusions_wire::{Frame, Hex128};
        let policy_revision = self.snapshot.policy_revision.ok_or_else(|| std::io::Error::other("combined checker policy revision absent"))?;
        let archive = self.snapshot.body_archive.as_ref().ok_or_else(|| std::io::Error::other("combined checker archive absent"))?;
        let queries = self.snapshot.native_raw_queries.as_ref().ok_or_else(|| std::io::Error::other("combined checker query owner absent"))?;
        Ok(crate::request_runner::PreparedCheckerTranscript {
            frame: Frame {
                semantic_revision: Hex128(self.snapshot.tree.identity()),
                source_revision: Hex128(self.snapshot.source_revision),
                policy_revision: Hex128(policy_revision),
            },
            clean,
            archive: Arc::downgrade(archive),
            queries: Arc::downgrade(queries),
        })
    }
}

impl SourceSnapshot {
    pub(super) fn require_staged_checker_body_domain(
        &self, checker: &crate::request_runner::PreparedCheckerTranscript,
    ) -> std::io::Result<()> {
        let same_archive = self.body_archive.as_ref().is_some_and(|archive| {
            checker.archive.upgrade().is_some_and(|owner| Arc::ptr_eq(&owner, archive))
        });
        let same_queries = self.native_raw_queries.as_ref().is_some_and(|queries| {
            checker.queries.upgrade().is_some_and(|owner| Arc::ptr_eq(&owner, queries))
        });
        if !same_archive || !same_queries {
            return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "selected untyped and Checker source owners differ"));
        }
        Ok(())
    }

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
        Self::capture_diagnostic_sources(frontend,queries,Some(Arc::clone(&policy)),Arc::clone(policy.semantic_source_evidence()))
    }
    fn capture_diagnostic_sources(
        frontend:&dm_tree::frontend::DiagnosticSourceView<'_>,queries:Arc<crate::query_db::QueryDb>,
        policy:Option<Arc<crate::runner_host::policy_capture::CapturedPolicyInputs>>,
        evidence:Arc<crate::input_snapshot::SemanticSourceEvidence>,
    )->std::io::Result<Self>{
        if frontend.preparation_purpose().is_structural(){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"partial structural frontend requires its own native query source role"))}
        let archive=frontend.archive();
        if !frontend.receipt().authenticates(frontend.tree()) || !archive.matches_tree(frontend.tree()) || !archive.uses_body_queries(queries.as_ref()) {return Err(std::io::Error::other("diagnostic source graph/archive/current Db differ"))}
        evidence.check(frontend.mapping())?;
        Ok(Self {
            analysis_subject:None,
            diagnostic_declarations: Some(Arc::clone(frontend.receipt())),
            image_dir_proof: None,
            original_notice_replay:frontend.retain_original_preprocess_notices().map_or(OriginalNoticeReplay::Ordinary,OriginalNoticeReplay::Retained),
            model_preparation:Some(frontend.preparation_purpose()),
            semantic_sources: Some(evidence),
            tree: Arc::clone(frontend.tree()),
            source_revision: frontend.source_revision(),
            policy_revision: policy.as_ref().and_then(|policy|policy.policy_revision()),
            outcome: "diagnostic_frontend_admitted",
            occurrences: Arc::clone(frontend.occurrences()),
            bodies: Some(Arc::clone(frontend.bodies())),
            body_archive: Some(Arc::clone(archive)),
            native_policy_inputs: policy,
            policy_role: SnapshotPolicyRole::ExplicitSubset,
            workspace_generator_selection: None,
            workspace_semantic_selection: None,
            native_workspace: None,
            generation_inputs: None,
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
            native_effect_request_input: Default::default(),
            source_answers: None,
            source_question_role: false,
        })
    }
    /// Only the current published diagnostic frame supplies this owner; no
    /// equal-hash sibling or old executable patch-base tree is substituted.
    /// Choose the exact current prepared original owner. A valid consuming
    /// diagnostic-to-ordinary transfer need not rebuild RetainedSemanticTree's
    /// older executable patch-base entry merely to serve read-only queries.
    pub(crate) fn prepared_query_tree(&self) -> Option<&Arc<dm_tree::SemanticTree>> {
        if self.source_question_role {
            return self.source_answers.as_ref().map(|_| &self.tree);
        }
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

    /// Stage the genuine diagnostic-only analysis owner with its separately
    /// issued current workspace. Complete freshness still controls publication.
    pub(crate) fn stage_analysis_workspace<P:crate::input_snapshot::SnapshotProvider>(
        &mut self,frontend:&dm_tree::frontend::DiagnosticSourceView<'_>,
        queries:Arc<crate::query_db::QueryDb>,
        workspace:Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,
        request:&crate::policy_request::WorkspacePolicyRequest,inputs:&crate::input_snapshot::RecordingInputs<P>,
        intent:&crate::policy_request::AdmittedPolicyRequest,
        joined:Option<&crate::runner_host::policy_capture::JoinedHeaderCharge>,
    )->std::io::Result<()>{
        if !self.enabled || frontend.mapping().initial_environment()!=dm_preprocess::InitialEnvironment::OriginalChecker0290 {
            return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"analysis workspace needs its actual retained original context"));
        }
        use dm_tree::frontend::DiagnosticPreparationPurpose as P;
        let analyze=intent.analysis_context()==Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290);
        if analyze&&!matches!(frontend.preparation_purpose(),P::OriginalSharedComplete|P::OriginalAnalyzePrefix)||!analyze&&!matches!(frontend.preparation_purpose(),P::Checker|P::OriginalSharedComplete){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"workspace role differs from actual complete/prefix native preparation"))}
        if !workspace.matches_source(frontend.mapping(),frontend.source_revision())||!workspace.matches_request(request)||!workspace.is_recorded_in(&inputs.snapshot()?){return Err(std::io::Error::other("analysis workspace capture differs from current actual source/request"))}
        let selected=WorkspaceSemanticSelection::from_admitted(intent,&workspace)?;
        let generators=if intent.workspace_generators().is_empty(){None}else{if selected.is_some(){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"generation and semantic child purposes must be issued separately"))}Some(WorkspaceGeneratorSelection::from_admitted(intent,&workspace)?)};
        let child=if generators.is_some(){Some(Arc::new(crate::runner_host::policy_capture::capture_analysis_generator(frontend,inputs,workspace.configuration().0)?))}else if selected.is_some()||intent.workspace_auxiliary()==[crate::policy_request::WorkspaceAuxiliaryQuestion::SemHandlers]{Some(Arc::new(crate::runner_host::policy_capture::capture_analysis_semantic_with_joined_headers(frontend,inputs,workspace.configuration().0,joined)?))}else{None};
        let evidence=if let Some(child)=&child{Arc::clone(child.semantic_source_evidence())}else{inputs.diagnostic_source_evidence(frontend)?};
        let mut snapshot=SourceSnapshot::capture_diagnostic_sources(frontend,Arc::clone(&queries),child,evidence)?;
        if intent.analysis_context()==Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290){let subject=inputs.original_analysis_subject().ok_or_else(||std::io::Error::other("full Analyze subject issuance absent"))?;subject.bind_frontend(frontend)?;subject.discovery().validate_recording(inputs)?;snapshot.analysis_subject=Some(Arc::clone(subject));}
        if intent.workspace_auxiliary()==[crate::policy_request::WorkspaceAuxiliaryQuestion::ImageDir]
            || intent.workspace_auxiliary()==crate::policy_request::WorkspaceAuxiliaryQuestion::PRIVATE_EXTENDED_AUTHORED_WITH_CHECKER_AND_IMAGE
            || crate::policy_request::WorkspaceAuxiliaryQuestion::is_private_authored_actor_domain(intent.workspace_auxiliary())
            || crate::policy_request::WorkspaceAuxiliaryQuestion::is_private_grep_domain(intent.workspace_auxiliary()) {
            snapshot.image_dir_proof=Some(frontend.clean_original_image_dir_proof()
                .map_err(|message|std::io::Error::new(std::io::ErrorKind::Unsupported,message))?);
        }
        if selected.is_some(){snapshot.policy_role=SnapshotPolicyRole::WorkspaceSemanticChild;snapshot.policy_revision=None;snapshot.workspace_semantic_selection=selected;}
        if let Some(generators)=generators{snapshot.policy_role=SnapshotPolicyRole::WorkspaceGeneratorChild;snapshot.policy_revision=None;snapshot.workspace_generator_selection=Some(generators);}
        self.pending_diagnostic=None;self.pending_source=None;
        self.pending_workspace=Some((workspace,queries));
        self.stage_source_snapshot(snapshot,inputs.snapshot()?)
    }
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
        if !matches!(frontend.preparation_purpose(),dm_tree::frontend::DiagnosticPreparationPurpose::Checker|dm_tree::frontend::DiagnosticPreparationPurpose::OriginalSharedComplete){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"Analyze model cannot stage the checker purpose"))}
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
        self.state.lock().unwrap_or_else(|e|e.into_inner()).raw_snapshot=None;self.state.lock().unwrap_or_else(|e|e.into_inner()).handlers_snapshot=None;
        self.captured = true;
        Ok(())
    }
}

#[cfg(test)]
#[path = "runner_query_diagnostic_tests.rs"]
mod diagnostic_tests;

#[path = "runner_query_bounded_json_writer.rs"]
mod bounded_json_writer;

#[path="runner_query_generator_bytes.rs"]mod generator_bytes;

impl SourceSnapshot {
    pub(crate) fn retire_for_generation(mut self)
        -> std::io::Result<crate::request_runner::runner_freshness::GenerationInputClosure>
    {
        {
            let guard = self.workspace_native_read()?;
            self.native_workspace.as_ref().ok_or_else(|| std::io::Error::other("generation workspace unavailable"))?.require_scope(&guard)?;
            if self.policy_role != SnapshotPolicyRole::WorkspaceGeneratorChild
                || self.workspace_generator_selection.as_ref().is_none_or(|selection|
                    self.generation_inputs.as_ref().is_none_or(|inputs| !inputs.matches_names(&selection.names)))
            {
                return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,
                    "prepared frame has no actual complete generation closure"));
            }
        }
        let inputs = self.generation_inputs.take().ok_or_else(|| std::io::Error::other("generation closure unavailable"))?;
        // The real source guard above has ended. No snapshot or its scope can
        // be used by the serialized host while these owned inputs authorize the
        // final freshness barrier. Source-output mutation happens only later.
        drop(self);
        Ok(inputs)
    }
}

#[path="runner_query_generation_stage.rs"]mod generation_stage;

pub(crate) use generation_stage::{ClosedGeneration,original_manifest_includes};

#[path="runner_query_keyword_overrides.rs"]mod keyword_overrides;

#[path="runner_query_workspace_fold.rs"]mod workspace_fold_report;

#[path="runner_query_allow_annotations.rs"]mod allow_annotations;

#[path="runner_query_call_arguments.rs"]mod call_arguments;

#[path="runner_query_keys.rs"]mod keys;

#[cfg(test)]
#[path="runner_query_analysis_context_tests.rs"]mod analysis_context_tests;

impl SourceSnapshot{
 pub(crate) fn with_original_semantic_policy<T>(&self,question:crate::policy_request::WorkspaceAuxiliaryQuestion,consume:impl FnOnce(&dq_analyze::captured_sem_reads::SemanticPolicyData)->std::io::Result<T>)->std::io::Result<T>{
  use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;if !matches!(question,Q::SemReads|Q::UntrackedInputs|Q::SetterPublishes){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"semantic policy endpoint does not issue this role"))}
  let capture=self.workspace_semantic_inputs(question)?;let guard=self.workspace_native_read()?;let workspace=self.native_workspace.as_ref().ok_or_else(||std::io::Error::other("original semantic workspace unavailable"))?;let queries=self.native_raw_queries.as_ref().ok_or_else(||std::io::Error::other("original semantic QueryDb unavailable"))?;
  queries.with_original_workspace_semantic_guard(workspace,&guard,capture,question,consume)
 }
}

impl SourceSnapshot{
 pub(crate) fn with_original_semantic_policy_report<T>(&self,question:crate::policy_request::WorkspaceAuxiliaryQuestion,consume:impl FnOnce(&dq_analyze::captured_sem_reads::SemanticPolicyData,&dq_analyze::captured_raw_file::Config,&Arc<dq_analyze::captured_generator_budget::Budget>)->std::io::Result<T>)->std::io::Result<T>{use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;if !matches!(question,Q::SemReads|Q::UntrackedInputs|Q::SetterPublishes){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"semantic report does not issue this role"))}let capture=self.workspace_semantic_inputs(question)?;let guard=self.workspace_native_read()?;let workspace=self.native_workspace.as_ref().ok_or_else(||std::io::Error::other("actual semantic report workspace unavailable"))?;let queries=self.native_raw_queries.as_ref().ok_or_else(||std::io::Error::other("actual semantic report QueryDb unavailable"))?;queries.with_original_workspace_semantic_guard_report(workspace,&guard,capture,question,consume)}
}

impl SourceSnapshot{
 /// Shared public report preflight. The complete registry is fixed by its
 /// genuine factory; the caller supplies no metadata or configuration bytes.
 pub(crate) fn require_public_report_configuration(&self,root:&std::path::Path,configuration:&std::path::Path,tree:&dm_tree::SemanticTree)->std::io::Result<()>{
  if !self.matches_tree(tree){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"public report tree differs from current snapshot"))}
  let capture=self.native_workspace.as_ref().ok_or_else(||std::io::Error::other("public report workspace absent"))?;
  if root!=capture.root()||configuration!=capture.configuration().0||self.policy_revision!=Some(capture.policy_revision()){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"public report configuration differs from actual capture"))}
  let guard=self.workspace_native_read()?;capture.require_scope(&guard)?;
  let queries=self.native_raw_queries.as_ref().ok_or_else(||std::io::Error::other("public report QueryDb absent"))?;
  queries.require_workspace_report_configuration(capture,&guard).map_err(|failure|match failure{dq_analyze::captured_reactive_reads::Failure::Operational(actual)=>actual,dq_analyze::captured_reactive_reads::Failure::Unsupported(message)=>std::io::Error::new(std::io::ErrorKind::InvalidInput,message)})
 }
}

impl SourceSnapshot{
 /// Only the actually selected Original diagnostic semantic child enters this
 /// producer. Its separate CODE_MAPS_DM EOF remains mandatory at the host.
 pub(crate) fn with_original_tracked_policy<T>(&self,tests:bool,consume:impl FnOnce(&dq_analyze::captured_tracked_pages::TrackedData)->std::io::Result<T>)->std::io::Result<T>{use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;let question=if tests{Q::TrackedTests}else{Q::Tracked};let capture=self.workspace_semantic_inputs(question)?;let guard=self.workspace_native_read()?;let workspace=self.native_workspace.as_ref().ok_or_else(||std::io::Error::other("original tracked workspace unavailable"))?;let queries=self.native_raw_queries.as_ref().ok_or_else(||std::io::Error::other("original tracked QueryDb unavailable"))?;queries.with_original_workspace_tracked_guard(workspace,&guard,capture,tests,consume)}
}

impl SourceSnapshot{
 pub(crate) fn with_native_api<T>(&self,tree:&dm_tree::SemanticTree,consume:impl FnOnce(&dq_analyze::captured_api_pages::ApiData,&dq_analyze::captured_raw_file::Config,&Arc<dq_analyze::captured_generator_budget::Budget>)->std::io::Result<T>)->Result<T,dq_analyze::captured_reactive_reads::Failure>{if !self.matches_tree(tree){return Err("API actual current tree differs".into())}let capture=self.native_workspace.as_ref().ok_or("API actual workspace capture absent")?;let guard=self.workspace_native_read()?;capture.require_scope(&guard)?;let queries=self.native_raw_queries.as_ref().ok_or("API actual QueryDb absent")?;queries.with_workspace_api(capture,&guard,consume)}
}
impl SourceSnapshot{
 pub(crate) fn with_native_fields<T>(&self,tree:&dm_tree::SemanticTree,consume:impl FnOnce(&dq_analyze::captured_sys_fields_pages::FieldData,&dq_analyze::captured_raw_file::Config,&Arc<dq_analyze::captured_generator_budget::Budget>)->std::io::Result<T>)->Result<T,dq_analyze::captured_reactive_reads::Failure>{if !self.matches_tree(tree){return Err("Sys fields actual current tree differs".into())}let capture=self.native_workspace.as_ref().ok_or("Sys fields actual workspace capture absent")?;let guard=self.workspace_native_read()?;capture.require_scope(&guard)?;let queries=self.native_raw_queries.as_ref().ok_or("Sys fields actual QueryDb absent")?;queries.with_workspace_fields(capture,&guard,consume)}
}
impl SourceSnapshot{
 pub(crate) fn with_native_appearance<T>(&self,tree:&dm_tree::SemanticTree,consume:impl FnOnce(&dq_analyze::captured_sys_appearance_pages::AppearanceData,&dq_analyze::captured_raw_file::Config,&Arc<dq_analyze::captured_generator_budget::Budget>)->std::io::Result<T>)->Result<T,dq_analyze::captured_reactive_reads::Failure>{if !self.matches_tree(tree){return Err("Appearance actual current tree differs".into())}let capture=self.native_workspace.as_ref().ok_or("Appearance actual workspace capture absent")?;let guard=self.workspace_native_read()?;capture.require_scope(&guard)?;let queries=self.native_raw_queries.as_ref().ok_or("Appearance actual QueryDb absent")?;queries.with_workspace_appearance(capture,&guard,consume)}
}

#[cfg(test)]#[path="runner_query_analysis_subject_tests.rs"]mod analysis_subject_tests;

impl SourceSnapshot{pub(crate) fn with_native_raw_tree<T>(&self,tree:&dm_tree::SemanticTree,policy:dq_analyze::captured_raw_tree_pages::Policy,consume:impl FnOnce(&dq_analyze::captured_raw_tree_pages::Data,&dq_analyze::captured_raw_file::Config,&Arc<dq_analyze::captured_generator_budget::Budget>)->std::io::Result<T>)->Result<T,dq_analyze::captured_reactive_reads::Failure>{if !self.matches_tree(tree){return Err("raw tree actual current tree differs".into())}let capture=self.native_workspace.as_ref().ok_or("raw tree actual capture absent")?;let guard=self.workspace_native_read()?;capture.require_scope(&guard)?;let queries=self.native_raw_queries.as_ref().ok_or("raw tree actual QueryDb absent")?;queries.with_workspace_raw_tree(capture,&guard,policy,consume)}}

impl SourceSnapshot{pub(crate) fn with_native_workspace_fold_report<R>(&self,tree:&dm_tree::SemanticTree,policy:dq_analyze::workspace_fold_policy::Policy,consume:impl FnOnce(dq_analyze::workspace_fold_policy::Data<'_>,&dq_analyze::captured_raw_file::Config,&Arc<dq_analyze::captured_generator_budget::Budget>)->std::io::Result<R>)->Result<R,dq_analyze::captured_reactive_reads::Failure>{use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;if !self.matches_tree(tree){return Err("whole policy report actual tree differs".into())}let workspace=self.native_workspace.as_ref().ok_or("whole policy report actual workspace absent")?;let guard=self.workspace_native_read()?;workspace.require_scope(&guard)?;let queries=self.native_raw_queries.as_ref().ok_or("whole policy report actual QueryDb absent")?;if let Some(tests)=policy.tracked(){let question=if tests{Q::TrackedTests}else{Q::Tracked};let capture=self.workspace_semantic_inputs(question)?;return queries.with_original_workspace_tracked_guard_report(workspace,&guard,capture,tests,|data,config,budget|consume(dq_analyze::workspace_fold_policy::Data::Tracked(data),config,budget)).map_err(dq_analyze::captured_reactive_reads::Failure::Operational)}queries.with_workspace_fold_report(workspace,&guard,policy,consume)}}

#[cfg(test)]#[path="runner_query_complete_policy_report_tests.rs"]mod complete_policy_reports;
impl SourceSnapshot{
 pub(crate) fn with_original_decl_policy<T>(&self,consume:impl FnOnce(&dq_analyze::captured_decl_pages::DeclData,&dq_analyze::captured_raw_file::Config,&Arc<dq_analyze::captured_generator_budget::Budget>)->std::io::Result<T>)->std::io::Result<T>{let question=crate::policy_request::WorkspaceAuxiliaryQuestion::Decl;let capture=self.workspace_semantic_inputs(question)?;let guard=self.workspace_native_read()?;let workspace=self.native_workspace.as_ref().ok_or_else(||std::io::Error::other("original decl workspace unavailable"))?;let queries=self.native_raw_queries.as_ref().ok_or_else(||std::io::Error::other("original decl QueryDb unavailable"))?;queries.with_original_workspace_decl_guard(workspace,&guard,capture,consume)}
}

impl SourceSnapshot{
 pub(crate) fn with_original_init_policy<T>(&self,consume:impl FnOnce(&dq_analyze::captured_init_pages::InitData,&dq_analyze::captured_raw_file::Config,&Arc<dq_analyze::captured_generator_budget::Budget>)->std::io::Result<T>)->std::io::Result<T>{let question=crate::policy_request::WorkspaceAuxiliaryQuestion::Init;let capture=self.workspace_semantic_inputs(question)?;let guard=self.workspace_native_read()?;let workspace=self.native_workspace.as_ref().ok_or_else(||std::io::Error::other("original init workspace unavailable"))?;let queries=self.native_raw_queries.as_ref().ok_or_else(||std::io::Error::other("original init QueryDb unavailable"))?;queries.with_original_workspace_init_guard(workspace,&guard,capture,consume)}
}

impl SourceSnapshot{
 pub(crate) fn with_original_base_vars_policy<T>(&self,consume:impl FnOnce(&dq_analyze::captured_base_vars_pages::BaseVarsData,&dq_analyze::captured_raw_file::Config,&Arc<dq_analyze::captured_generator_budget::Budget>)->std::io::Result<T>)->std::io::Result<T>{let question=crate::policy_request::WorkspaceAuxiliaryQuestion::BaseVars;let capture=self.workspace_semantic_inputs(question)?;let guard=self.workspace_native_read()?;let workspace=self.native_workspace.as_ref().ok_or_else(||std::io::Error::other("original base_vars workspace unavailable"))?;let queries=self.native_raw_queries.as_ref().ok_or_else(||std::io::Error::other("original base_vars QueryDb unavailable"))?;queries.with_original_workspace_base_vars_guard(workspace,&guard,capture,consume)}
}

impl SourceSnapshot{
 pub(crate) fn with_original_requirement_bool_policy<T>(&self,consume:impl FnOnce(&dq_analyze::captured_requirement_bool_pages::RequirementData,&dq_analyze::captured_raw_file::Config,&Arc<dq_analyze::captured_generator_budget::Budget>)->std::io::Result<T>)->std::io::Result<T>{let question=crate::policy_request::WorkspaceAuxiliaryQuestion::RequirementBool;let capture=self.workspace_semantic_inputs(question)?;let guard=self.workspace_native_read()?;let workspace=self.native_workspace.as_ref().ok_or_else(||std::io::Error::other("original requirement_bool workspace unavailable"))?;let queries=self.native_raw_queries.as_ref().ok_or_else(||std::io::Error::other("original requirement_bool QueryDb unavailable"))?;queries.with_original_workspace_requirement_bool_guard(workspace,&guard,capture,consume)}
}

#[cfg(test)]#[path="runner_query_raw_workspace_tests.rs"]mod raw_workspace_tests;

#[cfg(test)]#[path="runner_query_ownership_tests.rs"]mod ownership_complete_raw;

#[cfg(test)]#[path="runner_query_original_model_purpose_tests.rs"]mod original_model_purpose_tests;

#[cfg(test)]#[path="runner_query_engine_layering_tests.rs"]mod engine_layering_conditional_tests;

#[cfg(test)]#[path="runner_query_original_model_convergence_tests.rs"]mod original_model_convergence_tests;

#[cfg(test)]#[path="runner_query_ui_actions_tests.rs"]mod ui_actions_tests;

#[cfg(test)]#[path="runner_query_op_order_tests.rs"]mod op_order_complete_raw;

#[path="runner_query_allow_full_run.rs"]mod allow_full_run;
pub(super) use allow_full_run::{checked_stage as checked_selected_report_stage,stage_named_image_dir,validate_selection as validate_selected_report_selection,validate_selection_v2 as validate_selected_report_selection_v2,SelectedReportPlan};

impl SourceSnapshot{pub(crate) fn with_original_derived_policy_report<T>(&self,consume:impl FnOnce(&dq_analyze::captured_derived_reads::DerivedReadData,&dq_analyze::captured_raw_file::Config,&Arc<dq_analyze::captured_generator_budget::Budget>)->std::io::Result<T>)->std::io::Result<T>{self.with_original_derived_policy_report_to(&mut crate::daemon::stderr_writer(),consume)}pub(crate) fn with_original_derived_policy_report_to<T>(&self,diagnostics:&mut impl std::io::Write,consume:impl FnOnce(&dq_analyze::captured_derived_reads::DerivedReadData,&dq_analyze::captured_raw_file::Config,&Arc<dq_analyze::captured_generator_budget::Budget>)->std::io::Result<T>)->std::io::Result<T>{let capture=self.workspace_semantic_inputs(crate::policy_request::WorkspaceAuxiliaryQuestion::DerivedReads)?;let guard=self.workspace_native_read()?;let workspace=self.native_workspace.as_ref().ok_or_else(||std::io::Error::other("Derived actual workspace unavailable"))?;let queries=self.native_raw_queries.as_ref().ok_or_else(||std::io::Error::other("Derived actual QueryDb unavailable"))?;let subject=capture.original_analysis_subject().ok_or_else(||std::io::Error::other("Derived actual full subject absent"))?;subject.derived_preflight()?.require_current(subject,workspace,&guard,capture.policy(),queries)?;self.replay_original_preprocess_notices(diagnostics)?;queries.with_original_workspace_derived_guard_report(workspace,&guard,capture,consume)}}

#[cfg(test)]#[path="runner_query_derived_reads_tests.rs"]mod derived_reads_host_controls;

impl SourceSnapshot {
 /// Closed typed report request, not a public source/witness constructor.
 pub(crate) fn with_prepared_derived_request<R>(&self,request:&crate::request::BuildRequest,prepared:&crate::request::BuildOutcome,diagnostics:&mut impl std::io::Write,consume:impl FnOnce(&dq_analyze::captured_derived_reads::DerivedReadData,&dq_analyze::captured_raw_file::Config)->std::io::Result<R>)->std::io::Result<R>{
  self.with_prepared_derived_request_budget(request,prepared,diagnostics,|data,config,_budget|consume(data,config))
 }
 pub(crate) fn with_prepared_derived_request_budget<R>(&self,request:&crate::request::BuildRequest,prepared:&crate::request::BuildOutcome,diagnostics:&mut impl std::io::Write,consume:impl FnOnce(&dq_analyze::captured_derived_reads::DerivedReadData,&dq_analyze::captured_raw_file::Config,&Arc<dq_analyze::captured_generator_budget::Budget>)->std::io::Result<R>)->std::io::Result<R>{
  use crate::{request::{BuildCommand,BuildOutcome},policy_request::{AnalysisContext,WorkspaceAuxiliaryQuestion as Q}};
  let invalid=||std::io::Error::new(std::io::ErrorKind::InvalidInput,"prepared Derived report differs from its actual current request/source");
  if request.command!=BuildCommand::PrepareQuery||!request.project.is_absolute()||!request.defines.is_empty()||request.engine_template.is_some()||request.bootstrap_catalog||!self.matches_original_analysis_subject(&request.project){return Err(invalid())}
  let intent=request.policy_inputs.as_ref().ok_or_else(invalid)?.clone().admit().map_err(std::io::Error::other)?;
  if intent.analysis_context()!=Some(AnalysisContext::OriginalAnalyze0290)||intent.workspace_auxiliary()!=[Q::DerivedReads]||!intent.workspace_generators().is_empty()||!intent.files().is_empty()||!intent.search_folders().is_empty(){return Err(invalid())}
  let BuildOutcome::QueryPrepared{semantic_revision,source_revision,policy_revision:Some(policy_revision),retained:true}=prepared else{return Err(invalid())};
  let value=|s:&str|u128::from_str_radix(s,16).map_err(|_|invalid());
  if value(semantic_revision)?!=self.tree.identity()||value(source_revision)?!=self.source_revision||Some(value(policy_revision)?)!=self.policy_revision{return Err(invalid())}
  if matches!(self.original_notice_replay,OriginalNoticeReplay::Released){return Err(std::io::Error::new(std::io::ErrorKind::NotConnected,"Original notice/source queries were pressure-released; reprepare required"))}
  let actual=self.native_workspace.as_ref().ok_or_else(invalid)?;let workspace=intent.workspace().ok_or_else(invalid)?;
  if !actual.matches_request(workspace){return Err(invalid())}
  // Revision strings only reject stale requests. Authority still comes from
  // the genuine current SourceSnapshot, parent subject and SAME Kind12 scope.
  self.with_original_derived_policy_report_to(diagnostics,consume)
 }
}

impl SourceSnapshot{
 fn replay_original_preprocess_notices(&self,output:&mut impl std::io::Write)->std::io::Result<()>{
  match &self.original_notice_replay{
   OriginalNoticeReplay::Ordinary=>Ok(()),
   OriginalNoticeReplay::Released=>Err(std::io::Error::new(std::io::ErrorKind::NotConnected,"Original notice owner was pressure-released; reprepare required")),
   OriginalNoticeReplay::Retained(owner)=>{let mapping=self.source_mapping.as_ref().ok_or_else(||std::io::Error::other("Original notice replay lost actual source mapping"))?;if !owner.matches_mapping(mapping){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"Original notice replay differs from current mapping"))}crate::diagnostics::write_original_preprocess_notices(output,&owner.borrow())},
  }
 }
}
