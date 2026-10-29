use super::*;
use crate::input_snapshot::{FolderListing, RecordingInputs, SnapshotProvider, Stamp};
use crate::policy_request::{PolicyInputFile, PolicyInputRequest, PolicyInputRole};
use std::{path::PathBuf, sync::Arc};
#[derive(Clone)]
struct Files {
    config: Option<Vec<u8>>,
}
const CODE:&[u8]=b"/datum/probe/proc/run()\n    sleep(1)\n    sleep(2) // ALLOW(scheduler): this is an intentional annotation fixture\n";
impl SnapshotProvider for Files {
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        let bytes = if path.ends_with("sample.dm") {
            CODE
        } else {
            self.config.as_deref().ok_or(io::ErrorKind::NotFound)?
        };
        Ok(Stamp {
            size: bytes.len() as u64,
            modified_ns: 1,
            file_id: Some(1),
        })
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        let bytes = if path.ends_with("sample.dm") {
            CODE
        } else {
            self.config.as_deref().ok_or(io::ErrorKind::NotFound)?
        };
        Ok((self.stamp(path)?, bytes.to_vec()))
    }
    fn list(&self, _: &Path) -> io::Result<FolderListing> {
        Ok(FolderListing::Present(vec![
            "lint_scopes.toml".into(),
            "sample.dm".into(),
        ]))
    }
}
fn fixture(config: Option<&[u8]>, role: PolicyInputRole) -> (PathBuf, PathBuf, SourceSnapshot) {
    let root = std::env::current_dir().unwrap().join("raw-host-fixture");
    let configuration = root.join("tools/ci/lint_scopes.toml");
    let ledger = RecordingInputs::new(
        Files {
            config: config.map(Vec::from),
        },
        1,
    );
    let queries = Arc::new(crate::query_db::QueryDb::default());
    let frontend = dm_tree::frontend::build(
        &root.join("code/sample.dm"),
        &ledger,
        &Default::default(),
        1,
    )
    .unwrap()
    .with_body_queries(queries.clone());
    let request = PolicyInputRequest {
        workspace: None,
        files: vec![PolicyInputFile {
            path: configuration.clone(),
            role,
            required: config.is_some(),
        }],
        search_folders: vec![],
    }
    .admit()
    .unwrap();
    let captured = crate::runner_host::policy_capture::capture(
        &frontend,
        &ledger,
        &request.capture_files(),
        &[],
    )
    .unwrap()
    .bind_request(&request)
    .unwrap();
    let mut snapshot = SourceSnapshot::capture_policy(&frontend, Some(Arc::new(captured)));
    snapshot.native_raw_queries = Some(queries);
    (root, configuration, snapshot)
}
fn run(
    snapshot: &SourceSnapshot,
    root: &Path,
    configuration: &Path,
    lints: &[&str],
) -> io::Result<serde_json::Value> {
    let mut bytes = Vec::new();
    snapshot.write_native_raw_policy_fixture(
        root,
        configuration,
        &lints.iter().map(|s| s.to_string()).collect::<Vec<_>>(),
        &snapshot.tree,
        &mut bytes,
    )?;
    serde_json::from_slice(&bytes).map_err(io::Error::other)
}
#[test]
fn exact_raw_sites_allow_consumption_and_explicit_scope_are_preserved() {
    let (root, config, snapshot) = fixture(Some(b""), PolicyInputRole::Configuration);
    let row = run(&snapshot, &root, &config, &["scheduler"]).unwrap();
    assert_eq!(row["scope"], "explicit_captured_files");
    assert_eq!(row["full_policy_parity"], false);
    assert_eq!(row["baseline_applied"], false);
    assert_eq!(
        row["policy_revision"],
        format!("{:032x}", snapshot.policy_revision.unwrap())
    );
    let result = &row["results"][0];
    assert_eq!(result["name"], "scheduler");
    assert_eq!(result["sites"].as_array().unwrap().len(), 1);
    assert_eq!(result["sites"][0]["line"], 2);
    assert_eq!(result["allow_used"].as_array().unwrap().len(), 1);
    assert_eq!(result["allow_used"][0]["line"], 3);
    assert_eq!(result["notes"], serde_json::json!([]));
}
#[test]
fn proven_missing_configuration_defaults_but_unknown_and_wrong_role_refuse() {
    let (root, config, snapshot) = fixture(None, PolicyInputRole::Configuration);
    let row = run(&snapshot, &root, &config, &["scheduler"]).unwrap();
    assert_eq!(row["configuration_scope"], "proven_missing_configuration");
    assert!(run(
        &snapshot,
        &root,
        &root.join("unrequested.toml"),
        &["scheduler"]
    )
    .is_err());
    let (root, config, snapshot) = fixture(Some(b""), PolicyInputRole::DmSource);
    assert!(run(&snapshot, &root, &config, &["scheduler"]).is_err());
}
#[test]
fn unsupported_lints_and_malformed_configuration_emit_nothing() {
    for (config, lints) in [
        (b"".as_slice(), vec!["tracked"]),
        (b"not = [".as_slice(), vec!["scheduler"]),
    ] {
        let (root, path, snapshot) = fixture(Some(config), PolicyInputRole::Configuration);
        let mut out = Vec::new();
        assert!(snapshot
            .write_native_raw_policy_fixture(
                &root,
                &path,
                &lints.into_iter().map(str::to_owned).collect::<Vec<_>>(),
                &snapshot.tree,
                &mut out
            )
            .is_err());
        assert!(out.is_empty());
    }
}
#[test]
fn captured_configuration_exemptions_and_invalid_utf8_follow_existing_scopes_policy() {
    let (root, path, snapshot) = fixture(
        Some(b"[lint.scheduler]\nexempt_files=[\"code/sample.dm\"]\n"),
        PolicyInputRole::Configuration,
    );
    assert_eq!(
        run(&snapshot, &root, &path, &["scheduler"]).unwrap()["results"][0]["sites"],
        serde_json::json!([])
    );
    let (root, path, snapshot) = fixture(Some(b"\xff"), PolicyInputRole::Configuration);
    assert_eq!(
        run(&snapshot, &root, &path, &["scheduler"]).unwrap()["results"][0]["sites"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
}
