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
    let mut analysis_output = Vec::new();
    let returned = crate::analysis_export::write_resolved_selected_with_owners(
        &frontend,
        &engine.snapshot,
        &resolver,
        &links.inventory.spellings,
        &executor,
        &memo,
        &mut analysis_output,
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
    assert_eq!(
        returned, 1,
        "ordinary analysis must issue this static-bearing procedure"
    );
    assert!(
        !expected.is_empty(),
        "the independently produced current oracle must contain references"
    );
    for line in String::from_utf8(analysis_output).unwrap().lines() {
        let row: serde_json::Value = serde_json::from_str(line).unwrap();
        assert_ne!(
            row["row"], "diagnostic",
            "ordinary producer diagnostic: {row}"
        );
    }
    let archive = frontend.body_archive().unwrap();
    let declaration = frontend.bodies[0].declaration.0;
    let (abi, startup) = captured.expect("successful SAME analysis issued owners");
    let static_plan = startup.procedure(frontend.bodies[0].declaration).unwrap();
    let question = crate::daemon::query::QueryItem {
        subject: Some("actual procedure static".into()),
        query: dm_ir::ResolveQuery::ProcedureStatic {
            procedure: static_plan.procedure,
            name: static_plan.declarations[0].identity.name,
        },
    };
    let mut expected_host = Vec::new();
    let ordinary = dm_tree::procedure_statics::StaticResolver::from_inventory(
        &resolver,
        Arc::clone(startup.static_inventory()),
    )
    .unwrap();
    dm_analysis::tree_export::write_queries_jsonl(
        startup.plan().symbols.as_ref(),
        &ordinary,
        [dm_analysis::tree_export::AnalysisQuery {
            subject: question.subject.as_deref(),
            query: question.query,
        }],
        &mut expected_host,
    )
    .unwrap();
    let expected_host_row: serde_json::Value = serde_json::from_slice(&expected_host).unwrap();
    assert_eq!(expected_host_row["answer"]["name"]["text"], "shared");
    assert_eq!(expected_host_row["answer"]["kind"], "procedure_static");
    drop(ordinary);
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
    let mut request = crate::daemon::query::QueryRequest {
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
    assert!(
        String::from_utf8(expected).unwrap().contains("shared"),
        "the full ordinary oracle must retain the procedure static reference"
    );
    request.source_queries = vec![crate::daemon::query::SourceQuery::ResolvedQueries {
        queries: vec![question.clone()],
    }];
    let answer =
        crate::daemon::query::evaluate_snapshot(&request, &tree, &state.lock().unwrap()).unwrap();
    let row: serde_json::Value = serde_json::from_str(answer.jsonl.trim()).unwrap();
    assert_eq!(
        row["captured_jsonl"].as_str().unwrap().as_bytes(),
        expected_host
    );
    assert!(String::from_utf8(expected_host)
        .unwrap()
        .contains("procedure_static"));
    let mut stale = request.clone();
    stale.expected_source_revision = Some("00000000000000000000000000000000".into());
    assert_eq!(
        crate::daemon::query::evaluate_snapshot(&stale, &tree, &state.lock().unwrap())
            .unwrap_err()
            .kind(),
        io::ErrorKind::InvalidInput
    );
    let mut unpinned = request.clone();
    unpinned.expected_source_revision = None;
    assert_eq!(
        crate::daemon::query::evaluate_snapshot(&unpinned, &tree, &state.lock().unwrap())
            .unwrap_err()
            .kind(),
        io::ErrorKind::InvalidInput
    );
    let mut oversized = request.clone();
    oversized.source_queries = vec![crate::daemon::query::SourceQuery::ResolvedQueries {
        queries: vec![question; 129],
    }];
    assert_eq!(
        crate::daemon::query::evaluate_snapshot(&oversized, &tree, &state.lock().unwrap())
            .unwrap_err()
            .kind(),
        io::ErrorKind::InvalidInput
    );
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

#[test]
fn explicit_query_preparation_issues_host_without_lowering_invalid_body() {
    struct Unlowered;
    impl dm_preprocess::SourceProvider for Unlowered {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/datum/probe\n    var/value = 7\n    proc/read()\n        return formerly_missing()\n".into())
        }
    }
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
            &Unlowered,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(engine.frontend_seed()),
                observer: None,
            },
        )
        .unwrap(),
    );
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let state = Arc::new(std::sync::Mutex::new(super::super::QueryState::default()));
    let mut attempt = super::super::QueryAttempt::new(Arc::clone(&state), true);
    attempt.capture(&frontend);
    let result = crate::request_runner::runner_analysis::prepare_query(
        &frontend,
        Some(&engine),
        None,
        &executor,
        None,
        123,
        &mut attempt,
        true,
    )
    .unwrap();
    let crate::request::BuildOutcome::QueryPrepared {
        semantic_revision,
        source_revision,
        retained,
    } = result
    else {
        panic!("preparation outcome")
    };
    assert!(retained);
    assert_eq!(
        semantic_revision,
        format!("{:032x}", frontend.snapshot.tree.identity())
    );
    assert_eq!(
        source_revision,
        format!(
            "{:032x}",
            dm_analysis::tree_export::source_revision(&frontend)
        )
    );
    // No full-model emission or body lowering was needed to issue the host.
    attempt.finish_analyzed();
    let state = state.lock().unwrap();
    let snapshot = state.snapshot.as_ref().unwrap();
    let mut output = Vec::new();
    snapshot
        .write_resolved_queries(
            &[crate::daemon::query::QueryItem {
                subject: Some("current owner".into()),
                query: dm_ir::ResolveQuery::RuntimeType(frontend.snapshot.tree.types()[0].path),
            }],
            &frontend.snapshot.tree,
            &mut output,
        )
        .unwrap();
    assert!(!output.is_empty());
}
