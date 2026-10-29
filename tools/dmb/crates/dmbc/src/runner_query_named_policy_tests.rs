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

// Same native compiler source owner, engine receipt and successful preparation.
fn semantic_snapshot(source: &str, checker: Option<&[u8]>) -> SourceSnapshot {
    let root = root();
    let mut host = crate::runner_host::BuildHost::one_shot();
    let engine = host
        .engine(
            root.join("project.dme"),
            Default::default(),
            true,
            include_bytes!("../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap();
    let mut files = BTreeMap::from([(root.join("project.dme"), source.as_bytes().to_vec())]);
    if let Some(checker) = checker {
        files.insert(root.join("SpacemanDMM.toml"), checker.to_vec());
    }
    let inputs = RecordingInputs::new(Memory(files), 1);
    let db = Arc::new(crate::query_db::QueryDb::default());
    let frontend = dm_tree::frontend::FrontendRevision::new(
        dm_tree::frontend::build_with_config(
            &root.join("project.dme"),
            &inputs,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(engine.frontend_seed()),
                observer: None,
            },
        )
        .unwrap()
        .with_body_queries(db.clone()),
    );
    let intent = PolicyInputRequest {
        files: vec![PolicyInputFile {
            path: root.join("SpacemanDMM.toml"),
            role: PolicyInputRole::Configuration,
            required: false,
        }],
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
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let prepared = crate::request_runner::runner_analysis::prepare_query(
        &frontend,
        Some(&engine),
        None,
        &executor,
        None,
        987,
        &mut attempt,
        true,
    )
    .unwrap();
    assert!(matches!(
        prepared,
        crate::request::BuildOutcome::QueryPrepared { .. }
    ));
    attempt.finish_analyzed();
    drop(attempt);
    drop(frontend);
    let result = state.lock().unwrap().snapshot.take().unwrap();
    result
}
fn semantic_row(
    snapshot: &SourceSnapshot,
    ordinal: u32,
    family: &str,
) -> io::Result<serde_json::Value> {
    let mut bytes = Vec::new();
    snapshot.write_native_configured_checker(
        ordinal,
        family,
        &root().join("project.dme"),
        None,
        &snapshot.tree,
        &mut bytes,
    )?;
    serde_json::from_slice(&bytes).map_err(io::Error::other)
}
#[test]
fn retained_semantic_parent_and_undefined_policies_use_same_prepared_source_owner() {
    let snapshot = semantic_snapshot("/datum/example/proc/probe()\n    missing_outer(missing_hidden())\n    return ..(missing_parent_hidden())\n", None);
    let tree = Arc::as_ptr(&snapshot.tree);
    let archive = snapshot.body_archive.as_ref().unwrap();
    let before = archive.parse(0).unwrap();
    let parent = semantic_row(&snapshot, 0, "proc_has_no_parent").unwrap();
    let undefined = semantic_row(&snapshot, 0, "undefined_proc").unwrap();
    let after = archive.parse(0).unwrap();
    assert!(std::ptr::eq(
        before.statement_body(),
        after.statement_body()
    ));
    assert!(std::ptr::eq(archive.tree(), tree));
    for row in [&parent, &undefined] {
        assert_eq!(row["full_checker_parity"], false);
        assert_eq!(
            row["semantic_revision"],
            format!("{:032x}", snapshot.tree.identity())
        );
        assert_eq!(
            row["policy_revision"],
            format!("{:032x}", snapshot.policy_revision.unwrap())
        );
        assert_eq!(row["diagnostics"].as_array().unwrap().len(), 1);
        assert_eq!(row["diagnostics"][0]["severity"], "error");
    }
    assert_eq!(
        parent["diagnostics"][0]["message"],
        "proc has no parent: /datum/example/proc/probe"
    );
    assert_eq!(
        undefined["diagnostics"][0]["message"],
        "undefined proc: \"missing_outer\" on /datum/example"
    );
    assert_eq!(undefined["diagnostics"][0]["line"], 2);
}
#[test]
fn semantic_policies_preserve_real_tag_override_and_untagged_error_default() {
    let snapshot = semantic_snapshot(
        "/datum/example/proc/probe()\n    missing()\n    return ..()\n",
        Some(b"[diagnostics]\nproc_has_no_parent='hint'\nundefined_proc='off'\n"),
    );
    let parent = semantic_row(&snapshot, 0, "proc_has_no_parent").unwrap();
    let undefined = semantic_row(&snapshot, 0, "undefined_proc").unwrap();
    assert_eq!(parent["diagnostics"][0]["severity"], "hint");
    assert_eq!(undefined["diagnostics"][0]["severity"], "error");
    assert_eq!(undefined["diagnostics"].as_array().unwrap().len(), 1);
}
#[test]
fn semantic_host_unavailable_or_unsupported_body_never_becomes_false_clean() {
    let syntactic_only = snapshot(None);
    assert!(semantic_row(&syntactic_only, 0, "undefined_proc").is_err());
    let unsupported = semantic_snapshot("/datum/example/proc/probe()\n    missing_earlier()\n    var/datum/typed\n    missing_later()\n", None);
    let mut bytes = Vec::new();
    assert!(unsupported
        .write_native_configured_checker(
            0,
            "undefined_proc",
            &root().join("project.dme"),
            None,
            &unsupported.tree,
            &mut bytes
        )
        .is_err());
    assert!(
        bytes.is_empty(),
        "partial findings escaped unsupported body"
    );
}
#[test]
fn semantic_endpoint_refuses_equal_but_foreign_compiled_tree() {
    let a = semantic_snapshot("/datum/example/proc/probe()\n    return ..()\n", None);
    let b = semantic_snapshot("/datum/example/proc/probe()\n    return ..()\n", None);
    assert_eq!(a.tree.identity(), b.tree.identity());
    assert!(a
        .write_native_configured_checker(
            0,
            "proc_has_no_parent",
            &root().join("project.dme"),
            None,
            &b.tree,
            &mut Vec::new()
        )
        .is_err());
}
