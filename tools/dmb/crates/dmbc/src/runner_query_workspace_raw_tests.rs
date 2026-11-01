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
    fail_policy: Mutex<Option<PathBuf>>,
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
        if self.fail_policy.lock().unwrap().as_ref().is_some_and(|failed|failed==p){return Err(io::Error::from_raw_os_error(1450));}
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
        fail_policy: Mutex::new(None),
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
        fail_policy: Mutex::new(None),
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

#[test]
fn actual_raw_next_cohort_spans_original_workspace_pages_and_cancellation_without_reread(){
 let root=fixture("workspace-raw-next-129",129);
 for index in 0..129{std::fs::write(root.join(format!("code/{index:04}.dm")),format!("/proc/p{index}()\n    emag_act()\n    qdel(src)\n    usr.visible_message(\"raw fixture\")\n    verbs += /proc/p0 // ALLOW(sys_verb_write): this is deliberately ineffective annotation\n    add_overlay(\"fixture\")\n")).unwrap();}
 let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new()),fail_policy:Mutex::new(None)};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=frontend(&root,&inputs,&db);let capture=workspace_capture::capture(&front,&inputs,discover(&root,&inputs),&root.join("missing.toml")).unwrap();let snapshot=snapshot(&front,&db,&inputs,&capture);let scope=snapshot.workspace_native_read().unwrap();let names:Vec<String>=["lifeform_allows","escape_hatches","sys/contents","sys/damage_reactions","sys/emag","sys/grants","sys/dx_manual_transfer","sys/dx_raw_delay","sys/dx_raw_overlays","sys/dx_review","sys/messages","sys/presentation","sys/topic","sys/usr_use"].iter().map(|name|(*name).into()).collect();let before=physical.reads();let scans=Arc::new(AtomicUsize::new(0));let cold=db.workspace_raw_findings(&capture,&scope,&names,scans.clone()).unwrap();assert_eq!(cold.len(),14);for name in ["sys/emag","sys/grants","sys/dx_raw_overlays"]{let run=&cold.iter().find(|row|row.name==name).unwrap().run;assert_eq!(run.sites.len(),129,"{name} must cover uncompiled second page");assert!(run.sites.windows(2).all(|w|w[0].rel<w[1].rel));}
 let warm=db.workspace_raw_findings(&capture,&scope,&names,scans.clone()).unwrap();for(a,b)in cold.iter().zip(&warm){assert_eq!(a.run.sites,b.run.sites);assert_eq!(a.allow_used,b.allow_used);}assert_eq!(physical.reads(),before);
 let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(60));token.cancel();let error=db.workspace_raw_findings(&capture,&scope,&names,scans.clone()).err().expect("cancelled warm source must refuse");assert_eq!(error.kind(),io::ErrorKind::Interrupted);drop(binding);assert_eq!(db.workspace_raw_findings(&capture,&scope,&names,scans).unwrap().len(),14);assert_eq!(physical.reads(),before);
}
#[test]
fn actual_raw_next_late_original_provider_io_preserves_os_error_and_retry(){let root=fixture("workspace-raw-next-provider",129);let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new()),fail_policy:Mutex::new(Some(root.join("code/0128.dm")))};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=frontend(&root,&inputs,&db);let discovery=discover(&root,&inputs);let error=workspace_capture::capture(&front,&inputs,discovery.clone(),&root.join("missing.toml")).err().expect("late original IO is not source absence");assert_eq!(error.raw_os_error(),Some(1450));*physical.fail_policy.lock().unwrap()=None;let capture=workspace_capture::capture(&front,&inputs,discovery,&root.join("missing.toml")).unwrap();let snapshot=snapshot(&front,&db,&inputs,&capture);let names=vec!["escape_hatches".into(),"sys/emag".into()];assert_eq!(db.workspace_raw_findings(&capture,&snapshot.workspace_native_read().unwrap(),&names,Arc::new(AtomicUsize::new(0))).unwrap().len(),2);}

#[test]
fn actual_deadline_native_policy_spans_original_pages_warm_cancel_and_keeps_custom_judgment_separate(){
 let root=fixture("workspace-deadline-129",129);
 for i in 0..129{std::fs::write(root.join(format!("code/{i:04}.dm")),format!("/obj/probe{i}/process()\n\tif(world.time > expires)\n\t\treturn\n")).unwrap();}
 let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new()),fail_policy:Mutex::new(None)};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=frontend(&root,&inputs,&db);let capture=workspace_capture::capture(&front,&inputs,discover(&root,&inputs),&root.join("missing.toml")).unwrap();let snapshot=snapshot(&front,&db,&inputs,&capture);let scope=snapshot.workspace_native_read().unwrap();let names=vec!["deadline_polling".into()];let before=physical.reads();let scans=Arc::new(AtomicUsize::new(0));let cold=db.workspace_raw_findings(&capture,&scope,&names,scans.clone()).unwrap();assert_eq!(cold.len(),1);assert_eq!(cold[0].run.sites.len(),129,"the uncompiled second source page must be scanned");assert_eq!(cold[0].run.sites[0].key,"code/0000.dm:/obj/probe0/process");assert!(cold[0].run.sites.windows(2).all(|w|w[0].rel<w[1].rel));
 let warm=db.workspace_raw_findings(&capture,&scope,&names,scans.clone()).unwrap();assert_eq!(cold[0].run.sites,warm[0].run.sites);assert_eq!(physical.reads(),before);
 let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(60));token.cancel();assert_eq!(db.workspace_raw_findings(&capture,&scope,&names,scans.clone()).err().unwrap().kind(),io::ErrorKind::Interrupted);drop(binding);assert_eq!(db.workspace_raw_findings(&capture,&scope,&names,scans).unwrap()[0].run.sites.len(),129);assert_eq!(physical.reads(),before);
}

#[test]
fn actual_full_hygiene_dispatch_requires_meta_code_maps_eof_and_preserves_phase_allow_text(){
 let root=fixture("workspace-hygiene-full-129",129);std::fs::create_dir(root.join("maps")).unwrap();
 for index in 0..129{std::fs::write(root.join(format!("code/{index:04}.dm")),format!("/obj/probe{index}
	var/cached_charge
/obj/probe{index}/process()
	if(world.time > next_move) // ALLOW(sys_deadline_poll): a deliberate full-source annotation for this test
		return
	cached_charge = 2
	// ALLOW(scheduler): baseline when ci was wired
")).unwrap();}
 std::fs::write(root.join("maps/extra.dm"),"/obj/map_probe
	var/cached_charge
	// ALLOW(scheduler): baseline when ci was wired
").unwrap();
 let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new()),fail_policy:Mutex::new(None)};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=frontend(&root,&inputs,&db);let discovery=Arc::new(workspace_discovery::discover(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps")]}).unwrap());let capture=workspace_capture::capture(&front,&inputs,discovery,&root.join("missing.toml")).unwrap();let snapshot=snapshot(&front,&db,&inputs,&capture);let scope=snapshot.workspace_native_read().unwrap();let before=physical.reads();
 let check=|data:&dq_analyze::captured_sys_hygiene_pages::HygieneData|{assert!(data.sites().iter().any(|s|s.rel=="maps/extra.dm"));assert!(data.sites().iter().any(|s|s.rel=="code/0128.dm"));let rank=|rule:&str|match rule{"annotation_boilerplate"=>0,"cached_var"=>1,"deadline_poll"=>2,_=>panic!("actual original rule")};assert!(data.sites().windows(2).all(|w|(rank(&w[0].rule),w[0].rel.as_str())<=(rank(&w[1].rule),w[1].rel.as_str())));assert_eq!(data.allow_used().len(),129);assert_eq!(data.source_text().len(),data.sites().len());Ok((serde_json::to_vec(data.sites()).unwrap(),serde_json::to_vec(data.allow_used()).unwrap(),data.source_text().to_vec()))};
 let write_error=db.with_workspace_hygiene(&capture,&scope,|_|Err::<(),_>(io::Error::from_raw_os_error(1450))).err().unwrap();assert_eq!(write_error.raw_os_error(),Some(1450));let cold=db.with_workspace_hygiene(&capture,&scope,check).unwrap();let warm=db.with_workspace_hygiene(&capture,&scope,check).unwrap();assert_eq!(cold,warm);assert_eq!(physical.reads(),before,"complete original pages do not reread payloads");
 let foreign=crate::query_db::QueryDb::default();assert!(foreign.with_workspace_hygiene(&capture,&scope,|_| -> io::Result<()> {panic!("foreign Db cannot publish")}).is_err());
 let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(60));token.cancel();let error=db.with_workspace_hygiene(&capture,&scope,|_| -> io::Result<()> {panic!("canceled full fold cannot publish")}).err().unwrap();assert_eq!(error.kind(),io::ErrorKind::Interrupted);drop(binding);db.with_workspace_hygiene(&capture,&scope,|_|Ok(())).unwrap();
}
#[test]
fn actual_hygiene_code_only_discovery_cannot_promote_to_code_maps_scope(){let root=fixture("workspace-hygiene-code-only",1);std::fs::create_dir(root.join("maps")).unwrap();std::fs::write(root.join("maps/hidden-input.dm"),"/obj/map_only
	var/cached_charge
").unwrap();let db=Arc::new(crate::query_db::QueryDb::default());let inputs=RecordingInputs::new(FileSystemInputs,4_000_000_000);let front=frontend(&root,&inputs,&db);let capture=workspace_capture::capture(&front,&inputs,discover(&root,&inputs),&root.join("missing.toml")).unwrap();let snapshot=snapshot(&front,&db,&inputs,&capture);let error=db.with_workspace_hygiene(&capture,&snapshot.workspace_native_read().unwrap(),|_| -> io::Result<()> {panic!("CODE-only receipt cannot publish Hygiene")}).err().unwrap();assert_eq!(error.kind(),io::ErrorKind::InvalidInput);}

#[test]
fn hygiene_actual_captured_exempt_source_skips_normalization_before_page_loan(){
 let root=fixture("workspace-hygiene-exempt-before-view",1);std::fs::create_dir(root.join("maps")).unwrap();std::fs::write(root.join("code/exempt.dm"),"// intentionally exempt retained original\r\n".repeat(12_000)).unwrap();std::fs::write(root.join("scopes.toml"),r#"[lint."sys/hygiene"]
exempt_files=['code/exempt.dm']
"#).unwrap();
 let db=Arc::new(crate::query_db::QueryDb::default());let inputs=RecordingInputs::new(FileSystemInputs,4_000_000_000);let front=frontend(&root,&inputs,&db);let discovery=Arc::new(workspace_discovery::discover(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps")]}).unwrap());let capture=workspace_capture::capture(&front,&inputs,discovery,&root.join("scopes.toml")).unwrap();let snapshot=snapshot(&front,&db,&inputs,&capture);let scope=snapshot.workspace_native_read().unwrap();let config=dq_analyze::captured_raw_file::Config::capture(dq_analyze::captured_raw_policy::Configuration::Captured(capture.configuration().1.unwrap())).unwrap();let (files,end)=capture.hygiene_page(&scope,0,128,32*1024,&config,"sys/hygiene","sys").unwrap();assert_eq!(end,capture.file_count());let exempt=files.iter().find(|f|f.path.file_name().unwrap()=="exempt.dm").unwrap();assert!(exempt.text.is_none(),"actual interpreted exemption is applied before original normalization");drop(files);db.with_workspace_hygiene(&capture,&scope,|data|{assert!(data.sites().iter().all(|s|s.rel!="code/exempt.dm"));Ok(())}).unwrap();
}

#[test]
fn actual_resolver_full_dispatch_uses_two_original_eofs_and_uncompiled_map_roots_without_reread(){let root=fixture("workspace-resolver-two-pass-129",129);std::fs::create_dir(root.join("maps")).unwrap();std::fs::write(root.join("maps/roots.dm"),"CAPABILITIES(/obj/resolved)
	map_resolver(GLOBAL_PROC_REF(resolve))
").unwrap();for index in 0..129{std::fs::write(root.join(format!("code/{index:04}.dm")),format!("/obj/resolved/child{index}/Initialize()
	if(condition)
		return INITIALIZE_HINT_QDEL
")).unwrap()}let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new()),fail_policy:Mutex::new(None)};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=frontend(&root,&inputs,&db);let discovery=Arc::new(workspace_discovery::discover(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps")]}).unwrap());let capture=workspace_capture::capture(&front,&inputs,discovery,&root.join("missing.toml")).unwrap();let snapshot=snapshot(&front,&db,&inputs,&capture);let scope=snapshot.workspace_native_read().unwrap();let before=physical.reads();let cold=db.with_workspace_resolvers(&capture,&scope,|data|{assert_eq!(data.sites().len(),129,"nested QDEL requires actual raw resolver root from uncompiled maps file");assert!(data.sites().windows(2).all(|w|w[0].rel<w[1].rel));assert!(data.sites().iter().any(|s|s.rel=="code/0128.dm"));Ok(serde_json::to_vec(data.sites()).unwrap())}).unwrap();let warm=db.with_workspace_resolvers(&capture,&scope,|data|Ok(serde_json::to_vec(data.sites()).unwrap())).unwrap();assert_eq!(cold,warm);assert_eq!(physical.reads(),before);let error=db.with_workspace_resolvers(&capture,&scope,|_|Err::<(),_>(io::Error::from_raw_os_error(1450))).err().unwrap();assert_eq!(error.raw_os_error(),Some(1450));let foreign=crate::query_db::QueryDb::default();assert!(foreign.with_workspace_resolvers(&capture,&scope,|_| -> io::Result<()> {panic!("foreign cannot publish two-pass result")}).is_err());let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(60));token.cancel();assert_eq!(db.with_workspace_resolvers(&capture,&scope,|_| -> io::Result<()> {panic!("cancelled cannot publish")}).err().unwrap().kind(),io::ErrorKind::Interrupted);drop(binding);db.with_workspace_resolvers(&capture,&scope,|_|Ok(())).unwrap();}

#[test]
fn actual_tables_full_dispatch_uses_uncompiled_global_list_names_without_semantic_model_or_reread(){let root=fixture("workspace-tables-two-pass-129",129);std::fs::create_dir(root.join("maps")).unwrap();std::fs::write(root.join("maps/names.dm"),"GLOBAL_LIST_INIT(shared, list(1,2))
").unwrap();for index in 0..129{std::fs::write(root.join(format!("code/{index:04}.dm")),format!("/obj/listed/child{index}/values()
	return GLOB.shared
")).unwrap()}let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new()),fail_policy:Mutex::new(None)};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=frontend(&root,&inputs,&db);let discovery=Arc::new(workspace_discovery::discover(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps")]}).unwrap());let capture=workspace_capture::capture(&front,&inputs,discovery,&root.join("missing.toml")).unwrap();let snapshot=snapshot(&front,&db,&inputs,&capture);let scope=snapshot.workspace_native_read().unwrap();let before=physical.reads();let cold=db.with_workspace_tables(&capture,&scope,|data|{assert_eq!(data.sites().len(),129,"global static getter requires actual raw list name from uncompiled maps file");assert!(data.sites().windows(2).all(|w|w[0].rel<w[1].rel));assert!(data.sites().iter().any(|s|s.rel=="code/0128.dm"));Ok(serde_json::to_vec(data.sites()).unwrap())}).unwrap();let warm=db.with_workspace_tables(&capture,&scope,|data|Ok(serde_json::to_vec(data.sites()).unwrap())).unwrap();assert_eq!(cold,warm);assert_eq!(physical.reads(),before);let error=db.with_workspace_tables(&capture,&scope,|_|Err::<(),_>(io::Error::from_raw_os_error(1450))).err().unwrap();assert_eq!(error.raw_os_error(),Some(1450));let foreign=crate::query_db::QueryDb::default();assert!(foreign.with_workspace_tables(&capture,&scope,|_| -> io::Result<()> {panic!("foreign cannot publish two-pass result")}).is_err());let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(60));token.cancel();assert_eq!(db.with_workspace_tables(&capture,&scope,|_| -> io::Result<()> {panic!("cancelled cannot publish")}).err().unwrap().kind(),io::ErrorKind::Interrupted);drop(binding);db.with_workspace_tables(&capture,&scope,|_|Ok(())).unwrap();}

#[test]fn actual_complete_sys_folds_exceed_fixture_row_count_under_original_eof_and_budget(){let root=fixture("workspace-sys-whole-cardinality",129);std::fs::create_dir(root.join("maps")).unwrap();std::fs::write(root.join("maps/roots.dm"),"CAPABILITIES(/obj/resolved)\n\tmap_resolver(GLOBAL_PROC_REF(resolve))\nGLOBAL_LIST_INIT(shared,list(1))\n").unwrap();for file in 0..129{let mut text=String::new();for index in 0..80{text.push_str(&format!("/obj/resolved/c{file}_{index}\n\tvar/cached_v{index}\n/obj/resolved/c{file}_{index}/Initialize()\n\tif(condition)\n\t\treturn INITIALIZE_HINT_QDEL\n/obj/resolved/c{file}_{index}/values()\n\treturn GLOB.shared\n"));}std::fs::write(root.join(format!("code/{file:04}.dm")),text).unwrap();}let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new()),fail_policy:Mutex::new(None)};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=frontend(&root,&inputs,&db);let discovery=Arc::new(workspace_discovery::discover(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps")]}).unwrap());let capture=workspace_capture::capture(&front,&inputs,discovery,&root.join("missing.toml")).unwrap();let snapshot=snapshot(&front,&db,&inputs,&capture);let scope=snapshot.workspace_native_read().unwrap();let before=physical.reads();db.with_workspace_hygiene(&capture,&scope,|data|{assert_eq!(data.sites().iter().filter(|row|row.rule=="cached_var").count(),129*80);Ok(())}).unwrap();db.with_workspace_resolvers(&capture,&scope,|data|{assert_eq!(data.sites().len(),129*80);Ok(())}).unwrap();db.with_workspace_tables(&capture,&scope,|data|{assert_eq!(data.sites().len(),129*80);Ok(())}).unwrap();assert_eq!(physical.reads(),before);}

#[test]fn actual_boundary_fold_requires_both_source_eofs_uses_independent_scope_and_reuses_captured_payloads(){
 let root=fixture("workspace-boundary-full-129",129);std::fs::create_dir(root.join("maps")).unwrap();std::fs::create_dir_all(root.join("code/owner")).unwrap();std::fs::write(root.join("code/owner/model.dm"),"/datum/system/alpha\n").unwrap();
 for index in 1..129{std::fs::write(root.join(format!("code/{index:04}.dm")),format!("/proc/read{index}()\n    system(/datum/system/alpha).hidden\n")).unwrap();}
 std::fs::write(root.join("maps/extra.dm"),"/proc/map_reader()\n    system(/datum/system/alpha).hidden\n").unwrap();
 let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new()),fail_policy:Mutex::new(None)};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=frontend(&root,&inputs,&db);let discovery=Arc::new(workspace_discovery::discover(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps")]}).unwrap());let capture=workspace_capture::capture(&front,&inputs,discovery,&root.join("missing.toml")).unwrap();let snapshot=snapshot(&front,&db,&inputs,&capture);let scope=snapshot.workspace_native_read().unwrap();let before=physical.reads();
 let check=|data:&dq_analyze::captured_system_boundary_pages::BoundaryData|{assert!(data.sites().iter().any(|site|site.rule=="B1"&&site.rel=="code/0128.dm"));assert!(data.sites().iter().any(|site|site.rule=="B1"&&site.rel=="maps/extra.dm"));assert!(data.sites().iter().any(|site|site.rule=="B7"));assert_eq!(data.sites().len(),data.source_text().len());Ok((serde_json::to_vec(data.sites()).unwrap(),serde_json::to_vec(data.allow_used()).unwrap(),data.source_text().to_vec()))};
 let actual=db.with_workspace_boundary(&capture,&scope,check).unwrap();let warm=db.with_workspace_boundary(&capture,&scope,check).unwrap();assert_eq!(actual,warm);assert_eq!(physical.reads(),before,"all boundary payloads already issued, warm repeats no source I/O");
 let error=db.with_workspace_boundary(&capture,&scope,|_|Err::<(),_>(io::Error::from_raw_os_error(1450))).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));let foreign=crate::query_db::QueryDb::default();assert!(foreign.with_workspace_boundary(&capture,&scope,|_|->io::Result<()>{panic!("foreign owner cannot publish")}).is_err());let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(60));token.cancel();let error=db.with_workspace_boundary(&capture,&scope,|_|->io::Result<()>{panic!("canceled boundary cannot publish")}).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::Interrupted);drop(binding);db.with_workspace_boundary(&capture,&scope,|_|Ok(())).unwrap();
}

#[test]
fn actual_workspace_report_producer_passes_strict_dispatch_with_captured_scope_source_and_digest_without_io(){
 use crate::daemon::query::{QueryReply,SourceQuery};
 let root=fixture("workspace-report-producer-dispatch",1);
 std::fs::write(root.join("code/0000.dm"),"/proc/probe()\r\n    sleep(1) // ALLOW(scheduler): synchronous external operation requires an actual wait\r\n    sleep(2)\r\n").unwrap();
 let configuration=root.join("scopes.toml");std::fs::write(&configuration,"[lint.scheduler.ceilings]\nsleep=3\n").unwrap();
 let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new()),fail_policy:Mutex::new(None)};let inputs=RecordingInputs::new(&physical,4_000_000_000);
 let front=frontend(&root,&inputs,&db);let capture=workspace_capture::capture(&front,&inputs,discover(&root,&inputs),&configuration).unwrap();let snapshot=snapshot(&front,&db,&inputs,&capture);let before=physical.reads();
 // The report is snapshot-as-of, not a second read from current disk.
 std::fs::write(root.join("code/0000.dm"),"/proc/newer()\n    sleep(99)\n").unwrap();std::fs::write(&configuration,"[lint.scheduler.ceilings]\nsleep=0\n").unwrap();
 let names=vec!["scheduler".into()];let mut bytes=Vec::new();snapshot.write_native_workspace_raw_policy(&root,&configuration,&names,None,128,&snapshot.tree,&mut bytes).unwrap();
 let jsonl=String::from_utf8(bytes).unwrap();let row:serde_json::Value=serde_json::from_str(jsonl.trim_end()).unwrap();let items=row["items"].as_array().unwrap();
 assert!(items.iter().any(|item|item["kind"]=="site"&&item["source_text"]=="sleep(2)"));assert!(items.iter().any(|item|item["kind"]=="allow"&&item["source_digest"]=="6ab0999154e42b301af8cedf3c56ba0a12a37586"),"actual CRLF original must publish the same universal-newline SHA1 as old Analyze");
 let scope:serde_json::Value=serde_json::from_str(row["policy_scopes"][0][1].as_str().unwrap()).unwrap();assert_eq!(scope[5]["sleep"],3);
 let reply=QueryReply{schema:"dm-session-query-v1".into(),revision:format!("{:032x}",snapshot.tree.identity()),complete:false,coverage:"partial".into(),query_count:0,source_query_count:1,source_revision:Some(format!("{:032x}",snapshot.source_revision)),policy_revision:Some(format!("{:032x}",capture.policy_revision())),snapshot_outcome:"analyzed".into(),last_request_outcome:"analyzed".into(),publication_pair:None,jsonl};
 let questions=vec![SourceQuery::NativeWorkspaceRawPolicy{root:root.clone(),configuration,lints:names,cursor:None,limit:128}];
 crate::daemon::query::validate_workspace_policy_for_test(&reply,&questions).unwrap();assert_eq!(physical.reads(),before,"report and strict dispatcher must not reopen source or configuration");
 for field in ["policy_scopes","source_text","source_digest"]{
  let mut changed=row.clone();if field=="policy_scopes"{changed.as_object_mut().unwrap().remove(field);}else{let item=changed["items"].as_array_mut().unwrap().iter_mut().find(|item|item.as_object().unwrap().contains_key(field)).unwrap();item.as_object_mut().unwrap().remove(field);}
  let mut rejected=reply.clone();rejected.jsonl=format!("{changed}\n");assert!(crate::daemon::query::validate_workspace_policy_for_test(&rejected,&questions).is_err(),"missing {field}");
 }
 assert_eq!(physical.reads(),before);
}

#[test]
fn actual_public_analyze_report_uses_all_pinned_pages_captured_settings_and_text_after_disk_edit_without_io(){
 use crate::daemon::{analyze::{AnalyzeRequest,finish_captured_for_test},query::{QueryRequest,QueryReply,SourceQuery}};
 let root=fixture("public-analyze-report-129",129);let configuration=root.join("scopes.toml");std::fs::write(&configuration,"[lint.scheduler.ceilings]\nsleep=200\n").unwrap();
 std::fs::write(root.join("code/0000.dm"),"/proc/p0()\n    sleep(1) // ALLOW(scheduler): synchronous external operation requires an actual wait\n    sleep(2)\n").unwrap();
 let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new()),fail_policy:Mutex::new(None)};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=frontend(&root,&inputs,&db);let capture=workspace_capture::capture(&front,&inputs,discover(&root,&inputs),&configuration).unwrap();let snapshot=snapshot(&front,&db,&inputs,&capture);let before=physical.reads();
 let(_,mut build,_,_)=crate::generation_test_fixture::fixture();build.project=root.join("p.dme");let policy=build.policy_inputs.as_mut().unwrap();policy.workspace_generators.clear();policy.workspace=Some(crate::policy_request::WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code")],configuration:configuration.clone()});let request=AnalyzeRequest{build,lints:vec!["scheduler".into()],raw:false,changed:None,scopes_root:None,baseline_mode:None,ci:false};
 std::fs::write(root.join("code/0128.dm"),"/proc/changed()\n    sleep(9999)\n").unwrap();std::fs::write(&configuration,"[lint.scheduler.ceilings]\nsleep=0\n").unwrap();
 let mut cursor=None;let mut pages=Vec::new();loop{let mut bytes=Vec::new();snapshot.write_native_workspace_raw_report_page(&root,&configuration,&request.lints,cursor.as_ref(),32,&snapshot.tree,&mut bytes).unwrap();let jsonl=String::from_utf8(bytes).unwrap();let row:serde_json::Value=serde_json::from_str(jsonl.trim_end()).unwrap();let query=QueryRequest{timeout_seconds:None,project:request.build.project.clone(),defines:request.build.defines.clone(),engine_template:request.build.engine_template.clone(),bootstrap_catalog:request.build.bootstrap_catalog,expected_revision:Some(format!("{:032x}",snapshot.tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",capture.policy_revision())),queries:Vec::new(),source_queries:vec![SourceQuery::NativeWorkspaceRawReportPage{root:root.clone(),configuration:configuration.clone(),lints:request.lints.clone(),cursor:cursor.clone(),limit:32}]};let reply=QueryReply{schema:"dm-session-query-v1".into(),revision:query.expected_revision.clone().unwrap(),complete:false,coverage:"partial".into(),query_count:0,source_query_count:1,source_revision:query.expected_source_revision.clone(),policy_revision:query.expected_policy_revision.clone(),snapshot_outcome:"analyzed".into(),last_request_outcome:"analyzed".into(),publication_pair:None,jsonl};cursor=serde_json::from_value::<Option<crate::query_db::WorkspaceCursor>>(row["next_cursor"].clone()).unwrap();pages.push((reply,query));if cursor.is_none(){break}}
 assert!(pages.len()>4);let(clean,bytes)=finish_captured_for_test(&request,&pages,false).unwrap();assert!(clean,"captured ceiling 200 survives actual changed disk ceiling0");let report:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert_eq!(report["complete"],true);assert_eq!(report["full_policy_parity"],false);assert!(!report["text"].as_str().unwrap().contains("9999"));assert_eq!(report["allow_usage"].as_array().unwrap().len(),1);assert_eq!(physical.reads(),before);
 let again=finish_captured_for_test(&request,&pages,false).unwrap();assert_eq!(again.1,bytes);assert_eq!(physical.reads(),before);let mut truncated=pages.clone();truncated.pop();assert!(finish_captured_for_test(&request,&truncated,false).is_err());assert_eq!(physical.reads(),before);
}

#[test]
fn actual_public_analyze_report_refuses_subtree_without_promoting_raw_findings_to_complete_policy(){
 let root=fixture("public-analyze-report-real-domain",1);std::fs::create_dir(root.join("code/subtree")).unwrap();std::fs::write(root.join("code/subtree/only.dm"),"/proc/subtree()\n    sleep(7)\n").unwrap();
 let db=Arc::new(crate::query_db::QueryDb::default());let inputs=RecordingInputs::new(FileSystemInputs,4_000_000_000);let front=frontend(&root,&inputs,&db);
 let discovery=Arc::new(workspace_discovery::discover(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code/subtree")]}).unwrap());let configuration=root.join("missing.toml");let capture=workspace_capture::capture(&front,&inputs,discovery,&configuration).unwrap();let snapshot=snapshot(&front,&db,&inputs,&capture);let names=vec!["scheduler".into()];let mut output=Vec::new();
 let error=snapshot.write_native_workspace_raw_report_page(&root,&configuration,&names,None,128,&snapshot.tree,&mut output).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::Unsupported);assert!(output.is_empty(),"no completed-policy prefix before typed domain proof");
 snapshot.write_native_workspace_raw_policy(&root,&configuration,&names,None,128,&snapshot.tree,&mut output).unwrap();let row:serde_json::Value=serde_json::from_slice(&output).unwrap();assert_eq!(row["admission"],"raw_findings");assert_eq!(row["count"],1,"old explicitly partial findings endpoint remains useful and truthful");
}

#[path="runner_query_check_grep_tests.rs"]
mod check_grep_tests;

#[test]
fn actual_deadline_auxiliary_is_requested_recorded_pinned_validated_and_consumed_without_source_reopen(){
 use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;use crate::daemon::{query::{self,QueryRequest,SourceQuery},analyze::{AnalyzeRequest,finish_auxiliary_captured_for_test}};
 for case in ["missing","utf8","non_utf8","bad_reason"]{
  let root=fixture(&format!("deadline-actual-aux-{case}"),1);std::fs::create_dir_all(root.join("tools/ci")).unwrap();std::fs::write(root.join("code/0000.dm"),"/datum/probe\n\tvar/next_fire\n/datum/probe/proc/process()\n\tif(world.time >= next_fire)\n\t\treturn 1\n").unwrap();let configuration=root.join("tools/ci/lint_scopes.toml");let allowlist=root.join("tools/ci/deadline_polling_allowlist.txt");match case{"utf8"=>std::fs::write(&allowlist,"code/0000.dm:/datum/probe/process # actual fixed rate gate reason\n").unwrap(),"non_utf8"=>std::fs::write(&allowlist,[0xff]).unwrap(),"bad_reason"=>std::fs::write(&allowlist,"code/0000.dm:/datum/probe/process\n").unwrap(),_=>{}}
  let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new()),fail_policy:Mutex::new(None)};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=frontend(&root,&inputs,&db);let capture=workspace_capture::capture_with_auxiliary(&front,&inputs,discover(&root,&inputs),&configuration,&[Q::DeadlinePollingAllowlist]).unwrap();assert_eq!(capture.auxiliary(),[Q::DeadlinePollingAllowlist]);let snapshot=snapshot(&front,&db,&inputs,&capture);let tree=snapshot.tree.clone();let source=format!("{:032x}",snapshot.source_revision);let policy_pin=format!("{:032x}",capture.policy_revision());let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let before=physical.reads();
  let(_,mut build,_,_)=crate::generation_test_fixture::fixture();build.project=root.join("p.dme");let intent=build.policy_inputs.as_mut().unwrap();intent.workspace_generators.clear();intent.workspace_auxiliary=vec![Q::DeadlinePollingAllowlist];intent.workspace=Some(crate::policy_request::WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code")],configuration:configuration.clone()});let request=AnalyzeRequest{build,lints:vec!["deadline_polling".into()],raw:false,changed:None,scopes_root:None,baseline_mode:None,ci:false};
  let query=|question|QueryRequest{timeout_seconds:Some(300),project:root.join("p.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(source.clone()),expected_policy_revision:Some(policy_pin.clone()),queries:Vec::new(),source_queries:vec![question]};
  let page=query(SourceQuery::NativeWorkspaceRawReportPage{root:root.clone(),configuration:configuration.clone(),lints:request.lints.clone(),cursor:None,limit:128});let findings=query::evaluate_snapshot(&page,&tree,&state).unwrap();let evidence_query=query(SourceQuery::NativeDeadlinePollingEvidence{root:root.clone(),configuration:configuration.clone()});let evidence=query::evaluate_snapshot(&evidence_query,&tree,&state).unwrap();query::validate_deadline_evidence_delivery(&evidence,&evidence_query.source_queries).unwrap();let observed:serde_json::Value=serde_json::from_str(evidence.jsonl.trim_end()).unwrap();assert_eq!(observed["observation"],match case{"missing"=>"proven_missing","non_utf8"=>"captured_non_utf8",_=>"captured_utf8"});
  // A later disk edit is not substituted into this immutable delivered frame.
  std::fs::write(&allowlist,"different # newer disk observation is not current captured evidence\n").unwrap();let pages=vec![(findings,page)];let pair=(evidence.clone(),evidence_query.clone());let(clean,bytes)=finish_auxiliary_captured_for_test(&request,&pages,Some(&pair),false).unwrap();assert_eq!(clean,case=="utf8");let report:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert_eq!(report["complete"],true);assert_eq!(report["full_policy_parity"],false);assert!(report["text"].as_str().unwrap().contains(if case=="bad_reason"{"entry has no reason"}else{"Deadline polling:"}));assert!(!report["text"].as_str().unwrap().contains("newer disk"));assert_eq!(physical.reads(),before);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0);
  let warm=query::evaluate_snapshot(&evidence_query,&tree,&state).unwrap();assert_eq!(warm.jsonl,evidence.jsonl);assert_eq!(physical.reads(),before);

  for bad in ["missing_field","extra_field","wrong_question","wrong_path","wrong_text_shape"]{
   let mut forged=pair.clone();let mut row:serde_json::Value=serde_json::from_str(&forged.0.jsonl).unwrap();match bad{"missing_field"=>{row.as_object_mut().unwrap().remove("observation");},"extra_field"=>{row["completion"]=true.into();},"wrong_question"=>row["question"]="check_grep".into(),"wrong_path"=>row["path"]="elsewhere".into(),_=>{row["observation"]="captured_utf8".into();row["text"]=serde_json::Value::Null;}}
   forged.0.jsonl=format!("{row}\n");assert!(finish_auxiliary_captured_for_test(&request,&pages,Some(&forged),false).is_err(),"{bad}");
  }
assert!(finish_auxiliary_captured_for_test(&request,&pages,None,false).is_err());let mut foreign=pair.clone();foreign.0.policy_revision=Some("f".repeat(32));assert!(finish_auxiliary_captured_for_test(&request,&pages,Some(&foreign),false).is_err());
 }
}
#[test]
fn actual_deadline_auxiliary_refuses_unrequested_and_preserves_capture_writer_io_cancel_and_retry(){
 use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
 let root=fixture("deadline-aux-real-controls",1);std::fs::create_dir_all(root.join("tools/ci")).unwrap();let configuration=root.join("tools/ci/lint_scopes.toml");let path=root.join("tools/ci/deadline_polling_allowlist.txt");std::fs::write(&path,"key # actual reason\n").unwrap();let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new()),fail_policy:Mutex::new(Some(path.clone()))};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=frontend(&root,&inputs,&db);
 let error=workspace_capture::capture_with_auxiliary(&front,&inputs,discover(&root,&inputs),&configuration,&[Q::DeadlinePollingAllowlist]).err().unwrap();assert_eq!(error.raw_os_error(),Some(1450));*physical.fail_policy.lock().unwrap()=None;
 let capture=workspace_capture::capture_with_auxiliary(&front,&inputs,discover(&root,&inputs),&configuration,&[Q::DeadlinePollingAllowlist]).unwrap();let snap=snapshot(&front,&db,&inputs,&capture);let before=physical.reads();
 struct Fail;impl std::io::Write for Fail{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}
 assert_eq!(snap.write_native_deadline_evidence(&root,&configuration,&snap.tree,&mut Fail).unwrap_err().raw_os_error(),Some(1450));let mut bytes=Vec::new();snap.write_native_deadline_evidence(&root,&configuration,&snap.tree,&mut bytes).unwrap();assert!(!bytes.is_empty());assert_eq!(physical.reads(),before);
 let cancel=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(cancel.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));cancel.cancel();let mut refused=Vec::new();assert_eq!(snap.write_native_deadline_evidence(&root,&configuration,&snap.tree,&mut refused).unwrap_err().kind(),io::ErrorKind::Interrupted);assert!(refused.is_empty());drop(binding);snap.write_native_deadline_evidence(&root,&configuration,&snap.tree,&mut Vec::new()).unwrap();
 let raw=workspace_capture::capture(&front,&inputs,discover(&root,&inputs),&configuration).unwrap();let raw_snap=snapshot(&front,&db,&inputs,&raw);assert!(raw_snap.write_native_deadline_evidence(&root,&configuration,&raw_snap.tree,&mut Vec::new()).is_err(),"an unrequested file is not a proven missing auxiliary observation");assert_eq!(physical.reads(),before+1,"only separate ordinary config capture, never a query payload reopen");
}

#[test]
fn actual_public_hygiene_report_pages_use_real_code_maps_eof_scope_text_and_digest_then_common_finish(){
 use crate::daemon::{query::{self,QueryRequest,SourceQuery},analyze::{AnalyzeRequest,finish_captured_for_test}};
 let root=fixture("public-hygiene-report-129",129);std::fs::create_dir(root.join("maps")).unwrap();
 for index in 0..129{std::fs::write(root.join(format!("code/{index:04}.dm")),format!("/obj/probe{index}\n\tvar/cached_charge\n/obj/probe{index}/process()\n\tif(world.time > next_move) // ALLOW(sys_deadline_poll): a deliberate full source annotation for this test\n\t\treturn\n\tcached_charge=2\n\t// ALLOW(scheduler): baseline when ci was wired\n")).unwrap();}
 std::fs::write(root.join("maps/extra.dm"),"/obj/map_probe\n\tvar/cached_charge\n\t// ALLOW(scheduler): baseline when ci was wired\n").unwrap();let configuration=root.join("scopes.toml");std::fs::write(&configuration,"[lint.\"sys/hygiene\".ceilings]\nannotation_boilerplate=1000\ncached_var=1000\ndeadline_poll=1000\n").unwrap();
 let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new()),fail_policy:Mutex::new(None)};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=frontend(&root,&inputs,&db);let discovery=Arc::new(workspace_discovery::discover(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps")]}).unwrap());let capture=workspace_capture::capture(&front,&inputs,discovery,&configuration).unwrap();let snapshot=snapshot(&front,&db,&inputs,&capture);let tree=snapshot.tree.clone();let source=format!("{:032x}",snapshot.source_revision);let policy_pin=format!("{:032x}",capture.policy_revision());let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let before=physical.reads();
 let(_,mut build,_,_)=crate::generation_test_fixture::fixture();build.project=root.join("p.dme");let intent=build.policy_inputs.as_mut().unwrap();intent.workspace_generators.clear();intent.workspace=Some(crate::policy_request::WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps")],configuration:configuration.clone()});let request=AnalyzeRequest{build,lints:vec!["sys/hygiene".into()],raw:true,changed:None,scopes_root:None,baseline_mode:None,ci:false};
 let mut cursor=None;let mut pages=Vec::new();let mut sites=Vec::new();let mut allows=Vec::new();loop{let query=QueryRequest{timeout_seconds:Some(300),project:root.join("p.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(source.clone()),expected_policy_revision:Some(policy_pin.clone()),queries:Vec::new(),source_queries:vec![SourceQuery::NativeWorkspaceHygieneReportPage{root:root.clone(),configuration:configuration.clone(),lints:request.lints.clone(),cursor:cursor.clone(),limit:32}]};let reply=query::evaluate_snapshot(&query,&tree,&state).unwrap();query::validate_workspace_report_delivery(&reply,&query.source_queries).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim_end()).unwrap();assert_eq!(row["admission"],"complete_selected_hygiene_findings");for item in row["items"].as_array().unwrap(){if item["kind"]=="site"{sites.push(item["site"].clone());}else{allows.push(item["allow"].clone());assert_eq!(item["source_digest"].as_str().unwrap().len(),40);}}cursor=serde_json::from_value(row["next_cursor"].clone()).unwrap();pages.push((reply,query));if cursor.is_none(){break}}
 assert!(pages.len()>4);assert!(sites.iter().any(|site|site["rel"]=="maps/extra.dm"));assert!(sites.iter().any(|site|site["rel"]=="code/0128.dm"));assert_eq!(allows.len(),129);let snap=state.snapshot.as_ref().unwrap();db.with_workspace_hygiene(&capture,&snap.workspace_native_read().unwrap(),|data|{assert_eq!(serde_json::to_value(data.sites()).unwrap(),serde_json::Value::Array(sites));assert_eq!(serde_json::to_value(data.allow_used()).unwrap(),serde_json::Value::Array(allows));Ok(())}).unwrap();
 // Complete delivery is required before source-free report/baseline judgement.
 let(clean,bytes)=finish_captured_for_test(&request,&pages,false).unwrap();assert!(!clean);let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert_eq!(row["full_policy_parity"],false);assert_eq!(row["allow_usage"].as_array().unwrap().len(),129);assert!(row["text"].as_str().unwrap().ends_with("Ratchet lints failed: sys/hygiene\n"));let mut truncated=pages.clone();truncated.pop();assert!(finish_captured_for_test(&request,&truncated,false).is_err());assert_eq!(physical.reads(),before);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0);
 let mut judged=request.clone();judged.raw=false;let(clean,judged_bytes)=finish_captured_for_test(&judged,&pages,false).unwrap();assert!(clean,"actual captured per-rule ceilings1000 remain authoritative after delivery");assert!(serde_json::from_slice::<serde_json::Value>(&judged_bytes).unwrap()["text"].as_str().unwrap().ends_with("All ratchet lints passed.\n"));

 for (field,value) in [("row",serde_json::json!("source_native_workspace_raw_report")),("admission",serde_json::json!("complete_selected_raw_policy_findings")),("scope",serde_json::json!("typed_discovery_raw_files")),("full_policy_parity",serde_json::json!(true))]{let mut forged=pages[0].0.clone();let mut row:serde_json::Value=serde_json::from_str(forged.jsonl.trim_end()).unwrap();row[field]=value;forged.jsonl=format!("{row}\n");assert!(query::validate_workspace_report_delivery(&forged,&pages[0].1.source_queries).is_err(),"distinct full policy role must not become RAW: {field}");}
 let warm=query::evaluate_snapshot(&pages[0].1,&tree,&state).unwrap();assert_eq!(warm.jsonl,pages[0].0.jsonl);assert_eq!(physical.reads(),before,"page refolding revisits captured views, never current files; no shared-work/performance claim");
}
#[test]
fn actual_public_hygiene_report_rejects_code_only_receipt_foreign_cursor_cancel_and_writer_io_without_partial_success(){
 let root=fixture("public-hygiene-report-roles",1);std::fs::create_dir(root.join("maps")).unwrap();std::fs::write(root.join("maps/only.dm"),"/obj/map_probe\n\tvar/cached_charge\n").unwrap();let config=root.join("missing.toml");let db=Arc::new(crate::query_db::QueryDb::default());let inputs=RecordingInputs::new(FileSystemInputs,4_000_000_000);let front=frontend(&root,&inputs,&db);let capture=workspace_capture::capture(&front,&inputs,discover(&root,&inputs),&config).unwrap();let partial=snapshot(&front,&db,&inputs,&capture);let names=vec!["sys/hygiene".into()];let mut out=Vec::new();assert!(partial.write_native_workspace_hygiene_report_page(&root,&config,&names,None,128,&partial.tree,&mut out).is_err());assert!(out.is_empty(),"CODE completion must not certify the complete Hygiene source domain");
 let all=Arc::new(workspace_discovery::discover(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps")]}).unwrap());let capture=workspace_capture::capture(&front,&inputs,all,&config).unwrap();let snap=snapshot(&front,&db,&inputs,&capture);let mut expected=Vec::new();snap.write_native_workspace_hygiene_report_page(&root,&config,&names,None,128,&snap.tree,&mut expected).unwrap();
 struct Failing;impl std::io::Write for Failing{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}assert_eq!(snap.write_native_workspace_hygiene_report_page(&root,&config,&names,None,128,&snap.tree,&mut Failing).unwrap_err().raw_os_error(),Some(1450));
 let foreign:crate::query_db::WorkspaceCursor=serde_json::from_value(serde_json::json!({"aggregate_id":"f".repeat(32),"offset":0})).unwrap();let mut refused=Vec::new();assert!(snap.write_native_workspace_hygiene_report_page(&root,&config,&names,Some(&foreign),128,&snap.tree,&mut refused).is_err());assert!(refused.is_empty());let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(snap.write_native_workspace_hygiene_report_page(&root,&config,&names,None,128,&snap.tree,&mut refused).unwrap_err().kind(),io::ErrorKind::Interrupted);assert!(refused.is_empty());drop(binding);let mut recovered=Vec::new();snap.write_native_workspace_hygiene_report_page(&root,&config,&names,None,128,&snap.tree,&mut recovered).unwrap();assert_eq!(recovered,expected);
}

#[test]
fn actual_public_sys_reports_keep_distinct_complete_issuers_two_eofs_global_points_and_source_free_finish(){
 use crate::daemon::{query::{self,QueryRequest,SourceQuery},analyze::{AnalyzeRequest,finish_captured_for_test}};
 let root=fixture("public-sys-three-complete-129",129);std::fs::create_dir(root.join("maps")).unwrap();std::fs::create_dir_all(root.join("code/owner")).unwrap();
 std::fs::write(root.join("code/owner/system.dm"),"/datum/system/alpha\n").unwrap();
 std::fs::write(root.join("maps/roots.dm"),"CAPABILITIES(/obj/resolved)\n\tmap_resolver(GLOBAL_PROC_REF(resolve))\nGLOBAL_LIST_INIT(shared,list(1))\n/proc/map_reader()\n    system(/datum/system/alpha).hidden\n").unwrap();
 for n in 0..129{std::fs::write(root.join(format!("code/{n:04}.dm")),format!("/obj/resolved/c{n}/Initialize()\n\tif(condition)\n\t\treturn INITIALIZE_HINT_QDEL\n/obj/resolved/c{n}/values()\n\treturn GLOB.shared\n/proc/read{n}()\n    system(/datum/system/alpha).hidden\n")).unwrap();}
 let configuration=root.join("missing.toml");let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new()),fail_policy:Mutex::new(None)};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=frontend(&root,&inputs,&db);let discovery=Arc::new(workspace_discovery::discover(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps")]}).unwrap());let capture=workspace_capture::capture(&front,&inputs,discovery,&configuration).unwrap();let snapshot=snapshot(&front,&db,&inputs,&capture);let tree=snapshot.tree.clone();let source=format!("{:032x}",snapshot.source_revision);let policy=format!("{:032x}",capture.policy_revision());let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let before=physical.reads();
 for name in ["sys/resolvers","sys/tables","system_boundary"]{
  let(_,mut build,_,_)=crate::generation_test_fixture::fixture();build.project=root.join("p.dme");let intent=build.policy_inputs.as_mut().unwrap();intent.workspace_generators.clear();intent.workspace=Some(crate::policy_request::WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code"),root.join("maps")],configuration:configuration.clone()});let request=AnalyzeRequest{build,lints:vec![name.into()],raw:true,changed:None,scopes_root:None,baseline_mode:None,ci:false};
  let mut cursor=None;let mut pages=Vec::new();let mut sites=Vec::new();
  loop{let question=QueryRequest{timeout_seconds:Some(300),project:root.join("p.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(source.clone()),expected_policy_revision:Some(policy.clone()),queries:Vec::new(),source_queries:vec![SourceQuery::NativeWorkspaceSysReportPage{root:root.clone(),configuration:configuration.clone(),lints:request.lints.clone(),cursor:cursor.clone(),limit:32}]};let reply=query::evaluate_snapshot(&question,&tree,&state).unwrap();query::validate_workspace_report_delivery(&reply,&question.source_queries).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim_end()).unwrap();assert_eq!(row["admission"],"complete_selected_sys_findings");assert_eq!(row["lint_whitelist"],serde_json::json!([name]));for item in row["items"].as_array().unwrap(){if item["kind"]=="site"{if item["site"]["line"]==0{assert_eq!(name,"system_boundary");assert!(matches!(item["site"]["rule"].as_str(),Some("B5"|"B7")));assert_eq!(item["source_text"],"");}sites.push(item["site"].clone());}}cursor=serde_json::from_value(row["next_cursor"].clone()).unwrap();pages.push((reply,question));if cursor.is_none(){break}}
  assert!(pages.len()>4);assert!(sites.iter().any(|site|site["rel"]=="code/0128.dm"));let snap=state.snapshot.as_ref().unwrap();let guard=snap.workspace_native_read().unwrap();
  let expected=match name{"sys/resolvers"=>db.with_workspace_resolvers(&capture,&guard,|d|Ok(serde_json::to_value(d.sites()).unwrap())),"sys/tables"=>db.with_workspace_tables(&capture,&guard,|d|Ok(serde_json::to_value(d.sites()).unwrap())),_=>db.with_workspace_boundary(&capture,&guard,|d|Ok(serde_json::to_value(d.sites()).unwrap()))}.unwrap();assert_eq!(expected,serde_json::Value::Array(sites));
  let(clean,bytes)=finish_captured_for_test(&request,&pages,false).unwrap();assert!(!clean);let report:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert_eq!(report["complete"],true);assert_eq!(report["full_policy_parity"],false);assert!(report["text"].as_str().unwrap().ends_with(&format!("Ratchet lints failed: {name}\n")));
  let mut partial=pages.clone();partial.pop();assert!(finish_captured_for_test(&request,&partial,false).is_err());let mut forged=pages[0].0.clone();let mut row:serde_json::Value=serde_json::from_str(forged.jsonl.trim_end()).unwrap();row["row"]=serde_json::json!("source_native_workspace_raw_report");forged.jsonl=format!("{row}\n");assert!(query::validate_workspace_report_delivery(&forged,&pages[0].1.source_queries).is_err());

  struct Fail;impl std::io::Write for Fail{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}
  let error=state.snapshot.as_ref().unwrap().write_native_workspace_sys_report_page(&root,&configuration,&request.lints,None,32,&tree,&mut Fail).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));
  let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(60));token.cancel();let mut output=Vec::new();let error=state.snapshot.as_ref().unwrap().write_native_workspace_sys_report_page(&root,&configuration,&request.lints,None,32,&tree,&mut output).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::Interrupted);assert!(output.is_empty());drop(binding);
  let warm=query::evaluate_snapshot(&pages[0].1,&tree,&state).unwrap();assert_eq!(warm.jsonl,pages[0].0.jsonl);
 }
 assert_eq!(physical.reads(),before,"whole-fold page refolding uses actual captured views; no shared-warm-work claim");assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0);
}

#[path="runner_query_allow_annotations_tests.rs"]mod allow_annotations_validation;

#[path="runner_query_keys_tests.rs"]mod keys_original_policy;
