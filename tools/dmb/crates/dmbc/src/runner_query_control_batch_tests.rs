use super::*;
use crate::{
    input_snapshot::{FolderListing, RecordingInputs, SnapshotProvider, Stamp},
    policy_request::{PolicyInputFile, PolicyInputRequest, PolicyInputRole},
};
use std::{
    path::PathBuf,
    sync::{Arc, Mutex},
};
struct Files;
impl Files {
    fn bytes(path: &Path) -> io::Result<&'static [u8]> {
        match path.file_name().and_then(|p|p.to_str()){
    Some("p.dme")=>Ok(b"/proc/p()\n    if(1)\n        return\n    return\n"),
    Some("SpacemanDMM.toml")=>Ok(b"[diagnostics]\ncontrol_condition_static='hint'\nif_condition_determinate='warning'\n"),
    _=>Err(io::ErrorKind::NotFound.into()),
}
    }
}
impl SnapshotProvider for Files {
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        Ok(Stamp {
            size: Self::bytes(path)?.len() as u64,
            modified_ns: 1,
            file_id: Some(1),
        })
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        Ok((self.stamp(path)?, Self::bytes(path)?.to_vec()))
    }
    fn list(&self, _: &Path) -> io::Result<FolderListing> {
        Ok(FolderListing::Present(vec![
            "SpacemanDMM.toml".into(),
            "p.dme".into(),
        ]))
    }
}
fn root() -> PathBuf {
    std::env::current_dir()
        .unwrap()
        .join("configured-control-provider")
}
fn snapshot() -> SourceSnapshot {
    let inputs = RecordingInputs::new(Files, 1);
    let db = Arc::new(crate::query_db::QueryDb::default());
    let frontend = dm_tree::frontend::build(&root().join("p.dme"), &inputs, &Default::default(), 1)
        .unwrap()
        .with_body_queries(db.clone());
    let intent = PolicyInputRequest {workspace_generators:Vec::new(),
        workspace: None,
        files: vec![PolicyInputFile {
            path: root().join("SpacemanDMM.toml"),
            role: PolicyInputRole::Configuration,
            required: true,
        }],
        search_folders: vec![],
    }
    .admit()
    .unwrap();
    let capture = Arc::new(
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
    let state = Arc::new(Mutex::new(
        crate::runner_host::query_snapshot::QueryState::default(),
    ));
    let mut attempt = crate::runner_host::query_snapshot::QueryAttempt::new(state.clone(), true);
    attempt
        .capture_with_queries(&frontend, db, Some(capture))
        .unwrap();
    let snapshot = state.lock().unwrap().snapshot.take().unwrap();
    snapshot
}
fn families() -> Vec<String> {
    vec![
        "if_condition_determinate".into(),
        "control_condition_static".into(),
    ]
}
#[test]
fn batch_uses_common_event_order_configured_levels_and_the_same_primary_query_value() {
    let snapshot = snapshot();
    let archive = snapshot.body_archive.as_ref().unwrap();
    let before = archive.parse(0).unwrap();
    let mut bytes = Vec::new();
    snapshot
        .write_native_configured_control_batch(
            0,
            &families(),
            &root().join("p.dme"),
            None,
            &snapshot.tree,
            &mut bytes,
        )
        .unwrap();
    let row: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let rows = row["diagnostics"].as_array().unwrap();
    assert_eq!(rows.len(), 2);
    assert_eq!(rows[0]["family"], "control_condition_static");
    assert_eq!(rows[1]["family"], "if_condition_determinate");
    assert_eq!(rows[0]["severity"], "hint");
    assert_eq!(rows[1]["severity"], "warning");
    assert_eq!(rows[0]["expanded_span"], rows[1]["expanded_span"]);
    assert_eq!(row["full_checker_parity"], false);
    let after = archive.parse(0).unwrap();
    assert!(std::ptr::eq(
        before.statement_body(),
        after.statement_body()
    ));
}
#[test]
fn batch_rejects_duplicate_family_uncaptured_config_and_foreign_source_issuance() {
    let foreign = snapshot();
    let snapshot = snapshot();
    for selection in [
        vec![],
        vec!["unknown".into()],
        vec![
            "control_condition_static".into(),
            "control_condition_static".into(),
        ],
    ] {
        let mut bytes = Vec::new();
        assert!(snapshot
            .write_native_configured_control_batch(
                0,
                &selection,
                &root().join("p.dme"),
                None,
                &snapshot.tree,
                &mut bytes
            )
            .is_err());
        assert!(bytes.is_empty());
    }
    assert!(snapshot
        .write_native_configured_control_batch(
            0,
            &families(),
            &root().join("p.dme"),
            Some(&root().join("unrequested.toml")),
            &snapshot.tree,
            &mut Vec::new()
        )
        .is_err());
    assert!(snapshot
        .write_native_configured_control_batch(
            0,
            &families(),
            &root().join("p.dme"),
            None,
            &foreign.tree,
            &mut Vec::new()
        )
        .is_err());
}
