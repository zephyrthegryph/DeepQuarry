use super::*;
fn path(name: &str) -> PathBuf {
    std::env::temp_dir()
        .join("policy-request-fixture")
        .join(name)
}
fn file(name: &str, required: bool) -> PolicyInputFile {
    PolicyInputFile {
        path: path(name),
        required,
        role: PolicyInputRole::DmSource,
    }
}
#[test]
fn admission_is_canonical_order_independent_and_joins_requiredness() {
    let first = PolicyInputRequest {
        workspace: None,
        files: vec![file("b.dm", false), file("a.dm", true), file("b.dm", true)],
        search_folders: vec![path("z"), path("a"), path("z")],
    }
    .admit()
    .unwrap();
    let second = PolicyInputRequest {
        workspace: None,
        files: vec![file("b.dm", true), file("a.dm", true)],
        search_folders: vec![path("a"), path("z")],
    }
    .admit()
    .unwrap();
    assert_eq!(first, second);
    assert_eq!(first.files().len(), 2);
    assert!(first.files().iter().all(|file| file.required));
    assert_eq!(first.search_folders().len(), 2);
}
#[test]
fn contradictions_and_relative_paths_fail_without_disk_reads() {
    let mut other = file("a.dm", false);
    other.role = PolicyInputRole::Configuration;
    assert!(PolicyInputRequest {
        files: vec![file("a.dm", true), other],
        ..Default::default()
    }
    .admit()
    .is_err());
    assert!(PolicyInputRequest {
        search_folders: vec!["relative".into()],
        ..Default::default()
    }
    .admit()
    .is_err());
    let mut relative = file("a.dm", false);
    relative.path = "relative.dm".into();
    assert!(PolicyInputRequest {
        files: vec![relative],
        ..Default::default()
    }
    .admit()
    .is_err());
}
#[test]
fn omitted_wire_lists_default_but_admitted_deserialization_cannot_bypass_validation() {
    let empty: PolicyInputRequest = serde_json::from_str("{}").unwrap();
    assert_eq!(empty, PolicyInputRequest::default());
    let invalid = r#"{"files":[{"path":"relative","role":"dm_source","required":true}]}"#;
    assert!(serde_json::from_str::<AdmittedPolicyRequest>(invalid).is_err());
    let admitted = empty.admit().unwrap();
    assert_eq!(
        serde_json::from_slice::<AdmittedPolicyRequest>(&serde_json::to_vec(&admitted).unwrap())
            .unwrap(),
        admitted
    );
}
#[test]
fn identity_preserves_absence_and_distinguishes_every_contract_dimension() {
    let original = b"existing-configuration".to_vec();
    let mut absent = original.clone();
    append_identity(&mut absent, None).unwrap();
    assert_eq!(absent, original);
    let empty = PolicyInputRequest::default().admit().unwrap();
    let mut present = original.clone();
    append_identity(&mut present, Some(&empty)).unwrap();
    assert_ne!(present, absent);
    let first = PolicyInputRequest {
        files: vec![file("a.dm", false)],
        ..Default::default()
    };
    let variants = [
        first.clone(),
        PolicyInputRequest {
            files: vec![file("a.dm", true)],
            ..Default::default()
        },
        PolicyInputRequest {
            files: vec![PolicyInputFile {
                role: PolicyInputRole::Configuration,
                ..file("a.dm", false)
            }],
            ..Default::default()
        },
        PolicyInputRequest {
            search_folders: vec![path("search")],
            ..first
        },
    ];
    let keys = variants
        .into_iter()
        .map(|request| {
            let mut key = original.clone();
            append_identity(&mut key, Some(&request.admit().unwrap())).unwrap();
            key
        })
        .collect::<BTreeSet<_>>();
    assert_eq!(keys.len(), 4);
}

#[test]
fn external_policy_revision_binds_content_and_contract_without_changing_source_pins() {
    let facts = crate::input_snapshot::InputSnapshot::new(1);
    let empty = PolicyInputRequest::default().admit().unwrap();
    let changed = PolicyInputRequest {
        files: vec![file("a.dm", true)],
        ..Default::default()
    }
    .admit()
    .unwrap();
    let first = captured_revision(11, &facts, &empty).unwrap();
    assert_ne!(first, captured_revision(12, &facts, &empty).unwrap());
    assert_ne!(first, captured_revision(11, &facts, &changed).unwrap());
    assert_eq!(first, captured_revision(11, &facts, &empty).unwrap());
}

#[test]
fn policy_revision_ignores_scan_clock_but_binds_directory_and_absence_facts() {
    let request = PolicyInputRequest::default().admit().unwrap();
    let first = crate::input_snapshot::InputSnapshot::new(1);
    let mut later = crate::input_snapshot::InputSnapshot::new(2);
    assert_eq!(
        captured_revision(11, &first, &request).unwrap(),
        captured_revision(11, &later, &request).unwrap()
    );
    later.record_negative(&path("optional.toml")).unwrap();
    assert_ne!(
        captured_revision(11, &first, &request).unwrap(),
        captured_revision(11, &later, &request).unwrap()
    );
    let negative = later.clone();
    later
        .record_folder(
            &path("search"),
            crate::input_snapshot::FolderListing::Present(vec!["a.dm".into()]),
        )
        .unwrap();
    assert_ne!(
        captured_revision(11, &negative, &request).unwrap(),
        captured_revision(11, &later, &request).unwrap()
    );
}

#[test]
fn workspace_intent_is_normalized_distinct_and_cannot_mix_explicit_inputs() {
    let workspace = WorkspacePolicyRequest {
        root: path("root"),
        recursive_roots: vec![path("root/code"), path("root/code")],
        configuration: path("root/scopes.toml"),
    };
    let request = PolicyInputRequest {
        workspace: Some(workspace.clone()),
        ..Default::default()
    }
    .admit()
    .unwrap();
    assert_eq!(request.workspace().unwrap().recursive_roots.len(), 1);
    assert!(PolicyInputRequest {
        workspace: Some(workspace.clone()),
        files: vec![file("a.dm", true)],
        ..Default::default()
    }
    .admit()
    .is_err());
    assert!(PolicyInputRequest {
        workspace: Some(workspace),
        search_folders: vec![path("root")],
        ..Default::default()
    }
    .admit()
    .is_err());
    let encoded = serde_json::to_value(PolicyInputRequest::default().admit().unwrap()).unwrap();
    assert!(
        encoded.get("workspace").is_none(),
        "old explicit identity serialization remains byte-compatible"
    );
    let roundtrip: AdmittedPolicyRequest =
        serde_json::from_slice(&serde_json::to_vec(&request).unwrap()).unwrap();
    assert_eq!(request, roundtrip);
}
