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
fn snapshot_with_scopes(checker:Option<&[u8]>,scopes:&[u8])->SourceSnapshot{snapshot_with_source(checker,scopes,b"/datum/record\n    proc/rebuild(x,y)\n        return !x & y\n    proc/get_value()\n        return 1\n")}
fn snapshot_with_source(checker: Option<&[u8]>, scopes: &[u8],source:&[u8]) -> SourceSnapshot {
    let root = root();
    let mut files=BTreeMap::from([
        (root.join("project.dme"),source.to_vec()),
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
    let intent = PolicyInputRequest {workspace_auxiliary:Vec::new(),workspace_generators:Vec::new(),
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
    let intent = PolicyInputRequest {workspace_auxiliary:Vec::new(),workspace_generators:Vec::new(),
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

#[test]
fn configured_checker_actual_kind4_operational_cause_precedes_output_and_same_input_recovers(){
    let snapshot=snapshot(None);let db=snapshot.native_raw_queries.as_ref().unwrap();
    db.db().evict_values(&[dm_query::Kind(4)]);let before=db.db().stats(dm_query::Kind(4)).computed;
    let schedule=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));
    let mut bytes=Vec::new();let error=snapshot.write_native_configured_checker(0,"ambiguous_not_bitwise",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap_err();
    assert_eq!(error.raw_os_error(),Some(1450),"the genuine Kind4 IO cause must not become a source diagnostic string");
    assert!(bytes.is_empty(),"body demand failed before the first configured-checker output write");assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before,"actual operational failure has no syntax Outcome");drop(schedule);
    snapshot.write_native_configured_checker(0,"ambiguous_not_bitwise",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();
    let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert_eq!(row["row"],"source_native_configured_checker");assert_eq!(row["diagnostics"].as_array().unwrap().len(),1);assert_eq!(row["diagnostics"][0]["message"],"Ambiguous `!` on left side of bitwise `&` operator");
    let computed=db.db().stats(dm_query::Kind(4)).computed;assert_eq!(computed,before+1);let mut warm=Vec::new();snapshot.write_native_configured_checker(0,"ambiguous_not_bitwise",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,computed);
}
#[test]
fn configured_checker_actual_cancellation_has_no_output_and_preserves_warm_syntax_for_retry(){
    let snapshot=snapshot(None);let db=snapshot.native_raw_queries.as_ref().unwrap();let mut expected=Vec::new();snapshot.write_native_configured_checker(0,"ambiguous_not_bitwise",&root().join("project.dme"),None,&snapshot.tree,&mut expected).unwrap();let computed=db.db().stats(dm_query::Kind(4)).computed;
    let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(300));token.cancel();
    let mut bytes=Vec::new();let error=snapshot.write_native_configured_checker(0,"ambiguous_not_bitwise",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::Interrupted);assert!(bytes.is_empty());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,computed);drop(binding);
    snapshot.write_native_configured_checker(0,"ambiguous_not_bitwise",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();assert_eq!(bytes,expected);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,computed);
}

#[test]fn configured_unknown_linter_setting_uses_real_tag_original_statement_order_and_same_warm_body(){let snapshot=snapshot_with_checker_source(Some(b"[diagnostics]\nunknown_linter_setting='hint'\n"),b"",include_bytes!("../../../fixtures/unified_checks/unknown_linter_setting/probe.dme"));let db=snapshot.native_raw_queries.as_ref().unwrap();let mut bytes=Vec::new();snapshot.write_native_configured_checker(0,"unknown_linter_setting",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let found=row["diagnostics"].as_array().unwrap();assert_eq!(found.len(),2);assert!(found.iter().all(|d|d["severity"]=="hint"&&d["family"]=="unknown_linter_setting"&&d["message"]=="unknown linter setting \"SpacemanDMM_typo\""));assert_eq!(found[0]["line"],2);assert_eq!(found[1]["line"],3);let computed=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(0,"unknown_linter_setting",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,computed);let disabled=snapshot_with_checker_source(Some(b"[diagnostics]\nunknown_linter_setting='off'\n"),b"",include_bytes!("../../../fixtures/unified_checks/unknown_linter_setting/probe.dme"));let mut no_rows=Vec::new();disabled.write_native_configured_checker(0,"unknown_linter_setting",&root().join("project.dme"),None,&disabled.tree,&mut no_rows).unwrap();assert!(serde_json::from_slice::<serde_json::Value>(&no_rows).unwrap()["diagnostics"].as_array().unwrap().is_empty());assert_eq!(disabled.native_raw_queries.as_ref().unwrap().db().stats(dm_query::Kind(4)).computed,0);}
#[test]fn configured_unknown_linter_setting_actual_kind4_io_cancel_and_dispatch_validation_never_return_partial_reply(){use crate::daemon::query::{self,SourceQuery};let snapshot=snapshot_with_checker_source(None,b"",include_bytes!("../../../fixtures/unified_checks/unknown_linter_setting/probe.dme"));let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let request=query::QueryRequest{timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal:0,family:"unknown_linter_setting".into(),environment:root().join("project.dme"),configuration:None}]};request.validate().unwrap();let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().raw_os_error(),Some(1450));drop(failure);let healthy=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&healthy).unwrap();let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().kind(),io::ErrorKind::Interrupted);drop(guard);assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,healthy.jsonl);}

#[test]fn configured_unknown_setting_is_untagged_warning_even_when_observation_key_is_disabled_or_hint(){for config in [b"[diagnostics]\nunknown_setting='off'\n".as_slice(),b"[diagnostics]\nunknown_setting='hint'\n".as_slice()]{let snapshot=snapshot_with_checker_source(Some(config),b"",include_bytes!("../../../fixtures/unified_checks/unknown_setting/probe.dme"));let db=snapshot.native_raw_queries.as_ref().unwrap();let mut bytes=Vec::new();snapshot.write_native_configured_checker(0,"unknown_setting",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let found=row["diagnostics"].as_array().unwrap();assert_eq!(found.len(),2);assert!(found.iter().all(|d|d["severity"]=="warning"&&d["family"]=="unknown_setting"&&d["message"]=="unknown setting \"ordinary_unknown\""));assert_eq!(found[0]["line"],2);assert_eq!(found[1]["line"],3);let computed=db.db().stats(dm_query::Kind(4)).computed;assert!(computed>0);let mut warm=Vec::new();snapshot.write_native_configured_checker(0,"unknown_setting",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,computed);}}
#[test]fn configured_unknown_setting_actual_kind4_io_cancel_and_dispatch_validation_never_return_partial_reply(){use crate::daemon::query::{self,SourceQuery};let snapshot=snapshot_with_checker_source(None,b"",include_bytes!("../../../fixtures/unified_checks/unknown_setting/probe.dme"));let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let request=query::QueryRequest{timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal:0,family:"unknown_setting".into(),environment:root().join("project.dme"),configuration:None}]};request.validate().unwrap();let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().raw_os_error(),Some(1450));drop(failure);let healthy=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&healthy).unwrap();let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().kind(),io::ErrorKind::Interrupted);drop(guard);assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,healthy.jsonl);}

fn snapshot_with_checker_source(checker: Option<&[u8]>, scopes: &[u8],source:&[u8]) -> SourceSnapshot {
    snapshot_with_checker_source_seed(checker,scopes,source,None)
}
fn snapshot_with_checker_source_seed(checker:Option<&[u8]>,scopes:&[u8],source:&[u8],engine:Option<&dm_tree::frontend::EngineSeed>)->SourceSnapshot{
    let root = root();
    let mut files=BTreeMap::from([
        (root.join("project.dme"),source.to_vec()),
        (root.join("scopes.toml"), scopes.to_vec()),
    ]);
    if let Some(checker) = checker {
        files.insert(root.join("SpacemanDMM.toml"), checker.to_vec());
    }
    let inputs = RecordingInputs::new(Memory(files), 1);
    let db = Arc::new(crate::query_db::QueryDb::default());
    let executor=dm_exec::BuildExecutor::new(1).unwrap();
    let setting_host:Arc<dyn dm_tree::frontend::SettingExpressionQueries>=db.clone();
    let diagnostic=dm_tree::frontend::build_for_checker_diagnostics_with_state_checked(&root.join("project.dme"),&inputs,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine,observer:None},None,&executor,None,&setting_host).unwrap().with_body_queries(db.clone()).unwrap();
    let view=diagnostic.source_view().unwrap();
    let intent = PolicyInputRequest {workspace_auxiliary:Vec::new(),workspace_generators:Vec::new(),
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
        policy_capture::capture_diagnostic(&view, &inputs, &intent.capture_files(), &[])
            .unwrap()
            .bind_request(&intent)
            .unwrap(),
    );
    SourceSnapshot::capture_diagnostic(&view,db,captured).unwrap()
}

#[test]fn configured_directive_binding_preserves_tagged_severity_notes_and_same_warm_body(){for(family,source,count)in[("incompatible_directive",include_bytes!("../../../fixtures/unified_checks/incompatible_directive/probe.dme").as_slice(),1),("disabled_directive",include_bytes!("../../../fixtures/unified_checks/disabled_directive/probe.dme").as_slice(),1),("sets_directive_twice",include_bytes!("../../../fixtures/unified_checks/sets_directive_twice/probe.dme").as_slice(),1)]{let config=format!("[diagnostics]\n{family}='hint'\n");let snapshot=snapshot_with_source(Some(config.as_bytes()),b"",source);let db=snapshot.native_raw_queries.as_ref().unwrap();let mut bytes=Vec::new();snapshot.write_native_configured_checker(0,family,&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let found=row["diagnostics"].as_array().unwrap();assert_eq!(found.len(),count);assert!(found.iter().all(|d|d["severity"]=="hint"&&d["family"]==family));if family=="sets_directive_twice"{let notes=found[0]["notes"].as_array().unwrap();assert_eq!(notes.len(),1);assert!(notes[0].as_str().unwrap().ends_with("first definition here"));}let computed=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(0,family,&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,computed);}}
#[test]fn configured_directive_binding_actual_kind4_io_cancel_and_dispatch_never_return_partial_reply(){use crate::daemon::query::{self,SourceQuery};let snapshot=snapshot_with_source(None,b"",include_bytes!("../../../fixtures/unified_checks/sets_directive_twice/probe.dme"));let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let request=query::QueryRequest{timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal:0,family:"sets_directive_twice".into(),environment:root().join("project.dme"),configuration:None}]};request.validate().unwrap();let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().raw_os_error(),Some(1450));drop(failure);let healthy=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&healthy).unwrap();let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().kind(),io::ErrorKind::Interrupted);drop(guard);assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,healthy.jsonl);}

#[test]fn configured_invalid_directive_value_borrows_funded_complete_debug_messages_and_warm_original_body(){
 let snapshot=snapshot_with_checker_source(Some(b"[diagnostics]\ninvalid_lint_directive_value='hint'\n"),b"",include_bytes!("../../../fixtures/unified_checks/invalid_lint_directive_value/probe.dme"));let db=snapshot.native_raw_queries.as_ref().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;let mut bytes=Vec::new();snapshot.write_native_configured_checker(0,"invalid_lint_directive_value",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let diagnostics=row["diagnostics"].as_array().unwrap();assert_eq!(diagnostics.len(),10);assert!(diagnostics.iter().all(|d|d["family"]=="invalid_lint_directive_value"&&d["severity"]=="hint"&&d["notes"].as_array().unwrap().is_empty()));assert_eq!(diagnostics[0]["message"],"invalid value for set Base { term: Spanned { location: Location { file: FileId(1), line: 2, column: 42 }, elem: Int(2) }, follow: [] }");assert!(diagnostics[2]["message"].as_str().unwrap().contains("InterpString"));assert!(diagnostics[5]["message"].as_str().unwrap().contains("As((empty))"));assert!(diagnostics[6]["message"].as_str().unwrap().contains("LessOrGreater"));assert!(diagnostics[7]["message"].as_str().unwrap().contains("Reference"));assert!(diagnostics[8]["message"].as_str().unwrap().contains("GlobalIdent"));let computed=db.db().stats(dm_query::Kind(4)).computed;assert!(computed>before);let body=snapshot.body_archive.as_ref().unwrap().parse_checked(0).unwrap();let address=body.statement_body()as*const _;let mut warm=Vec::new();snapshot.write_native_configured_checker(0,"invalid_lint_directive_value",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,computed);let after=snapshot.body_archive.as_ref().unwrap().parse_checked(0).unwrap();assert_eq!(after.statement_body()as*const _,address);
 let disabled=snapshot_with_checker_source(Some(b"[diagnostics]\ninvalid_lint_directive_value='off'\n"),b"",include_bytes!("../../../fixtures/unified_checks/invalid_lint_directive_value/probe.dme"));let db=disabled.native_raw_queries.as_ref().unwrap();let baseline=db.db().stats(dm_query::Kind(4)).computed;let mut bytes=Vec::new();disabled.write_native_configured_checker(0,"invalid_lint_directive_value",&root().join("project.dme"),None,&disabled.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert!(row["diagnostics"].as_array().unwrap().is_empty());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,baseline);
}
#[test]fn configured_invalid_directive_value_actual_kind4_io_cancel_and_dispatch_preserve_no_partial_output(){
 use crate::daemon::query::{self,SourceQuery};let snapshot=snapshot_with_checker_source(None,b"",include_bytes!("../../../fixtures/unified_checks/invalid_lint_directive_value/probe.dme"));let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let request=query::QueryRequest{timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal:0,family:"invalid_lint_directive_value".into(),environment:root().join("project.dme"),configuration:None}]};request.validate().unwrap();let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));let mut output=Vec::new();let snapshot=state.snapshot.as_ref().unwrap();assert_eq!(snapshot.write_native_configured_checker(0,"invalid_lint_directive_value",&root().join("project.dme"),None,&tree,&mut output).err().unwrap().raw_os_error(),Some(1450));assert!(output.is_empty());drop(failure);let healthy=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&healthy).unwrap();let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().kind(),io::ErrorKind::Interrupted);drop(guard);assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,healthy.jsonl);
}

#[test]fn configured_invalid_directive_value_foreign_frame_refuses_before_root_and_actual_same_budget_quota_recovers(){
 let source=include_bytes!("../../../fixtures/unified_checks/invalid_lint_directive_value/probe.dme");let snapshot=snapshot_with_checker_source(None,b"",source);let foreign=snapshot_with_checker_source(None,b"",source);let db=snapshot.native_raw_queries.as_ref().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;let mut rejected=Vec::new();assert!(snapshot.write_native_configured_checker(0,"invalid_lint_directive_value",&root().join("project.dme"),None,&foreign.tree,&mut rejected).is_err());assert!(rejected.is_empty());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);
 let mut healthy=Vec::new();snapshot.write_native_configured_checker(0,"invalid_lint_directive_value",&root().join("project.dme"),None,&snapshot.tree,&mut healthy).unwrap();let counter=crate::query_db::body_syntax_counter_for_test(db);let limit=crate::query_db::body_syntax_budget_for_test();let used=counter.load(std::sync::atomic::Ordering::Acquire);let held=dm_syntax::SettingRootLease::reserve(counter,limit,limit.checked_sub(used).unwrap()).unwrap();let mut denied=Vec::new();let error=snapshot.write_native_configured_checker(0,"invalid_lint_directive_value",&root().join("project.dme"),None,&snapshot.tree,&mut denied).err().unwrap();assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);assert!(denied.is_empty());drop(held);let mut recovered=Vec::new();snapshot.write_native_configured_checker(0,"invalid_lint_directive_value",&root().join("project.dme"),None,&snapshot.tree,&mut recovered).unwrap();assert_eq!(recovered,healthy);
}

#[test]fn diagnostic_invalid_directive_role_accepts_only_registered_original_syntax_question_and_rejects_mixed_semantics_before_demand(){
 use crate::daemon::query::{self,SourceQuery};let snapshot=snapshot_with_checker_source(None,b"",include_bytes!("../../../fixtures/unified_checks/invalid_lint_directive_value/probe.dme"));let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let mut request=query::QueryRequest{timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal:0,family:"invalid_lint_directive_value".into(),environment:root().join("project.dme"),configuration:None}]};let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};request.validate().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;
 request.source_queries.push(SourceQuery::NativeConfiguredChecker{ordinal:0,family:"undefined_variable".into(),environment:root().join("project.dme"),configuration:None});request.validate().unwrap();let error=query::evaluate_snapshot(&request,&tree,&state).err().expect("diagnostic role must not become an ordinary semantic checker frame");assert!(error.to_string().contains("no ordinary ABI/model query"));assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before,"entire mixed request is refused before source/body demand");request.source_queries.pop();let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();assert_eq!(row["family"],"invalid_lint_directive_value");assert_eq!(row["diagnostics"].as_array().unwrap().len(),10);assert_eq!(row["full_checker_parity"],false);
}

#[test]fn configured_invalid_directive_value_keeps_original_escape_syntax_when_native_runtime_refuses(){
 let source=br#"/datum/debug_escape/proc/probe()
    set SpacemanDMM_should_call_parent = "a\q"
    set SpacemanDMM_should_call_parent = "a\q[value + 1]tail"
    set SpacemanDMM_should_call_parent = 1.#IND
    return 0
"#;
 let snapshot=snapshot_with_checker_source(None,b"",source);let db=snapshot.native_raw_queries.as_ref().unwrap();let mut bytes=Vec::new();snapshot.write_native_configured_checker(0,"invalid_lint_directive_value",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let diagnostics=row["diagnostics"].as_array().unwrap();assert_eq!(diagnostics.len(),3);assert_eq!(diagnostics[0]["message"],r#"invalid value for set Base { term: Spanned { location: Location { file: FileId(1), line: 2, column: 42 }, elem: String("a\\q") }, follow: [] }"#,"whole pinned Term::String Debug must quote its retained lexical backslash");assert!(diagnostics[1]["message"].as_str().unwrap().contains("InterpString"));assert!(diagnostics[2]["message"].as_str().unwrap().contains("Float(NaN)"));let body=snapshot.body_archive.as_ref().unwrap().parse_checked(0).unwrap();assert!(!body.statement_body().syntax_complete(),"native runtime decoding remains explicitly refused");assert!(body.statement_body().original_literal_syntax_complete(),"the same prepared primary children remain available to the original checker");let computed=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(0,"invalid_lint_directive_value",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,computed);
}

#[test]fn configured_directive_definition_gate_is_untagged_warning_even_with_a_fake_disabled_observation_key(){
 let source=include_bytes!("../../../fixtures/unified_checks/directive_at_definition/probe.dme");let snapshot=snapshot_with_checker_source(Some(b"[diagnostics]\ndirective_at_definition='off'\n"),b"",source);let db=snapshot.native_raw_queries.as_ref().unwrap();let mut bytes=Vec::new();snapshot.write_native_configured_checker(1,"directive_at_definition",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let rows=row["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),2);assert_eq!(rows[0]["message"],"Can't define procs SpacemanDMM_private_proc outside their initial definition");assert_eq!(rows[0]["line"],5);assert_eq!(rows[1]["line"],6);assert!(rows.iter().all(|d|d["family"]=="directive_at_definition"&&d["severity"]=="warning"&&d["notes"].as_array().unwrap().is_empty()));let count=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(1,"directive_at_definition",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,count);
}
#[test]fn configured_directive_definition_gate_actual_io_and_cancel_preserve_no_partial_output_and_dispatch(){
 use crate::daemon::query::{self,SourceQuery};let snapshot=snapshot_with_checker_source(None,b"",include_bytes!("../../../fixtures/unified_checks/directive_at_definition/probe.dme"));let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let request=query::QueryRequest{timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal:1,family:"directive_at_definition".into(),environment:root().join("project.dme"),configuration:None}]};request.validate().unwrap();let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));let mut bytes=Vec::new();assert_eq!(state.snapshot.as_ref().unwrap().write_native_configured_checker(1,"directive_at_definition",&root().join("project.dme"),None,&tree,&mut bytes).err().unwrap().raw_os_error(),Some(1450));assert!(bytes.is_empty());drop(failure);let good=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&good).unwrap();let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().kind(),io::ErrorKind::Interrupted);drop(binding);assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,good.jsonl);
}

#[test]fn diagnostic_at_definition_role_accepts_only_its_registered_header_question_and_refuses_mixed_semantics_before_demand(){
 use crate::daemon::query::{self,SourceQuery};let snapshot=snapshot_with_checker_source(None,b"",include_bytes!("../../../fixtures/unified_checks/directive_at_definition/probe.dme"));let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let mut request=query::QueryRequest{timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal:1,family:"directive_at_definition".into(),environment:root().join("project.dme"),configuration:None}]};let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};request.validate().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;
 request.source_queries.push(SourceQuery::NativeConfiguredChecker{ordinal:1,family:"undefined_variable".into(),environment:root().join("project.dme"),configuration:None});request.validate().unwrap();let error=query::evaluate_snapshot(&request,&tree,&state).err().expect("diagnostic role must not become an ordinary semantic checker frame");assert!(error.to_string().contains("no ordinary ABI/model query"));assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before,"entire mixed request is refused before source/body demand");request.source_queries.pop();let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();assert_eq!(row["family"],"directive_at_definition");assert_eq!(row["diagnostics"].as_array().unwrap().len(),2);assert_eq!(row["full_checker_parity"],false);
}

const PROC_VISIBILITY_SOURCE:&str="/datum/access\n    proc/secret(value)\n        set SpacemanDMM_private_proc = TRUE\n        return value\n    proc/guarded(value)\n        set SpacemanDMM_protected_proc = TRUE\n        return value\n/datum/access/child\n/datum/unrelated/proc/probe(datum/access/exact, datum/access/child/derived)\n    exact.secret(derived.secret(1))\n    derived.secret(exact.secret(1))\n    exact.guarded(exact.secret(1))\n";
fn visibility_ordinal(snapshot:&SourceSnapshot,owner:&str,name:&str)->u32{snapshot.body_archive.as_ref().unwrap().occurrences().iter().position(|body|{let node=snapshot.tree.member(body.member).unwrap();snapshot.tree.type_node(node.owner).unwrap().path==dm_ir::SymbolId::of(owner)&&node.name==dm_ir::SymbolId::of(name)}).unwrap()as u32}
#[test]fn configured_procedure_visibility_keeps_static_receiver_abort_caller_check_and_argument_order(){
 let snapshot=semantic_snapshot_primary(PROC_VISIBILITY_SOURCE,Some(b"[diagnostics]\nprivate_proc='hint'\nprotected_proc='info'\n"),true);let ordinal=visibility_ordinal(&snapshot,"/datum/unrelated","probe");let db=snapshot.native_raw_queries.as_ref().unwrap();let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,"private_proc",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let value:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let rows=value["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),4,"outer lexical caller check then nested static refusal; second static refusal skips nested argument; final protected call still evaluates private argument");assert!(rows.iter().all(|row|row["severity"]=="hint"&&row["notes"].as_array().unwrap().len()==1));assert_eq!(rows.iter().map(|row|row["line"].as_u64().unwrap()).collect::<Vec<_>>(),[10,10,11,12]);let count=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"private_proc",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,count);
 let mut protected=Vec::new();snapshot.write_native_configured_checker(ordinal,"protected_proc",&root().join("project.dme"),None,&snapshot.tree,&mut protected).unwrap();let value:serde_json::Value=serde_json::from_slice(&protected).unwrap();let rows=value["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),1);assert_eq!(rows[0]["line"],12);assert_eq!(rows[0]["severity"],"info");assert!(rows[0]["message"].as_str().unwrap().contains("attempting to call protected proc /datum/access/proc/guarded"));assert_eq!(value["full_checker_parity"],false);
}
#[test]fn configured_procedure_visibility_disabled_foreign_edited_and_actual_body_io_cancel_have_no_partial_output(){
 for family in ["private_proc","protected_proc"]{let disabled=semantic_snapshot_primary(PROC_VISIBILITY_SOURCE,Some(b"[diagnostics]\nprivate_proc='off'\nprotected_proc='off'\n"),true);let ordinal=visibility_ordinal(&disabled,"/datum/unrelated","probe");let db=disabled.native_raw_queries.as_ref().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;let mut output=Vec::new();disabled.write_native_configured_checker(ordinal,family,&root().join("project.dme"),None,&disabled.tree,&mut output).unwrap();assert!(serde_json::from_slice::<serde_json::Value>(&output).unwrap()["diagnostics"].as_array().unwrap().is_empty());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);}
 let snapshot=semantic_snapshot_primary(PROC_VISIBILITY_SOURCE,None,true);let ordinal=visibility_ordinal(&snapshot,"/datum/unrelated","probe");let foreign=semantic_snapshot_primary(PROC_VISIBILITY_SOURCE,None,true);let db=snapshot.native_raw_queries.as_ref().unwrap();let mut output=Vec::new();assert!(snapshot.write_native_configured_checker(ordinal,"private_proc",&root().join("project.dme"),None,&foreign.tree,&mut output).is_err());assert!(output.is_empty());let caller=snapshot.body_archive.as_ref().unwrap().parse_checked(ordinal as usize).unwrap();drop(caller);let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));assert_eq!(snapshot.write_native_configured_checker(ordinal,"private_proc",&root().join("project.dme"),None,&snapshot.tree,&mut output).unwrap_err().raw_os_error(),Some(1450));assert!(output.is_empty());drop(failure);snapshot.write_native_configured_checker(ordinal,"private_proc",&root().join("project.dme"),None,&snapshot.tree,&mut output).unwrap();assert!(!output.is_empty());let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();let mut denied=Vec::new();assert_eq!(snapshot.write_native_configured_checker(ordinal,"private_proc",&root().join("project.dme"),None,&snapshot.tree,&mut denied).unwrap_err().kind(),io::ErrorKind::Interrupted);assert!(denied.is_empty());drop(guard);
 let changed=PROC_VISIBILITY_SOURCE.replace("set SpacemanDMM_private_proc = TRUE","set SpacemanDMM_private_proc = FALSE");let edited=semantic_snapshot_primary(&changed,None,true);let ordinal=visibility_ordinal(&edited,"/datum/unrelated","probe");let mut bytes=Vec::new();edited.write_native_configured_checker(ordinal,"private_proc",&root().join("project.dme"),None,&edited.tree,&mut bytes).unwrap();assert!(serde_json::from_slice::<serde_json::Value>(&bytes).unwrap()["diagnostics"].as_array().unwrap().is_empty(),"disabled directive insertion must not turn into a private annotation");
}

#[test]fn private_proc_parent_call_and_end_of_body_override_use_the_actual_parent_occurrence(){
 let source="/datum/access/proc/secret(value)\n    set SpacemanDMM_private_proc = TRUE\n    return value\n/datum/access/child/secret(value)\n    return ..(value)\n";let snapshot=procedure_diagnostic_snapshot(source,None);let ordinal=visibility_ordinal(&snapshot,"/datum/access/child","secret");let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,"private_proc",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let value:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let rows=value["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),2);assert!(rows[0]["message"].as_str().unwrap().contains("attempting to call private proc /datum/access/proc/secret"));assert_eq!(rows[0]["line"],5);assert_eq!(rows[1]["message"],"proc overrides private parent, prohibited by /datum/access/proc/secret");assert_eq!(rows[1]["line"],4);assert!(rows.iter().all(|row|row["notes"][0].as_str().unwrap().contains("prohibited by this private_proc annotation")));
}

#[test]fn private_proc_suffix_constructor_reports_the_actual_parser_synthetic_point_and_strict_reply_kind(){
 use crate::daemon::query::{self,SourceQuery};let source="/list/proc/New(size)\n    set SpacemanDMM_private_proc = TRUE\n/proc/probe()\n    var/list/items[2]\n";let snapshot=procedure_diagnostic_snapshot(source,None);assert!(snapshot.resolved.is_none(),"source diagnostic question must not fabricate an ABI EngineHost");let ordinal=visibility_ordinal(&snapshot,"/","probe");let tree=snapshot.tree.clone();let request=query::QueryRequest{timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal,family:"private_proc".into(),environment:root().join("project.dme"),configuration:None}]};request.validate().unwrap();let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();let diagnostics=row["diagnostics"].as_array().unwrap();assert_eq!(diagnostics.len(),1);let d=&diagnostics[0];assert_eq!(d["location_kind"],"parser_synthetic");assert_eq!(d["file"],"(unknown)");assert_eq!(d["line"],0);assert_eq!(d["column"],0);assert!(d["expanded_span"].is_null()&&d["expression_span"].is_null());assert!(d["notes"][0].as_str().unwrap().contains(":2:5: prohibited by this private_proc annotation"));let mut invalid=reply.clone();let mut value=row;value["diagnostics"][0]["location_kind"]="source".into();invalid.jsonl=format!("{value}\n");assert!(query::validate_effect_batch_for_test(&request,&invalid).is_err(),"zero synthetic point cannot be relabeled as a source location");
}

#[test]fn source_private_annotation_on_an_inherited_builtin_formal_is_rejected_at_definition_before_value(){
 let source="/mob/Login()\n    set SpacemanDMM_private_proc = TRUE\n    return 0\n/datum/unrelated/proc/probe(mob/target)\n    target.Login()\n";let snapshot=semantic_snapshot_primary(source,None,true);let ordinal=visibility_ordinal(&snapshot,"/datum/unrelated","probe");let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,"private_proc",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();assert!(serde_json::from_slice::<serde_json::Value>(&bytes).unwrap()["diagnostics"].as_array().unwrap().is_empty(),"actual builtin declaration at FileId0 cannot equal an authored source header");
}

#[test]fn procedure_visibility_visits_prepared_lexical_interpolation_children_while_runtime_text_stays_refused(){
 let source=PROC_VISIBILITY_SOURCE.replace("exact.guarded(exact.secret(1))",r#""a\q[exact.secret(1)]""#);let snapshot=semantic_snapshot_primary(&source,None,true);let ordinal=visibility_ordinal(&snapshot,"/datum/unrelated","probe");let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,"private_proc",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let rows=serde_json::from_slice::<serde_json::Value>(&bytes).unwrap();assert_eq!(rows["diagnostics"].as_array().unwrap().len(),4);let body=snapshot.body_archive.as_ref().unwrap().parse_checked(ordinal as usize).unwrap();assert!(!body.statement_body().syntax_complete());assert!(dm_analysis::checker_reachable::archived(&body).is_err(),"ordinary runtime-ready traversal remains strict");assert!(body.statement_body().original_literal_syntax_complete());
}

#[test]fn private_child_own_accepted_annotation_masks_parent_override_finding_like_the_pinned_lookup(){
 let source="/datum/access/proc/secret()\n    set SpacemanDMM_private_proc = TRUE\n    return 0\n/datum/access/child/proc/secret()\n    set SpacemanDMM_private_proc = TRUE\n    return 0\n";let snapshot=procedure_diagnostic_snapshot(source,None);let ordinal=visibility_ordinal(&snapshot,"/datum/access/child","secret");let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,"private_proc",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let value:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert!(value["diagnostics"].as_array().unwrap().is_empty(),"original end rule queries get_self_or_parent(current), so an accepted current annotation stops inheritance");
}

fn procedure_diagnostic_snapshot(source:&str,checker:Option<&[u8]>)->SourceSnapshot{let mut host=crate::runner_host::BuildHost::one_shot();let engine=host.engine(root().join("project.dme"),Default::default(),true,include_bytes!("../../../fixtures/native_template.bin").to_vec()).unwrap();snapshot_with_checker_source_seed(checker,b"",source.as_bytes(),Some(engine.frontend_seed()))}

#[test]fn procedure_diagnostic_source_role_never_promotes_to_ordinary_semantics_and_keeps_actual_io(){
 use crate::daemon::query::{self,SourceQuery};let source="/datum/access/proc/secret()\n    set SpacemanDMM_private_proc = TRUE\n    return 0\n/datum/access/child/proc/secret()\n    set SpacemanDMM_private_proc = TRUE\n    return 0\n";
 let snapshot=procedure_diagnostic_snapshot(&source,None);assert!(snapshot.resolved.is_none());let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let ordinal=visibility_ordinal(&snapshot,"/datum/access/child","secret");let mut request=query::QueryRequest{timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal,family:"private_proc".into(),environment:root().join("project.dme"),configuration:None}]};
 let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let before=db.db().stats(dm_query::Kind(4)).computed;request.source_queries.push(SourceQuery::NativeConfiguredChecker{ordinal,family:"undefined_variable".into(),environment:root().join("project.dme"),configuration:None});assert!(query::evaluate_snapshot(&request,&tree,&state).is_err());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);request.source_queries.pop();let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().raw_os_error(),Some(1450));drop(failure);let good=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&good).unwrap();let row:serde_json::Value=serde_json::from_str(good.jsonl.lines().next().unwrap()).unwrap();assert_eq!(row["declaration_profile"],"native-diagnostic-source-declarations-v2");assert_eq!(row["native_declaration_error_count"],1);assert!(row["diagnostics"].as_array().unwrap().is_empty());let warm=db.db().stats(dm_query::Kind(4)).computed;assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,good.jsonl);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,warm);
 let mut wrong=good;let mut forged=row;forged["native_declaration_error_count"]=serde_json::json!(0);wrong.jsonl=serde_json::to_string(&forged).unwrap()+"\n";assert!(query::validate_effect_batch_for_test(&request,&wrong).is_err(),"v2 requires an actual inherited procedure declaration error");
}

#[test]fn diagnostic_unknown_setting_frame_variable_visibility_reply_keeps_its_actual_zero_error_profile(){
 use crate::daemon::query::{self,SourceQuery};let snapshot=procedure_diagnostic_snapshot("/datum/probe/proc/run()\n    set ordinary_unknown = 1\n    return 0\n",None);assert!(snapshot.resolved.is_none());let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let request=query::QueryRequest{timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredVariableVisibility{environment:root().join("project.dme"),configuration:None}]};let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let good=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&good).unwrap();let row:serde_json::Value=serde_json::from_str(good.jsonl.trim()).unwrap();assert_eq!(row["declaration_profile"],"native-diagnostic-inherited-variable-v1");assert_eq!(row["native_declaration_error_count"],0);let before=db.db().stats(dm_query::Kind(4)).computed;assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,good.jsonl);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);
}

#[test]fn inherited_parent_directives_use_actual_evaluated_parent_calls_and_accepted_false_state(){
 let source="/datum/required/proc/run()\n    set SpacemanDMM_should_call_parent = TRUE\n    return 0\n/datum/required/missing/run()\n    return 0\n/datum/required/calls/run()\n    return ..()\n/datum/required/disabled/run()\n    set SpacemanDMM_should_call_parent = FALSE\n    return 0\n/datum/required/own/proc/run()\n    set SpacemanDMM_should_call_parent = TRUE\n    return 0\n";let snapshot=procedure_diagnostic_snapshot(source,None);
 for(owner,count)in[("/datum/required",1),("/datum/required/missing",1),("/datum/required/calls",0),("/datum/required/disabled",0),("/datum/required/own",1)]{let ordinal=visibility_ordinal(&snapshot,owner,"run");let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,"must_call_parent",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert_eq!(row["diagnostics"].as_array().unwrap().len(),count,"{owner}");if count==1{assert!(row["diagnostics"][0]["message"].as_str().unwrap().starts_with("proc never calls parent, required by "));assert!(row["diagnostics"][0]["notes"][0].as_str().unwrap().ends_with("required by this must_call_parent annotation"));}}
}
#[test]fn private_static_receiver_refusal_prevents_hidden_parent_call_from_satisfying_requirement(){
 let source="/datum/access/proc/secret(x)\n    set SpacemanDMM_private_proc = TRUE\n    return x\n/datum/access/child\n/datum/required/proc/run()\n    set SpacemanDMM_should_call_parent = TRUE\n    return 0\n/datum/required/child/run(datum/access/child/receiver)\n    receiver.secret(..())\n";let snapshot=procedure_diagnostic_snapshot(source,None);let ordinal=visibility_ordinal(&snapshot,"/datum/required/child","run");let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,"must_call_parent",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert_eq!(row["diagnostics"].as_array().unwrap().len(),1,"the original private static receiver check aborts before arguments, so hidden ..() is never visited");
}
#[test]fn must_not_override_inherits_actual_final_seed_but_current_accepted_annotation_masks_parent(){
 let source="/datum/base/proc/final/locked()\n    return 0\n/datum/base/child/locked()\n    return 0\n/datum/declared/proc/locked()\n    set SpacemanDMM_should_not_override = TRUE\n    return 0\n/datum/declared/own/proc/locked()\n    set SpacemanDMM_should_not_override = TRUE\n    return 0\n/datum/declared/rejected/locked()\n    set SpacemanDMM_should_not_override = FALSE\n    return 0\n";let snapshot=procedure_diagnostic_snapshot(source,None);for(owner,count)in[("/datum/base",0),("/datum/base/child",1),("/datum/declared/own",0),("/datum/declared/rejected",1)]{let ordinal=visibility_ordinal(&snapshot,owner,"locked");let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,"must_not_override",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert_eq!(row["diagnostics"].as_array().unwrap().len(),count,"{owner}");if count==1{assert!(row["diagnostics"][0]["message"].as_str().unwrap().starts_with("proc overrides parent, prohibited by "));assert!(row["diagnostics"][0]["notes"][0].as_str().unwrap().ends_with("prohibited by this must_not_override annotation"));}}
}

#[test]fn inherited_directive_families_keep_configured_severity_warm_edit_foreign_and_actual_io_controls(){
 for(family,setting)in[("must_call_parent","SpacemanDMM_should_call_parent"),("must_not_override","SpacemanDMM_should_not_override")]{let source=format!("/datum/required/proc/run()\n    set {setting} = TRUE\n    return 0\n/datum/required/child/run()\n    return 0\n");let config=format!("[diagnostics]\n{family}='info'\n");let snapshot=procedure_diagnostic_snapshot(&source,Some(config.as_bytes()));let ordinal=visibility_ordinal(&snapshot,"/datum/required/child","run");let db=snapshot.native_raw_queries.as_ref().unwrap();let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));let mut partial=Vec::new();assert_eq!(snapshot.write_native_configured_checker(ordinal,family,&root().join("project.dme"),None,&snapshot.tree,&mut partial).err().unwrap().raw_os_error(),Some(1450));assert!(partial.is_empty());drop(failure);let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,family,&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let value:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert_eq!(value["diagnostics"].as_array().unwrap().len(),1);assert_eq!(value["diagnostics"][0]["severity"],"info");let before=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,family,&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);
 let edited=procedure_diagnostic_snapshot(&source.replace(&format!("    set {setting} = TRUE\n"),""),None);let mut output=Vec::new();edited.write_native_configured_checker(visibility_ordinal(&edited,"/datum/required/child","run"),family,&root().join("project.dme"),None,&edited.tree,&mut output).unwrap();let value:serde_json::Value=serde_json::from_slice(&output).unwrap();assert!(value["diagnostics"].as_array().unwrap().is_empty());let before=db.db().stats(dm_query::Kind(4)).computed;let mut foreign=Vec::new();assert!(snapshot.write_native_configured_checker(ordinal,family,&root().join("project.dme"),None,&edited.tree,&mut foreign).is_err());assert!(foreign.is_empty());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);
 let config=format!("[diagnostics]\n{family}='off'\n");let disabled=procedure_diagnostic_snapshot(&source,Some(config.as_bytes()));let ddb=disabled.native_raw_queries.as_ref().unwrap();let before=ddb.db().stats(dm_query::Kind(4)).computed;let mut output=Vec::new();disabled.write_native_configured_checker(visibility_ordinal(&disabled,"/datum/required/child","run"),family,&root().join("project.dme"),None,&disabled.tree,&mut output).unwrap();let value:serde_json::Value=serde_json::from_slice(&output).unwrap();assert!(value["diagnostics"].as_array().unwrap().is_empty());assert_eq!(ddb.db().stats(dm_query::Kind(4)).computed,before);
 let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();let mut output=Vec::new();assert_eq!(snapshot.write_native_configured_checker(ordinal,family,&root().join("project.dme"),None,&snapshot.tree,&mut output).err().unwrap().kind(),io::ErrorKind::Interrupted);assert!(output.is_empty());drop(guard);
 }
}

#[test]fn own_parent_requirement_on_a_genuine_no_parent_name_does_not_emit(){let source="/datum/required/proc/no_parent_probe()\n    set SpacemanDMM_should_call_parent = TRUE\n    return 0\n";let snapshot=procedure_diagnostic_snapshot(source,None);let ordinal=visibility_ordinal(&snapshot,"/datum/required","no_parent_probe");let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,"must_call_parent",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert!(row["diagnostics"].as_array().unwrap().is_empty(),"pinned original no_parent_probe has no global builtin parent, unlike run");}

#[test]fn recursive_original_parameter_and_suffix_local_lists_retain_each_static_element_layer(){let source="/datum/access\n    proc/secret()\n        set SpacemanDMM_private_proc = TRUE\n        return 0\n/proc/recursive_param(list/list/datum/access/values)\n    values[1][1].secret()\n/proc/recursive_local()\n    var/list/list/datum/access/records[2]\n    records[1][1][1].secret()\n";let snapshot=procedure_diagnostic_snapshot(source,None);let db=snapshot.native_raw_queries.as_ref().unwrap();for name in ["recursive_param","recursive_local"]{let ordinal=visibility_ordinal(&snapshot,"/",name);let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,"private_proc",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert_eq!(row["diagnostics"].as_array().unwrap().len(),1,"{name}: every real index must peel exactly one native-issued list layer");assert!(row["diagnostics"][0]["message"].as_str().unwrap().contains("attempting to call private proc /datum/access/proc/secret"));let before=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"private_proc",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);}}

#[test]fn redefined_procedure_hints_use_actual_same_owner_predecessor_and_accepted_redefinition_permission(){
 let source="/datum/redefinition/proc/plain()\n    return 0\n/datum/redefinition/plain()\n    return 1\n/datum/redefinition/proc/allowed()\n    set SpacemanDMM_can_be_redefined = TRUE\n    return 0\n/datum/redefinition/allowed()\n    return 1\n/datum/redefinition/proc/own()\n    return 0\n/datum/redefinition/own()\n    set SpacemanDMM_can_be_redefined = TRUE\n    return 1\n/datum/redefinition/proc/rejected()\n    return 0\n/datum/redefinition/rejected()\n    set SpacemanDMM_can_be_redefined = FALSE\n    return 1\n/datum/redefinition/child/plain()\n    return 2\n/proc/global_plain()\n    return 0\n/global_plain()\n    return 1\n";
 let snapshot=procedure_diagnostic_snapshot(source,None);let archive=snapshot.body_archive.as_ref().unwrap();let mut found=Vec::new();for ordinal in 0..archive.len(){let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal as u32,"redefined_proc",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();for d in row["diagnostics"].as_array().unwrap(){assert_eq!(d["severity"],"hint");assert_eq!(d["notes"].as_array().unwrap().len(),1);assert!(d["notes"][0].as_str().unwrap().ends_with("previous definition is here"));found.push(d["message"].as_str().unwrap().to_owned());}}
 assert_eq!(found,vec!["redefining proc /datum/redefinition/plain","redefining proc /datum/redefinition/rejected","redefining proc (global)/global_plain"]);
}

#[test]fn original_proc_redeclaration_companion_is_fixed_error_when_redefinition_is_disabled(){
 use crate::daemon::query::{self,SourceQuery};let source="/datum/redefinition/proc/plain()\n    return 0\n/datum/redefinition/proc/plain()\n    return 1\n";let snapshot=procedure_diagnostic_snapshot(source,Some(b"[diagnostics]\nredefined_proc='off'\nprocedure_redeclaration='off'\n"));assert!(snapshot.resolved.is_none());let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();assert_eq!(snapshot.body_archive.as_ref().unwrap().len(),2);let mut request=query::QueryRequest{timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal:1,family:"redefined_proc".into(),environment:root().join("project.dme"),configuration:None}]};let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let before=db.db().stats(dm_query::Kind(4)).computed;request.source_queries.push(SourceQuery::NativeConfiguredChecker{ordinal:0,family:"undefined_variable".into(),environment:root().join("project.dme"),configuration:None});assert!(query::evaluate_snapshot(&request,&tree,&state).is_err());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);request.source_queries.pop();let good=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&good).unwrap();assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before,"structural header projection must not prepare a disabled body");let row:serde_json::Value=serde_json::from_str(good.jsonl.trim()).unwrap();assert_eq!(row["declaration_profile"],"native-diagnostic-procedure-versions-v3");let d=&row["diagnostics"][0];assert_eq!(row["diagnostics"].as_array().unwrap().len(),1);assert_eq!(d["family"],"procedure_redeclaration");assert!(d["registration_tag"].is_null());assert_eq!(d["severity"],"error");assert_eq!((d["line"].as_u64(),d["column"].as_u64()),(Some(3),Some(31)));assert_eq!(d["message"],"duplicate definition of proc/plain");assert_eq!(d["notes"],serde_json::json!(["1:31: previous definition"]));
 for(key,value)in[("registration_tag",serde_json::json!("redefined_proc")),("severity",serde_json::json!("warning")),("family",serde_json::json!("native_inherited_duplicate"))]{let mut bad=good.clone();let mut data=row.clone();data["diagnostics"][0][key]=value;bad.jsonl=format!("{data}\n");assert!(query::validate_effect_batch_for_test(&request,&bad).is_err());}
 let enabled=procedure_diagnostic_snapshot(source,Some(b"[diagnostics]\nredefined_proc='warning'\n"));let mut bytes=Vec::new();enabled.write_native_configured_checker(0,"redefined_proc",&root().join("project.dme"),None,&enabled.tree,&mut bytes).unwrap();let value:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let d=&value["diagnostics"][0];assert_eq!(d["family"],"redefined_proc");assert_eq!(d["registration_tag"],"redefined_proc");assert_eq!(d["severity"],"warning");assert_eq!((d["line"].as_u64(),d["column"].as_u64()),(Some(1),Some(31)));assert_eq!(d["message"],"redefining proc /datum/redefinition/plain");assert_eq!(d["notes"],serde_json::json!(["3:31: previous definition is here"]));
}

#[test]fn redefined_source_body_actual_io_foreign_edit_and_cancel_keep_atomic_configured_rows(){
 let source="/datum/redefinition/proc/plain()\n    return 0\n/datum/redefinition/proc/plain()\n    return 1\n";let snapshot=procedure_diagnostic_snapshot(source,None);let db=snapshot.native_raw_queries.as_ref().unwrap();let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));let mut bytes=Vec::new();assert_eq!(snapshot.write_native_configured_checker(0,"redefined_proc",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).err().unwrap().raw_os_error(),Some(1450));assert!(bytes.is_empty());drop(failure);snapshot.write_native_configured_checker(0,"redefined_proc",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let value:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert_eq!(value["diagnostics"][0]["severity"],"hint");let before=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(0,"redefined_proc",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);
 let edited=procedure_diagnostic_snapshot("/datum/redefinition/proc/plain()\n    return 0\n/datum/redefinition/plain()\n    return 1\n",None);let mut foreign=Vec::new();assert!(snapshot.write_native_configured_checker(0,"redefined_proc",&root().join("project.dme"),None,&edited.tree,&mut foreign).is_err());assert!(foreign.is_empty());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);let mut changed=Vec::new();edited.write_native_configured_checker(1,"redefined_proc",&root().join("project.dme"),None,&edited.tree,&mut changed).unwrap();let value:serde_json::Value=serde_json::from_slice(&changed).unwrap();assert_eq!((value["diagnostics"][0]["line"].as_u64(),value["diagnostics"][0]["column"].as_u64()),(Some(3),Some(26)));assert_eq!(value["declaration_profile"],"native-diagnostic-inherited-variable-v1");
 let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();let mut denied=Vec::new();assert_eq!(snapshot.write_native_configured_checker(0,"redefined_proc",&root().join("project.dme"),None,&snapshot.tree,&mut denied).err().unwrap().kind(),io::ErrorKind::Interrupted);assert!(denied.is_empty());drop(guard);let mut recovery=Vec::new();snapshot.write_native_configured_checker(0,"redefined_proc",&root().join("project.dme"),None,&snapshot.tree,&mut recovery).unwrap();assert_eq!(recovery,bytes);
}

fn keyword_request(snapshot:&SourceSnapshot)->crate::daemon::query::QueryRequest{use crate::daemon::query::{QueryRequest,SourceQuery};QueryRequest{timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",snapshot.tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeKeywordOverrides{environment:root().join("project.dme"),configuration:None}]}}
const KEYWORD_SOURCE:&str="/datum/keyword_base/proc/work(alpha,beta)\n    return alpha\n/datum/keyword_base/child/work(beta)\n    return beta\n/proc/keyword_calls(datum/keyword_base/value)\n    value.work(alpha=1,beta=2)\n    value.work(\"alpha\"=3)\n";
#[test]fn whole_keyword_overrides_keep_static_receiver_accepted_names_first_calls_and_original_finish_order(){
 use crate::daemon::query;let snapshot=procedure_diagnostic_snapshot(KEYWORD_SOURCE,None);let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let request=keyword_request(&snapshot);request.validate().unwrap();let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();assert_eq!(row["coverage"],"whole_original_archive");assert_eq!(row["complete"],true);assert_eq!(row["body_count"],3);assert_eq!(row["full_checker_parity"],false);let found=row["diagnostics"].as_array().unwrap();assert_eq!(found.len(),1,"{row}");assert_eq!(found[0]["message"],"an override of /datum/keyword_base/proc/work is missing keyword args");assert_eq!(found[0]["severity"],"error");let notes=found[0]["notes"].as_array().unwrap();assert_eq!(notes.len(),2);assert!(notes[0].as_str().unwrap().ends_with("/datum/keyword_base/child is missing \"alpha\""));assert!(notes[1].as_str().unwrap().ends_with("called with \"alpha\" here, and 1 other places"));assert!(!notes.iter().any(|note|note.as_str().unwrap().contains("beta")));
 let before=db.db().stats(dm_query::Kind(4)).computed;assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,reply.jsonl);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);assert_eq!(db.db().stats(dm_query::Kind(23)).computed,0,"whole keyword fold does not invent a PAGE semantic answer");assert_eq!(db.effect_graph_work_for_test(),0);
 let mut wrong=reply.clone();for(key,value)in[("complete",serde_json::json!(false)),("coverage",serde_json::json!("body_subset")),("family",serde_json::json!("private_proc"))]{let mut forged=row.clone();forged[key]=value;wrong.jsonl=format!("{forged}\n");assert!(query::validate_effect_batch_for_test(&request,&wrong).is_err());}
}
#[test]fn whole_keyword_overrides_preserve_exact_calls_static_private_abort_and_multivalue_display_nonmatches(){
 use crate::daemon::query;let source="/datum/keyword_base/proc/work(alpha)\n    return alpha\n/datum/keyword_base/child/work()\n    return 0\n/datum/keyword_base/proc/secret(alpha)\n    set SpacemanDMM_private_proc=TRUE\n    return alpha\n/datum/keyword_base/proc/only_exact(alpha)\n    .(alpha=1)\n    return alpha\n/datum/keyword_base/child/only_exact()\n    return 0\n/datum/keyword_base/child/proc/blocked(datum/keyword_base/child/receiver,datum/keyword_base/base)\n    receiver.secret(alpha=base.work(alpha=1))\n/datum/keyword_base/proc/versions(alpha)\n    return alpha\n/datum/keyword_base/versions(alpha)\n    return alpha\n/datum/keyword_base/child/versions()\n    return 0\n/proc/version_call(datum/keyword_base/base)\n    base.versions(alpha=1)\n";let snapshot=procedure_diagnostic_snapshot(source,None);let tree=snapshot.tree.clone();let request=keyword_request(&snapshot);let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();assert_eq!(row["diagnostics"],serde_json::json!([]),"private static receiver abort must skip hidden work kwargs; exact self calls and original [idx/count] parent keys must not record/match unsuffixed usage: {row}");
}
#[test]fn whole_keyword_overrides_configuration_severity_disabled_edit_and_foreign_owner_remain_source_bound(){
 use crate::daemon::query;for(config,level,count)in[(b"[diagnostics]\noverride_missing_keyword_arg='warning'\n".as_slice(),"warning",1),(b"[diagnostics]\noverride_missing_keyword_arg='hint'\n".as_slice(),"hint",1),(b"[diagnostics]\noverride_missing_keyword_arg='off'\n".as_slice(),"",0)]{let snapshot=procedure_diagnostic_snapshot(KEYWORD_SOURCE,Some(config));let tree=snapshot.tree.clone();let request=keyword_request(&snapshot);let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();assert_eq!(row["diagnostics"].as_array().unwrap().len(),count);if count>0{assert_eq!(row["diagnostics"][0]["severity"],level)}let foreign=procedure_diagnostic_snapshot(KEYWORD_SOURCE,Some(config));let mut output=b"prefix".to_vec();assert!(state.snapshot.as_ref().unwrap().write_native_keyword_overrides(&root().join("project.dme"),None,&foreign.tree,&mut output).is_err());assert_eq!(output,b"prefix");}
 let old=procedure_diagnostic_snapshot(KEYWORD_SOURCE,None);let old_request=keyword_request(&old);let edited=KEYWORD_SOURCE.replace("/child/work(beta)","/child/work(alpha,beta)");let snapshot=procedure_diagnostic_snapshot(&edited,None);let tree=snapshot.tree.clone();let request=keyword_request(&snapshot);let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let before=state.snapshot.as_ref().unwrap().native_raw_queries.as_ref().unwrap().db().stats(dm_query::Kind(4)).computed;assert!(query::evaluate_snapshot(&old_request,&tree,&state).is_err());assert_eq!(state.snapshot.as_ref().unwrap().native_raw_queries.as_ref().unwrap().db().stats(dm_query::Kind(4)).computed,before);let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();assert_eq!(row["diagnostics"],serde_json::json!([]));
}
#[test]fn whole_keyword_overrides_actual_body_io_quota_cancel_and_unwind_release_same_operation_before_recovery(){
 use crate::daemon::query;let snapshot=procedure_diagnostic_snapshot(KEYWORD_SOURCE,None);let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let request=keyword_request(&snapshot);let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let before=db.db().stats(dm_query::Kind(4)).computed;let mut mixed=request.clone();mixed.source_queries.push(crate::daemon::query::SourceQuery::NativeConfiguredChecker{ordinal:0,family:"undefined_variable".into(),environment:root().join("project.dme"),configuration:None});assert!(query::evaluate_snapshot(&mixed,&tree,&state).is_err());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);let mut per_body=request.clone();per_body.source_queries=vec![crate::daemon::query::SourceQuery::NativeConfiguredChecker{ordinal:0,family:"override_missing_keyword_arg".into(),environment:root().join("project.dme"),configuration:None}];assert!(per_body.validate().is_err(),"the whole family has no per-body empty-result fallback");let other=crate::query_db::QueryDb::default();let archive=state.snapshot.as_ref().unwrap().body_archive.as_ref().unwrap();assert!(other.with_original_keyword_overrides(archive,&*tree,tree.checker_builtin_profile().unwrap(),||Ok(()),|_|Ok(())).is_err());assert_eq!(other.effect_graph_work_for_test(),0);let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));let mut bytes=b"prefix".to_vec();let actual=state.snapshot.as_ref().unwrap().write_native_keyword_overrides(&root().join("project.dme"),None,&tree,&mut bytes).unwrap_err();assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(bytes,b"prefix");assert_eq!(db.effect_graph_work_for_test(),0);drop(failure);
 let quota=db.effect_storage_limit_for_test(1);assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(db.effect_graph_work_for_test(),0);drop(quota);let healthy=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&healthy).unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().kind(),io::ErrorKind::Interrupted);drop(guard);
 struct Panic;impl io::Write for Panic{fn write(&mut self,_:&[u8])->io::Result<usize>{panic!("keyword writer unwind control")}fn flush(&mut self)->io::Result<()>{Ok(())}}assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(||state.snapshot.as_ref().unwrap().write_native_keyword_overrides(&root().join("project.dme"),None,&tree,&mut Panic))).is_err());assert_eq!(db.effect_graph_work_for_test(),0);assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,healthy.jsonl);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);
}

#[test]fn whole_keyword_overrides_real_builtin_definition_has_original_builtin_point_without_source_span(){use crate::daemon::query;let snapshot=procedure_diagnostic_snapshot("/list/keyword_child/Copy()\n    return 0\n/proc/use_copy(list/value)\n    value.Copy(Start=1)\n",None);let tree=snapshot.tree.clone();let request=keyword_request(&snapshot);let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();let diagnostics=row["diagnostics"].as_array().unwrap();assert_eq!(diagnostics.len(),1,"{row}");let diagnostic=&diagnostics[0];assert_eq!(diagnostic["file"],"(builtins)");assert_eq!(diagnostic["line"],1);assert_eq!(diagnostic["column"],1);assert_eq!(diagnostic["location_kind"],"builtin");assert!(diagnostic["expanded_span"].is_null()&&diagnostic["expression_span"].is_null());let mut forged=reply;let mut bad=row;bad["diagnostics"][0]["location_kind"]="source".into();forged.jsonl=format!("{bad}\n");assert!(query::validate_effect_batch_for_test(&request,&forged).is_err());}

#[test]fn whole_keyword_finish_orders_real_owner_prefix_groups_by_original_concatenated_path(){use crate::daemon::query;let snapshot=procedure_diagnostic_snapshot(include_str!("../../../fixtures/unified_checks/override_missing_keyword_arg_owner_prefix/project.dme"),None);let tree=snapshot.tree.clone();let request=keyword_request(&snapshot);let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();let rows=row["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),2,"{row}");assert_eq!(rows[0]["message"],"an override of /datum/keyword_prefix/branch/proc/inner is missing keyword args");assert_eq!(rows[1]["message"],"an override of /datum/keyword_prefix/proc/outer is missing keyword args");}

#[test]fn whole_keyword_borrowed_writer_preserves_actual_1450_before_late_cancellation_and_recovery(){
 let snapshot=procedure_diagnostic_snapshot(KEYWORD_SOURCE,None);let db=snapshot.native_raw_queries.as_ref().unwrap();let mut expected=Vec::new();snapshot.write_native_keyword_overrides(&root().join("project.dme"),None,&snapshot.tree,&mut expected).unwrap();let count=db.db().stats(dm_query::Kind(4)).computed;
 struct Failing{token:crate::daemon::control::Cancellation}impl io::Write for Failing{fn write(&mut self,_:&[u8])->io::Result<usize>{self.token.cancel();Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}
 let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));let error=snapshot.write_native_keyword_overrides(&root().join("project.dme"),None,&snapshot.tree,&mut Failing{token}).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450),"actual serializer writer IO must survive both serde and later request guards: {error:?}");assert_eq!(db.effect_graph_work_for_test(),0);drop(guard);let mut recovered=Vec::new();snapshot.write_native_keyword_overrides(&root().join("project.dme"),None,&snapshot.tree,&mut recovered).unwrap();assert_eq!(recovered,expected);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,count);
}

const CALL_ARGUMENT_SOURCE:&[u8]=b"/datum/argument_base/proc/work(alpha)\n    return alpha\n/datum/argument_base/child/work(alpha,beta)\n    return beta\n/datum/argument_base/child/grand/work(alpha,gamma)\n    return gamma\n/datum/argument_base/proc/probe()\n    work(beta=1,2)\n";
fn call_argument_ordinal(snapshot:&SourceSnapshot)->u32{let archive=snapshot.body_archive.as_ref().unwrap();(0..archive.len()).find(|&ordinal|archive.callables().identity(ordinal).is_some_and(|id|snapshot.tree.symbols().text(id.name)==Some("probe"))).unwrap() as u32}
// The argument evaluator requires the authentic pinned hierarchy, just like the
// existing whole-keyword fixture. Reuse the real retained engine issuer.
fn call_argument_snapshot(checker:Option<&[u8]>,scopes:&[u8],source:&[u8])->SourceSnapshot{let mut host=crate::runner_host::BuildHost::one_shot();let engine=host.engine(root().join("project.dme"),Default::default(),true,include_bytes!("../../../fixtures/native_template.bin").to_vec()).unwrap();let snapshot=snapshot_with_checker_source_seed(checker,scopes,source,Some(engine.frontend_seed()));let profile=snapshot.tree.checker_builtin_profile().expect("actual issued argument fixture profile");snapshot.tree.validate_checker_builtin_profile(profile).unwrap();snapshot}
#[test]fn original_call_argument_errors_keep_lexical_child_notes_fixed_error_and_warm_source_body(){for config in[None,Some(b"[diagnostics]\ncall_arguments='off'\nbad_keyword_argument='hint'\nnon_keyword_after_keyword='off'\n".as_slice())]{let snapshot=call_argument_snapshot(config,b"",CALL_ARGUMENT_SOURCE);let ordinal=call_argument_ordinal(&snapshot);let db=snapshot.native_raw_queries.as_ref().unwrap();let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,"call_arguments",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let findings=row["diagnostics"].as_array().unwrap();assert_eq!(findings.len(),2);assert_eq!(findings[0]["family"],"bad_keyword_argument");assert_eq!(findings[0]["message"],"bad keyword argument \"beta\" to /datum/argument_base/proc/work");assert_eq!(findings[0]["notes"].as_array().unwrap().len(),1);assert!(findings[0]["notes"][0].as_str().unwrap().contains("an override has this parameter: /datum/argument_base/child/proc/work"));assert_eq!(findings[1]["family"],"non_keyword_after_keyword");assert_eq!(findings[1]["message"],"proc called with non-kwargs after kwargs: work()");assert!(findings.iter().all(|d|d["severity"]=="error"));let computed=db.db().stats(dm_query::Kind(4)).computed;assert!(computed>0);let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"call_arguments",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(computed,db.db().stats(dm_query::Kind(4)).computed);}}
#[test]fn original_call_argument_actual_io_cancel_foreign_and_strict_dispatch_keep_no_partial_rows(){use crate::daemon::query::{self,SourceQuery};let snapshot=call_argument_snapshot(None,b"",CALL_ARGUMENT_SOURCE);let ordinal=call_argument_ordinal(&snapshot);let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let request=query::QueryRequest{timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal,family:"call_arguments".into(),environment:root().join("project.dme"),configuration:None}]};request.validate().unwrap();let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));let mut output=Vec::new();assert_eq!(snapshot.write_native_configured_checker(ordinal,"call_arguments",&root().join("project.dme"),None,&tree,&mut output).err().unwrap().raw_os_error(),Some(1450));assert!(output.is_empty());drop(failure);let foreign=call_argument_snapshot(None,b"",CALL_ARGUMENT_SOURCE);assert!(snapshot.write_native_configured_checker(ordinal,"call_arguments",&root().join("project.dme"),None,&foreign.tree,&mut output).is_err());assert!(output.is_empty());let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let healthy=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&healthy).unwrap();let mut forged=healthy.clone();let mut bad:serde_json::Value=serde_json::from_str(healthy.jsonl.trim()).unwrap();bad["diagnostics"][0]["family"]="call_arguments".into();forged.jsonl=format!("{bad}\n");assert!(query::validate_effect_batch_for_test(&request,&forged).is_err());bad["diagnostics"][0]["family"]="bad_keyword_argument".into();bad["diagnostics"][0]["severity"]="warning".into();forged.jsonl=format!("{bad}\n");assert!(query::validate_effect_batch_for_test(&request,&forged).is_err());let mut mixed=request.clone();mixed.source_queries.push(SourceQuery::NativeConfiguredChecker{ordinal,family:"undefined_variable".into(),environment:root().join("project.dme"),configuration:None});let before=db.db().stats(dm_query::Kind(4)).computed;assert!(query::evaluate_snapshot(&mixed,&tree,&state).is_err());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().kind(),io::ErrorKind::Interrupted);drop(guard);assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,healthy.jsonl);}

#[test]fn original_call_argument_same_ledger_quota_writer_io_and_unwind_drop_before_recovery(){let snapshot=call_argument_snapshot(None,b"",CALL_ARGUMENT_SOURCE);let ordinal=call_argument_ordinal(&snapshot);let db=snapshot.native_raw_queries.as_ref().unwrap();let env=root().join("project.dme");let baseline=db.effect_graph_work_for_test();let quota=db.effect_graph_headroom_for_test(1).unwrap();let held=db.effect_graph_work_for_test();assert!(held>baseline);let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));let mut first=Vec::new();assert_eq!(snapshot.write_native_configured_checker(ordinal,"call_arguments",&env,None,&snapshot.tree,&mut first).unwrap_err().raw_os_error(),Some(1450));assert!(first.is_empty());assert_eq!(db.effect_graph_work_for_test(),held);drop(failure);let mut out=Vec::new();assert_eq!(snapshot.write_native_configured_checker(ordinal,"call_arguments",&env,None,&snapshot.tree,&mut out).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert!(out.is_empty());assert_eq!(db.effect_graph_work_for_test(),held,"failed operation must retain only the independently held real reservation");drop(quota);assert_eq!(db.effect_graph_work_for_test(),baseline);let mut healthy=Vec::new();snapshot.write_native_configured_checker(ordinal,"call_arguments",&env,None,&snapshot.tree,&mut healthy).unwrap();let count=db.db().stats(dm_query::Kind(4)).computed;
struct Fail(crate::daemon::control::Cancellation);impl io::Write for Fail{fn write(&mut self,_:&[u8])->io::Result<usize>{self.0.cancel();Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));assert_eq!(snapshot.write_native_configured_checker(ordinal,"call_arguments",&env,None,&snapshot.tree,&mut Fail(token)).unwrap_err().raw_os_error(),Some(1450));drop(guard);assert_eq!(db.effect_graph_work_for_test(),0);
struct Panic;impl io::Write for Panic{fn write(&mut self,_:&[u8])->io::Result<usize>{panic!("argument output unwind") }fn flush(&mut self)->io::Result<()>{Ok(())}}assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(||snapshot.write_native_configured_checker(ordinal,"call_arguments",&env,None,&snapshot.tree,&mut Panic))).is_err());assert_eq!(db.effect_graph_work_for_test(),0);let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"call_arguments",&env,None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,healthy);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,count);}

#[test]fn original_call_arguments_validate_exact_self_parent_and_animate_but_preserve_static_private_abort(){let cases:[(&[u8],&str,&str,usize);6]=[
(b"/datum/argument_exact/proc/probe(alpha)\n    .(wrong=1,2)\n","/datum/argument_exact","probe",2),
(b"/datum/argument_parent/proc/work(alpha)\n    return alpha\n/datum/argument_parent/child/work(alpha)\n    ..(wrong=1,2)\n","/datum/argument_parent/child","work",2),
(b"/datum/argument_construct/New(alpha)\n    return alpha\n/proc/probe()\n    new /datum/argument_construct(wrong=1,2)\n","/","probe",2),
(b"/proc/probe()\n    animate(__not_an_animate_parameter__=1,2)\n","/","probe",1),
// Pinned old exact-parent receiver emits private plus BOTH argument errors.
(b"/datum/argument_private/proc/secret(alpha)\n    set SpacemanDMM_private_proc=1\n    return alpha\n/proc/probe(datum/argument_private/value)\n    value.secret(wrong=1,2)\n","/","probe",2),
// Only the genuinely different static child receiver aborts before arguments.
(b"/datum/argument_private/proc/secret(alpha)\n    set SpacemanDMM_private_proc=1\n    return alpha\n/datum/argument_private/child\n/proc/probe(datum/argument_private/child/value)\n    value.secret(wrong=1,2)\n","/","probe",0)];for(source,owner,name,count)in cases{let snapshot=call_argument_snapshot(None,b"",source);let archive=snapshot.body_archive.as_ref().unwrap();let ordinal=(0..archive.len()).find(|&ordinal|archive.callables().identity(ordinal).is_some_and(|id|snapshot.tree.symbols().text(id.owner)==Some(owner)&&snapshot.tree.symbols().text(id.name)==Some(name))).unwrap();let mut output=Vec::new();snapshot.write_native_configured_checker(ordinal as u32,"call_arguments",&root().join("project.dme"),None,&snapshot.tree,&mut output).unwrap();let row:serde_json::Value=serde_json::from_slice(&output).unwrap();assert_eq!(row["diagnostics"].as_array().unwrap().len(),count,"source={} output={row}",String::from_utf8_lossy(source));if owner=="/"&&count==1{assert_eq!(row["diagnostics"][0]["family"],"bad_keyword_argument");}}}

#[test]fn original_call_argument_bad_key_notes_include_real_builtin_lexical_child_without_authored_child(){let snapshot=call_argument_snapshot(None,b"",b"/proc/probe()\n    new /database(text=\"select\")\n");let archive=snapshot.body_archive.as_ref().unwrap();let profile=snapshot.tree.checker_builtin_profile().unwrap();snapshot.tree.validate_checker_builtin_profile(profile).unwrap();let child=snapshot.tree.lookup_type(dm_ir::SymbolId::of("/database/query")).expect("actual pinned-profile node");assert!(!snapshot.tree.declarations().iter().any(|target|matches!(target,dm_tree::Target::Member(member)if snapshot.tree.member(*member).is_some_and(|row|row.owner==child))),"fixture must not author the builtin child");let ordinal=call_argument_ordinal(&snapshot);let mut output=Vec::new();snapshot.write_native_configured_checker(ordinal,"call_arguments",&root().join("project.dme"),None,&snapshot.tree,&mut output).unwrap();let row:serde_json::Value=serde_json::from_slice(&output).unwrap();let findings=row["diagnostics"].as_array().unwrap();assert_eq!(findings.len(),1,"{row}");assert_eq!(findings[0]["message"],"bad keyword argument \"text\" to /database/proc/New");assert_eq!(findings[0]["notes"],serde_json::json!(["(builtins):1:1: an override has this parameter: /database/query/proc/New"]));}

#[test]fn original_call_argument_mixed_builtin_source_chronology_refuses_before_even_empty_arguments(){for call in["abs(alpha=1)","abs()"]{let source=format!("/proc/abs(alpha)\n    return alpha\n/proc/probe()\n    {call}\n");let snapshot=call_argument_snapshot(None,b"",source.as_bytes());let ordinal=call_argument_ordinal(&snapshot);let mut output=Vec::new();let error=snapshot.write_native_configured_checker(ordinal,"call_arguments",&root().join("project.dme"),None,&snapshot.tree,&mut output).unwrap_err();assert!(error.to_string().contains("source/builtin value chronology"),"{error:?}");assert!(output.is_empty());assert_eq!(snapshot.native_raw_queries.as_ref().unwrap().effect_graph_work_for_test(),0);}}

#[test]fn original_call_argument_mixed_builtin_child_signature_refuses_before_missing_note_can_be_omitted(){let snapshot=call_argument_snapshot(None,b"",b"/database/query/New(fake)\n    return fake\n/proc/probe()\n    new /database(text=\"select\")\n");let ordinal=call_argument_ordinal(&snapshot);let mut output=Vec::new();let error=snapshot.write_native_configured_checker(ordinal,"call_arguments",&root().join("project.dme"),None,&snapshot.tree,&mut output).unwrap_err();assert!(error.to_string().contains("source/builtin value chronology"),"{error:?}");assert!(output.is_empty());assert_eq!(snapshot.native_raw_queries.as_ref().unwrap().effect_graph_work_for_test(),0);}


#[test]fn original_call_argument_missing_builtin_profile_refuses_before_body_or_output(){let snapshot=snapshot_with_checker_source(None,b"",CALL_ARGUMENT_SOURCE);assert!(snapshot.tree.checker_builtin_profile().is_none());let db=snapshot.native_raw_queries.as_ref().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;let mut output=b"prefix".to_vec();let error=snapshot.write_native_configured_checker(call_argument_ordinal(&snapshot),"call_arguments",&root().join("project.dme"),None,&snapshot.tree,&mut output).unwrap_err();assert!(error.to_string().contains("actual pinned builtin profile"),"{error:?}");assert_eq!(output,b"prefix");assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);assert_eq!(db.effect_graph_work_for_test(),0);}
#[test]fn whole_keyword_overrides_mixed_builtin_source_calls_refuse_before_even_empty_arguments(){for call in["abs(alpha=1)","abs()"]{let source=format!("/proc/abs(alpha)\n    return alpha\n/proc/probe()\n    {call}\n");let snapshot=procedure_diagnostic_snapshot(&source,None);let mut output=Vec::new();let error=snapshot.write_native_keyword_overrides(&root().join("project.dme"),None,&snapshot.tree,&mut output).unwrap_err();assert!(error.to_string().contains("source/builtin value chronology"),"{error:?}");assert!(output.is_empty());assert_eq!(snapshot.native_raw_queries.as_ref().unwrap().effect_graph_work_for_test(),0);}}

#[test]fn original_call_argument_pending_ledger_escrow_checks_actual_headroom_and_unwind_releases_it(){let snapshot=call_argument_snapshot(None,b"",CALL_ARGUMENT_SOURCE);let db=snapshot.native_raw_queries.as_ref().unwrap();let before=db.effect_graph_work_for_test();assert_eq!(db.effect_graph_headroom_for_test(usize::MAX).err().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(db.effect_graph_work_for_test(),before);assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{let pending=db.effect_graph_headroom_for_test(1).unwrap();assert!(db.effect_graph_work_for_test()>before);let _keep_pending=pending;panic!("pending allocation escrow unwind")})).is_err());assert_eq!(db.effect_graph_work_for_test(),before);let pending=db.effect_graph_headroom_for_test(1).unwrap();assert!(db.effect_graph_work_for_test()>before);drop(pending);assert_eq!(db.effect_graph_work_for_test(),before);}
