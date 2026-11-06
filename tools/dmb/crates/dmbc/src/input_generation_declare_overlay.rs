//! Opt-in fixed-DME Declare-only typed probes. No original raw receipt,
//! installed file, raw marker source or ordinary query snapshot is issued.
use super::*;
use dm_preprocess::regions::prepared_source::PreparedSource;
use dq_analyze::{
    captured_declare_pages::RelationTypeCandidate,
    captured_generator_budget::Budget,
    captured_reactive_reads::Failure,
};
use std::sync::Arc;

pub(crate) struct DeclareOverlayProbe<'a, 'config> {
    pub(crate) defines: &'a BTreeMap<String, String>,
    pub(crate) config: dm_tree::frontend::FrontendConfig<'config>,
    pub(crate) executor: &'a dm_exec::BuildExecutor,
    pub(crate) settings: &'a Arc<dyn dm_tree::frontend::SettingExpressionQueries>,
    pub(crate) db: &'a Arc<crate::query_db::QueryDb>,
}

fn allocation(message: impl Into<String>) -> io::Error {
    io::Error::new(io::ErrorKind::OutOfMemory, message.into())
}
fn charge(budget: &Budget, bytes: usize) -> io::Result<()> {
    budget.charge(bytes).map_err(allocation)
}
fn declaration_failure(failure: dm_tree::frontend::GenerationPreparationFailure) -> Failure {
    use dm_tree::frontend::{FrontendBuildFailure, GenerationPreparationFailure};
    match failure {
        GenerationPreparationFailure::Frontend(FrontendBuildFailure::Operational(actual)) => actual.into(),
        other => Failure::Unsupported(format!("Declare overlay declaration preparation: {other:?}")),
    }
}

impl<P: SnapshotProvider> RecordingInputs<P> {
    fn prepared_overlay_original(&self, path: &Path) -> io::Result<Option<Arc<PreparedSource>>> {
        crate::daemon::control::checkpoint()?;
        let acquired = self.source_acquisitions.lock()
            .map_err(|_| invalid("generation source acquisition mutex poisoned"))?
            .get(path).cloned().ok_or_else(|| invalid("Declare overlay exposed a source outside the captured physical plan"))?;
        if !self.validate_source_acquisition(path, &acquired) {
            return Err(invalid("Declare overlay physical acquisition changed"));
        }
        Ok(Some(Arc::clone(acquired.prepared())))
    }

    pub(crate) fn probe_declare_overlay(
        &self,
        frame: &GenerationDeclarePlanBootstrap,
        staged: &str,
        candidates: &[RelationTypeCandidate],
        budget: &Arc<Budget>,
        probe: &DeclareOverlayProbe<'_, '_>,
    ) -> Result<Vec<Option<String>>, Failure> {
        frame.require_recording(self)?;
        let scope = frame.omission();
        let scratch = Budget::scoped_temporaries(budget).map_err(allocation)?;
        // Coarse pregrant for the existing prepared-source implementation:
        // text copies, logical-line vectors and their overlapping capacities.
        // Deliberately fail closed when this opt-in path cannot fit the current
        // envelope. The generated source never enters the lexical memo.
        let lines = staged.bytes().filter(|byte| *byte == b'\n').count().checked_add(1)
            .ok_or_else(|| allocation("Declare overlay line count overflow"))?;
        let lexical = staged.len().checked_mul(32).and_then(|n| n.checked_add(lines.checked_mul(1024)?))
            .and_then(|n| n.checked_add(8192)).ok_or_else(|| allocation("Declare overlay lexical grant overflow"))?;
        charge(&scratch, lexical)?;
        let source = dm_preprocess::AcquiredSource::synthetic_utf8(staged.to_owned().into(), ());
        let plan = scope.prepare(
            self, probe.defines, &source, &|path| self.prepared_overlay_original(path),
            &mut |bytes| charge(&scratch, bytes),
        )?;
        let declarations = dm_tree::frontend::prepare_generation_declarations_from_plan(
            plan, probe.config, probe.executor, probe.settings, true,
        ).map_err(declaration_failure)?;
        let bodies: Arc<dyn dm_tree::frontend::BodySyntaxQueries> = probe.db.clone();
        let questions = declarations.into_declare_type_questions(probe.config, probe.executor, bodies, probe.settings)
            .map_err(declaration_failure)?;
        for (path, lease) in questions.original_sources() {
            crate::daemon::control::checkpoint()?;
            let lease = lease.ok_or("Declare overlay source lease absent")?;
            if path == scope.path() {
                if !source.lease().same_binding(lease) || self.validate_source_lease(path, lease) {
                    return Err("Declare overlay lease was substituted or published as a physical input".into());
                }
            } else if !self.validate_source_lease(path, lease) {
                return Err("Declare overlay lost a physical source acquisition".into());
            }
        }
        questions.prepare_original_member_groups().map_err(|failure| match failure {
            dm_tree::frontend::BodySyntaxFailure::Operational(actual) => Failure::Operational(actual),
            dm_tree::frontend::BodySyntaxFailure::Syntax(error) => Failure::Unsupported(error.message),
        })?;
        let metadata = questions.generation_retained_question_charge()
            .ok_or_else(|| allocation("Declare overlay typed metadata overflow"))?;
        charge(&scratch, metadata)?;
        let answers = dq_analyze::captured_declare_pages::probe_relation_types(
            &questions, candidates, budget, &|| crate::daemon::control::checkpoint(),
        )?;
        drop(questions);
        drop(source);
        drop(scratch);
        frame.require_recording(self)?;
        Ok(answers)
    }
}
