use super::*;
use crate::input_snapshot::{FileSystemInputs, RecordingInputs};
const SOURCE: &str =
    "/datum/base\n    var/SpacemanDMM_private/p=null\n/datum/base/child\n    var/p=null\n";
fn staged(
    label: &str,
    checker: Option<&[u8]>,
) -> (
    PathBuf,
    dm_tree::frontend::DiagnosticFrontend,
    Arc<crate::query_db::QueryDb>,
    Arc<crate::runner_host::policy_capture::CapturedPolicyInputs>,
    RecordingInputs<FileSystemInputs>,
) {
    let root = crate::test_scratch::dir(label);
    std::fs::write(root.join("p.dme"), SOURCE).unwrap();
    if let Some(bytes) = checker {
        std::fs::write(root.join("SpacemanDMM.toml"), bytes).unwrap();
    }
    let inputs = RecordingInputs::new(FileSystemInputs, 4_000_000_000);
    let db = Arc::new(crate::query_db::QueryDb::default());
    let mut host = crate::runner_host::BuildHost::one_shot();
    let engine = host
        .engine(
            root.join("p.dme"),
            Default::default(),
            true,
            include_bytes!("../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let front = dm_tree::frontend::build_for_checker_diagnostics(
        &root.join("p.dme"),
        &inputs,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(engine.frontend_seed()),
            observer: None,
        },
        None,
        &executor,
    )
    .unwrap()
    .with_body_queries(db.clone())
    .unwrap();
    let intent = crate::policy_request::PolicyInputRequest {analysis_context:None,workspace_auxiliary:Vec::new(),workspace_generators:Vec::new(),
        workspace: None,
        files: vec![crate::policy_request::PolicyInputFile {
            path: root.join("SpacemanDMM.toml"),
            role: crate::policy_request::PolicyInputRole::Configuration,
            required: false,
        }],
        search_folders: vec![],
    }
    .admit()
    .unwrap();
    let capture = Arc::new(
        crate::runner_host::policy_capture::capture_diagnostic(
            &front.source_view().unwrap(),
            &inputs,
            &intent.capture_files(),
            &[],
        )
        .unwrap()
        .bind_request(&intent)
        .unwrap()
        .bind_diagnostic_profile()
        .unwrap(),
    );
    (root, front, db, capture, inputs)
}
fn admit(
    inputs: &RecordingInputs<FileSystemInputs>,
    capture: Arc<crate::runner_host::policy_capture::CapturedPolicyInputs>,
) -> crate::request_runner::runner_freshness::DiagnosticPolicyAdmission {
    crate::request_runner::runner_freshness::admit_diagnostic_captured(
        inputs,
        None,
        &crate::frozen_inputs::Inputs::Live,
        &Default::default(),
        capture,
    )
    .unwrap()
    .1
}
#[test]
fn diagnostic_frame_is_private_until_actual_freshness_and_runs_original_untagged_case() {
    let (root, front, db, capture, inputs) = staged("diagnostic-original-untagged", None);
    let state = Arc::new(Mutex::new(QueryState::default()));
    let mut attempt = QueryAttempt::new(state.clone(), true);
    attempt
        .stage_diagnostic(&front.source_view().unwrap(), db, capture.clone())
        .unwrap();
    assert!(
        state.lock().unwrap().snapshot.is_none(),
        "capture is not checker-policy publication"
    );
    attempt
        .admit_diagnostic_policy(admit(&inputs, capture))
        .unwrap();
    attempt.finish_analyzed();
    drop(attempt);
    let locked = state.lock().unwrap();
    let snapshot = locked.snapshot.as_ref().unwrap();
    assert!(Arc::ptr_eq(
        snapshot.diagnostic_tree().unwrap(),
        front.source_view().unwrap().tree()
    ));
    assert!(
        snapshot.resolved.is_none()
            && snapshot.native_value_input.is_none()
            && snapshot.native_value_queries.is_none(),
        "no ABI/value-admission receipt may escape the diagnostic source frame"
    );
    let mut out = Vec::new();
    snapshot
        .write_native_configured_variable_visibility(
            &root.join("p.dme"),
            None,
            &snapshot.tree,
            &mut out,
        )
        .unwrap();
    let row: serde_json::Value = serde_json::from_slice(&out).unwrap();
    let rows = row["diagnostics"].as_array().unwrap();
    assert_eq!(rows.len(), 2);
    assert_eq!(rows[0]["registration_tag"], serde_json::Value::Null);
    assert_eq!(rows[0]["severity"], "error");
    assert_eq!(rows[0]["origin"]["line"], 4);
    assert_eq!(rows[0]["notes"][0]["source"]["line"], 2);
    assert!(rows[0]["message"]
        .as_str()
        .unwrap()
        .contains("redeclares var"));
    assert_eq!(rows[1]["registration_tag"], "private_var");
    assert!(
        front.try_into_compilable().is_err(),
        "checker success is not executable admission"
    );
}
#[test]
fn failed_diagnostic_freshness_does_not_publish_current_frame_or_pin() {
    let (root, front, db, capture, inputs) = staged("diagnostic-failed-freshness", None);
    let state = Arc::new(Mutex::new(QueryState::default()));
    {
        let mut attempt = QueryAttempt::new(state.clone(), true);
        attempt
            .stage_diagnostic(&front.source_view().unwrap(), db, capture.clone())
            .unwrap();
        std::fs::write(root.join("SpacemanDMM.toml"), b"# appeared after capture\n").unwrap();
        assert!(
            crate::request_runner::runner_freshness::admit_diagnostic_captured(
                &inputs,
                None,
                &crate::frozen_inputs::Inputs::Live,
                &Default::default(),
                capture
            )
            .is_err()
        );
    }
    assert!(
        state.lock().unwrap().snapshot.is_none(),
        "Drop cannot leak an unadmitted diagnostic frame"
    );
}
#[test]
fn diagnostic_current_frame_refuses_foreign_db_and_equal_foreign_capture() {
    let (_, front, db, capture, inputs) = staged("diagnostic-exact-binding", None);
    let state = Arc::new(Mutex::new(QueryState::default()));
    let mut attempt = QueryAttempt::new(state.clone(), true);
    assert!(attempt
        .stage_diagnostic(
            &front.source_view().unwrap(),
            Arc::new(crate::query_db::QueryDb::default()),
            capture.clone()
        )
        .is_err());
    attempt
        .stage_diagnostic(&front.source_view().unwrap(), db, capture)
        .unwrap();
    let (_, _, _, foreign, foreign_inputs) = staged("diagnostic-foreign-capture", None);
    assert!(attempt
        .admit_diagnostic_policy(admit(&foreign_inputs, foreign))
        .is_err());
    assert!(state.lock().unwrap().snapshot.is_none());
    let correct = attempt.pending_diagnostic_policy().unwrap();
    attempt
        .admit_diagnostic_policy(admit(&inputs, correct))
        .unwrap();
    // Deliberate later failure after actual frontend admission preserves it.
    drop(attempt);
    assert!(state
        .lock()
        .unwrap()
        .snapshot
        .as_ref()
        .unwrap()
        .diagnostic_tree()
        .is_some());
}

#[test]
fn diagnostic_untagged_redeclaration_survives_disabled_registered_families() {
    let (root, front, db, capture, inputs) = staged(
        "diagnostic-original-off",
        Some(b"[diagnostics]\nprivate_var='off'\nvariable_redeclaration='off'\n"),
    );
    let state = Arc::new(Mutex::new(QueryState::default()));
    let mut attempt = QueryAttempt::new(state.clone(), true);
    attempt
        .stage_diagnostic(&front.source_view().unwrap(), db, capture.clone())
        .unwrap();
    attempt
        .admit_diagnostic_policy(admit(&inputs, capture))
        .unwrap();
    attempt.finish_analyzed();
    let locked = state.lock().unwrap();
    let snapshot = locked.snapshot.as_ref().unwrap();
    let mut out = Vec::new();
    snapshot
        .write_native_configured_variable_visibility(
            &root.join("p.dme"),
            None,
            &snapshot.tree,
            &mut out,
        )
        .unwrap();
    let row: serde_json::Value = serde_json::from_slice(&out).unwrap();
    let rows = row["diagnostics"].as_array().unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["registration_tag"], serde_json::Value::Null);
    assert_eq!(rows[0]["origin"]["line"], 4);
    assert_eq!(rows[0]["notes"][0]["source"]["line"], 2);
}
