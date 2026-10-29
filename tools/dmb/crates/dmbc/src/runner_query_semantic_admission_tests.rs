use super::*;
use crate::input_snapshot::{FolderListing, RecordingInputs, SnapshotProvider, Stamp};
use crate::policy_request::{PolicyInputFile, PolicyInputRequest, PolicyInputRole};
use std::{io, path::Path};
#[derive(Clone)]
struct Original(&'static [u8]);
impl SnapshotProvider for Original {
    fn stamp(&self, p: &Path) -> io::Result<Stamp> {
        if p.file_name().and_then(|p| p.to_str()) != Some("native_encoding.dm") {
            return Err(io::ErrorKind::NotFound.into());
        }
        Ok(Stamp {
            size: self.0.len() as u64,
            modified_ns: 1,
            file_id: Some(1),
        })
    }
    fn read(&self, p: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        Ok((self.stamp(p)?, self.0.to_vec()))
    }
    fn list(&self, p: &Path) -> io::Result<FolderListing> {
        Ok(FolderListing::Present(if p.ends_with("code") {
            vec!["native_encoding.dm".into()]
        } else {
            vec!["code".into()]
        }))
    }
}
fn root() -> PathBuf {
    std::env::current_dir()
        .unwrap()
        .join("native-encoding-fixture")
}
fn source(
    bytes: &'static [u8],
    db: &Arc<crate::query_db::QueryDb>,
) -> (RecordingInputs<Original>, ColdFrontend) {
    let inputs = RecordingInputs::new(Original(bytes), 1);
    let frontend = dm_tree::frontend::build(
        &root().join("code/native_encoding.dm"),
        &inputs,
        &Default::default(),
        1,
    )
    .unwrap()
    .with_body_queries(db.clone());
    (inputs, frontend)
}
#[test]
fn equal_decoded_revision_does_not_admit_current_incompatible_none_policy_checker() {
    let db = Arc::new(crate::query_db::QueryDb::default());
    let (old_inputs, old) = source(
        "/proc/probe(x)\n    // €\n    return !x & 1\n".as_bytes(),
        &db,
    );
    let old_evidence = old_inputs.semantic_source_evidence(&old).unwrap();
    let mut old_snapshot = SourceSnapshot::capture(&old);
    old_snapshot.semantic_sources = Some(old_evidence.clone());
    assert!(old_snapshot.policy_revision.is_none());
    let old_archive = old_snapshot.body_archive.as_ref().unwrap();
    let old_parse = old_archive.parse(0).unwrap();
    let mut old_result = Vec::new();
    old_snapshot
        .write_native_checker(0, "warning", &old.snapshot.tree, &mut old_result)
        .unwrap();
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&old_result).unwrap()["diagnostics"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    let (new_inputs, new) = source(b"/proc/probe(x)\n    // \x80\n    return !x & 1\n", &db);
    assert_eq!(
        old.source_export_revision(),
        new.source_export_revision(),
        "compiler source pin intentionally describes native decoded source"
    );
    let old_lease = old.plan.source_acquisitions.values().next().unwrap();
    let new_lease = new.plan.source_acquisitions.values().next().unwrap();
    let old_full = dm_preprocess::SourceProvider::source_acquisition(
        &old_inputs,
        old.plan.occurrences[0].path.as_ref(),
        old_lease.source_text(),
    )
    .unwrap();
    let new_full = dm_preprocess::SourceProvider::source_acquisition(
        &new_inputs,
        new.plan.occurrences[0].path.as_ref(),
        new_lease.source_text(),
    )
    .unwrap();
    assert!(Arc::ptr_eq(old_full.prepared(), new_full.prepared()));
    assert!(!old_lease.same_original_acquisition(new_lease));
    let mut current = SourceSnapshot::capture(&new);
    current.semantic_sources = Some(new_inputs.semantic_source_evidence(&new).unwrap());
    assert!(current.policy_revision.is_none());
    let before = db.db().stats(dm_query::Kind(4)).computed;
    let mut refused = Vec::new();
    assert!(current
        .write_native_checker(0, "warning", &new.snapshot.tree, &mut refused)
        .is_err());
    assert!(refused.is_empty());
    for explicit in [None, Some(root().join("SpacemanDMM.toml"))] {
        let mut visibility = Vec::new();
        let error = current
            .write_native_configured_variable_visibility(
                &root().join("code/native_encoding.dm"),
                explicit.as_deref(),
                &new.snapshot.tree,
                &mut visibility,
            )
            .unwrap_err();
        assert!(error
            .to_string()
            .contains("original source encoding lacks legacy semantic parity"));
        assert!(visibility.is_empty());
    }
    assert_eq!(
        db.db().stats(dm_query::Kind(4)).computed,
        before,
        "current refusal precedes semantic query fetch"
    );
    let old_again = old_archive.parse(0).unwrap();
    assert!(
        std::ptr::eq(old_parse.statement_body(), old_again.statement_body()),
        "immutable old archive still borrows its existing cached body"
    );
    assert!(
        old_evidence
            .check(new.source_export_mapping().unwrap())
            .is_err(),
        "old semantic admission cannot authorize new equal-decoded capture"
    );
}
#[test]
fn unknown_string_provider_cannot_return_clean_none_policy_checker_rows() {
    struct Text;
    impl dm_preprocess::SourceProvider for Text {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/proc/probe()\n    return\n".into())
        }
    }
    let frontend = dm_tree::frontend::build(
        &root().join("code/native_encoding.dm"),
        &Text,
        &Default::default(),
        1,
    )
    .unwrap();
    let snapshot = SourceSnapshot::capture(&frontend);
    let mut output = Vec::new();
    assert!(snapshot
        .write_native_checker(0, "disabled", &frontend.snapshot.tree, &mut output)
        .is_err());
    assert!(output.is_empty());
    let mut visibility = Vec::new();
    let error = snapshot
        .write_native_configured_variable_visibility(
            &root().join("code/native_encoding.dm"),
            None,
            &frontend.snapshot.tree,
            &mut visibility,
        )
        .unwrap_err();
    assert!(error
        .to_string()
        .contains("semantic source original encoding unproven"));
    assert!(visibility.is_empty());
}
#[test]
fn incompatible_original_still_has_byte_faithful_raw_policy_findings() {
    let db = Arc::new(crate::query_db::QueryDb::default());
    let (inputs, frontend) = source(b"/proc/probe()\n    // \x80\n    sleep(1)\n", &db);
    let config = root().join("scopes.toml");
    let intent = PolicyInputRequest {
        workspace: None,
        files: vec![PolicyInputFile {
            path: config.clone(),
            role: PolicyInputRole::Configuration,
            required: false,
        }],
        search_folders: vec![],
    }
    .admit()
    .unwrap();
    let captured = Arc::new(
        crate::runner_host::policy_capture::capture(
            &frontend,
            &inputs,
            &intent.capture_files(),
            &[],
        )
        .unwrap()
        .bind_request(&intent)
        .unwrap(),
    );
    let mut snapshot = SourceSnapshot::capture_policy(&frontend, Some(captured));
    snapshot.native_raw_queries = Some(db);
    assert!(snapshot.require_semantic_source_encoding().is_err());
    let mut output = Vec::new();
    snapshot
        .write_native_raw_policy_fixture(
            &root(),
            &config,
            &["scheduler".into()],
            &frontend.snapshot.tree,
            &mut output,
        )
        .unwrap();
    let row: serde_json::Value = serde_json::from_slice(&output).unwrap();
    assert_eq!(row["results"][0]["sites"].as_array().unwrap().len(), 1);
    assert_eq!(row["results"][0]["sites"][0]["line"], 3);
}

#[test]
fn disabled_plain_compile_does_not_attempt_semantic_capture_or_mapping_admission() {
    struct Text;
    impl dm_preprocess::SourceProvider for Text {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/proc/probe()\n    return\n".into())
        }
    }
    let mut frontend = dm_tree::frontend::build(
        &root().join("code/native_encoding.dm"),
        &Text,
        &Default::default(),
        1,
    )
    .unwrap();
    frontend.plan.source_acquisitions.insert(
        0,
        dm_preprocess::AcquiredSource::synthetic_utf8("/proc/foreign()\n    return\n".into(), ())
            .lease()
            .clone(),
    );
    assert!(
        frontend.source_export_mapping().is_none(),
        "deliberate invalid public compatibility mutation"
    );
    let inputs = RecordingInputs::new(Original(b"unread"), 1);
    let state = Arc::new(Mutex::new(QueryState::default()));
    let mut attempt = QueryAttempt::new(state.clone(), false);
    attempt
        .capture_with_recorded_sources(
            &frontend,
            Arc::new(crate::query_db::QueryDb::default()),
            None,
            &inputs,
        )
        .unwrap();
    assert!(state.lock().unwrap().snapshot.is_none());
    assert_eq!(inputs.snapshot().unwrap().files().count(), 0);
}

#[test]
fn uncaptured_compiled_occurrence_is_unknown_not_a_vacuous_semantic_allow() {
    let db = Arc::new(crate::query_db::QueryDb::default());
    let (inputs, frontend) = source(b"/proc/probe()\n    return\n", &db);
    let evidence = inputs
        .semantic_source_evidence_without_captured_roster(&frontend)
        .unwrap();
    let mut snapshot = SourceSnapshot::capture(&frontend);
    snapshot.semantic_sources = Some(evidence);
    let mut output = Vec::new();
    assert!(snapshot
        .write_native_checker(0, "disabled", &frontend.snapshot.tree, &mut output)
        .is_err());
    assert!(output.is_empty());
    // Recording/capture itself remains valid; only semantic-policy admission refuses.
    assert!(inputs.snapshot().is_ok());
}

#[test]
fn immutable_admission_verdict_reuses_current_mapping_only_and_keeps_first_refusal() {
    let db = Arc::new(crate::query_db::QueryDb::default());
    let (inputs, frontend) = source(b"/proc/probe()\n    // \x80\n    return\n", &db);
    let evidence = inputs.semantic_source_evidence(&frontend).unwrap();
    let mapping = frontend.source_export_mapping().unwrap();
    let first = evidence.check(mapping).unwrap_err().to_string();
    for _ in 0..8 {
        assert_eq!(evidence.check(mapping).unwrap_err().to_string(), first);
    }
    let (_, foreign) = source(b"/proc/probe()\n    // \x80\n    return\n", &db);
    let foreign_error = evidence
        .check(foreign.source_export_mapping().unwrap())
        .unwrap_err()
        .to_string();
    assert!(foreign_error.contains("another issued source mapping"));
    assert_ne!(
        foreign_error, first,
        "foreign identity refuses before cached compatibility verdict"
    );
}
