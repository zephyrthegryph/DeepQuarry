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
        workspace: None,
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
    semantic_snapshot_primary(source, checker, false)
}
pub(super) fn semantic_snapshot_primary(
    source: &str,
    checker: Option<&[u8]>,
    primary: bool,
) -> SourceSnapshot {
    semantic_snapshot_primary_result(source, checker, primary).unwrap()
}
pub(super) fn semantic_snapshot_primary_result(
    source: &str,
    checker: Option<&[u8]>,
    primary: bool,
) -> Result<SourceSnapshot, Vec<dm_tree::frontend::Diagnostic>> {
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
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let frontend = dm_tree::frontend::FrontendRevision::new(
        dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
            &root.join("project.dme"),
            &inputs,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(engine.frontend_seed()),
                observer: None,
            },
            None,
            &executor,
            None,
            primary,
        )?
        .with_body_queries(db.clone()),
    );
    let intent = PolicyInputRequest {
        workspace: None,
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
    Ok(result)
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
    let supported=semantic_snapshot("/datum/example/proc/probe()\n    missing_earlier()\n    var/datum/typed[1]\n    missing_later()\n",None);
    let rows = semantic_row(&supported, 0, "undefined_proc").unwrap();
    let diagnostics = rows["diagnostics"].as_array().unwrap();
    assert_eq!(diagnostics.len(), 2);
    assert_eq!(
        diagnostics[0]["message"],
        "undefined proc: \"missing_earlier\" on /datum/example"
    );
    assert_eq!(diagnostics[0]["line"], 2);
    assert_eq!(
        diagnostics[1]["message"],
        "undefined proc: \"missing_later\" on /datum/example"
    );
    assert_eq!(diagnostics[1]["line"], 4);
    let unsupported = semantic_snapshot("/datum/example/proc/probe()\n    missing_earlier()\n    for(var/datum/item[1] in list())\n        missing_later()\n", None);
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

#[test]
fn untagged_variable_errors_use_exact_retained_host_and_ignore_fake_named_override() {
    let snapshot = semantic_snapshot(
        "/datum/example/proc/probe()\n    missing_variable\n",
        Some(b"[diagnostics]\nundefined_variable='off'\n"),
    );
    let row = semantic_row(&snapshot, 0, "undefined_variable").unwrap();
    assert_eq!(row["full_checker_parity"], false);
    assert_eq!(row["diagnostics"].as_array().unwrap().len(), 1);
    assert_eq!(row["diagnostics"][0]["severity"], "error");
    assert_eq!(
        row["diagnostics"][0]["message"],
        "undefined var: \"missing_variable\""
    );
    assert_eq!(row["diagnostics"][0]["line"], 2);
}

// Independently observed with the SHA-pinned checker suite-1.11, source
// commit 0290db5c752fa292f9824521515b603a2afd11dc. Original static source has
// zero errors; the single-variable witness below proves this is not a disabled
// family/default-empty row. DATA evidence: host-negative-repair-probes/.
#[test]
fn checker_static_local_inventory_matches_old_clean_source_and_nonempty_witness() {
    let source="/datum/example/proc/probe()\n    var/static/shared = 1\n    shared += 1\n    return shared\n";
    let snapshot = semantic_snapshot(source, None);
    let declaration = snapshot.body_archive.as_ref().unwrap().occurrences()[0]
        .declaration
        .0;
    let mut selected = Vec::new();
    snapshot.write_selected(declaration, &mut selected).unwrap();
    assert!(String::from_utf8(selected).unwrap().contains("shared"));
    let row = semantic_row(&snapshot, 0, "undefined_variable").unwrap();
    assert_eq!(row["diagnostics"], serde_json::json!([]));
    let witness=semantic_snapshot("/datum/example/proc/probe()\n    var/static/shared = 1\n    shared += 1\n    return shared + missing_after_shared\n",None);
    let row = semantic_row(&witness, 0, "undefined_variable").unwrap();
    let rows = row["diagnostics"].as_array().unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(
        rows[0]["message"],
        "undefined var: \"missing_after_shared\""
    );
    assert_eq!(rows[0]["severity"], "error");
    assert_eq!(rows[0]["line"], 4);
    assert_eq!(rows[0]["notes"], serde_json::json!([]));
    let point = witness
        .body_archive
        .as_ref()
        .unwrap()
        .original_note_origin(rows[0]["expanded_span"][0].as_u64().unwrap() as usize)
        .unwrap();
    assert_eq!((point.line, point.byte_column), (4, 21));
}
#[test]
fn checker_storage_gap_does_not_narrow_native_stored_local_lowering() {
    let runtime=semantic_snapshot("/datum/example/proc/probe()\n    var/static/shared = 1\n    shared += 1\n    return shared\n",None);
    let declaration = runtime.body_archive.as_ref().unwrap().occurrences()[0]
        .declaration
        .0;
    let mut selected = Vec::new();
    runtime.write_selected(declaration, &mut selected).unwrap();
    assert!(String::from_utf8(selected).unwrap().contains("shared"));
    // Preserve the exact former array-negative source as a proved positive.
    let supported=semantic_snapshot("/datum/example/proc/probe()\n    var/static/shared = 1\n    shared += 1\n    missing_earlier\n    var/datum/typed[1]\n    return shared\n",None);
    let row = semantic_row(&supported, 0, "undefined_variable").unwrap();
    let diagnostics = row["diagnostics"].as_array().unwrap();
    assert_eq!(diagnostics.len(), 1);
    assert_eq!(
        diagnostics[0]["message"],
        "undefined var: \"missing_earlier\""
    );
    assert_eq!(diagnostics[0]["line"], 4);
    // A nonempty for-in binding is still outside the original checker grammar.
    let snapshot=semantic_snapshot("/datum/example/proc/probe()\n    var/static/shared = 1\n    shared += 1\n    missing_earlier\n    for(var/datum/item[1] in list())\n        return shared\n",None);
    let mut bytes = Vec::new();
    let error = snapshot
        .write_native_configured_checker(
            0,
            "undefined_variable",
            &root().join("project.dme"),
            None,
            &snapshot.tree,
            &mut bytes,
        )
        .unwrap_err();
    assert!(
        error
            .to_string()
            .contains("nonempty array initializer is not an old for-in/all binding"),
        "{error}"
    );
    assert!(
        bytes.is_empty(),
        "earlier undefined-variable row escaped later array refusal"
    );
}

#[test]
fn field_static_warning_uses_retained_real_host_and_original_callable_note() {
    let snapshot = semantic_snapshot(
        "/proc/untyped()\n    return null\n/proc/probe()\n    untyped().field\n",
        None,
    );
    let row = semantic_row(&snapshot, 1, "field_access_static_type").unwrap();
    assert_eq!(row["full_checker_parity"], false);
    assert_eq!(row["diagnostics"].as_array().unwrap().len(), 1);
    assert_eq!(row["diagnostics"][0]["severity"], "warning");
    assert_eq!(
        row["diagnostics"][0]["message"],
        "field access requires static type: \"field\""
    );
    assert_eq!(
        row["diagnostics"][0]["notes"],
        serde_json::json!(["1:14: add a return type annotation to /proc/untyped"])
    );
}

#[test]
fn field_static_real_tag_override_and_disabled_family_preserve_protocol() {
    let source = "/proc/untyped()\n    return null\n/proc/probe()\n    untyped().field\n";
    let raised = semantic_snapshot(
        source,
        Some(b"[diagnostics]\nfield_access_static_type='error'\n"),
    );
    let row = semantic_row(&raised, 1, "field_access_static_type").unwrap();
    assert_eq!(row["diagnostics"][0]["severity"], "error");
    let disabled = semantic_snapshot(
        source,
        Some(b"[diagnostics]\nfield_access_static_type='off'\n"),
    );
    assert!(
        semantic_row(&disabled, 1, "field_access_static_type").unwrap()["diagnostics"]
            .as_array()
            .unwrap()
            .is_empty()
    );
    assert!(semantic_row(&snapshot(None), 0, "field_access_static_type").is_err());
}

#[test]
fn configured_checker_original_byte_positions_survive_retained_host() {
    let snapshot = semantic_snapshot("/proc/probe(a,b)\n\tlist(\"é漢\"); !a & b\n", None);
    let row = semantic_row(&snapshot, 0, "ambiguous_not_bitwise").unwrap();
    let rows = row["diagnostics"].as_array().unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["line"], 2);
    let offset = rows[0]["expanded_span"][0].as_u64().unwrap() as usize;
    let origin = snapshot
        .body_archive
        .as_ref()
        .unwrap()
        .original_note_origin(offset)
        .unwrap();
    assert_eq!((origin.line, origin.byte_column), (2, 17));
}
#[test]
fn configured_checker_simple_macro_uses_exact_pinned_invocation_byte_points() {
    // Actual pinned checker: warnings at 3:2 and 4:2, each with these three notes.
    let snapshot = semantic_snapshot(
        "#define MASK !a & b\n/proc/probe(a,b)\n\t!a & b\n\tMASK\n",
        None,
    );
    let row = semantic_row(&snapshot, 0, "ambiguous_not_bitwise").unwrap();
    let rows = row["diagnostics"].as_array().unwrap();
    assert_eq!(rows.len(), 2);
    for (diagnostic, line) in rows.iter().zip([3, 4]) {
        assert_eq!(diagnostic["severity"], "warning");
        assert_eq!(diagnostic["line"], line);
        assert_eq!(
            diagnostic["message"],
            "Ambiguous `!` on left side of bitwise `&` operator"
        );
        assert_eq!(
            diagnostic["notes"],
            serde_json::json!([
                "Did you mean `!(x & y)`?",
                "Did you mean `!x && y`?",
                "Did you mean `~x & y`?"
            ])
        );
        let point = snapshot
            .body_archive
            .as_ref()
            .unwrap()
            .source_note_point(diagnostic["expanded_span"][0].as_u64().unwrap() as usize)
            .unwrap();
        assert_eq!((point.line, point.byte_column), (line as usize, 2));
    }
}
#[test]
fn configured_checker_unproved_later_macro_position_writes_no_partial_row() {
    // Original primary byte-layout tests explicitly withhold receipts for
    // joined physical macro lines and expanded string interpolation. Pinned
    // checker actually reports both cases at 3:2 and 4:2; neither is a parse gap.
    let cases = [
        "#define MASK !a & b\n/proc/probe(a,b)\n\t!a & b\n\tMASK \\\n\t\t\n",
        "#define MASK !a & b\n/proc/probe(a,b)\n\t!a & b\n\t\"[MASK]\"\n",
    ];
    for source in cases {
        let snapshot = semantic_snapshot(source, None);
        let archive = snapshot.body_archive.as_ref().unwrap();
        let body = archive.parse(0).unwrap();
        let candidates = dm_analysis::checks::archived_ambiguous_not_bitwise(
            &body,
            dm_analysis::checks::Severity::Warning,
        )
        .unwrap();
        assert_eq!(
            candidates.len(),
            2,
            "fixture must reach two real checker findings"
        );
        let first = archive.source_note_point(candidates[0].span.start).unwrap();
        assert_eq!((first.line, first.byte_column), (3, 2));
        assert!(
            archive.source_note_point(candidates[1].span.start).is_err(),
            "unissued transformed point unexpectedly acquired authority"
        );
        let mut bytes = Vec::new();
        let error = snapshot
            .write_native_configured_checker(
                0,
                "ambiguous_not_bitwise",
                &root().join("project.dme"),
                None,
                &snapshot.tree,
                &mut bytes,
            )
            .unwrap_err();
        assert!(
            error.to_string().contains("macro") || error.to_string().contains("original"),
            "{error}"
        );
        assert!(
            bytes.is_empty(),
            "earlier warning escaped a later unissued original position"
        );
    }
}

#[test]
fn implicit_new_real_tag_default_override_disabled_and_suppressed_arguments() {
    let source = "/proc/p()\n    new(hidden_missing())\n";
    let default = semantic_snapshot(source, None);
    let row = semantic_row(&default, 0, "no_typehint_implicit_new").unwrap();
    assert_eq!(row["diagnostics"].as_array().unwrap().len(), 1);
    assert_eq!(
        row["diagnostics"][0]["message"],
        "no type hint available on implicit new()"
    );
    assert_eq!(row["diagnostics"][0]["severity"], "error");
    assert_eq!(row["diagnostics"][0]["notes"], serde_json::json!([]));
    assert!(
        semantic_row(&default, 0, "undefined_proc").unwrap()["diagnostics"]
            .as_array()
            .unwrap()
            .is_empty()
    );
    let raised = semantic_snapshot(
        source,
        Some(b"[diagnostics]\nno_typehint_implicit_new='warning'\n"),
    );
    assert_eq!(
        semantic_row(&raised, 0, "no_typehint_implicit_new").unwrap()["diagnostics"][0]["severity"],
        "warning"
    );
    let disabled = semantic_snapshot(
        source,
        Some(b"[diagnostics]\nno_typehint_implicit_new='off'\n"),
    );
    assert!(
        semantic_row(&disabled, 0, "no_typehint_implicit_new").unwrap()["diagnostics"]
            .as_array()
            .unwrap()
            .is_empty()
    );
}
#[test]
fn implicit_new_static_local_source_matches_exact_pinned_diagnostic() {
    let snapshot = semantic_snapshot("/proc/p()\n    new()\n    var/static/datum/kept\n", None);
    let row = semantic_row(&snapshot, 0, "no_typehint_implicit_new").unwrap();
    let rows = row["diagnostics"].as_array().unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["severity"], "error");
    assert_eq!(
        rows[0]["message"],
        "no type hint available on implicit new()"
    );
    assert_eq!(rows[0]["line"], 2);
    assert_eq!(rows[0]["notes"], serde_json::json!([]));
    let point = snapshot
        .body_archive
        .as_ref()
        .unwrap()
        .original_note_origin(rows[0]["expanded_span"][0].as_u64().unwrap() as usize)
        .unwrap();
    assert_eq!((point.line, point.byte_column), (2, 5));
}
#[test]
fn implicit_new_unsupported_later_context_does_not_emit_partial_row() {
    let supported = semantic_snapshot(
        "/proc/p()\n    new()\n    var/static/datum/kept\n    var/datum/typed[1]\n",
        None,
    );
    let row = semantic_row(&supported, 0, "no_typehint_implicit_new").unwrap();
    let diagnostics = row["diagnostics"].as_array().unwrap();
    assert_eq!(diagnostics.len(), 1);
    assert_eq!(
        diagnostics[0]["message"],
        "no type hint available on implicit new()"
    );
    assert_eq!(diagnostics[0]["line"], 2);
    let snapshot = semantic_snapshot(
        "/proc/p()\n    new()\n    var/static/datum/kept\n    for(var/datum/item[1] in list())\n        return\n", None,
    );
    let mut bytes = Vec::new();
    let error = snapshot
        .write_native_configured_checker(
            0,
            "no_typehint_implicit_new",
            &root().join("project.dme"),
            None,
            &snapshot.tree,
            &mut bytes,
        )
        .unwrap_err();
    assert!(
        error
            .to_string()
            .contains("nonempty array initializer is not an old for-in/all binding"),
        "{error}"
    );
    assert!(
        bytes.is_empty(),
        "earlier implicit-new error escaped genuinely unissued for-binding context"
    );
}

#[test]
fn proc_static_seed_matches_exact_independent_notes_bytes_order_and_argument_suppression() {
    let source = include_str!("../../../fixtures/unified_checks/proc_static/probe.dm");
    let snapshot = semantic_snapshot(source, None);
    let row = semantic_row(&snapshot, 2, "proc_call_static_type").unwrap();
    let rows = row["diagnostics"].as_array().unwrap();
    let expected = [
        (7, 9),
        (8, 8),
        (9, 16),
        (10, 16),
        (11, 12),
        (12, 9),
        (12, 18),
    ];
    assert_eq!(rows.len(), expected.len());
    let archive = snapshot.body_archive.as_ref().unwrap();
    for (index, (actual, (line, column))) in rows.iter().zip(expected).enumerate() {
        assert_eq!(actual["severity"], "warning");
        assert_eq!(
            actual["message"],
            if index == 6 {
                "proc call requires static type: \"again\""
            } else {
                "proc call requires static type: \"invoke\""
            }
        );
        let offset = actual["expanded_span"][0].as_u64().unwrap() as usize;
        let origin = archive.original_note_origin(offset).unwrap();
        assert_eq!((origin.line, origin.byte_column), (line, column));
    }
    assert_eq!(
        rows[0]["notes"],
        serde_json::json!(["1:12: add a return type annotation to /proc/plain"])
    );
    assert_eq!(
        rows[1]["notes"],
        serde_json::json!(["8:2: return type evaluated to None"])
    );
    for index in [2, 3, 6] {
        assert_eq!(rows[index]["notes"], serde_json::json!([]));
    }
    for index in [4, 5] {
        assert_eq!(rows[index]["notes"], rows[0]["notes"]);
    }
    assert!(
        semantic_row(&snapshot, 2, "undefined_proc").unwrap()["diagnostics"]
            .as_array()
            .unwrap()
            .is_empty()
    );
}
#[test]
fn proc_static_real_tag_override_and_disabled_are_preserved() {
    let source =
        "/proc/plain()\n    return null\n/proc/probe()\n    plain().invoke(hidden_missing())\n";
    let raised = semantic_snapshot(
        source,
        Some(b"[diagnostics]\nproc_call_static_type='error'\n"),
    );
    assert_eq!(
        semantic_row(&raised, 1, "proc_call_static_type").unwrap()["diagnostics"][0]["severity"],
        "error"
    );
    let disabled = semantic_snapshot(
        source,
        Some(b"[diagnostics]\nproc_call_static_type='off'\n"),
    );
    assert!(
        semantic_row(&disabled, 1, "proc_call_static_type").unwrap()["diagnostics"]
            .as_array()
            .unwrap()
            .is_empty()
    );
}
#[test]
fn proc_static_unknown_parameter_note_is_unsupported_not_silently_dropped() {
    let snapshot = semantic_snapshot("/proc/p(value)\n    value.invoke(hidden_missing())\n", None);
    let mut bytes = Vec::new();
    assert!(snapshot
        .write_native_configured_checker(
            0,
            "proc_call_static_type",
            &root().join("project.dme"),
            None,
            &snapshot.tree,
            &mut bytes
        )
        .is_err());
    assert!(bytes.is_empty());
}

#[test]
fn proc_static_utf8_tab_warning_and_definition_notes_are_original_bytes() {
    let snapshot = semantic_snapshot(
        include_str!("../../../fixtures/unified_checks/proc_static_bytes/probe.dm"),
        None,
    );
    let row = semantic_row(&snapshot, 2, "proc_call_static_type").unwrap();
    let rows = row["diagnostics"].as_array().unwrap();
    assert_eq!(rows.len(), 2);
    let archive = snapshot.body_archive.as_ref().unwrap();
    for (actual, expected) in rows.iter().zip([(6, 26), (7, 10)]) {
        let origin = archive
            .original_note_origin(actual["expanded_span"][0].as_u64().unwrap() as usize)
            .unwrap();
        assert_eq!((origin.line, origin.byte_column), expected);
    }
    assert_eq!(
        rows[0]["notes"],
        serde_json::json!(["1:27: add a return type annotation to /proc/unicode"])
    );
    assert_eq!(
        rows[1]["notes"],
        serde_json::json!(["3:14: add a return type annotation to /proc/tabbed"])
    );
}
#[test]
fn proc_static_inherited_override_and_explicit_null_notes_select_actual_callable() {
    let snapshot = semantic_snapshot(
        include_str!("../../../fixtures/unified_checks/proc_static_inherited/probe.dm"),
        None,
    );
    let row = semantic_row(&snapshot, 5, "proc_call_static_type").unwrap();
    let rows = row["diagnostics"].as_array().unwrap();
    assert_eq!(rows.len(), 3);
    assert_eq!(
        rows[0]["notes"],
        serde_json::json!(["1:27: add a return type annotation to /datum/base/proc/inherited"])
    );
    assert_eq!(
        rows[1]["notes"],
        serde_json::json!([
            "7:29: add a return type annotation to /datum/base/child/proc/overridden"
        ])
    );
    assert_eq!(
        rows[2]["notes"],
        serde_json::json!(["15:6: return type evaluated to None"])
    );
}
