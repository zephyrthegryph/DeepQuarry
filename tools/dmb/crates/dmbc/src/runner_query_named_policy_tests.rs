use super::*;
use crate::input_snapshot::{FolderListing, RecordingInputs, SnapshotProvider, Stamp};
use crate::policy_request::{PolicyInputFile, PolicyInputRequest, PolicyInputRole};
use crate::runner_host::policy_capture;
use std::{collections::BTreeMap, path::PathBuf, sync::Mutex};
#[derive(Clone)]
struct Memory(BTreeMap<PathBuf, Vec<u8>>);
impl SnapshotProvider for Memory {
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        let b = self
            .0
            .get(&dm_preprocess::regions::canonical_path(path))
            .ok_or(io::ErrorKind::NotFound)?;
        Ok(Stamp {
            size: b.len() as u64,
            modified_ns: 1,
            file_id: Some(1),
        })
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        Ok((
            self.stamp(path)?,
            self.0[&dm_preprocess::regions::canonical_path(path)].clone(),
        ))
    }
    fn list(&self, path: &Path) -> io::Result<FolderListing> {
        Ok(FolderListing::Present(
            self.0
                .keys()
                .filter(|p| p.parent() == Some(path))
                .filter_map(|p| p.file_name().map(|n| n.to_string_lossy().into_owned()))
                .collect(),
        ))
    }
}
fn root() -> PathBuf {
    std::env::current_dir()
        .unwrap()
        .join("named-policy-provider")
}
fn snapshot(checker: Option<&[u8]>) -> SourceSnapshot {
    snapshot_with_scopes(
        checker,
        b"[lint.base_vars.lists]\nrecord_accessor_prefixes=['get_']\n",
    )
}
fn snapshot_with_scopes(checker: Option<&[u8]>, scopes: &[u8]) -> SourceSnapshot {
    let root = root();
    let mut files=BTreeMap::from([
        (root.join("project.dme"),b"/datum/record\n    proc/rebuild(x,y)\n        return !x & y\n    proc/get_value()\n        return 1\n".to_vec()),
        (root.join("scopes.toml"), scopes.to_vec()),
    ]);
    if let Some(checker) = checker {
        files.insert(root.join("SpacemanDMM.toml"), checker.to_vec());
    }
    let inputs = RecordingInputs::new(Memory(files), 1);
    let db = Arc::new(crate::query_db::QueryDb::default());
    let frontend =
        dm_tree::frontend::build(&root.join("project.dme"), &inputs, &Default::default(), 1)
            .unwrap()
            .with_body_queries(db.clone());
    let intent = PolicyInputRequest {
        files: vec![
            PolicyInputFile {
                path: root.join("scopes.toml"),
                role: PolicyInputRole::Configuration,
                required: true,
            },
            PolicyInputFile {
                path: root.join("SpacemanDMM.toml"),
                role: PolicyInputRole::Configuration,
                required: false,
            },
        ],
        search_folders: vec![],
    }
    .admit()
    .unwrap();
    let captured = Arc::new(
        policy_capture::capture(&frontend, &inputs, &intent.capture_files(), &[])
            .unwrap()
            .bind_request(&intent)
            .unwrap(),
    );
    let state = Arc::new(Mutex::new(
        crate::runner_host::query_snapshot::QueryState::default(),
    ));
    let mut attempt = crate::runner_host::query_snapshot::QueryAttempt::new(state.clone(), true);
    attempt
        .capture_with_queries(&frontend, db, Some(captured))
        .unwrap();
    let snapshot = state.lock().unwrap().snapshot.take().unwrap();
    snapshot
}
#[test]
fn named_record_rule_uses_exact_captured_scope_and_retained_native_declarations() {
    let snapshot = snapshot(None);
    let mut bytes = Vec::new();
    snapshot
        .write_native_named_rule(
            &root(),
            "base_vars",
            "records_data_only",
            &root().join("scopes.toml"),
            &snapshot.tree,
            &mut bytes,
        )
        .unwrap();
    let row: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(row["full_lint_parity"], false);
    assert_eq!(row["findings"].as_array().unwrap().len(), 1);
    assert_eq!(row["findings"][0]["line"], 2);
    assert!(snapshot
        .write_native_named_rule(
            &root(),
            "base_vars",
            "whole_lint",
            &root().join("scopes.toml"),
            &snapshot.tree,
            &mut Vec::new()
        )
        .is_err());
    assert!(snapshot
        .write_native_named_rule(
            &root(),
            "base_vars",
            "records_data_only",
            &root().join("uncaptured.toml"),
            &snapshot.tree,
            &mut Vec::new()
        )
        .is_err());
}
#[test]
fn configured_checker_reads_complete_strict_config_and_reuses_same_query_syntax() {
    let snapshot = snapshot(Some(b"[diagnostics]\nambiguous_not_bitwise='hint'\n"));
    let archive = snapshot.body_archive.as_ref().unwrap();
    let before = archive.parse(0).unwrap();
    let mut bytes = Vec::new();
    snapshot
        .write_native_configured_checker(
            0,
            "ambiguous_not_bitwise",
            &root().join("project.dme"),
            None,
            &snapshot.tree,
            &mut bytes,
        )
        .unwrap();
    let row: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(row["full_checker_parity"], false);
    assert_eq!(row["configuration_present"], true);
    assert_eq!(row["diagnostics"][0]["severity"], "hint");
    let after = archive.parse(0).unwrap();
    assert!(std::ptr::eq(
        before.statement_body(),
        after.statement_body()
    ));
}
#[test]
fn absent_auto_config_is_distinct_from_explicit_or_uncaptured_config() {
    let snapshot = snapshot(None);
    let captured = snapshot.named_policy_capture(&snapshot.tree).unwrap();
    assert!(
        !configuration(captured, &root().join("project.dme"), None)
            .unwrap()
            .present
    );
    assert!(configuration(
        captured,
        &root().join("project.dme"),
        Some(&root().join("SpacemanDMM.toml"))
    )
    .is_err());
    assert!(configuration(
        captured,
        &root().join("project.dme"),
        Some(&root().join("other.toml"))
    )
    .is_err());
    assert!(configuration(
        captured,
        &root().join("project.dme"),
        Some(&root().join("project.dme"))
    )
    .is_err());
}
#[test]
fn invalid_utf8_and_invalid_nonpolicy_checker_sections_are_not_lossily_accepted() {
    for bytes in [b"# bad \xff".as_slice(), b"[langserver]\ndreamchecker=1\n"] {
        let snapshot = snapshot(Some(bytes));
        assert!(snapshot
            .write_native_configured_checker(
                0,
                "ambiguous_not_bitwise",
                &root().join("project.dme"),
                None,
                &snapshot.tree,
                &mut Vec::new()
            )
            .is_err());
    }
}

#[test]
fn foreign_equal_source_tree_cannot_rebind_named_policy_archive() {
    let original = snapshot(None);
    let foreign = snapshot(None);
    assert_eq!(original.tree.identity(), foreign.tree.identity());
    assert!(original
        .write_native_named_rule(
            &root(),
            "base_vars",
            "records_data_only",
            &root().join("scopes.toml"),
            &foreign.tree,
            &mut Vec::new()
        )
        .is_err());
}

#[test]
fn invalid_utf8_scopes_match_analyze_read_failure_default_without_lossy_repair() {
    let snapshot = snapshot_with_scopes(None, b"# bad \xff");
    let mut bytes = Vec::new();
    snapshot
        .write_native_named_rule(
            &root(),
            "base_vars",
            "records_data_only",
            &root().join("scopes.toml"),
            &snapshot.tree,
            &mut bytes,
        )
        .unwrap();
    let row: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(row["findings"].as_array().unwrap().len(), 2);
}
