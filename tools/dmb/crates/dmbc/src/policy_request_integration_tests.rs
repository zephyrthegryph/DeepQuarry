//! Wired only alongside the reviewed request preparation patch.
use crate::{
    frozen_inputs::Inputs,
    policy_request::{PolicyInputFile, PolicyInputRequest, PolicyInputRole},
};
fn intent(required: bool) -> crate::policy_request::AdmittedPolicyRequest {
    PolicyInputRequest {analysis_context:None,workspace_auxiliary:Vec::new(),workspace_generators:Vec::new(),
        workspace: None,
        files: vec![PolicyInputFile {
            path: std::env::temp_dir().join("policy-intent-fixture/a.dm"),
            role: PolicyInputRole::DmSource,
            required,
        }],
        search_folders: vec![],
    }
    .admit()
    .unwrap()
}
#[test]
fn old_wire_request_defaults_to_absence_and_omits_it_on_output() {
    let arguments = vec!["analyze".into(), "fixture.dme".into()];
    let crate::request::Command::Build(request) = crate::cli::parse(&arguments).unwrap() else {
        panic!("build request expected")
    };
    let mut value = serde_json::to_value(&*request).unwrap();
    value.as_object_mut().unwrap().remove("policy_inputs");
    let decoded: crate::request::BuildRequest = serde_json::from_value(value).unwrap();
    assert!(decoded.policy_inputs.is_none());
    assert!(serde_json::to_value(decoded)
        .unwrap()
        .get("policy_inputs")
        .is_none());
}
#[test]
fn configuration_preserves_absent_identity_and_binds_explicit_intent() {
    let root = std::env::current_dir().unwrap();
    let manifest = root.join("intent.dme");
    let base =
        crate::session::Configuration::new(&root, &manifest, Default::default(), 1, 2, 3).unwrap();
    assert!(serde_json::to_value(&base)
        .unwrap()
        .get("policy_inputs")
        .is_none());
    assert_eq!(
        base.identity().unwrap(),
        base.clone().with_policy_inputs(None).identity().unwrap()
    );
    let empty = PolicyInputRequest::default().admit().unwrap();
    assert_ne!(
        base.identity().unwrap(),
        base.clone()
            .with_policy_inputs(Some(&empty))
            .identity()
            .unwrap()
    );
    let first = base.clone().with_policy_inputs(Some(&intent(false)));
    let next = base.with_policy_inputs(Some(&intent(true)));
    assert_ne!(first.identity().unwrap(), next.identity().unwrap());
    assert_eq!(
        serde_json::from_slice::<crate::session::Configuration>(
            &serde_json::to_vec(&first).unwrap()
        )
        .unwrap(),
        first
    );
}
#[test]
fn journal_replay_binds_roles_requiredness_and_absent_legacy_intent() {
    let root = crate::test_scratch::dir("policy-intent-journal");
    let absent_path = root.join("absent");
    {
        let recording = Inputs::record(&absent_path).unwrap();
        recording.bind_policy_request(None).unwrap();
        assert!(recording.bind_policy_request(Some(&intent(false))).is_err());
        recording.finish().unwrap();
    }
    let absent = Inputs::replay(&absent_path).unwrap();
    absent.bind_policy_request(None).unwrap();
    assert!(absent
        .bind_policy_request(Some(&PolicyInputRequest::default().admit().unwrap()))
        .is_err());
    let present_path = root.join("present");
    {
        let recording = Inputs::record(&present_path).unwrap();
        recording.bind_policy_request(Some(&intent(false))).unwrap();
        recording.finish().unwrap();
    }
    let present = Inputs::replay(&present_path).unwrap();
    present.bind_policy_request(Some(&intent(false))).unwrap();
    assert!(present.bind_policy_request(None).is_err());
    assert!(present.bind_policy_request(Some(&intent(true))).is_err());
}

#[test]
fn cli_explicit_contract_is_inline_and_duplicate_flags_are_rejected() {
    let args = vec![
        "prepare-query".into(),
        "fixture.dme".into(),
        "--policy-inputs-json".into(),
        "{}".into(),
    ];
    let crate::request::Command::Build(request) = crate::cli::parse(&args).unwrap() else {
        panic!("build expected")
    };
    assert_eq!(request.policy_inputs, Some(PolicyInputRequest::default()));
    let mut repeated = args;
    repeated.extend(["--policy-inputs-json".into(), "{}".into()]);
    assert!(crate::cli::parse(&repeated).is_err());
}

#[test]
fn foreign_policy_pin_is_rejected_while_source_revision_remains_unchanged() {
    use crate::input_snapshot::{FolderListing, RecordingInputs, SnapshotProvider, Stamp};
    use std::{
        io,
        path::Path,
        sync::{Arc, Mutex},
    };
    struct Files;
    impl SnapshotProvider for Files {
        fn stamp(&self, path: &Path) -> io::Result<Stamp> {
            let size = if path.ends_with("p.dme") {
                b"/datum/test\n    var/saved\n".len()
            } else {
                b"SCHEMA(/datum/test, saved, schema_msg())\n".len()
            };
            Ok(Stamp {
                size: size as u64,
                modified_ns: 1,
                file_id: Some(1),
            })
        }
        fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
            let bytes = if path.ends_with("p.dme") {
                b"/datum/test\n    var/saved\n".as_slice()
            } else {
                b"SCHEMA(/datum/test, saved, schema_msg())\n".as_slice()
            };
            Ok((self.stamp(path)?, bytes.to_vec()))
        }
        fn list(&self, _: &Path) -> io::Result<FolderListing> {
            Ok(FolderListing::Present(vec![
                "marker.dm".into(),
                "p.dme".into(),
            ]))
        }
    }
    let root = std::env::current_dir().unwrap().join("policy-fixture");
    let db = Arc::new(crate::query_db::QueryDb::default());
    let ledger = RecordingInputs::new(Files, 1);
    let frontend = dm_tree::frontend::build(&root.join("p.dme"), &ledger, &Default::default(), 1)
        .unwrap()
        .with_body_queries(db.clone());
    let empty = PolicyInputRequest::default().admit().unwrap();
    let first = crate::runner_host::policy_capture::capture(&frontend, &ledger, &[], &[])
        .unwrap()
        .bind_request(&empty)
        .unwrap();
    let old_policy = first.policy_revision().unwrap();
    let state = Arc::new(Mutex::new(
        crate::runner_host::query_snapshot::QueryState::default(),
    ));
    let mut attempt = crate::runner_host::query_snapshot::QueryAttempt::new(state.clone(), true);
    attempt
        .capture_with_queries(&frontend, db.clone(), Some(Arc::new(first)))
        .unwrap();
    let source = dm_analysis::tree_export::source_revision(&frontend);
    let next = PolicyInputRequest {analysis_context:None,workspace_auxiliary:Vec::new(),workspace_generators:Vec::new(),
        workspace: None,
        files: vec![PolicyInputFile {
            path: root.join("marker.dm"),
            role: PolicyInputRole::DmSource,
            required: true,
        }],
        search_folders: vec![],
    }
    .admit()
    .unwrap();
    let captured =
        crate::runner_host::policy_capture::capture(&frontend, &ledger, &next.capture_files(), &[])
            .unwrap()
            .bind_request(&next)
            .unwrap();
    assert_ne!(old_policy, captured.policy_revision().unwrap());
    attempt
        .capture_with_queries(&frontend, db, Some(Arc::new(captured)))
        .unwrap();
    let request = crate::daemon::query::QueryRequest {analysis_context:None,
        timeout_seconds: None,
        project: root.join("p.dme"),
        defines: Default::default(),
        engine_template: None,
        bootstrap_catalog: false,
        expected_revision: Some(format!("{:032x}", frontend.snapshot.tree.identity())),
        queries: vec![],
        expected_source_revision: Some(format!("{source:032x}")),
        expected_policy_revision: Some(format!("{old_policy:032x}")),
        source_queries: vec![crate::daemon::query::SourceQuery::NativeUntypedFixture {
            root: root.clone(),
        }],
    };
    let state = state.lock().unwrap();
    assert_eq!(state.snapshot.as_ref().unwrap().source_revision, source);
    let error = crate::daemon::query::evaluate_snapshot(&request, &frontend.snapshot.tree, &state)
        .unwrap_err();
    assert!(error.to_string().contains("policy query revision"));
    let mut missing = request;
    missing.expected_policy_revision = None;
    let error = crate::daemon::query::evaluate_snapshot(&missing, &frontend.snapshot.tree, &state)
        .unwrap_err();
    assert!(error
        .to_string()
        .contains("requires its exact policy revision"));
}

#[test]
fn configured_session_open_preserves_admitted_policy_intent_during_canonical_check() {
    let root = crate::test_scratch::dir("policy-intent-session-open");
    let manifest = root.join("project.dme");
    let base =
        crate::session::Configuration::new(&root, &manifest, Default::default(), 1, 2, 3).unwrap();
    let empty = PolicyInputRequest::default().admit().unwrap();
    let explicit = PolicyInputRequest {analysis_context:None,workspace_auxiliary:Vec::new(),workspace_generators:Vec::new(),
        workspace: None,
        files: vec![PolicyInputFile {
            path: root.join("marker.dm"),
            role: PolicyInputRole::DmSource,
            required: true,
        }],
        search_folders: vec![root.join("search")],
    }
    .admit()
    .unwrap();
    for admitted in [None, Some(&empty), Some(&explicit)] {
        let configuration = base.clone().with_policy_inputs(admitted);
        let identity = configuration.identity().unwrap();
        let owner = crate::session::SessionRecords::open(configuration.clone()).unwrap();
        assert!(root
            .join(".dmbc/input-sessions")
            .join(format!("{identity:032x}"))
            .is_dir());
        drop(owner);
        // Preserving admitted intent must not weaken the original path check.
        let mut noncanonical = configuration;
        noncanonical.manifest = root.join("nested/../project.dme");
        assert!(crate::session::SessionRecords::open(noncanonical).is_err());
    }
}
