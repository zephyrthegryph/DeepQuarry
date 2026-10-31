use super::*;
use crate::input_snapshot::{
    FileSystemInputs, FolderListing, RecordingInputs, SnapshotProvider, Stamp,
};
use crate::policy_request::{PolicyInputFile, PolicyInputRequest, PolicyInputRole};
use std::{
    path::Path,
    sync::atomic::{AtomicBool, Ordering},
};
fn fixture(label: &str) -> PathBuf {
    let root = crate::test_scratch::dir(label);
    std::fs::create_dir_all(root.join("code")).unwrap();
    std::fs::write(root.join("p.dme"), b"#include \"code/a.dm\"\n").unwrap();
    std::fs::write(root.join("code/a.dm"), b"/proc/p()\n    sleep(1)\n").unwrap();
    root
}
fn staged(
    root: &Path,
    db: &Arc<crate::query_db::QueryDb>,
    policy: bool,
) -> (
    ColdFrontend,
    RecordingInputs<FileSystemInputs>,
    Option<Arc<crate::runner_host::policy_capture::CapturedPolicyInputs>>,
) {
    let inputs = RecordingInputs::new(FileSystemInputs, 4_000_000_000);
    let front = dm_tree::frontend::build(&root.join("p.dme"), &inputs, &Default::default(), 1)
        .unwrap()
        .with_body_queries(db.clone());
    let capture = policy.then(|| {
        let intent = PolicyInputRequest {workspace_generators:Vec::new(),
            workspace: None,
            files: vec![PolicyInputFile {
                path: root.join("scopes.toml"),
                role: PolicyInputRole::Configuration,
                required: false,
            }],
            search_folders: vec![],
        }
        .admit()
        .unwrap();
        Arc::new(
            crate::runner_host::policy_capture::capture(
                &front,
                &inputs,
                &intent.capture_files(),
                &[],
            )
            .unwrap()
            .bind_request(&intent)
            .unwrap(),
        )
    });
    (front, inputs, capture)
}
fn admit(attempt: &mut QueryAttempt, inputs: &RecordingInputs<FileSystemInputs>) {
    let frame = attempt.pending_source().unwrap();
    let (_, admission) = crate::request_runner::runner_freshness::admit_source_captured(
        inputs,
        None,
        &crate::frozen_inputs::Inputs::Live,
        &Default::default(),
        frame,
    )
    .unwrap();
    attempt.admit_source_frame(admission).unwrap();
}
fn publish_old(
    root: &Path,
    db: &Arc<crate::query_db::QueryDb>,
    state: &Arc<Mutex<QueryState>>,
    policy: bool,
) -> Arc<dm_tree::frontend::SourceExportMapping> {
    let (front, inputs, capture) = staged(root, db, policy);
    let mut attempt = QueryAttempt::new(state.clone(), true);
    attempt
        .capture_with_recorded_sources(&front, db.clone(), capture, &inputs)
        .unwrap();
    assert!(state.lock().unwrap().snapshot.is_none());
    assert!(attempt.policy_revision().is_none());
    admit(&mut attempt, &inputs);
    attempt.finish_analyzed();
    state
        .lock()
        .unwrap()
        .snapshot
        .as_ref()
        .unwrap()
        .source_mapping
        .as_ref()
        .unwrap()
        .clone()
}
fn require_old(
    state: &Arc<Mutex<QueryState>>,
    mapping: &Arc<dm_tree::frontend::SourceExportMapping>,
    root: &Path,
) {
    let state = state.lock().unwrap();
    let snapshot = state.snapshot.as_ref().unwrap();
    assert!(Arc::ptr_eq(
        snapshot.source_mapping.as_ref().unwrap(),
        mapping
    ));
    let mut bytes = Vec::new();
    if snapshot.native_policy_inputs.is_some() {
        snapshot
            .write_native_raw_policy_fixture(
                root,
                &root.join("scopes.toml"),
                &["scheduler".into()],
                &snapshot.tree,
                &mut bytes,
            )
            .unwrap();
        let row: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(
            row["results"][0]["sites"].as_array().unwrap().len(),
            1,
            "old prepared capture remains queryable without reading current disk"
        );
    } else {
        snapshot.occurrence(0, &snapshot.tree).unwrap();
    }
}
#[test]
fn normal_source_frame_drop_never_publishes_a_candidate_pin_or_replaces_previous_frame() {
    let root = fixture("normal-source-drop");
    let db = Arc::new(crate::query_db::QueryDb::default());
    let state = Arc::new(Mutex::new(QueryState::default()));
    let old = publish_old(&root, &db, &state, true);
    std::fs::write(
        root.join("code/a.dm"),
        b"/proc/p()\n    sleep(2)\n// candidate\n",
    )
    .unwrap();
    let (front, inputs, capture) = staged(&root, &db, true);
    let candidate = capture.as_ref().unwrap().policy_revision();
    {
        let mut attempt = QueryAttempt::new(state.clone(), true);
        attempt
            .capture_with_recorded_sources(&front, db, capture, &inputs)
            .unwrap();
        assert!(attempt.pending_source().is_some());
        assert!(attempt.policy_revision().is_none());
        assert_ne!(
            state
                .lock()
                .unwrap()
                .snapshot
                .as_ref()
                .unwrap()
                .policy_revision,
            candidate
        );
        require_old(&state, &old, &root);
    }
    require_old(&state, &old, &root);
}
struct MutatingFileSystem {
    path: PathBuf,
    bytes: &'static [u8],
    fired: AtomicBool,
}
impl MutatingFileSystem {
    fn mutate(&self) {
        if !self.fired.swap(true, Ordering::SeqCst) {
            std::fs::write(&self.path, self.bytes).unwrap();
        }
    }
}
impl SnapshotProvider for MutatingFileSystem {
    fn stamp(&self, path: &Path) -> std::io::Result<Stamp> {
        self.mutate();
        FileSystemInputs.stamp(path)
    }
    fn read(&self, _: &Path) -> std::io::Result<(Stamp, Vec<u8>)> {
        panic!("freshness must not reread payloads")
    }
    fn list(&self, path: &Path) -> std::io::Result<FolderListing> {
        self.mutate();
        FileSystemInputs.list(path)
    }
}
#[test]
fn normal_policy_config_appearing_during_real_filesystem_barrier_keeps_old_frame() {
    let root = fixture("normal-config-barrier");
    let db = Arc::new(crate::query_db::QueryDb::default());
    let state = Arc::new(Mutex::new(QueryState::default()));
    let old = publish_old(&root, &db, &state, true);
    let (front, inputs, capture) = staged(&root, &db, true);
    let mut attempt = QueryAttempt::new(state.clone(), true);
    attempt
        .capture_with_recorded_sources(&front, db, capture, &inputs)
        .unwrap();
    let provider = MutatingFileSystem {
        path: root.join("scopes.toml"),
        bytes: b"[lint.scheduler]\nexempt_contains=[\"a.dm\"]\n",
        fired: AtomicBool::new(false),
    };
    assert!(
        crate::request_runner::runner_freshness::admit_source_captured_with_provider_for_test(
            &inputs,
            &provider,
            attempt.pending_source().unwrap()
        )
        .is_err()
    );
    assert!(provider.fired.load(Ordering::SeqCst));
    assert!(attempt.policy_revision().is_none());
    drop(attempt);
    require_old(&state, &old, &root);
}
#[test]
fn source_only_change_during_real_filesystem_barrier_keeps_previous_epoch() {
    let root = fixture("normal-source-barrier");
    let db = Arc::new(crate::query_db::QueryDb::default());
    let state = Arc::new(Mutex::new(QueryState::default()));
    let old = publish_old(&root, &db, &state, false);
    let (front, inputs, capture) = staged(&root, &db, false);
    let mut attempt = QueryAttempt::new(state.clone(), true);
    attempt
        .capture_with_recorded_sources(&front, db, capture, &inputs)
        .unwrap();
    let provider = MutatingFileSystem {
        path: root.join("code/a.dm"),
        bytes: b"/proc/p()\n    sleep(9)\n// changed while restatting\n",
        fired: AtomicBool::new(false),
    };
    assert!(
        crate::request_runner::runner_freshness::admit_source_captured_with_provider_for_test(
            &inputs,
            &provider,
            attempt.pending_source().unwrap()
        )
        .is_err()
    );
    drop(attempt);
    require_old(&state, &old, &root);
}
#[test]
fn normal_frame_cancellation_after_real_freshness_still_cannot_publish() {
    let root = fixture("normal-source-cancel");
    let db = Arc::new(crate::query_db::QueryDb::default());
    let state = Arc::new(Mutex::new(QueryState::default()));
    let old = publish_old(&root, &db, &state, true);
    let (front, inputs, capture) = staged(&root, &db, true);
    let mut attempt = QueryAttempt::new(state.clone(), true);
    attempt
        .capture_with_recorded_sources(&front, db, capture, &inputs)
        .unwrap();
    let (_, admission) = crate::request_runner::runner_freshness::admit_source_captured(
        &inputs,
        None,
        &crate::frozen_inputs::Inputs::Live,
        &Default::default(),
        attempt.pending_source().unwrap(),
    )
    .unwrap();
    {
        let token = crate::daemon::control::Cancellation::default();
        let _binding = crate::daemon::control::bind_with_deadline(
            token.clone(),
            std::time::Instant::now() + std::time::Duration::from_secs(30),
        );
        token.cancel();
        assert!(attempt.admit_source_frame(admission).is_err());
    }
    drop(attempt);
    require_old(&state, &old, &root);
}
#[test]
fn genuinely_admitted_normal_frontend_survives_later_backend_failure() {
    let root = fixture("normal-admitted-backend-failure");
    let db = Arc::new(crate::query_db::QueryDb::default());
    let state = Arc::new(Mutex::new(QueryState::default()));
    let (front, inputs, capture) = staged(&root, &db, true);
    let pin = capture.as_ref().unwrap().policy_revision();
    {
        let mut attempt = QueryAttempt::new(state.clone(), true);
        attempt
            .capture_with_recorded_sources(&front, db, capture, &inputs)
            .unwrap();
        assert!(state.lock().unwrap().snapshot.is_none());
        admit(&mut attempt, &inputs);
    }
    let state = state.lock().unwrap();
    let snapshot = state.snapshot.as_ref().unwrap();
    assert_eq!(snapshot.policy_revision, pin);
    assert_eq!(snapshot.outcome, "frontend_analyzed_build_failed");
}
#[test]
fn source_admission_rejects_equal_foreign_frame_and_foreign_query_db() {
    let root = fixture("normal-source-exact-owner");
    let db = Arc::new(crate::query_db::QueryDb::default());
    let state = Arc::new(Mutex::new(QueryState::default()));
    let (front, inputs, capture) = staged(&root, &db, true);
    let mut a = QueryAttempt::new(state.clone(), true);
    a.capture_with_recorded_sources(&front, db.clone(), capture.clone(), &inputs)
        .unwrap();
    let mut b = QueryAttempt::new(Arc::new(Mutex::new(QueryState::default())), true);
    b.capture_with_recorded_sources(&front, db.clone(), capture.clone(), &inputs)
        .unwrap();
    let (_, foreign) = crate::request_runner::runner_freshness::admit_source_captured(
        &inputs,
        None,
        &crate::frozen_inputs::Inputs::Live,
        &Default::default(),
        b.pending_source().unwrap(),
    )
    .unwrap();
    assert!(a.admit_source_frame(foreign).is_err());
    assert!(state.lock().unwrap().snapshot.is_none());
    let mut wrong = QueryAttempt::new(state, true);
    assert!(wrong
        .capture_with_recorded_sources(
            &front,
            Arc::new(crate::query_db::QueryDb::default()),
            capture,
            &inputs
        )
        .is_err());
}

#[test]
fn source_frame_without_optional_body_graph_is_admitted_without_inventing_one() {
    let root = fixture("normal-source-no-body-graph");
    let db = Arc::new(crate::query_db::QueryDb::default());
    let inputs = RecordingInputs::new(FileSystemInputs, 4_000_000_000);
    let front =
        dm_tree::frontend::build(&root.join("p.dme"), &inputs, &Default::default(), 1).unwrap();
    let state = Arc::new(Mutex::new(QueryState::default()));
    let mut attempt = QueryAttempt::new(state.clone(), true);
    attempt
        .capture_with_recorded_sources(&front, db, None, &inputs)
        .unwrap();
    assert!(attempt
        .pending_source
        .as_ref()
        .unwrap()
        .0
        .body_archive
        .as_ref()
        .unwrap()
        .body_query_host()
        .is_none());
    assert!(state.lock().unwrap().snapshot.is_none());
    admit(&mut attempt, &inputs);
    let state = state.lock().unwrap();
    let snapshot = state.snapshot.as_ref().unwrap();
    assert!(snapshot
        .body_archive
        .as_ref()
        .unwrap()
        .body_query_host()
        .is_none());
    assert!(Arc::ptr_eq(&snapshot.tree, &front.snapshot.tree));
}
