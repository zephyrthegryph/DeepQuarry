//! Request-local selected-reference demand through the ordinary frontend pipeline.
use super::*;
use crate::daemon::query::{QueryReply, QueryRequest, SourceQuery};
pub(crate) struct Demand {
    request: QueryRequest,
    reply: Option<QueryReply>,
}
pub(crate) fn execute(
    request: &QueryRequest,
    host: &mut crate::runner_host::BuildHost,
) -> Result<QueryReply, Box<dyn std::error::Error>> {
    request.validate()?;
    let mut demand = Demand {
        request: request.clone(),
        reply: None,
    };
    let build = BuildRequest {
        command: BuildCommand::AnalyzeResolved,
        project: request.project.clone(),
        defines: request.defines.clone(),
        workers: 1,
        engine_template: request.engine_template.clone(),
        bootstrap_catalog: request.bootstrap_catalog,
        progress_enabled: false,
        output_store: None,
        exact_inputs: true,
        no_cache: false,
        cache_root: Some(crate::request::client_cache_root()?),
        record_inputs: None,
        replay_inputs: None,
        artifact_directory: None,
        no_daemon: false,
        trace_path: None,
    };
    runner_freshness::run(build, |build| {
        run_build_attempt(build, host, Some(&mut demand))
    })?;
    demand
        .reply
        .ok_or_else(|| "selected query produced no reply".into())
}
impl Demand {
    pub(super) fn complete(
        &mut self,
        frontend: &dm_tree::frontend::FrontendRevision,
        engine: &Arc<crate::runner_host::RetainedEngine>,
        facts: Option<&runner_facts::RetainedHostFacts>,
        executor: &dm_exec::BuildExecutor,
        memo: Option<&crate::lowering_memo::ProcedureMemo>,
        policy: u128,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let state = Arc::new(std::sync::Mutex::new(
            crate::runner_host::query_snapshot::QueryState::default(),
        ));
        let mut attempt =
            crate::runner_host::query_snapshot::QueryAttempt::new(Arc::clone(&state), true);
        attempt.capture(frontend);
        // The ordinary query validator checks both exact pins before any body lowering.
        let mut pins = self.request.clone();
        pins.source_queries.clear();
        pins.queries.clear();
        crate::daemon::query::evaluate_snapshot(
            &pins,
            &frontend.snapshot.tree,
            &state.lock().unwrap(),
        )?;
        let mut selected = Vec::new();
        for query in &self.request.source_queries {
            if let SourceQuery::SelectedReferences { ordinal } = query {
                let body = frontend
                    .bodies
                    .iter()
                    .find(|body| body.declaration.0 == *ordinal)
                    .ok_or_else(|| {
                        io::Error::new(
                            io::ErrorKind::InvalidInput,
                            "selected query requires a current procedure occurrence",
                        )
                    })?;
                if !selected
                    .iter()
                    .any(|old: &&dm_tree::frontend::BodyOccurrence| {
                        old.declaration == body.declaration
                    })
                {
                    selected.push(body);
                }
            }
        }
        let (resolver, _scalar) = runner_facts::prepare_retained(frontend, engine, facts)?;
        let links = engine.link_overlay()?;
        let fallback = crate::lowering_memo::ProcedureMemo::new(policy);
        crate::analysis_export::write_resolved_selected(
            frontend,
            &engine.snapshot,
            &resolver,
            &links.inventory.spellings,
            executor,
            memo.unwrap_or(&fallback),
            &mut io::sink(),
            Some(&selected),
            |current| attempt.capture_selected(frontend, current),
        )?;
        attempt.finish_analyzed();
        self.reply = Some(crate::daemon::query::evaluate_snapshot(
            &self.request,
            &frontend.snapshot.tree,
            &state.lock().unwrap(),
        )?);
        Ok(())
    }
}

pub(super) fn capture_output_digest(
    snapshot: &mut dmbc::input_snapshot::InputSnapshot,
    path: &std::path::Path,
) -> io::Result<()> {
    use dmbc::input_snapshot::{FileSystemInputs, SnapshotProvider};
    let (stamp, content) = FileSystemInputs.digest(path)?;
    snapshot.record_verified_digest(path, stamp, content)
}

#[cfg(test)]
#[path = "runner_selected_demand_tests.rs"]
mod tests;
