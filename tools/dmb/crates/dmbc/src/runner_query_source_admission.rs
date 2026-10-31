//! Publication authority for the existing prepared source frame, not a model
//! cache. Only QueryAttempt can issue this immutable challenge; only the full
//! captured-input freshness barrier can issue its consuming admission receipt.
use super::*;
use crate::input_snapshot::{InputSnapshot, SemanticSourceEvidence};
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum SourceAnswersMode {
    NotRequested,
    Required,
}
pub(crate) struct SourceFrameCapture {
    mapping: Arc<dm_tree::frontend::SourceExportMapping>,
    evidence: Arc<SemanticSourceEvidence>,
    archive: Arc<dm_tree::frontend::BodyArchive>,
    queries: Arc<crate::query_db::QueryDb>,
    policy: Option<Arc<crate::runner_host::policy_capture::CapturedPolicyInputs>>,
    policy_role: SnapshotPolicyRole,
    workspace_generator_selection: Option<WorkspaceGeneratorSelection>,
    source_revision: u128,
    facts: InputSnapshot,
    query_request: u64,
    mode: SourceAnswersMode,
    questions: Option<crate::query_db::SourceQuestionRoster>,
}
/// One-use stack publication ticket. Only the real final SourceFrame admission
/// transaction can construct it, after complete closure freshness/owner checks.
/// Handles are original owners; no sibling tree, model, facts table or manager.
pub(crate) struct SourceAnswerPublication {
    tree: Arc<dm_tree::SemanticTree>,
    mapping: Arc<dm_tree::frontend::SourceExportMapping>,
    archive: Arc<dm_tree::frontend::BodyArchive>,
    queries: Arc<crate::query_db::QueryDb>,
    eligible: bool,
    query_request: u64,
    mode: SourceAnswersMode,
    question_frame: Option<Arc<SourceFrameCapture>>,
}
impl SourceAnswerPublication {
    pub(crate) fn questions(&self) -> Option<&crate::query_db::SourceQuestionRoster> {
        self.question_frame
            .as_ref()
            .and_then(|f| f.questions.as_ref())
    }
    pub(crate) fn parts(
        &self,
    ) -> (
        &Arc<dm_tree::SemanticTree>,
        &Arc<dm_tree::frontend::SourceExportMapping>,
        &Arc<dm_tree::frontend::BodyArchive>,
        &Arc<crate::query_db::QueryDb>,
        bool,
        u64,
        SourceAnswersMode,
    ) {
        (
            &self.tree,
            &self.mapping,
            &self.archive,
            &self.queries,
            self.eligible,
            self.query_request,
            self.mode,
        )
    }
}
impl SourceFrameCapture {
    // The private constructor records an explicit source role. A workspace
    // child has its own bound subset revision while the staged published
    // workspace revision remains None until actual WorkspacePolicyAdmission.
    fn policy_matches(snapshot:&SourceSnapshot)->bool{
        match (&snapshot.native_policy_inputs,snapshot.policy_role){
            (Some(policy),SnapshotPolicyRole::ExplicitSubset)=>snapshot.workspace_generator_selection.is_none()&&policy.policy_revision().is_some()&&snapshot.policy_revision==policy.policy_revision(),
            (Some(policy),SnapshotPolicyRole::WorkspaceGeneratorChild)=>snapshot.workspace_generator_selection.is_some()&&policy.policy_revision().is_some()&&snapshot.policy_revision.is_none(),
            (None,SnapshotPolicyRole::ExplicitSubset)=>snapshot.workspace_generator_selection.is_none()&&snapshot.policy_revision.is_none(),
            (None,SnapshotPolicyRole::WorkspaceGeneratorChild)=>false,
        }
    }
    // Constructor intentionally private to this child of the snapshot owner.
    fn issue(snapshot: &SourceSnapshot, facts: InputSnapshot) -> std::io::Result<Arc<Self>> {
        let mapping = snapshot
            .source_mapping
            .as_ref()
            .ok_or_else(|| std::io::Error::other("staged source mapping unavailable"))?;
        let evidence = snapshot
            .semantic_sources
            .as_ref()
            .ok_or_else(|| std::io::Error::other("staged original-source evidence unavailable"))?;
        evidence.require_mapping(mapping)?;
        let archive = snapshot
            .body_archive
            .as_ref()
            .ok_or_else(|| std::io::Error::other("staged original body archive unavailable"))?;
        let queries = snapshot
            .native_raw_queries
            .as_ref()
            .ok_or_else(|| std::io::Error::other("staged compiler query owner unavailable"))?;
        // Plain Compile/Analyze and raw-workspace preparation may legitimately
        // have no attached body query graph. Never invent one or force parsing.
        // If attached, it MUST be this exact compiler Db; the archive/map/Db
        // frame identities remain mandatory in either case.
        if !archive.matches_tree(&snapshot.tree)
            || (archive.body_query_host().is_some() && !archive.uses_body_queries(queries.as_ref()))
            || !Arc::ptr_eq(mapping, archive.source_mapping())
        {
            return Err(std::io::Error::other(
                "staged source archive/map/compiler query owner differs",
            ));
        }
        if !Self::policy_matches(snapshot) || snapshot
            .native_policy_inputs
            .as_ref()
            .is_some_and(|policy| {
                !policy.is_recorded_in(&facts) || !Arc::ptr_eq(archive, policy.policy().archive())
            })
        {
            return Err(std::io::Error::other(
                "staged policy facts/archive differ from original source frame",
            ));
        }
        Ok(Arc::new(Self {
            mapping: Arc::clone(mapping),
            evidence: Arc::clone(evidence),
            archive: Arc::clone(archive),
            queries: Arc::clone(queries),
            policy: snapshot.native_policy_inputs.as_ref().map(Arc::clone),
            policy_role: snapshot.policy_role,
            workspace_generator_selection: snapshot.workspace_generator_selection,
            source_revision: snapshot.source_revision,
            facts,
            query_request: queries.source_answer_request(),
            mode: SourceAnswersMode::NotRequested,
            questions: None,
        }))
    }
    pub(crate) fn is_recorded_in(&self, complete: &InputSnapshot) -> bool {
        let mut union = complete.clone();
        union.merge(&self.facts).is_ok() && union.same_recorded_facts(complete)
    }
    pub(super) fn require_snapshot(&self, snapshot: &SourceSnapshot) -> std::io::Result<()> {
        if snapshot
            .source_mapping
            .as_ref()
            .is_none_or(|m| !Arc::ptr_eq(m, &self.mapping))
            || snapshot
                .semantic_sources
                .as_ref()
                .is_none_or(|e| !Arc::ptr_eq(e, &self.evidence))
            || snapshot
                .body_archive
                .as_ref()
                .is_none_or(|a| !Arc::ptr_eq(a, &self.archive))
            || snapshot
                .native_raw_queries
                .as_ref()
                .is_none_or(|db| !Arc::ptr_eq(db, &self.queries))
            || snapshot.source_revision != self.source_revision
            || snapshot.policy_role != self.policy_role
            || snapshot.workspace_generator_selection != self.workspace_generator_selection
            || !Self::policy_matches(snapshot)
            || !match (&self.policy, &snapshot.native_policy_inputs) {
                (Some(a), Some(b)) => {
                    Arc::ptr_eq(a, b)
                }
                (None, None) => true,
                _ => false,
            }
        {
            return Err(std::io::Error::other(
                "source admission is not for this exact staged frame",
            ));
        }
        self.evidence.require_mapping(&self.mapping)?;
        if !self.archive.matches_tree(&snapshot.tree)
            || (self.archive.body_query_host().is_some()
                && !self.archive.uses_body_queries(self.queries.as_ref()))
        {
            return Err(std::io::Error::other(
                "source admission original compiler graph changed",
            ));
        }
        Ok(())
    }
}
impl QueryAttempt {
    pub(crate) fn require_source_questions(
        &mut self,
        questions: &[crate::daemon::query::QueryItem],
    ) -> std::io::Result<()> {
        if self.pending_workspace.is_some() || self.pending_diagnostic.is_some() {
            return Err(std::io::ErrorKind::Unsupported.into());
        }
        let (_, frame) = self
            .pending_source
            .as_mut()
            .ok_or(std::io::ErrorKind::InvalidInput)?;
        let frame = Arc::get_mut(frame).ok_or(std::io::ErrorKind::InvalidInput)?;
        let roster = crate::query_db::SourceQuestionRoster::capture(&frame.queries, questions)?;
        // Allocation/cancellation failure above cannot promote a partial role.
        frame.questions = Some(roster);
        frame.mode = SourceAnswersMode::Required;
        Ok(())
    }
    /// Trusted internal question-plan selection ONLY. Once the freshness frame
    /// is borrowed/issued this cannot mutate its mode. No RPC boolean/default.
    pub(crate) fn require_source_answers(&mut self) -> std::io::Result<()> {
        if self.pending_workspace.is_some() || self.pending_diagnostic.is_some() {
            return Err(std::io::ErrorKind::Unsupported.into());
        }
        let (_, frame) = self
            .pending_source
            .as_mut()
            .ok_or(std::io::ErrorKind::InvalidInput)?;
        let frame = Arc::get_mut(frame).ok_or(std::io::ErrorKind::InvalidInput)?;
        frame.mode = SourceAnswersMode::Required;
        Ok(())
    }
    pub(super) fn stage_source_snapshot(
        &mut self,
        snapshot: SourceSnapshot,
        facts: InputSnapshot,
    ) -> std::io::Result<()> {
        let frame = SourceFrameCapture::issue(&snapshot, facts)?;
        self.pending_source = Some((snapshot, frame));
        self.captured = false;
        Ok(())
    }
    pub(crate) fn pending_source(&self) -> Option<Arc<SourceFrameCapture>> {
        self.pending_source
            .as_ref()
            .map(|(_, frame)| Arc::clone(frame))
    }
    pub(crate) fn admit_source_frame(
        &mut self,
        admission: crate::request_runner::runner_freshness::SourceFrameAdmission,
    ) -> std::io::Result<()> {
        crate::daemon::control::checkpoint()?;
        if self.pending_workspace.is_some() || self.pending_diagnostic.is_some() {
            return Err(std::io::Error::other(
                "source-only admission cannot publish another capture family",
            ));
        }
        let (snapshot, frame) = self
            .pending_source
            .as_ref()
            .ok_or_else(|| std::io::Error::other("no staged normal source frame"))?;
        if !Arc::ptr_eq(frame, admission.frame()) {
            return Err(std::io::Error::other(
                "freshness admission belongs to another source frame",
            ));
        }
        frame.require_snapshot(snapshot)?;
        let publication = SourceAnswerPublication {
            tree: Arc::clone(&snapshot.tree),
            mapping: Arc::clone(&frame.mapping),
            archive: Arc::clone(&frame.archive),
            queries: Arc::clone(&frame.queries),
            // Raw preparation still supports incompatible original encodings
            // and unprofiled trees. It cannot issue a semantic source scope.
            query_request: frame.query_request,
            mode: frame.mode,
            question_frame: frame.questions.as_ref().map(|_| Arc::clone(frame)),
            eligible: frame.mode == SourceAnswersMode::Required
                && snapshot.require_semantic_source_encoding().is_ok()
                && snapshot.tree.checker_builtin_profile().is_some()
                && snapshot.tree.intrinsic_hierarchy_certified(),
        };
        let queries = Arc::clone(&frame.queries);
        let mut current = self.state.lock().unwrap_or_else(|e| e.into_inner());
        let pending = &mut self.pending_source;
        let captured = &mut self.captured;
        queries.commit_source_answer_publication(publication, |scope| {
            let (mut snapshot, _) = pending.take().expect("validated staged source");
            snapshot.source_question_role =
                scope.as_ref().is_some_and(|scope| scope.has_questions());
            snapshot.source_answers = scope;
            current.snapshot = Some(snapshot);
            *captured = true;
        })?;
        Ok(())
    }
    pub(super) fn with_current_source<T>(
        &mut self,
        consume: impl FnOnce(&mut SourceSnapshot) -> std::io::Result<T>,
    ) -> std::io::Result<T> {
        if let Some((snapshot, _)) = self.pending_source.as_mut() {
            return consume(snapshot);
        }
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        consume(
            state
                .snapshot
                .as_mut()
                .ok_or_else(|| std::io::Error::other("current source snapshot unavailable"))?,
        )
    }
}

#[cfg(test)]
#[path = "runner_query_source_admission_tests.rs"]
mod tests;
