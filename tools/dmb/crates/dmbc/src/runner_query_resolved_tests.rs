use super::*;
use std::path::Path;
struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok("/datum/probe\n    var/value = 7\n    proc/read(argument)\n        var/static/shared = 2\n        return value + argument + shared\n".into())
    }
}
#[test]
fn resident_selected_model_uses_same_producer_after_frontend_release() {
    let mut host = crate::runner_host::BuildHost::one_shot();
    let engine = host
        .engine(
            "project.dme".into(),
            Default::default(),
            true,
            include_bytes!("../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap();
    let frontend = dm_tree::frontend::FrontendRevision::new(
        dm_tree::frontend::build_with_config(
            Path::new("project.dme"),
            &Source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(engine.frontend_seed()),
                observer: None,
            },
        )
        .unwrap(),
    );
    let (resolver, _) =
        crate::request_runner::runner_facts::prepare(&frontend, &engine.snapshot).unwrap();
    let links = engine.link_overlay().unwrap();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let memo = crate::lowering_memo::ProcedureMemo::new(123);
    let mut expected = Vec::new();
    let mut captured = None;
    crate::analysis_export::write_resolved_selected_with_owners(
        &frontend,
        &engine.snapshot,
        &resolver,
        &links.inventory.spellings,
        &executor,
        &memo,
        &mut io::sink(),
        None,
        |row: &crate::selected_query::CurrentProcedureReferences| -> std::io::Result<()> {
            row.write_jsonl(&mut expected).map_err(io::Error::other)?;
            Ok(())
        },
        |abi, startup| {
            captured = Some((Arc::clone(abi), startup));
            Ok(())
        },
    )
    .unwrap();
    let archive = frontend.body_archive().unwrap();
    let declaration = frontend.bodies[0].declaration.0;
    let (abi, startup) = captured.expect("successful SAME analysis issued owners");
    let tree = Arc::clone(&frontend.snapshot.tree);
    let source_revision = dm_analysis::tree_export::source_revision(&frontend);
    let state = Arc::new(std::sync::Mutex::new(super::super::QueryState::default()));
    let mut attempt = super::super::QueryAttempt::new(Arc::clone(&state), true);
    attempt.capture(&frontend);
    // No per-procedure rows are inserted into the bounded captured-row cache.
    attempt
        .capture_analysis_host(&frontend, resolver, abi, startup)
        .unwrap();
    attempt.finish_analyzed();
    drop(attempt);
    drop(frontend);
    let request = crate::daemon::query::QueryRequest {
        timeout_seconds: None,
        project: "project.dme".into(),
        defines: Default::default(),
        engine_template: None,
        bootstrap_catalog: true,
        expected_revision: Some(format!("{:032x}", tree.identity())),
        expected_source_revision: Some(format!("{source_revision:032x}")),
        queries: vec![],
        source_queries: vec![crate::daemon::query::SourceQuery::SelectedReferences {
            ordinal: declaration,
        }],
    };
    let answer =
        crate::daemon::query::evaluate_snapshot(&request, &tree, &state.lock().unwrap()).unwrap();
    let row: serde_json::Value = serde_json::from_str(answer.jsonl.trim()).unwrap();
    assert_eq!(row["captured_jsonl"].as_str().unwrap().as_bytes(), expected);
    assert_eq!(archive.len(), 1);
    state
        .lock()
        .unwrap()
        .snapshot
        .as_mut()
        .unwrap()
        .release_body_queries();
    assert_eq!(
        crate::daemon::query::evaluate_snapshot(&request, &tree, &state.lock().unwrap())
            .unwrap_err()
            .kind(),
        io::ErrorKind::NotFound
    );
}
