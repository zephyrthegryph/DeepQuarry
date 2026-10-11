use super::*;
use crate::runner_host::query_snapshot::{QueryAttempt, QueryState};
use std::{
    path::Path,
    sync::{Arc, Mutex},
};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
#[test]
fn selected_rows_require_current_pins_and_explicit_existing_producer_capture() {
    let mut host = crate::runner_host::BuildHost::one_shot();
    let engine = host
        .engine(
            "project.dme".into(),
            BTreeMap::new(),
            true,
            include_bytes!("../../../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap();
    let frontend = dm_tree::frontend::FrontendRevision::new(
        dm_tree::frontend::build_with_config(
            Path::new("project.dme"),
            &Source("/proc/query_probe(x)\n    return x\n"),
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(engine.frontend_seed()),
                observer: None,
            },
        )
        .unwrap(),
    );
    let state = Arc::new(Mutex::new(QueryState::default()));
    let mut attempt = QueryAttempt::new(Arc::clone(&state), true);
    attempt.capture(&frontend);
    let mut request = QueryRequest {
        timeout_seconds: None,
        project: "project.dme".into(),
        defines: BTreeMap::new(),
        engine_template: None,
        bootstrap_catalog: true,
        expected_revision: Some(format!("{:032x}", frontend.snapshot.tree.identity())),
        queries: vec![],
        expected_source_revision: Some(format!(
            "{:032x}",
            dm_analysis::tree_export::source_revision(&frontend)
        )),
        source_queries: vec![SourceQuery::SelectedReferences {
            ordinal: frontend.bodies[0].declaration.0,
        }],
    };
    assert_eq!(
        evaluate_snapshot(&request, &frontend.snapshot.tree, &state.lock().unwrap())
            .unwrap_err()
            .kind(),
        io::ErrorKind::NotFound
    );
    let (resolver, _scalar) =
        crate::request_runner::runner_facts::prepare(&frontend, &engine.snapshot).unwrap();
    let links = engine.link_overlay().unwrap();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let memo = crate::lowering_memo::ProcedureMemo::new(123);
    crate::analysis_export::write_resolved_observed(
        &frontend,
        &engine.snapshot,
        &resolver,
        &links.inventory.spellings,
        &executor,
        &memo,
        &mut Vec::new(),
        |current| attempt.capture_selected(&frontend, current),
    )
    .unwrap();
    attempt.finish_analyzed();
    let reply =
        evaluate_snapshot(&request, &frontend.snapshot.tree, &state.lock().unwrap()).unwrap();
    validate_reply(
        &reply,
        0,
        1,
        request.expected_revision.as_deref(),
        request.expected_source_revision.as_deref(),
    )
    .unwrap();
    let envelope: serde_json::Value = serde_json::from_str(reply.jsonl.trim()).unwrap();
    assert_eq!(envelope["row"], "source_selected_references");
    assert_eq!(envelope["occurrence"], frontend.bodies[0].declaration.0);
    let mut wrong = reply.clone();
    let mut tampered = envelope.clone();
    tampered["source_revision"] = "0".repeat(32).into();
    wrong.jsonl = serde_json::to_string(&tampered).unwrap();
    assert!(validate_reply(
        &wrong,
        0,
        1,
        request.expected_revision.as_deref(),
        request.expected_source_revision.as_deref()
    )
    .is_err());
    assert!(!reply.complete);
    assert!(reply.jsonl.contains("selected_reference"));
    assert!(envelope["captured_jsonl"]
        .as_str()
        .unwrap()
        .contains("semantic_resolution_complete\":false"));
    request.expected_source_revision = Some("0".repeat(32));
    assert!(evaluate_snapshot(&request, &frontend.snapshot.tree, &state.lock().unwrap()).is_err());
    request.expected_source_revision = None;
    assert!(request.validate().is_err());
}
