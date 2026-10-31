use super::*;
use crate::input_snapshot::{
    CapturedInputRead, FileSystemInputs, FolderListing, RecordingInputs, SnapshotProvider, Stamp,
};
use crate::runner_host::{
    workspace_capture,
    workspace_discovery::{self, DiscoveryContract},
};
use std::{
    io,
    path::Path,
    sync::atomic::{AtomicUsize, Ordering},
};
struct Physical {
    reads: Mutex<BTreeMap<PathBuf, usize>>,
}
impl Physical {
    fn bump(&self, p: &Path) {
        *self
            .reads
            .lock()
            .unwrap()
            .entry(p.to_path_buf())
            .or_default() += 1;
    }
    fn reads(&self) -> usize {
        self.reads.lock().unwrap().values().sum()
    }
}
impl SnapshotProvider for Physical {
    fn stamp(&self, p: &Path) -> io::Result<Stamp> {
        FileSystemInputs.stamp(p)
    }
    fn read(&self, p: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        self.bump(p);
        FileSystemInputs.read(p)
    }
    fn read_verified(&self, p: &Path) -> io::Result<CapturedInputRead> {
        self.bump(p);
        FileSystemInputs.read_verified(p)
    }
    fn read_policy_bounded(&self, p: &Path, n: usize) -> io::Result<Option<CapturedInputRead>> {
        self.bump(p);
        FileSystemInputs.read_policy_bounded(p, n)
    }
    fn policy_directory(
        &self,
        p: &Path,
        follow: bool,
        n: usize,
    ) -> io::Result<Option<crate::input_snapshot::PolicyDirectoryListing>> {
        FileSystemInputs.policy_directory(p, follow, n)
    }
    fn source_alias(
        &self,
        p: &Path,
        c: &crate::input_snapshot::SourceAliasChallenge,
    ) -> io::Result<Option<crate::input_snapshot::SourceAliasProof>> {
        FileSystemInputs.source_alias(p, c)
    }
    fn list(&self, p: &Path) -> io::Result<FolderListing> {
        FileSystemInputs.list(p)
    }
}
fn fixture(label: &str, count: usize) -> PathBuf {
    let root = crate::test_scratch::dir(label);
    std::fs::create_dir(root.join("code")).unwrap();
    std::fs::write(root.join("p.dme"), b"#include \"code/0000.dm\"\n").unwrap();
    for i in 0..count {
        std::fs::write(
            root.join(format!("code/{i:04}.dm")),
            format!("/proc/p{i}()\n    sleep(1)\n"),
        )
        .unwrap();
    }
    root
}
fn frontend<P: SnapshotProvider>(
    root: &Path,
    inputs: &RecordingInputs<P>,
    db: &Arc<crate::query_db::QueryDb>,
) -> ColdFrontend {
    dm_tree::frontend::build(&root.join("p.dme"), inputs, &Default::default(), 1)
        .unwrap()
        .with_body_queries(db.clone())
}
fn snapshot(
    frontend: &ColdFrontend,
    db: &Arc<crate::query_db::QueryDb>,
    inputs: &RecordingInputs<impl SnapshotProvider>,
    capture: &Arc<workspace_capture::WorkspaceCapture>,
) -> SourceSnapshot {
    let state = Arc::new(Mutex::new(QueryState::default()));
    let mut attempt = QueryAttempt::new(state.clone(), true);
    let request = crate::policy_request::WorkspacePolicyRequest {
        root: capture.root().into(),
        recursive_roots: capture.recursive_roots().to_vec(),
        configuration: capture.configuration().0.into(),
    };
    attempt
        .capture_with_workspace_recorded_sources(
            frontend,
            db.clone(),
            capture.clone(),
            &request,
            inputs,
        )
        .unwrap();
    let (_, admission) = crate::request_runner::runner_freshness::admit_workspace_captured(
        inputs,
        None,
        &crate::frozen_inputs::Inputs::Live,
        &Default::default(),
        capture.clone(),
    )
    .unwrap();
    attempt.admit_workspace_policy(admission).unwrap();
    attempt.finish_analyzed();
    let mut locked = state.lock().unwrap();
    locked.snapshot.take().unwrap()
}

fn discover<P: SnapshotProvider>(
    root: &Path,
    inputs: &RecordingInputs<P>,
) -> Arc<workspace_discovery::DiscoveryReceipt> {
    Arc::new(
        workspace_discovery::discover(
            inputs,
            DiscoveryContract {
                root: root.to_path_buf(),
                recursive_roots: vec![root.join("code")],
            },
        )
        .unwrap(),
    )
}
#[test]
fn workspace_257_sources_use_same_graph_and_borrow_native_original_without_reread() {
    let root = fixture("workspace-raw-257", 257);
    let db = Arc::new(crate::query_db::QueryDb::default());
    let physical = Physical {
        reads: Mutex::new(BTreeMap::new()),
    };
    let inputs = RecordingInputs::new(&physical, 4_000_000_000);
    let frontend = frontend(&root, &inputs, &db);
    let before = physical.reads();
    let capture = workspace_capture::capture(
        &frontend,
        &inputs,
        discover(&root, &inputs),
        &root.join("missing.toml"),
    )
    .unwrap();
    assert_eq!(
        physical.reads() - before,
        257,
        "256 noncompiled files plus one proven-missing config; compiled raw is borrowed"
    );
    assert!(capture.retained_charge().unwrap() <= 64 * 1024 * 1024);
    let snapshot = snapshot(&frontend, &db, &inputs, &capture);
    let scope = snapshot.workspace_native_read().unwrap();
    let scans = Arc::new(AtomicUsize::new(0));
    let cold = db
        .workspace_raw_findings(&capture, &scope, &["scheduler".into()], scans.clone())
        .unwrap();
    assert_eq!(cold[0].run.sites.len(), 257);
    assert_eq!(scans.load(Ordering::Relaxed), 257);
    let warm = db
        .workspace_raw_findings(&capture, &scope, &["scheduler".into()], scans.clone())
        .unwrap();
    assert_eq!(warm[0].run.sites, cold[0].run.sites);
    assert_eq!(scans.load(Ordering::Relaxed), 257);
    assert_eq!(
        physical.reads() - before,
        257,
        "query performs no filesystem payload reads"
    );
}
#[test]
fn workspace_rejects_foreign_recorder_graph_and_native_mapping() {
    let root = fixture("workspace-raw-foreign", 1);
    let db = Arc::new(crate::query_db::QueryDb::default());
    let a = RecordingInputs::new(FileSystemInputs, 4_000_000_000);
    let b = RecordingInputs::new(FileSystemInputs, 5_000_000_000);
    let front = frontend(&root, &a, &db);
    let discovery = discover(&root, &a);
    assert!(
        workspace_capture::capture(&front, &b, discovery.clone(), &root.join("missing.toml"))
            .is_err()
    );
    let capture =
        workspace_capture::capture(&front, &a, discovery, &root.join("missing.toml")).unwrap();
    let snapshot = snapshot(&front, &db, &a, &capture);
    let scope = snapshot.workspace_native_read().unwrap();
    let foreign = crate::query_db::QueryDb::default();
    assert!(foreign
        .workspace_raw_findings(
            &capture,
            &scope,
            &["scheduler".into()],
            Arc::new(AtomicUsize::new(0))
        )
        .is_err());
    let front2 = frontend(&root, &b, &db);
    let capture2 =
        workspace_capture::capture(&front2, &b, discover(&root, &b), &root.join("missing.toml"))
            .unwrap();
    let snapshot2 = self::snapshot(&front2, &db, &b, &capture2);
    assert!(db
        .workspace_raw_findings(
            &capture,
            &snapshot2.workspace_native_read().unwrap(),
            &["scheduler".into()],
            Arc::new(AtomicUsize::new(0))
        )
        .is_err());
}
#[test]
fn added_file_and_missing_configuration_invalidate_complete_recorded_closure() {
    let root = fixture("workspace-raw-negative", 1);
    let db = Arc::new(crate::query_db::QueryDb::default());
    let inputs = RecordingInputs::new(FileSystemInputs, 4_000_000_000);
    let front = frontend(&root, &inputs, &db);
    let capture = workspace_capture::capture(
        &front,
        &inputs,
        discover(&root, &inputs),
        &root.join("missing.toml"),
    )
    .unwrap();
    std::fs::write(root.join("code/late.dm"), b"/datum/late\n").unwrap();
    assert!(!capture
        .facts()
        .validate(&FileSystemInputs, true, u128::MAX / 2)
        .unwrap()
        .0
        .unchanged());
    std::fs::remove_file(root.join("code/late.dm")).unwrap();
    std::fs::write(root.join("missing.toml"), b"# now present\n").unwrap();
    assert!(!capture
        .facts()
        .validate(&FileSystemInputs, true, u128::MAX / 2)
        .unwrap()
        .0
        .unchanged());
}

#[test]
fn workspace_frame_is_exact_and_failed_prepare_never_publishes_its_policy_pin() {
    let root = fixture("workspace-policy-frame", 1);
    let db = Arc::new(crate::query_db::QueryDb::default());
    let inputs = RecordingInputs::new(FileSystemInputs, 4_000_000_000);
    let front = frontend(&root, &inputs, &db);
    let capture = workspace_capture::capture(
        &front,
        &inputs,
        discover(&root, &inputs),
        &root.join("missing.toml"),
    )
    .unwrap();
    let other = workspace_capture::capture(
        &front,
        &inputs,
        discover(&root, &inputs),
        &root.join("missing.toml"),
    )
    .unwrap();
    assert_eq!(capture.policy_revision(), other.policy_revision());
    let current = snapshot(&front, &db, &inputs, &capture);
    let guard = current.workspace_native_read().unwrap();
    capture.require_scope(&guard).unwrap();
    assert!(
        other.require_scope(&guard).is_err(),
        "equal public pins do not issue another capture Arc"
    );
    let state = Arc::new(Mutex::new(QueryState::default()));
    let request = crate::policy_request::WorkspacePolicyRequest {
        root: capture.root().into(),
        recursive_roots: capture.recursive_roots().to_vec(),
        configuration: capture.configuration().0.into(),
    };
    {
        let mut attempt = QueryAttempt::new(state.clone(), true);
        attempt
            .capture_with_workspace_recorded_sources(
                &front,
                db.clone(),
                capture.clone(),
                &request,
                &inputs,
            )
            .unwrap();
        assert!(
            state.lock().unwrap().snapshot.is_none(),
            "capture is not publication"
        );
        std::fs::write(root.join("missing.toml"), b"# appeared after capture\n").unwrap();
        assert!(
            crate::request_runner::runner_freshness::admit_workspace_captured(
                &inputs,
                None,
                &crate::frozen_inputs::Inputs::Live,
                &Default::default(),
                capture.clone()
            )
            .is_err(),
            "negative configuration fact changed before preparation publication"
        );
        // No private admission receipt exists, so dropping cannot publish the staged pin.
    }
    let locked = state.lock().unwrap();
    assert!(
        locked.snapshot.is_none(),
        "failed freshness cannot replace the previously published source frame"
    );
}

#[test]
fn closure_admitted_workspace_survives_unrelated_later_backend_failure() {
    let root = fixture("workspace-policy-admitted-frontend", 1);
    let db = Arc::new(crate::query_db::QueryDb::default());
    let inputs = RecordingInputs::new(FileSystemInputs, 4_000_000_000);
    let front = frontend(&root, &inputs, &db);
    let capture = workspace_capture::capture(
        &front,
        &inputs,
        discover(&root, &inputs),
        &root.join("missing.toml"),
    )
    .unwrap();
    let state = Arc::new(Mutex::new(QueryState::default()));
    let request = crate::policy_request::WorkspacePolicyRequest {
        root: capture.root().into(),
        recursive_roots: capture.recursive_roots().to_vec(),
        configuration: capture.configuration().0.into(),
    };
    {
        let mut attempt = QueryAttempt::new(state.clone(), true);
        attempt
            .capture_with_workspace_recorded_sources(
                &front,
                db.clone(),
                capture.clone(),
                &request,
                &inputs,
            )
            .unwrap();
        let (_, admission) = crate::request_runner::runner_freshness::admit_workspace_captured(
            &inputs,
            None,
            &crate::frozen_inputs::Inputs::Live,
            &Default::default(),
            capture.clone(),
        )
        .unwrap();
        attempt.admit_workspace_policy(admission).unwrap();
        // A later backend failure does not invalidate already-proven frontend facts.
    }
    let locked = state.lock().unwrap();
    let current = locked.snapshot.as_ref().unwrap();
    assert_eq!(current.outcome, "frontend_analyzed_build_failed");
    assert_eq!(current.policy_revision, Some(capture.policy_revision()));
    capture
        .require_scope(&current.workspace_native_read().unwrap())
        .unwrap();
}

#[test]
fn policy_frames_share_actual_original_compiler_owners_and_query_without_io() {
    let root = fixture("workspace-policy-original-owner", 1);
    let db = Arc::new(crate::query_db::QueryDb::default());
    let physical = Physical {
        reads: Mutex::new(BTreeMap::new()),
    };
    let inputs = RecordingInputs::new(&physical, 4_000_000_000);
    let front = frontend(&root, &inputs, &db);
    let compiled_reads = || {
        physical
            .reads
            .lock()
            .unwrap()
            .iter()
            .filter(|(path, _)| path.file_name().is_some_and(|name| name == "0000.dm"))
            .map(|(_, count)| *count)
            .sum::<usize>()
    };
    let before = compiled_reads();
    let a = workspace_capture::capture(
        &front,
        &inputs,
        discover(&root, &inputs),
        &root.join("missing-a.toml"),
    )
    .unwrap();
    let b = workspace_capture::capture(
        &front,
        &inputs,
        discover(&root, &inputs),
        &root.join("missing-b.toml"),
    )
    .unwrap();
    let first = snapshot(&front, &db, &inputs, &a);
    let second = snapshot(&front, &db, &inputs, &b);
    assert!(Arc::ptr_eq(&first.tree, &second.tree));
    assert!(Arc::ptr_eq(
        first.source_mapping.as_ref().unwrap(),
        second.source_mapping.as_ref().unwrap()
    ));
    assert!(Arc::ptr_eq(
        first.native_raw_queries.as_ref().unwrap(),
        second.native_raw_queries.as_ref().unwrap()
    ));
    assert_ne!(first.policy_revision, second.policy_revision);
    assert_eq!(
        compiled_reads(),
        before,
        "policy contract edits do not reread the compiled original"
    );
    let reads = physical.reads();
    let guard = second.workspace_native_read().unwrap();
    let scans = Arc::new(AtomicUsize::new(0));
    let cold = db
        .workspace_raw_findings(&b, &guard, &["scheduler".into()], scans.clone())
        .unwrap();
    let warm = db
        .workspace_raw_findings(&b, &guard, &["scheduler".into()], scans.clone())
        .unwrap();
    assert_eq!(cold[0].run.sites, warm[0].run.sites);
    assert_eq!(
        physical.reads(),
        reads,
        "pinned queries do no filesystem IO"
    );
}

#[test]
fn cancelled_empty_workspace_is_not_a_clean_result() {
    let root = fixture("workspace-raw-cancelled-empty", 0);
    std::fs::write(root.join("p.dme"), b"// empty compiled input\n").unwrap();
    let db = Arc::new(crate::query_db::QueryDb::default());
    let inputs = RecordingInputs::new(FileSystemInputs, 4_000_000_000);
    let front = frontend(&root, &inputs, &db);
    let capture = workspace_capture::capture(
        &front,
        &inputs,
        discover(&root, &inputs),
        &root.join("missing.toml"),
    )
    .unwrap();
    assert_eq!(capture.file_count(), 0);
    let snapshot = snapshot(&front, &db, &inputs, &capture);
    let scope = snapshot.workspace_native_read().unwrap();
    let names = ["scheduler".to_owned()];
    assert!(db
        .workspace_raw_findings(&capture, &scope, &names, Arc::new(AtomicUsize::new(0)))
        .unwrap()[0]
        .run
        .sites
        .is_empty());
    let token = crate::daemon::control::Cancellation::default();
    let _binding = crate::daemon::control::bind_with_deadline(
        token.clone(),
        std::time::Instant::now() + std::time::Duration::from_secs(60),
    );
    token.cancel();
    let failure = db
        .workspace_raw_findings(&capture, &scope, &names, Arc::new(AtomicUsize::new(0)))
        .err()
        .expect("cancelled empty capture must refuse");
    assert_eq!(failure.kind(), std::io::ErrorKind::Interrupted);
}

#[path="runner_query_workspace_code_tests.rs"]
mod original_code_tests;
