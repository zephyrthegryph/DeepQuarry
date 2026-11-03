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
    let intent = PolicyInputRequest {analysis_context:None,workspace_auxiliary:Vec::new(),workspace_generators:Vec::new(),
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
    let intent = PolicyInputRequest {analysis_context:None,workspace_auxiliary:Vec::new(),workspace_generators:Vec::new(),
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
    let source = include_str!("../../../fixtures/native-checker-utf8-byte-positions.dm");
    assert_eq!(source.as_bytes(), b"/proc/probe(a,b)\n\tlist(\"\xC3\xA9\xE6\xBC\xA2\"); !a & b\n", "the original Unicode fixture must not be transcoded");
    let snapshot = semantic_snapshot(source, None);
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
#[test]fn configured_unknown_linter_setting_actual_kind4_io_cancel_and_dispatch_validation_never_return_partial_reply(){use crate::daemon::query::{self,SourceQuery};let snapshot=snapshot_with_checker_source(None,b"",include_bytes!("../../../fixtures/unified_checks/unknown_linter_setting/probe.dme"));let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let request=query::QueryRequest{analysis_context:None,timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal:0,family:"unknown_linter_setting".into(),environment:root().join("project.dme"),configuration:None}]};request.validate().unwrap();let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().raw_os_error(),Some(1450));drop(failure);let healthy=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&healthy).unwrap();let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().kind(),io::ErrorKind::Interrupted);drop(guard);assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,healthy.jsonl);}

#[test]fn configured_unknown_setting_is_untagged_warning_even_when_observation_key_is_disabled_or_hint(){for config in [b"[diagnostics]\nunknown_setting='off'\n".as_slice(),b"[diagnostics]\nunknown_setting='hint'\n".as_slice()]{let snapshot=snapshot_with_checker_source(Some(config),b"",include_bytes!("../../../fixtures/unified_checks/unknown_setting/probe.dme"));let db=snapshot.native_raw_queries.as_ref().unwrap();let mut bytes=Vec::new();snapshot.write_native_configured_checker(0,"unknown_setting",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let found=row["diagnostics"].as_array().unwrap();assert_eq!(found.len(),2);assert!(found.iter().all(|d|d["severity"]=="warning"&&d["family"]=="unknown_setting"&&d["message"]=="unknown setting \"ordinary_unknown\""));assert_eq!(found[0]["line"],2);assert_eq!(found[1]["line"],3);let computed=db.db().stats(dm_query::Kind(4)).computed;assert!(computed>0);let mut warm=Vec::new();snapshot.write_native_configured_checker(0,"unknown_setting",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,computed);}}
#[test]fn configured_unknown_setting_actual_kind4_io_cancel_and_dispatch_validation_never_return_partial_reply(){use crate::daemon::query::{self,SourceQuery};let snapshot=snapshot_with_checker_source(None,b"",include_bytes!("../../../fixtures/unified_checks/unknown_setting/probe.dme"));let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let request=query::QueryRequest{analysis_context:None,timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal:0,family:"unknown_setting".into(),environment:root().join("project.dme"),configuration:None}]};request.validate().unwrap();let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().raw_os_error(),Some(1450));drop(failure);let healthy=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&healthy).unwrap();let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().kind(),io::ErrorKind::Interrupted);drop(guard);assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,healthy.jsonl);}

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
    let intent = PolicyInputRequest {analysis_context:None,workspace_auxiliary:Vec::new(),workspace_generators:Vec::new(),
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
#[test]fn configured_directive_binding_actual_kind4_io_cancel_and_dispatch_never_return_partial_reply(){use crate::daemon::query::{self,SourceQuery};let snapshot=snapshot_with_source(None,b"",include_bytes!("../../../fixtures/unified_checks/sets_directive_twice/probe.dme"));let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let request=query::QueryRequest{analysis_context:None,timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal:0,family:"sets_directive_twice".into(),environment:root().join("project.dme"),configuration:None}]};request.validate().unwrap();let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().raw_os_error(),Some(1450));drop(failure);let healthy=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&healthy).unwrap();let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().kind(),io::ErrorKind::Interrupted);drop(guard);assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,healthy.jsonl);}

#[test]fn configured_invalid_directive_value_borrows_funded_complete_debug_messages_and_warm_original_body(){
 let snapshot=snapshot_with_checker_source(Some(b"[diagnostics]\ninvalid_lint_directive_value='hint'\n"),b"",include_bytes!("../../../fixtures/unified_checks/invalid_lint_directive_value/probe.dme"));let db=snapshot.native_raw_queries.as_ref().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;let mut bytes=Vec::new();snapshot.write_native_configured_checker(0,"invalid_lint_directive_value",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let diagnostics=row["diagnostics"].as_array().unwrap();assert_eq!(diagnostics.len(),10);assert!(diagnostics.iter().all(|d|d["family"]=="invalid_lint_directive_value"&&d["severity"]=="hint"&&d["notes"].as_array().unwrap().is_empty()));assert_eq!(diagnostics[0]["message"],"invalid value for set Base { term: Spanned { location: Location { file: FileId(1), line: 2, column: 42 }, elem: Int(2) }, follow: [] }");assert!(diagnostics[2]["message"].as_str().unwrap().contains("InterpString"));assert!(diagnostics[5]["message"].as_str().unwrap().contains("As((empty))"));assert!(diagnostics[6]["message"].as_str().unwrap().contains("LessOrGreater"));assert!(diagnostics[7]["message"].as_str().unwrap().contains("Reference"));assert!(diagnostics[8]["message"].as_str().unwrap().contains("GlobalIdent"));let computed=db.db().stats(dm_query::Kind(4)).computed;assert!(computed>before);let body=snapshot.body_archive.as_ref().unwrap().parse_checked(0).unwrap();let address=body.statement_body()as*const _;let mut warm=Vec::new();snapshot.write_native_configured_checker(0,"invalid_lint_directive_value",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,computed);let after=snapshot.body_archive.as_ref().unwrap().parse_checked(0).unwrap();assert_eq!(after.statement_body()as*const _,address);
 let disabled=snapshot_with_checker_source(Some(b"[diagnostics]\ninvalid_lint_directive_value='off'\n"),b"",include_bytes!("../../../fixtures/unified_checks/invalid_lint_directive_value/probe.dme"));let db=disabled.native_raw_queries.as_ref().unwrap();let baseline=db.db().stats(dm_query::Kind(4)).computed;let mut bytes=Vec::new();disabled.write_native_configured_checker(0,"invalid_lint_directive_value",&root().join("project.dme"),None,&disabled.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert!(row["diagnostics"].as_array().unwrap().is_empty());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,baseline);
}
#[test]fn configured_invalid_directive_value_actual_kind4_io_cancel_and_dispatch_preserve_no_partial_output(){
 use crate::daemon::query::{self,SourceQuery};let snapshot=snapshot_with_checker_source(None,b"",include_bytes!("../../../fixtures/unified_checks/invalid_lint_directive_value/probe.dme"));let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let request=query::QueryRequest{analysis_context:None,timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal:0,family:"invalid_lint_directive_value".into(),environment:root().join("project.dme"),configuration:None}]};request.validate().unwrap();let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));let mut output=Vec::new();let snapshot=state.snapshot.as_ref().unwrap();assert_eq!(snapshot.write_native_configured_checker(0,"invalid_lint_directive_value",&root().join("project.dme"),None,&tree,&mut output).err().unwrap().raw_os_error(),Some(1450));assert!(output.is_empty());drop(failure);let healthy=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&healthy).unwrap();let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().kind(),io::ErrorKind::Interrupted);drop(guard);assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,healthy.jsonl);
}

#[test]fn configured_invalid_directive_value_foreign_frame_refuses_before_root_and_actual_same_budget_quota_recovers(){
 let source=include_bytes!("../../../fixtures/unified_checks/invalid_lint_directive_value/probe.dme");let snapshot=snapshot_with_checker_source(None,b"",source);let foreign=snapshot_with_checker_source(None,b"",source);let db=snapshot.native_raw_queries.as_ref().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;let mut rejected=Vec::new();assert!(snapshot.write_native_configured_checker(0,"invalid_lint_directive_value",&root().join("project.dme"),None,&foreign.tree,&mut rejected).is_err());assert!(rejected.is_empty());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);
 let mut healthy=Vec::new();snapshot.write_native_configured_checker(0,"invalid_lint_directive_value",&root().join("project.dme"),None,&snapshot.tree,&mut healthy).unwrap();let counter=crate::query_db::body_syntax_counter_for_test(db);let limit=crate::query_db::body_syntax_budget_for_test();let used=counter.load(std::sync::atomic::Ordering::Acquire);let held=dm_syntax::SettingRootLease::reserve(counter,limit,limit.checked_sub(used).unwrap()).unwrap();let mut denied=Vec::new();let error=snapshot.write_native_configured_checker(0,"invalid_lint_directive_value",&root().join("project.dme"),None,&snapshot.tree,&mut denied).err().unwrap();assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);assert!(denied.is_empty());drop(held);let mut recovered=Vec::new();snapshot.write_native_configured_checker(0,"invalid_lint_directive_value",&root().join("project.dme"),None,&snapshot.tree,&mut recovered).unwrap();assert_eq!(recovered,healthy);
}

#[test]fn diagnostic_invalid_directive_role_accepts_only_registered_original_syntax_question_and_rejects_mixed_semantics_before_demand(){
 use crate::daemon::query::{self,SourceQuery};let snapshot=snapshot_with_checker_source(None,b"",include_bytes!("../../../fixtures/unified_checks/invalid_lint_directive_value/probe.dme"));let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let mut request=query::QueryRequest{analysis_context:None,timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal:0,family:"invalid_lint_directive_value".into(),environment:root().join("project.dme"),configuration:None}]};let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};request.validate().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;
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
 use crate::daemon::query::{self,SourceQuery};let snapshot=snapshot_with_checker_source(None,b"",include_bytes!("../../../fixtures/unified_checks/directive_at_definition/probe.dme"));let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let request=query::QueryRequest{analysis_context:None,timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal:1,family:"directive_at_definition".into(),environment:root().join("project.dme"),configuration:None}]};request.validate().unwrap();let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));let mut bytes=Vec::new();assert_eq!(state.snapshot.as_ref().unwrap().write_native_configured_checker(1,"directive_at_definition",&root().join("project.dme"),None,&tree,&mut bytes).err().unwrap().raw_os_error(),Some(1450));assert!(bytes.is_empty());drop(failure);let good=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&good).unwrap();let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().kind(),io::ErrorKind::Interrupted);drop(binding);assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,good.jsonl);
}

#[test]fn diagnostic_at_definition_role_accepts_only_its_registered_header_question_and_refuses_mixed_semantics_before_demand(){
 use crate::daemon::query::{self,SourceQuery};let snapshot=snapshot_with_checker_source(None,b"",include_bytes!("../../../fixtures/unified_checks/directive_at_definition/probe.dme"));let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let mut request=query::QueryRequest{analysis_context:None,timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal:1,family:"directive_at_definition".into(),environment:root().join("project.dme"),configuration:None}]};let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};request.validate().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;
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
 use crate::daemon::query::{self,SourceQuery};let source="/list/proc/New(size)\n    set SpacemanDMM_private_proc = TRUE\n/proc/probe()\n    var/list/items[2]\n";let snapshot=procedure_diagnostic_snapshot(source,None);assert!(snapshot.resolved.is_none(),"source diagnostic question must not fabricate an ABI EngineHost");let ordinal=visibility_ordinal(&snapshot,"/","probe");let tree=snapshot.tree.clone();let request=query::QueryRequest{analysis_context:None,timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal,family:"private_proc".into(),environment:root().join("project.dme"),configuration:None}]};request.validate().unwrap();let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();let diagnostics=row["diagnostics"].as_array().unwrap();assert_eq!(diagnostics.len(),1);let d=&diagnostics[0];assert_eq!(d["location_kind"],"parser_synthetic");assert_eq!(d["file"],"(unknown)");assert_eq!(d["line"],0);assert_eq!(d["column"],0);assert!(d["expanded_span"].is_null()&&d["expression_span"].is_null());assert!(d["notes"][0].as_str().unwrap().contains(":2:5: prohibited by this private_proc annotation"));let mut invalid=reply.clone();let mut value=row;value["diagnostics"][0]["location_kind"]="source".into();invalid.jsonl=format!("{value}\n");assert!(query::validate_effect_batch_for_test(&request,&invalid).is_err(),"zero synthetic point cannot be relabeled as a source location");
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
 let snapshot=procedure_diagnostic_snapshot(&source,None);assert!(snapshot.resolved.is_none());let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let ordinal=visibility_ordinal(&snapshot,"/datum/access/child","secret");let mut request=query::QueryRequest{analysis_context:None,timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal,family:"private_proc".into(),environment:root().join("project.dme"),configuration:None}]};
 let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let before=db.db().stats(dm_query::Kind(4)).computed;request.source_queries.push(SourceQuery::NativeConfiguredChecker{ordinal,family:"undefined_variable".into(),environment:root().join("project.dme"),configuration:None});assert!(query::evaluate_snapshot(&request,&tree,&state).is_err());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);request.source_queries.pop();let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().raw_os_error(),Some(1450));drop(failure);let good=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&good).unwrap();let row:serde_json::Value=serde_json::from_str(good.jsonl.lines().next().unwrap()).unwrap();assert_eq!(row["declaration_profile"],"native-diagnostic-source-declarations-v2");assert_eq!(row["native_declaration_error_count"],1);assert!(row["diagnostics"].as_array().unwrap().is_empty());let warm=db.db().stats(dm_query::Kind(4)).computed;assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,good.jsonl);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,warm);
 let mut wrong=good;let mut forged=row;forged["native_declaration_error_count"]=serde_json::json!(0);wrong.jsonl=serde_json::to_string(&forged).unwrap()+"\n";assert!(query::validate_effect_batch_for_test(&request,&wrong).is_err(),"v2 requires an actual inherited procedure declaration error");
}

#[test]fn diagnostic_unknown_setting_frame_variable_visibility_reply_keeps_its_actual_zero_error_profile(){
 use crate::daemon::query::{self,SourceQuery};let snapshot=procedure_diagnostic_snapshot("/datum/probe/proc/run()\n    set ordinary_unknown = 1\n    return 0\n",None);assert!(snapshot.resolved.is_none());let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let request=query::QueryRequest{analysis_context:None,timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredVariableVisibility{environment:root().join("project.dme"),configuration:None}]};let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let good=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&good).unwrap();let row:serde_json::Value=serde_json::from_str(good.jsonl.trim()).unwrap();assert_eq!(row["declaration_profile"],"native-diagnostic-inherited-variable-v1");assert_eq!(row["native_declaration_error_count"],0);let before=db.db().stats(dm_query::Kind(4)).computed;assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,good.jsonl);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);
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
 use crate::daemon::query::{self,SourceQuery};let source="/datum/redefinition/proc/plain()\n    return 0\n/datum/redefinition/proc/plain()\n    return 1\n";let snapshot=procedure_diagnostic_snapshot(source,Some(b"[diagnostics]\nredefined_proc='off'\nprocedure_redeclaration='off'\n"));assert!(snapshot.resolved.is_none());let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();assert_eq!(snapshot.body_archive.as_ref().unwrap().len(),2);let mut request=query::QueryRequest{analysis_context:None,timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal:1,family:"redefined_proc".into(),environment:root().join("project.dme"),configuration:None}]};let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let before=db.db().stats(dm_query::Kind(4)).computed;request.source_queries.push(SourceQuery::NativeConfiguredChecker{ordinal:0,family:"undefined_variable".into(),environment:root().join("project.dme"),configuration:None});assert!(query::evaluate_snapshot(&request,&tree,&state).is_err());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);request.source_queries.pop();let good=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&good).unwrap();assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before,"structural header projection must not prepare a disabled body");let row:serde_json::Value=serde_json::from_str(good.jsonl.trim()).unwrap();assert_eq!(row["declaration_profile"],"native-diagnostic-procedure-versions-v3");let d=&row["diagnostics"][0];assert_eq!(row["diagnostics"].as_array().unwrap().len(),1);assert_eq!(d["family"],"procedure_redeclaration");assert!(d["registration_tag"].is_null());assert_eq!(d["severity"],"error");assert_eq!((d["line"].as_u64(),d["column"].as_u64()),(Some(3),Some(31)));assert_eq!(d["message"],"duplicate definition of proc/plain");assert_eq!(d["notes"],serde_json::json!(["1:31: previous definition"]));
 for(key,value)in[("registration_tag",serde_json::json!("redefined_proc")),("severity",serde_json::json!("warning")),("family",serde_json::json!("native_inherited_duplicate"))]{let mut bad=good.clone();let mut data=row.clone();data["diagnostics"][0][key]=value;bad.jsonl=format!("{data}\n");assert!(query::validate_effect_batch_for_test(&request,&bad).is_err());}
 let enabled=procedure_diagnostic_snapshot(source,Some(b"[diagnostics]\nredefined_proc='warning'\n"));let mut bytes=Vec::new();enabled.write_native_configured_checker(0,"redefined_proc",&root().join("project.dme"),None,&enabled.tree,&mut bytes).unwrap();let value:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let d=&value["diagnostics"][0];assert_eq!(d["family"],"redefined_proc");assert_eq!(d["registration_tag"],"redefined_proc");assert_eq!(d["severity"],"warning");assert_eq!((d["line"].as_u64(),d["column"].as_u64()),(Some(1),Some(31)));assert_eq!(d["message"],"redefining proc /datum/redefinition/plain");assert_eq!(d["notes"],serde_json::json!(["3:31: previous definition is here"]));
}

#[test]fn redefined_source_body_actual_io_foreign_edit_and_cancel_keep_atomic_configured_rows(){
 let source="/datum/redefinition/proc/plain()\n    return 0\n/datum/redefinition/proc/plain()\n    return 1\n";let snapshot=procedure_diagnostic_snapshot(source,None);let db=snapshot.native_raw_queries.as_ref().unwrap();let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));let mut bytes=Vec::new();assert_eq!(snapshot.write_native_configured_checker(0,"redefined_proc",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).err().unwrap().raw_os_error(),Some(1450));assert!(bytes.is_empty());drop(failure);snapshot.write_native_configured_checker(0,"redefined_proc",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let value:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert_eq!(value["diagnostics"][0]["severity"],"hint");let before=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(0,"redefined_proc",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);
 let edited=procedure_diagnostic_snapshot("/datum/redefinition/proc/plain()\n    return 0\n/datum/redefinition/plain()\n    return 1\n",None);let mut foreign=Vec::new();assert!(snapshot.write_native_configured_checker(0,"redefined_proc",&root().join("project.dme"),None,&edited.tree,&mut foreign).is_err());assert!(foreign.is_empty());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);let mut changed=Vec::new();edited.write_native_configured_checker(1,"redefined_proc",&root().join("project.dme"),None,&edited.tree,&mut changed).unwrap();let value:serde_json::Value=serde_json::from_slice(&changed).unwrap();assert_eq!((value["diagnostics"][0]["line"].as_u64(),value["diagnostics"][0]["column"].as_u64()),(Some(3),Some(26)));assert_eq!(value["declaration_profile"],"native-diagnostic-inherited-variable-v1");
 let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();let mut denied=Vec::new();assert_eq!(snapshot.write_native_configured_checker(0,"redefined_proc",&root().join("project.dme"),None,&snapshot.tree,&mut denied).err().unwrap().kind(),io::ErrorKind::Interrupted);assert!(denied.is_empty());drop(guard);let mut recovery=Vec::new();snapshot.write_native_configured_checker(0,"redefined_proc",&root().join("project.dme"),None,&snapshot.tree,&mut recovery).unwrap();assert_eq!(recovery,bytes);
}

fn keyword_request(snapshot:&SourceSnapshot)->crate::daemon::query::QueryRequest{use crate::daemon::query::{QueryRequest,SourceQuery};QueryRequest{analysis_context:None,timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",snapshot.tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeKeywordOverrides{environment:root().join("project.dme"),configuration:None}]}}
const KEYWORD_SOURCE:&str="/datum/keyword_base/proc/work(alpha,beta)\n    return alpha\n/datum/keyword_base/child/work(beta)\n    return beta\n/proc/keyword_calls(datum/keyword_base/value)\n    value.work(alpha=1,beta=2)\n    value.work(\"alpha\"=3)\n";
#[test]fn whole_keyword_overrides_keep_static_receiver_accepted_names_first_calls_and_original_finish_order(){
 use crate::daemon::query;let snapshot=procedure_diagnostic_snapshot(KEYWORD_SOURCE,None);let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let request=keyword_request(&snapshot);request.validate().unwrap();let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();assert_eq!(row["coverage"],"whole_original_archive");assert_eq!(row["complete"],true);assert_eq!(row["body_count"],3);assert_eq!(row["full_checker_parity"],false);let found=row["diagnostics"].as_array().unwrap();assert_eq!(found.len(),1,"{row}");assert_eq!(found[0]["message"],"an override of /datum/keyword_base/proc/work is missing keyword args");assert_eq!(found[0]["severity"],"error");let notes=found[0]["notes"].as_array().unwrap();assert_eq!(notes.len(),2);assert!(notes[0].as_str().unwrap().ends_with("/datum/keyword_base/child is missing \"alpha\""));assert!(notes[1].as_str().unwrap().ends_with("called with \"alpha\" here, and 1 other places"));assert!(!notes.iter().any(|note|note.as_str().unwrap().contains("beta")));
 let before=db.db().stats(dm_query::Kind(4)).computed;assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,reply.jsonl);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);assert_eq!(db.db().stats(dm_query::Kind(23)).computed,0,"whole keyword fold does not invent a PAGE semantic answer");assert_eq!(db.effect_graph_work_for_test(),0);
 let mut wrong=reply.clone();for(key,value)in[("complete",serde_json::json!(false)),("coverage",serde_json::json!("body_subset")),("family",serde_json::json!("private_proc"))]{let mut forged=row.clone();forged[key]=value;wrong.jsonl=format!("{forged}\n");assert!(query::validate_effect_batch_for_test(&request,&wrong).is_err());}
}
#[test]fn whole_keyword_overrides_preserve_exact_calls_static_private_abort_and_multivalue_display_nonmatches(){
 use crate::daemon::query;let source="/datum/keyword_base/proc/work(alpha)\n    return alpha\n/datum/keyword_base/child/work()\n    return 0\n/datum/keyword_base/proc/secret(alpha)\n    set SpacemanDMM_private_proc=TRUE\n    return alpha\n/datum/keyword_base/proc/only_exact(alpha)\n    .(alpha=1)\n    return alpha\n/datum/keyword_base/child/only_exact()\n    return 0\n/datum/keyword_base/child/proc/blocked(datum/keyword_base/child/receiver,datum/keyword_base/base)\n    receiver.secret(alpha=base.work(alpha=1))\n/datum/keyword_base/proc/versions(alpha)\n    return alpha\n/datum/keyword_base/versions(alpha)\n    return alpha\n/datum/keyword_base/child/versions()\n    return 0\n/proc/version_call(datum/keyword_base/base)\n    base.versions(alpha=1)\n";let snapshot=procedure_diagnostic_snapshot(source,None);let tree=snapshot.tree.clone();let request=keyword_request(&snapshot);let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();assert_eq!(row["diagnostics"],serde_json::json!([]),"private static receiver abort must skip hidden work kwargs; exact self calls and original [idx/count] parent keys must not record/match unsuffixed usage: {row}");
}
#[test]fn whole_keyword_overrides_configuration_severity_disabled_edit_and_foreign_owner_remain_source_bound(){
 use crate::daemon::query;for(config,level,count)in[(b"[diagnostics]\noverride_missing_keyword_arg='warning'\n".as_slice(),"warning",1),(b"[diagnostics]\noverride_missing_keyword_arg='hint'\n".as_slice(),"hint",1),(b"[diagnostics]\noverride_missing_keyword_arg='off'\n".as_slice(),"",0)]{let snapshot=procedure_diagnostic_snapshot(KEYWORD_SOURCE,Some(config));let tree=snapshot.tree.clone();let request=keyword_request(&snapshot);let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();assert_eq!(row["diagnostics"].as_array().unwrap().len(),count);if count>0{assert_eq!(row["diagnostics"][0]["severity"],level)}let foreign=procedure_diagnostic_snapshot(KEYWORD_SOURCE,Some(config));let mut output=b"prefix".to_vec();assert!(state.snapshot.as_ref().unwrap().write_native_keyword_overrides(&root().join("project.dme"),None,&foreign.tree,&mut output).is_err());assert_eq!(output,b"prefix");}
 let old=procedure_diagnostic_snapshot(KEYWORD_SOURCE,None);let old_request=keyword_request(&old);let edited=KEYWORD_SOURCE.replace("/child/work(beta)","/child/work(alpha,beta)");let snapshot=procedure_diagnostic_snapshot(&edited,None);let tree=snapshot.tree.clone();let request=keyword_request(&snapshot);let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let before=state.snapshot.as_ref().unwrap().native_raw_queries.as_ref().unwrap().db().stats(dm_query::Kind(4)).computed;assert!(query::evaluate_snapshot(&old_request,&tree,&state).is_err());assert_eq!(state.snapshot.as_ref().unwrap().native_raw_queries.as_ref().unwrap().db().stats(dm_query::Kind(4)).computed,before);let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();assert_eq!(row["diagnostics"],serde_json::json!([]));
}
#[test]fn whole_keyword_overrides_actual_body_io_quota_cancel_and_unwind_release_same_operation_before_recovery(){
 use crate::daemon::query;let snapshot=procedure_diagnostic_snapshot(KEYWORD_SOURCE,None);let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let request=keyword_request(&snapshot);let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let before=db.db().stats(dm_query::Kind(4)).computed;let mut mixed=request.clone();mixed.source_queries.push(crate::daemon::query::SourceQuery::NativeConfiguredChecker{ordinal:0,family:"undefined_variable".into(),environment:root().join("project.dme"),configuration:None});assert!(query::evaluate_snapshot(&mixed,&tree,&state).is_err());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);let mut per_body=request.clone();per_body.source_queries=vec![crate::daemon::query::SourceQuery::NativeConfiguredChecker{ordinal:0,family:"override_missing_keyword_arg".into(),environment:root().join("project.dme"),configuration:None}];assert!(per_body.validate().is_err(),"the whole family has no per-body empty-result fallback");let other=crate::query_db::QueryDb::default();let archive=state.snapshot.as_ref().unwrap().body_archive.as_ref().unwrap();assert!(other.with_original_keyword_overrides(archive,&*tree,tree.checker_builtin_profile().unwrap(),||Ok(()),|_|Ok(())).is_err());assert_eq!(other.effect_graph_work_for_test(),0);let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));let mut bytes=b"prefix".to_vec();let actual=state.snapshot.as_ref().unwrap().write_native_keyword_overrides(&root().join("project.dme"),None,&tree,&mut bytes).unwrap_err();assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(bytes,b"prefix");assert_eq!(db.effect_graph_work_for_test(),0);drop(failure);
 let quota=db.effect_storage_limit_for_test(1);assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(db.effect_graph_work_for_test(),0);drop(quota);let healthy=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&healthy).unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().kind(),io::ErrorKind::Interrupted);drop(guard);
 struct Panic;impl io::Write for Panic{fn write(&mut self,_:&[u8])->io::Result<usize>{panic!("keyword writer unwind control")}fn flush(&mut self)->io::Result<()>{Ok(())}}assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(||state.snapshot.as_ref().unwrap().write_native_keyword_overrides(&root().join("project.dme"),None,&tree,&mut Panic))).is_err());assert_eq!(db.effect_graph_work_for_test(),0);assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,healthy.jsonl);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);
}

#[test]fn whole_keyword_overrides_real_builtin_definition_has_original_builtin_point_without_source_span(){use crate::daemon::query;let snapshot=procedure_diagnostic_snapshot("/list/keyword_child/Copy()\n    return 0\n/proc/use_copy(list/value)\n    value.Copy(Start=1)\n",None);let tree=snapshot.tree.clone();let request=keyword_request(&snapshot);let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();let diagnostics=row["diagnostics"].as_array().unwrap();assert_eq!(diagnostics.len(),1,"{row}");let diagnostic=&diagnostics[0];assert_eq!(diagnostic["file"],"(builtins)");assert_eq!(diagnostic["line"],1);assert_eq!(diagnostic["column"],1);assert_eq!(diagnostic["location_kind"],"builtin");assert!(diagnostic["expanded_span"].is_null()&&diagnostic["expression_span"].is_null());let mut forged=reply;let mut bad=row;bad["diagnostics"][0]["location_kind"]="source".into();forged.jsonl=format!("{bad}\n");assert!(query::validate_effect_batch_for_test(&request,&forged).is_err());}

#[test]fn whole_keyword_finish_orders_real_owner_prefix_groups_by_original_concatenated_path(){use crate::daemon::query;let snapshot=procedure_diagnostic_snapshot(include_str!("../../../fixtures/unified_checks/override_missing_keyword_arg_owner_prefix/project.dme"),None);let tree=snapshot.tree.clone();let request=keyword_request(&snapshot);let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();let rows=row["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),2,"{row}");assert_eq!(rows[0]["message"],"an override of /datum/keyword_prefix/branch/proc/inner is missing keyword args");assert_eq!(rows[1]["message"],"an override of /datum/keyword_prefix/proc/outer is missing keyword args");}

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
#[test]fn original_call_argument_actual_io_cancel_foreign_and_strict_dispatch_keep_no_partial_rows(){use crate::daemon::query::{self,SourceQuery};let snapshot=call_argument_snapshot(None,b"",CALL_ARGUMENT_SOURCE);let ordinal=call_argument_ordinal(&snapshot);let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let request=query::QueryRequest{analysis_context:None,timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal,family:"call_arguments".into(),environment:root().join("project.dme"),configuration:None}]};request.validate().unwrap();let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));let mut output=Vec::new();assert_eq!(snapshot.write_native_configured_checker(ordinal,"call_arguments",&root().join("project.dme"),None,&tree,&mut output).err().unwrap().raw_os_error(),Some(1450));assert!(output.is_empty());drop(failure);let foreign=call_argument_snapshot(None,b"",CALL_ARGUMENT_SOURCE);assert!(snapshot.write_native_configured_checker(ordinal,"call_arguments",&root().join("project.dme"),None,&foreign.tree,&mut output).is_err());assert!(output.is_empty());let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let healthy=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&healthy).unwrap();let mut forged=healthy.clone();let mut bad:serde_json::Value=serde_json::from_str(healthy.jsonl.trim()).unwrap();bad["diagnostics"][0]["family"]="call_arguments".into();forged.jsonl=format!("{bad}\n");assert!(query::validate_effect_batch_for_test(&request,&forged).is_err());bad["diagnostics"][0]["family"]="bad_keyword_argument".into();bad["diagnostics"][0]["severity"]="warning".into();forged.jsonl=format!("{bad}\n");assert!(query::validate_effect_batch_for_test(&request,&forged).is_err());let mut mixed=request.clone();mixed.source_queries.push(SourceQuery::NativeConfiguredChecker{ordinal,family:"undefined_variable".into(),environment:root().join("project.dme"),configuration:None});let before=db.db().stats(dm_query::Kind(4)).computed;assert!(query::evaluate_snapshot(&mixed,&tree,&state).is_err());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().kind(),io::ErrorKind::Interrupted);drop(guard);assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,healthy.jsonl);}

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

#[test]fn original_call_argument_mixed_builtin_source_calls_use_real_builtin_winner_before_even_empty_arguments(){for call in["abs(alpha=1)","abs()"]{let source=format!("/proc/abs(alpha)\n    return alpha\n/proc/probe()\n    {call}\n");let snapshot=call_argument_snapshot(None,b"",source.as_bytes());let ordinal=call_argument_ordinal(&snapshot);let mut output=Vec::new();snapshot.write_native_configured_checker(ordinal,"call_arguments",&root().join("project.dme"),None,&snapshot.tree,&mut output).unwrap();let row:serde_json::Value=serde_json::from_slice(&output).unwrap();let diagnostics=row["diagnostics"].as_array().unwrap();assert_eq!(diagnostics.len(),usize::from(call.contains("alpha")),"{row}");if let Some(row)=diagnostics.first(){assert_eq!(row["message"],"bad keyword argument \"alpha\" to /proc/abs[1/2]");}assert_eq!(snapshot.native_raw_queries.as_ref().unwrap().effect_graph_work_for_test(),0);}}

#[test]fn original_call_argument_mixed_builtin_child_uses_actual_latest_implicit_signature(){let snapshot=call_argument_snapshot(None,b"",b"/database/query/New(fake)\n    return fake\n/proc/probe()\n    new /database(text=\"select\")\n");let ordinal=call_argument_ordinal(&snapshot);let mut output=Vec::new();snapshot.write_native_configured_checker(ordinal,"call_arguments",&root().join("project.dme"),None,&snapshot.tree,&mut output).unwrap();let row:serde_json::Value=serde_json::from_slice(&output).unwrap();let diagnostics=row["diagnostics"].as_array().unwrap();assert_eq!(diagnostics.len(),1,"{row}");assert_eq!(diagnostics[0]["message"],"bad keyword argument \"text\" to /database/proc/New");assert_eq!(diagnostics[0]["notes"],serde_json::json!([]));assert_eq!(snapshot.native_raw_queries.as_ref().unwrap().effect_graph_work_for_test(),0);}


#[test]fn original_call_argument_missing_builtin_profile_refuses_before_body_or_output(){let snapshot=snapshot_with_checker_source(None,b"",CALL_ARGUMENT_SOURCE);assert!(snapshot.tree.checker_builtin_profile().is_none());let db=snapshot.native_raw_queries.as_ref().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;let mut output=b"prefix".to_vec();let error=snapshot.write_native_configured_checker(call_argument_ordinal(&snapshot),"call_arguments",&root().join("project.dme"),None,&snapshot.tree,&mut output).unwrap_err();assert!(error.to_string().contains("actual pinned builtin profile"),"{error:?}");assert_eq!(output,b"prefix");assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);assert_eq!(db.effect_graph_work_for_test(),0);}
#[test]fn whole_keyword_overrides_mixed_builtin_source_calls_use_actual_signature_before_even_empty_arguments(){for call in["abs(alpha=1)","abs()"]{let source=format!("/proc/abs(alpha)\n    return alpha\n/proc/probe()\n    {call}\n");let snapshot=procedure_diagnostic_snapshot(&source,None);let mut output=Vec::new();snapshot.write_native_keyword_overrides(&root().join("project.dme"),None,&snapshot.tree,&mut output).unwrap();let row:serde_json::Value=serde_json::from_slice(&output).unwrap();assert_eq!(row["diagnostics"],serde_json::json!([]),"builtin abs has no alpha parameter to record");assert_eq!(snapshot.native_raw_queries.as_ref().unwrap().effect_graph_work_for_test(),0);}}

#[test]fn original_call_argument_pending_ledger_escrow_checks_actual_headroom_and_unwind_releases_it(){let snapshot=call_argument_snapshot(None,b"",CALL_ARGUMENT_SOURCE);let db=snapshot.native_raw_queries.as_ref().unwrap();let before=db.effect_graph_work_for_test();assert_eq!(db.effect_graph_headroom_for_test(usize::MAX).err().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(db.effect_graph_work_for_test(),before);assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{let pending=db.effect_graph_headroom_for_test(1).unwrap();assert!(db.effect_graph_work_for_test()>before);let _keep_pending=pending;panic!("pending allocation escrow unwind")})).is_err());assert_eq!(db.effect_graph_work_for_test(),before);let pending=db.effect_graph_headroom_for_test(1).unwrap();assert!(db.effect_graph_work_for_test()>before);drop(pending);assert_eq!(db.effect_graph_work_for_test(),before);}

#[test]fn original_call_argument_actual_implicit_builtin_override_keeps_all_old_words_warm_and_typed_writer_io(){let snapshot=call_argument_snapshot(None,b"",include_bytes!("../../../fixtures/unified_checks/call_arguments_mixed_implicit/project.dme"));let ordinal=call_argument_ordinal(&snapshot);let db=snapshot.native_raw_queries.as_ref().unwrap();let mut output=Vec::new();snapshot.write_native_configured_checker(ordinal,"call_arguments",&root().join("project.dme"),None,&snapshot.tree,&mut output).unwrap();let row:serde_json::Value=serde_json::from_slice(&output).unwrap();let rows=row["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),2,"{row}");assert_eq!(rows[0]["message"],"bad keyword argument \"wrong\" to /proc/abs[1/2]");assert_eq!(rows[1]["message"],"proc called with non-kwargs after kwargs: abs()");let before=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"call_arguments",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,output);assert_eq!(before,db.db().stats(dm_query::Kind(4)).computed);struct Fail;impl io::Write for Fail{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}assert_eq!(snapshot.write_native_configured_checker(ordinal,"call_arguments",&root().join("project.dme"),None,&snapshot.tree,&mut Fail).unwrap_err().raw_os_error(),Some(1450));assert_eq!(db.effect_graph_work_for_test(),0);}

#[test]fn original_mixed_group_actual_bound_cancellation_and_first_io_refuse_before_body_then_recover(){use dm_analysis::policy_body_demand::PolicyFailure;let mut source=String::new();for i in 0..48{source.push_str(&format!("/abs(arg{i})\n    return arg{i}\n"));}source.push_str("/proc/probe()\n    abs(wrong=1)\n");let snapshot=call_argument_snapshot(None,b"",source.as_bytes());let tree=&*snapshot.tree;let db=snapshot.native_raw_queries.as_ref().unwrap();let profile=tree.checker_builtin_profile().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;for actual_io in [false,true]{let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));let polls=std::cell::Cell::new(0usize);let error=dm_analysis::checker_call_facts::callable_any_using(tree,tree,profile,dm_ir::SymbolId::of("/"),dm_ir::SymbolId::of("abs"),&mut||{let next=polls.get()+1;polls.set(next);if next==12{token.cancel();if actual_io{return Err(PolicyFailure::Operational(io::Error::from_raw_os_error(1450)))}}crate::daemon::control::checkpoint().map_err(PolicyFailure::Operational)}).err().unwrap();assert_eq!(polls.get(),12,"control must stop in the newly checked source-group scan");let PolicyFailure::Operational(error)=error else{panic!("actual operation control became semantic text")};if actual_io{assert_eq!(error.raw_os_error(),Some(1450))}else{assert_eq!(error.kind(),io::ErrorKind::Interrupted)}assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);assert_eq!(db.effect_graph_work_for_test(),0);drop(binding);}let ordinal=call_argument_ordinal(&snapshot);let mut output=Vec::new();snapshot.write_native_configured_checker(ordinal,"call_arguments",&root().join("project.dme"),None,tree,&mut output).unwrap();let row:serde_json::Value=serde_json::from_slice(&output).unwrap();assert_eq!(row["diagnostics"].as_array().unwrap().len(),1);assert_eq!(row["diagnostics"][0]["message"],"bad keyword argument \"wrong\" to /proc/abs[48/49]");let count=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"call_arguments",&root().join("project.dme"),None,tree,&mut warm).unwrap();assert_eq!(warm,output);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,count);}

#[test]fn original_mixed_group_checked_body_lends_real_control_and_preserves_first_io_before_recovery(){use dm_analysis::{checker_effects::{EffectInput,ExecutionAdmission},policy_body_demand::PolicyFailure};let snapshot=call_argument_snapshot(None,b"",include_bytes!("../../../fixtures/unified_checks/call_arguments_mixed_implicit/project.dme"));let profile=snapshot.tree.checker_builtin_profile().unwrap();let input=EffectInput::new(Arc::clone(snapshot.body_archive.as_ref().unwrap()),profile).unwrap();let ordinal=call_argument_ordinal(&snapshot)as usize;for actual_io in[false,true]{let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));let polls=std::cell::Cell::new(0usize);let error=input.compute_body_checked_controlled(ordinal,&*snapshot.tree,&ExecutionAdmission::default(),&||{let next=polls.get()+1;polls.set(next);if next==3{token.cancel();if actual_io{return Err(io::Error::from_raw_os_error(1450))}}crate::daemon::control::checkpoint()}).err().expect("actual body pipeline must use its supplied operation control");assert_eq!(polls.get(),3);let PolicyFailure::Operational(error)=error else{panic!("body operation control became semantic text")};if actual_io{assert_eq!(error.raw_os_error(),Some(1450))}else{assert_eq!(error.kind(),io::ErrorKind::Interrupted)}drop(binding);}let healthy=input.compute_body_checked_controlled(ordinal,&*snapshot.tree,&ExecutionAdmission::default(),&||crate::daemon::control::checkpoint()).unwrap();assert!(healthy.charge()>0);let bodies=input.order().iter().map(|&(i,_)|if i==ordinal{Arc::clone(&healthy)}else{input.compute_body_checked_controlled(i,&*snapshot.tree,&ExecutionAdmission::default(),&||crate::daemon::control::checkpoint()).unwrap()}).collect();let plan=input.plan_checked_controlled(bodies,&*snapshot.tree,&ExecutionAdmission::default(),&||crate::daemon::control::checkpoint()).unwrap();plan.validate(&input).unwrap();plan.summarize(&input).unwrap();}

#[test]fn original_call_argument_mixed_parent_calls_follow_actual_value_position_before_arguments(){for(source,rows)in[("/proc/abs(alpha)\n    ..(wrong=1,2)\n",0),(include_str!("../../../fixtures/unified_checks/call_arguments_mixed_parent_implicit/project.dme"),2)]{let snapshot=call_argument_snapshot(None,b"",source.as_bytes());let archive=snapshot.body_archive.as_ref().unwrap();let ordinal=(0..archive.len()).find(|&ordinal|archive.callables().identity(ordinal).is_some_and(|id|id.owner==dm_ir::SymbolId::of("/")&&id.name==dm_ir::SymbolId::of("abs"))).unwrap();let mut output=Vec::new();snapshot.write_native_configured_checker(ordinal as u32,"call_arguments",&root().join("project.dme"),None,&snapshot.tree,&mut output).unwrap();let row:serde_json::Value=serde_json::from_slice(&output).unwrap();let found=row["diagnostics"].as_array().unwrap();assert_eq!(found.len(),rows,"source={source} output={row}");if rows!=0{assert_eq!(found[0]["message"],"bad keyword argument \"wrong\" to /proc/abs[0/2]");assert_eq!(found[1]["message"],"proc called with non-kwargs after kwargs: abs()");}}}

fn original_callable_ordinal(snapshot:&SourceSnapshot,owner:&str,name:&str)->u32{let archive=snapshot.body_archive.as_ref().unwrap();let wanted_owner=dm_ir::SymbolId::of(owner);let wanted_name=dm_ir::SymbolId::of(name);u32::try_from((0..archive.len()).find(|&ordinal|archive.callables().identity(ordinal).is_some_and(|identity|identity.owner==wanted_owner&&identity.name==wanted_name)).unwrap_or_else(||panic!("actual callable {owner}/proc/{name} absent"))).unwrap()}
fn filter_ordinal(snapshot:&SourceSnapshot,name:&str)->u32{let archive=snapshot.body_archive.as_ref().unwrap();u32::try_from((0..archive.len()).find(|&ordinal|archive.callables().identity(ordinal).is_some_and(|id|snapshot.tree.symbols().text(id.owner)==Some("/")&&snapshot.tree.symbols().text(id.name)==Some(name))).unwrap()).unwrap()}
const FILTER_BASIC:&[u8]=b"/proc/probe()\n    filter(type=0)\n    filter(type=\"blur\",color=\"#fff\")\n";
#[test]fn original_filter_call_uses_actual_values_and_flag_terms_without_compiler_constant_guess(){
 let source=b"/proc/probe()\n    var/kind=\"blur\"\n    filter(type=kind,color=\"#fff\")\n    kind=\"outline\"\n    filter(type=kind,color=\"#fff\")\n    filter(type=(kind=\"blur\"),color=\"#fff\")\n    filter(type=(0 ? \"blur\" : \"outline\"),color=\"#fff\")\n    filter(type=astype(\"blur\"),color=\"#fff\")\n    filter(type=/datum)\n    filter(type=0)\n    filter(type=null)\n";let snapshot=call_argument_snapshot(None,b"",source);let mut output=Vec::new();snapshot.write_native_configured_checker(filter_ordinal(&snapshot,"probe"),"filter_call",&root().join("project.dme"),None,&snapshot.tree,&mut output).unwrap();let row:serde_json::Value=serde_json::from_slice(&output).unwrap();let rows=row["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),8,"{row}");for row in &rows[..4]{assert_eq!(row["message"],"filter(type=\"blur\") called with invalid keyword parameter 'color'");}assert_eq!(rows[4]["message"],"filter() called with non-string type keyword parameter value 'None'");assert_eq!(rows[5]["message"],"filter() called with non-string type keyword parameter value 'Some(Prefab(Pop { path: [\"datum\"], vars: {} }))'");assert_eq!(rows[6]["message"],"filter() called with non-string type keyword parameter value 'Some(Float(0.0))'");assert_eq!(rows[7]["message"],"filter() called with non-string type keyword parameter value 'Some(Null(None))'");assert!(rows.iter().all(|row|row["severity"]=="error"));
 let db=snapshot.native_raw_queries.as_ref().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(filter_ordinal(&snapshot,"probe"),"filter_call",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,output);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);assert_eq!(db.effect_graph_work_for_test(),0);
}
#[test]fn original_filter_flags_keep_original_tables_term_words_and_direct_arglist_shape(){
 let source=b"/proc/probe()\n    filter(type=\"layer\",flags=FILTER_OVERLAY|FILTER_UNDERLAY)\n    filter(type=\"color\",space=0)\n    filter(type=\"alpha\",flags=1)\n    filter(type=\"alpha\",flags=~MASK_INVERSE)\n    filter(type=\"outline\",flags=1|OUTLINE_SHARP)\n    filter(type=\"alpha\",flags=0)\n    filter(arglist(list()))\n    filter((arglist(list())))\n    filter(size=1,2)\n";let(host,environment)=original_filter_flags_host(source);let current=host.query_state();let state=current.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let mut output=Vec::new();snapshot.write_native_configured_checker(filter_ordinal(&snapshot,"probe"),"filter_call",&environment,None,&snapshot.tree,&mut output).unwrap();let row:serde_json::Value=serde_json::from_slice(&output).unwrap();let rows=row["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),8,"{row}");assert_eq!(rows[0]["message"],"filter(type=\"layer\") 'flags' parameter must have one value, found bitwise OR");assert_eq!(rows[1]["message"],"filter(type=\"color\") called with invalid 'space' value 'Int(0)'");assert_eq!(rows[2]["message"],"filter(type=\"alpha\") called with invalid 'flags' value 'Int(1)'");assert_eq!(rows[3]["message"],"filter() flag fields cannot have unary ops or field accesses");assert_eq!(rows[3]["notes"],serde_json::json!([]));assert_eq!(rows[4]["message"],"filter(type=\"outline\") called with invalid 'flags' value 'Int(1)'");assert_eq!(rows[5]["message"],"filter() called without mandatory keyword parameter 'type'");assert_eq!(rows[6]["family"],"non_keyword_after_keyword");assert_eq!(rows[7]["message"],"filter() called without mandatory keyword parameter 'type'");
}
#[test]fn original_filter_fixed_error_config_dispatch_edit_and_foreign_controls_are_source_bound(){
 use crate::daemon::query::{self,SourceQuery};let snapshot=call_argument_snapshot(Some(b"[diagnostics]\nfilter_call='off'\nbad_keyword_argument='off'\n"),b"",FILTER_BASIC);let ordinal=filter_ordinal(&snapshot,"probe");let tree=snapshot.tree.clone();let request=query::QueryRequest{analysis_context:None,timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal,family:"filter_call".into(),environment:root().join("project.dme"),configuration:None}]};let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();assert_eq!(row["diagnostics"].as_array().unwrap().len(),2);assert!(row["diagnostics"].as_array().unwrap().iter().all(|row|row["severity"]=="error"));let mut forged=reply.clone();let mut value=row.clone();value["diagnostics"][0]["severity"]="warning".into();forged.jsonl=format!("{value}\n");assert!(query::validate_effect_batch_for_test(&request,&forged).is_err());value["diagnostics"][0]["severity"]="error".into();value["diagnostics"][0]["family"]="private_proc".into();forged.jsonl=format!("{value}\n");assert!(query::validate_effect_batch_for_test(&request,&forged).is_err());
 let foreign=call_argument_snapshot(None,b"",FILTER_BASIC);let mut output=b"prefix".to_vec();assert!(state.snapshot.as_ref().unwrap().write_native_configured_checker(ordinal,"filter_call",&root().join("project.dme"),None,&foreign.tree,&mut output).is_err());assert_eq!(output,b"prefix");let edited=call_argument_snapshot(None,b"",b"/proc/probe()\n    filter(type=\"blur\",size=1)\n");let edited_tree=edited.tree.clone();let edited_state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(edited),last_request_outcome:"analyzed",publication_pair:None};assert!(query::evaluate_snapshot(&request,&edited_tree,&edited_state).is_err());
}
#[test]fn original_filter_actual_io_quota_writer_cancel_and_unwind_drop_before_recovery(){
 let snapshot=call_argument_snapshot(None,b"",FILTER_BASIC);let ordinal=filter_ordinal(&snapshot,"probe");let db=snapshot.native_raw_queries.as_ref().unwrap();let env=root().join("project.dme");let mut output=Vec::new();let injected=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));assert_eq!(snapshot.write_native_configured_checker(ordinal,"filter_call",&env,None,&snapshot.tree,&mut output).unwrap_err().raw_os_error(),Some(1450));assert!(output.is_empty());drop(injected);let quota=db.effect_graph_headroom_for_test(1).unwrap();let held=db.effect_graph_work_for_test();assert_eq!(snapshot.write_native_configured_checker(ordinal,"filter_call",&env,None,&snapshot.tree,&mut output).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert!(output.is_empty());assert_eq!(db.effect_graph_work_for_test(),held);drop(quota);let mut healthy=Vec::new();snapshot.write_native_configured_checker(ordinal,"filter_call",&env,None,&snapshot.tree,&mut healthy).unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;
 struct Fail(crate::daemon::control::Cancellation);impl io::Write for Fail{fn write(&mut self,_:&[u8])->io::Result<usize>{self.0.cancel();Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}let cancellation=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(cancellation.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));assert_eq!(snapshot.write_native_configured_checker(ordinal,"filter_call",&env,None,&snapshot.tree,&mut Fail(cancellation)).unwrap_err().raw_os_error(),Some(1450));drop(binding);assert_eq!(db.effect_graph_work_for_test(),0);
 struct Panic;impl io::Write for Panic{fn write(&mut self,_:&[u8])->io::Result<usize>{panic!("filter output unwind")}fn flush(&mut self)->io::Result<()>{Ok(())}}assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(||snapshot.write_native_configured_checker(ordinal,"filter_call",&env,None,&snapshot.tree,&mut Panic))).is_err());assert_eq!(db.effect_graph_work_for_test(),0);let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"filter_call",&env,None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,healthy);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);
}

#[test]fn original_filter_relative_dot_and_colon_values_share_actual_native_archive_and_warm_query(){let snapshot=call_argument_snapshot(None,b"",include_bytes!("../../../fixtures/unified_checks/filter_call_navigation/project.dme"));let archive=snapshot.body_archive.as_ref().unwrap();let ordinal=(0..archive.len()).find(|&i|archive.callables().identity(i).is_some_and(|id|snapshot.tree.symbols().text(id.owner)==Some("/datum/filter_nav")&&snapshot.tree.symbols().text(id.name)==Some("probe"))).unwrap()as u32;let mut output=Vec::new();snapshot.write_native_configured_checker(ordinal,"filter_call",&root().join("project.dme"),None,&snapshot.tree,&mut output).unwrap();let row:serde_json::Value=serde_json::from_slice(&output).unwrap();let rows=row["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),2,"{row}");for row in rows{assert_eq!(row["message"],"filter() called with non-string type keyword parameter value 'Some(Prefab(Pop { path: [\"datum\", \"filter_nav\", \"child\"], vars: {} }))'");}assert_eq!(rows[0]["line"],3);assert_eq!(rows[1]["line"],4);let db=snapshot.native_raw_queries.as_ref().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"filter_call",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,output);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);assert_eq!(db.effect_graph_work_for_test(),0);}

#[test]fn original_filter_colon_checks_each_parent_direct_child_before_its_descendant_subtrees(){let snapshot=call_argument_snapshot(None,b"",include_bytes!("../../../fixtures/unified_checks/filter_call_navigation_competing/project.dme"));let archive=snapshot.body_archive.as_ref().unwrap();let ordinal=(0..archive.len()).find(|&i|archive.callables().identity(i).is_some_and(|id|snapshot.tree.symbols().text(id.owner)==Some("/datum/filter_nav")&&snapshot.tree.symbols().text(id.name)==Some("probe"))).unwrap()as u32;let mut output=Vec::new();snapshot.write_native_configured_checker(ordinal,"filter_call",&root().join("project.dme"),None,&snapshot.tree,&mut output).unwrap();let row:serde_json::Value=serde_json::from_slice(&output).unwrap();let rows=row["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),1,"{row}");assert_eq!(rows[0]["message"],"filter() called with non-string type keyword parameter value 'Some(Prefab(Pop { path: [\"datum\", \"filter_nav\", \"a\", \"target\"], vars: {} }))'");assert_eq!(rows[0]["line"],5);assert_eq!(rows[0]["column"],5);}

#[test]fn original_catch_parameter_warning_binds_every_issued_local_and_cannot_be_config_muted(){
 let snapshot=call_argument_snapshot(Some(b"[diagnostics]\ncatch_parameter_count='off'\n"),b"",include_bytes!("../../../fixtures/unified_checks/catch_parameter_count/project.dme"));let ordinal=filter_ordinal(&snapshot,"probe");let mut output=Vec::new();snapshot.write_native_configured_checker(ordinal,"catch_parameter_count",&root().join("project.dme"),None,&snapshot.tree,&mut output).unwrap();let row:serde_json::Value=serde_json::from_slice(&output).unwrap();let rows=row["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),1,"{row}");assert_eq!(rows[0]["family"],"catch_parameter_count");assert_eq!(rows[0]["severity"],"warning");assert_eq!(rows[0]["message"],"Expected 0 or 1 catch parameters, got 2");assert_eq!(rows[0]["line"],2);assert_eq!(rows[0]["column"],5);let archive=snapshot.body_archive.as_ref().unwrap();let body=archive.parse_checked(ordinal as usize).unwrap();let profile=snapshot.tree.checker_builtin_profile().unwrap();let undefined=dm_analysis::checks_undefined_variable::archived(archive,&body,&*snapshot.tree,profile,true).unwrap();assert!(undefined.is_empty(),"all actual catch parameters, especially return b, must be bound: {undefined:?}");let db=snapshot.native_raw_queries.as_ref().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"catch_parameter_count",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,output);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);assert_eq!(db.effect_graph_work_for_test(),0);
 for catch in["catch","catch()","catch(var/a)","catch(var/a,)"]{let source=format!("/proc/probe()\n    try\n        return 0\n    {catch}\n        return 1\n");let control=call_argument_snapshot(None,b"",source.as_bytes());let mut bytes=Vec::new();control.write_native_configured_checker(filter_ordinal(&control,"probe"),"catch_parameter_count",&root().join("project.dme"),None,&control.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert_eq!(row["diagnostics"],serde_json::json!([]),"{catch}: {row}");}
}
#[test]fn original_catch_warning_strict_dispatch_keeps_fixed_severity_source_role_and_foreign_refusal(){use crate::daemon::query::{self,SourceQuery};let snapshot=call_argument_snapshot(None,b"",include_bytes!("../../../fixtures/unified_checks/catch_parameter_count/project.dme"));let ordinal=filter_ordinal(&snapshot,"probe");let tree=snapshot.tree.clone();let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let request=query::QueryRequest{analysis_context:None,timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal,family:"catch_parameter_count".into(),environment:root().join("project.dme"),configuration:None}]};let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let mut forged=reply.clone();let mut row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();row["diagnostics"][0]["severity"]="error".into();forged.jsonl=format!("{row}\n");assert!(query::validate_effect_batch_for_test(&request,&forged).is_err());row["diagnostics"][0]["severity"]="warning".into();row["diagnostics"][0]["family"]="private_proc".into();forged.jsonl=format!("{row}\n");assert!(query::validate_effect_batch_for_test(&request,&forged).is_err());let mut mixed=request.clone();mixed.source_queries.push(SourceQuery::NativeConfiguredChecker{ordinal,family:"undefined_variable".into(),environment:root().join("project.dme"),configuration:None});let before=db.db().stats(dm_query::Kind(4)).computed;assert!(query::evaluate_snapshot(&mixed,&tree,&state).is_err());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);let foreign=call_argument_snapshot(None,b"",include_bytes!("../../../fixtures/unified_checks/catch_parameter_count/project.dme"));let mut bytes=b"prefix".to_vec();assert!(state.snapshot.as_ref().unwrap().write_native_configured_checker(ordinal,"catch_parameter_count",&root().join("project.dme"),None,&foreign.tree,&mut bytes).is_err());assert_eq!(bytes,b"prefix");}
#[test]fn original_catch_warning_actual_io_quota_writer_cancel_and_unwind_leave_no_partial_result(){
 let snapshot=call_argument_snapshot(None,b"",include_bytes!("../../../fixtures/unified_checks/catch_parameter_count/project.dme"));let ordinal=filter_ordinal(&snapshot,"probe");let db=snapshot.native_raw_queries.as_ref().unwrap();let env=root().join("project.dme");let mut output=Vec::new();let injected=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));assert_eq!(snapshot.write_native_configured_checker(ordinal,"catch_parameter_count",&env,None,&snapshot.tree,&mut output).unwrap_err().raw_os_error(),Some(1450));assert!(output.is_empty());drop(injected);let quota=db.effect_graph_headroom_for_test(1).unwrap();let held=db.effect_graph_work_for_test();assert_eq!(snapshot.write_native_configured_checker(ordinal,"catch_parameter_count",&env,None,&snapshot.tree,&mut output).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert!(output.is_empty());assert_eq!(db.effect_graph_work_for_test(),held);drop(quota);let mut healthy=Vec::new();snapshot.write_native_configured_checker(ordinal,"catch_parameter_count",&env,None,&snapshot.tree,&mut healthy).unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;
 struct Fail(crate::daemon::control::Cancellation);impl io::Write for Fail{fn write(&mut self,_:&[u8])->io::Result<usize>{self.0.cancel();Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}let cancellation=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(cancellation.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));assert_eq!(snapshot.write_native_configured_checker(ordinal,"catch_parameter_count",&env,None,&snapshot.tree,&mut Fail(cancellation)).unwrap_err().raw_os_error(),Some(1450));drop(binding);assert_eq!(db.effect_graph_work_for_test(),0);struct Panic;impl io::Write for Panic{fn write(&mut self,_:&[u8])->io::Result<usize>{panic!("catch warning output unwind")}fn flush(&mut self)->io::Result<()>{Ok(())}}assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(||snapshot.write_native_configured_checker(ordinal,"catch_parameter_count",&env,None,&snapshot.tree,&mut Panic))).is_err());assert_eq!(db.effect_graph_work_for_test(),0);let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"catch_parameter_count",&env,None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,healthy);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);
}

#[test]fn original_filter_unary_values_clear_after_operand_and_preserve_nested_evaluation_order(){
 let snapshot=call_argument_snapshot(None,b"",include_bytes!("../../../fixtures/unified_checks/filter_unary_values/project.dme"));let ordinal=filter_ordinal(&snapshot,"probe");let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,"filter_call",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let rows=row["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),7,"{row}");for row in rows.iter().take(5){assert_eq!(row["message"],"filter() called with non-string type keyword parameter value 'None'");}assert_eq!(rows[5]["message"],"filter() called with non-string type keyword parameter value 'Some(Float(1.0))'");assert_eq!(rows[6]["message"],"filter() called with non-string type keyword parameter value 'None'");assert!(rows[5]["column"].as_u64().unwrap()>rows[6]["column"].as_u64().unwrap());let db=snapshot.native_raw_queries.as_ref().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"filter_call",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);assert_eq!(db.effect_graph_work_for_test(),0);
}

// Genuine production PrepareQuery purpose; no test macro-table/seed override.
fn original_filter_flags_host(source:&[u8])->(crate::runner_host::BuildHost,PathBuf){original_filter_flags_host_purpose(source,true)}
fn original_filter_flags_host_purpose(source:&[u8],observe_environment:bool)->(crate::runner_host::BuildHost,PathBuf){original_filter_flags_host_configuration(source,observe_environment,None)}
fn original_filter_flags_host_configuration(source:&[u8],observe_environment:bool,configuration:Option<&[u8]>)->(crate::runner_host::BuildHost,PathBuf){
 use crate::policy_request::AnalysisContext;use crate::request::{Command,BuildOutcome};
 let root=crate::test_scratch::dir("original-filter-flags-context");let project=root.join("project.dme");std::fs::write(&project,source).unwrap();std::fs::write(root.join("scopes.toml"),b"").unwrap();if let Some(bytes)=configuration{std::fs::write(root.join("SpacemanDMM.toml"),bytes).unwrap();}
 let args=vec!["prepare-query".to_owned(),project.to_string_lossy().into_owned()];let Command::Build(request)=crate::cli::parse(&args).unwrap()else{panic!("actual PrepareQuery parser")};let mut request=*request;request.no_cache=true;request.exact_inputs=true;request.workers=1;request.progress_enabled=false;request.cache_root=Some(root.join("cache"));let mut intent=PolicyInputRequest::default();intent.analysis_context=Some(AnalysisContext::OriginalChecker0290);intent.files=vec![PolicyInputFile{path:root.join("scopes.toml"),role:PolicyInputRole::Configuration,required:true},PolicyInputFile{path:root.join("SpacemanDMM.toml"),role:PolicyInputRole::Configuration,required:false}];if observe_environment{intent.files.push(PolicyInputFile{path:project.clone(),role:PolicyInputRole::DmSource,required:true});}request.policy_inputs=Some(intent);let mut host=crate::runner_host::BuildHost::default();let outcome=crate::request_runner::run_build_with_host(request,&mut host).unwrap();assert!(matches!(outcome,BuildOutcome::QueryPrepared{retained:true,..}));{let current=host.query_state();let state=current.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();snapshot.require_analysis_context(Some(AnalysisContext::OriginalChecker0290)).unwrap();assert!(snapshot.resolved.is_none());assert!(snapshot.native_policy_inputs.is_some());assert!(snapshot.native_workspace.is_none());let profile=snapshot.tree.checker_builtin_profile().unwrap();snapshot.tree.validate_checker_builtin_profile(profile).unwrap();} (host,project)
}
#[test]fn original_filter_flags_context_is_real_query_purpose_and_native_literals_remain_distinct(){
 use crate::daemon::query::{self,SourceQuery};use crate::policy_request::AnalysisContext;let source=b"/proc/probe()\n    filter(type=\"outline\",flags=1|OUTLINE_SHARP)\n";
 let native=call_argument_snapshot(None,b"",source);let mut native_bytes=Vec::new();native.write_native_configured_checker(filter_ordinal(&native,"probe"),"filter_call",&root().join("project.dme"),None,&native.tree,&mut native_bytes).unwrap();let native_row:serde_json::Value=serde_json::from_slice(&native_bytes).unwrap();assert_eq!(native_row["diagnostics"].as_array().unwrap().len(),2,"actual Native5161687 expands OUTLINE_SHARP to its second literal1");assert_eq!(native_row["diagnostics"][0]["message"],native_row["diagnostics"][1]["message"]);
 let(host,environment)=original_filter_flags_host(source);let current=host.query_state();let state=current.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let ordinal=filter_ordinal(snapshot,"probe");let request=query::QueryRequest{analysis_context:Some(AnalysisContext::OriginalChecker0290),timeout_seconds:Some(300),project:environment.clone(),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",snapshot.tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:Vec::new(),source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal,family:"filter_call".into(),environment:environment.clone(),configuration:None}]};let reply=query::evaluate_snapshot(&request,&snapshot.tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();assert_eq!(row["diagnostics"].as_array().unwrap().len(),1);assert_eq!(row["diagnostics"][0]["message"],"filter(type=\"outline\") called with invalid 'flags' value 'Int(1)'");let db=snapshot.native_raw_queries.as_ref().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;let warm=query::evaluate_snapshot(&request,&snapshot.tree,&state).unwrap();assert_eq!(warm.jsonl,reply.jsonl);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);let mut wrong=request;wrong.analysis_context=None;assert_eq!(query::evaluate_snapshot(&wrong,&snapshot.tree,&state).unwrap_err().kind(),io::ErrorKind::InvalidInput);
}

#[test]fn original_static_reference_uses_typed_and_value_receivers_without_visiting_reference_arguments(){let snapshot=call_argument_snapshot(Some(b"[diagnostics]
static_reference='off'"),b"",include_bytes!("../../../fixtures/unified_checks/static_reference_errors/project.dme"));let ordinal=filter_ordinal(&snapshot,"probe");let db=snapshot.native_raw_queries.as_ref().unwrap();let mut output=Vec::new();snapshot.write_native_configured_checker(ordinal,"static_reference",&root().join("project.dme"),None,&snapshot.tree,&mut output).unwrap();let row:serde_json::Value=serde_json::from_slice(&output).unwrap();let rows=row["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),4,"{row}");let expected=[(10,10,"static access requires a static typepath, null found instead"),(12,11,"static access requires a static typepath, 5 found instead"),(13,9,"undefined field: \"absent\" on /datum/static_target"),(14,10,"undefined proc: \"absent_proc\" on /datum/static_target")];for(row,(line,column,message))in rows.iter().zip(expected){assert_eq!(row["line"],line);assert_eq!(row["column"],column);assert_eq!(row["message"],message);assert_eq!(row["severity"],"error");}let before=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"static_reference",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,output);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);assert_eq!(db.effect_graph_work_for_test(),0);}
#[test]fn original_proc_reference_keeps_real_receiver_and_inherited_declaration_kind_as_filter_value(){let snapshot=call_argument_snapshot(None,b"",include_bytes!("../../../fixtures/unified_checks/filter_static_reference/project.dme"));let ordinal=original_callable_ordinal(&snapshot,"/datum/static_child","probe");let mut output=Vec::new();snapshot.write_native_configured_checker(ordinal,"filter_call",&root().join("project.dme"),None,&snapshot.tree,&mut output).unwrap();let row:serde_json::Value=serde_json::from_slice(&output).unwrap();let rows=row["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),1,"{row}");assert_eq!(rows[0]["message"],"filter() called with non-string type keyword parameter value 'Some(Prefab(Pop { path: [\"datum\", \"static_child\", \"proc\", \"work\"], vars: {} }))'");assert_eq!(rows[0]["line"],8);assert_eq!(rows[0]["column"],5);}
#[test]fn original_static_reference_strict_dispatch_keeps_fixed_error_source_role_and_foreign_refusal(){use crate::daemon::query::{self,SourceQuery};let snapshot=call_argument_snapshot(None,b"",include_bytes!("../../../fixtures/unified_checks/static_reference_errors/project.dme"));let ordinal=filter_ordinal(&snapshot,"probe");let tree=snapshot.tree.clone();let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let request=query::QueryRequest{analysis_context:None,timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal,family:"static_reference".into(),environment:root().join("project.dme"),configuration:None}]};let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let mut forged=reply.clone();let mut row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();row["diagnostics"][0]["severity"]="warning".into();forged.jsonl=format!("{row}\n");assert!(query::validate_effect_batch_for_test(&request,&forged).is_err());row["diagnostics"][0]["severity"]="error".into();row["diagnostics"][0]["family"]="private_proc".into();forged.jsonl=format!("{row}\n");assert!(query::validate_effect_batch_for_test(&request,&forged).is_err());let mut mixed=request.clone();mixed.source_queries.push(SourceQuery::NativeConfiguredChecker{ordinal,family:"undefined_variable".into(),environment:root().join("project.dme"),configuration:None});let before=db.db().stats(dm_query::Kind(4)).computed;assert!(query::evaluate_snapshot(&mixed,&tree,&state).is_err());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);let foreign=call_argument_snapshot(None,b"",include_bytes!("../../../fixtures/unified_checks/static_reference_errors/project.dme"));let mut bytes=b"prefix".to_vec();assert!(state.snapshot.as_ref().unwrap().write_native_configured_checker(ordinal,"static_reference",&root().join("project.dme"),None,&foreign.tree,&mut bytes).is_err());assert_eq!(bytes,b"prefix");}
#[test]fn original_static_reference_actual_io_quota_writer_cancel_and_unwind_leave_no_partial_result(){
 let snapshot=call_argument_snapshot(None,b"",include_bytes!("../../../fixtures/unified_checks/static_reference_errors/project.dme"));let ordinal=filter_ordinal(&snapshot,"probe");let db=snapshot.native_raw_queries.as_ref().unwrap();let env=root().join("project.dme");let mut output=Vec::new();let injected=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));assert_eq!(snapshot.write_native_configured_checker(ordinal,"static_reference",&env,None,&snapshot.tree,&mut output).unwrap_err().raw_os_error(),Some(1450));assert!(output.is_empty());drop(injected);let quota=db.effect_graph_headroom_for_test(1).unwrap();let held=db.effect_graph_work_for_test();assert_eq!(snapshot.write_native_configured_checker(ordinal,"static_reference",&env,None,&snapshot.tree,&mut output).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert!(output.is_empty());assert_eq!(db.effect_graph_work_for_test(),held);drop(quota);let mut healthy=Vec::new();snapshot.write_native_configured_checker(ordinal,"static_reference",&env,None,&snapshot.tree,&mut healthy).unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;
 struct Fail(crate::daemon::control::Cancellation);impl io::Write for Fail{fn write(&mut self,_:&[u8])->io::Result<usize>{self.0.cancel();Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}let cancellation=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(cancellation.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));assert_eq!(snapshot.write_native_configured_checker(ordinal,"static_reference",&env,None,&snapshot.tree,&mut Fail(cancellation)).unwrap_err().raw_os_error(),Some(1450));drop(binding);assert_eq!(db.effect_graph_work_for_test(),0);struct Panic;impl io::Write for Panic{fn write(&mut self,_:&[u8])->io::Result<usize>{panic!("static reference output unwind")}fn flush(&mut self)->io::Result<()>{Ok(())}}assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(||snapshot.write_native_configured_checker(ordinal,"static_reference",&env,None,&snapshot.tree,&mut Panic))).is_err());assert_eq!(db.effect_graph_work_for_test(),0);let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"static_reference",&env,None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,healthy);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);
}

#[test]fn original_proc_reference_uses_actual_verb_and_fixed_builtin_declaration_kinds(){let snapshot=call_argument_snapshot(None,b"",include_bytes!("../../../fixtures/unified_checks/filter_static_builtin_reference/project.dme"));for(owner,name,path)in[("/datum/static_verb","probe","[\"datum\", \"static_verb\", \"verb\", \"wave\"]"),("/","global_probe","[\"proc\", \"abs\"]")]{let ordinal=original_callable_ordinal(&snapshot,owner,name);let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,"filter_call",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let rows=row["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),1,"{row}");assert_eq!(rows[0]["message"],format!("filter() called with non-string type keyword parameter value 'Some(Prefab(Pop {{ path: {path}, vars: {{}} }}))'"));}}

#[test]fn original_static_modified_prefabs_discard_modifiers_without_visiting_reference_arguments(){let snapshot=call_argument_snapshot(None,b"",include_bytes!("../../../fixtures/unified_checks/static_modified_prefab/project.dme"));let ordinal=filter_ordinal(&snapshot,"probe");let db=snapshot.native_raw_queries.as_ref().unwrap();let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,"static_reference",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert_eq!(row["diagnostics"].as_array().unwrap().len(),0,"{row}");let before=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"static_reference",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);assert_eq!(db.effect_graph_work_for_test(),0);}

#[test]fn original_iteration_ranges_keep_fixed_errors_hidden_hint_and_post_body_order(){let snapshot=call_argument_snapshot(Some(b"[diagnostics]
iteration_range='off'
iteration_noniterable_type='off'"),b"",include_bytes!("../../../fixtures/unified_checks/iteration_range_errors/project.dme"));let ordinal=filter_ordinal(&snapshot,"probe");let db=snapshot.native_raw_queries.as_ref().unwrap();let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,"iteration_range",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let rows=row["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),6,"{row}");let expected=[(5,"hint","iterating over a /datum which might not be an /atom"),(7,"error","iterating over a /datum/not_iterable which cannot be iterated"),(17,"error","iterating over a procpath which cannot be iterated"),(19,"error","iterating over a /datum/not_iterable which cannot be iterated"),(21,"error","for range loop body is never reached due to invalid range"),(23,"error","for range loop body is never reached due to invalid range")];for(row,(line,severity,message))in rows.iter().zip(expected){assert_eq!(row["line"],line);assert_eq!(row["column"],5);assert_eq!(row["severity"],severity);assert_eq!(row["message"],message);}let before=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"iteration_range",&root().join("project.dme"),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);assert_eq!(db.effect_graph_work_for_test(),0);}
#[test]fn original_iteration_ranges_use_actual_parent_chain_instead_of_path_prefix(){let snapshot=call_argument_snapshot(None,b"",include_bytes!("../../../fixtures/unified_checks/iteration_parent_types/project.dme"));let mut bytes=Vec::new();snapshot.write_native_configured_checker(filter_ordinal(&snapshot,"probe"),"iteration_range",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let rows=row["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),1,"{row}");assert_eq!(rows[0]["line"],8);assert_eq!(rows[0]["message"],"iterating over a /obj/odd_nonatom which cannot be iterated");}

#[test]fn original_iteration_ranges_actual_io_quota_writer_cancel_and_unwind_leave_no_partial_result(){
 let snapshot=call_argument_snapshot(None,b"",include_bytes!("../../../fixtures/unified_checks/iteration_range_errors/project.dme"));let ordinal=filter_ordinal(&snapshot,"probe");let db=snapshot.native_raw_queries.as_ref().unwrap();let env=root().join("project.dme");let mut output=Vec::new();let injected=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));assert_eq!(snapshot.write_native_configured_checker(ordinal,"iteration_range",&env,None,&snapshot.tree,&mut output).unwrap_err().raw_os_error(),Some(1450));assert!(output.is_empty());drop(injected);let quota=db.effect_graph_headroom_for_test(1).unwrap();let held=db.effect_graph_work_for_test();assert_eq!(snapshot.write_native_configured_checker(ordinal,"iteration_range",&env,None,&snapshot.tree,&mut output).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert!(output.is_empty());assert_eq!(db.effect_graph_work_for_test(),held);drop(quota);let mut healthy=Vec::new();snapshot.write_native_configured_checker(ordinal,"iteration_range",&env,None,&snapshot.tree,&mut healthy).unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;
 struct Fail(crate::daemon::control::Cancellation);impl io::Write for Fail{fn write(&mut self,_:&[u8])->io::Result<usize>{self.0.cancel();Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}let cancellation=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(cancellation.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));assert_eq!(snapshot.write_native_configured_checker(ordinal,"iteration_range",&env,None,&snapshot.tree,&mut Fail(cancellation)).unwrap_err().raw_os_error(),Some(1450));drop(binding);assert_eq!(db.effect_graph_work_for_test(),0);struct Panic;impl io::Write for Panic{fn write(&mut self,_:&[u8])->io::Result<usize>{panic!("static reference output unwind")}fn flush(&mut self)->io::Result<()>{Ok(())}}assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(||snapshot.write_native_configured_checker(ordinal,"iteration_range",&env,None,&snapshot.tree,&mut Panic))).is_err());assert_eq!(db.effect_graph_work_for_test(),0);let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"iteration_range",&env,None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,healthy);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);
}

#[test]fn original_iteration_ranges_strict_dispatch_keeps_exact_hint_error_and_source_role(){use crate::daemon::query::{self,SourceQuery};let snapshot=call_argument_snapshot(None,b"",include_bytes!("../../../fixtures/unified_checks/iteration_range_errors/project.dme"));let ordinal=filter_ordinal(&snapshot,"probe");let tree=snapshot.tree.clone();let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let request=query::QueryRequest{analysis_context:None,timeout_seconds:Some(300),project:root().join("project.dme"),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal,family:"iteration_range".into(),environment:root().join("project.dme"),configuration:None}]};let state=crate::runner_host::query_snapshot::QueryState{raw_snapshot:None,snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let mut forged=reply.clone();let mut row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();row["diagnostics"][0]["severity"]="warning".into();forged.jsonl=format!("{row}\n");assert!(query::validate_effect_batch_for_test(&request,&forged).is_err());row["diagnostics"][0]["severity"]="error".into();row["diagnostics"][0]["family"]="private_proc".into();forged.jsonl=format!("{row}\n");assert!(query::validate_effect_batch_for_test(&request,&forged).is_err());let mut mixed=request.clone();mixed.source_queries.push(SourceQuery::NativeConfiguredChecker{ordinal,family:"undefined_variable".into(),environment:root().join("project.dme"),configuration:None});let before=db.db().stats(dm_query::Kind(4)).computed;assert!(query::evaluate_snapshot(&mixed,&tree,&state).is_err());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);let foreign=call_argument_snapshot(None,b"",include_bytes!("../../../fixtures/unified_checks/iteration_range_errors/project.dme"));let mut bytes=b"prefix".to_vec();assert!(state.snapshot.as_ref().unwrap().write_native_configured_checker(ordinal,"iteration_range",&root().join("project.dme"),None,&foreign.tree,&mut bytes).is_err());assert_eq!(bytes,b"prefix");}
#[test]fn original_iteration_hint_obeys_global_display_threshold_and_not_observation_keys(){for(config,count)in[(b"[display]\nerror_level='warning'".as_slice(),5usize),(b"[display]\nerror_level='off'".as_slice(),0usize)]{let snapshot=call_argument_snapshot(Some(config),b"",include_bytes!("../../../fixtures/unified_checks/iteration_range_errors/project.dme"));let db=snapshot.native_raw_queries.as_ref().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;let mut bytes=Vec::new();snapshot.write_native_configured_checker(filter_ordinal(&snapshot,"probe"),"iteration_range",&root().join("project.dme"),None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert_eq!(row["diagnostics"].as_array().unwrap().len(),count,"{row}");assert!(db.db().stats(dm_query::Kind(4)).computed>before,"global display does not bypass actual evaluator");assert_eq!(db.effect_graph_work_for_test(),0);}}

#[test]fn original_undefined_declared_types_use_real_parameter_cursor_and_local_ledger(){let(host,environment)=original_declared_types_host(include_bytes!("../../../fixtures/unified_checks/undefined_declared_type/project.dme"),Some(b"[diagnostics]\nundefined_type='off'"));let current=host.query_state();let state=current.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();{let profile=snapshot.tree.checker_builtin_profile().unwrap();let query=dm_ir::ResolveQuery::Type(dm_ir::SymbolId::of("/missing"));eprintln!("ACTUAL_DECLARED_TYPE_DOMAIN path=/missing checker_present={} native={:?} node_present={} inventory_complete={}",snapshot.tree.checker_source_type_presence(profile,"/missing").unwrap(),dm_ir::Resolver::resolve(snapshot.tree.as_ref(),query),snapshot.tree.lookup_type(dm_ir::SymbolId::of("/missing")).is_some(),snapshot.tree.intrinsic_inventory_complete());}let ordinal=filter_ordinal(snapshot,"probe");let db=snapshot.native_raw_queries.as_ref().unwrap();let mut strict=b"prefix".to_vec();assert!(snapshot.write_native_configured_checker(ordinal,"call_arguments",&environment,None,&snapshot.tree,&mut strict).is_err());assert_eq!(strict,b"prefix");let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,"undefined_type",&environment,None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let rows=row["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),3,"{row}");for(row,(line,column))in rows.iter().zip([(3,29),(4,5),(5,5)]){assert_eq!(row["line"],line);assert_eq!(row["column"],column);assert_eq!(row["message"],"undefined type: /missing");assert_eq!(row["severity"],"error");}let before=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"undefined_type",&environment,None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);assert_eq!(db.effect_graph_work_for_test(),0);}

fn original_declared_types_host(source:&[u8],config:Option<&[u8]>)->(crate::runner_host::BuildHost,PathBuf){
 use crate::policy_request::AnalysisContext;use crate::request::{Command,BuildOutcome};
 let root=crate::test_scratch::dir("original-filter-flags-context");let project=root.join("project.dme");std::fs::write(&project,source).unwrap();std::fs::write(root.join("scopes.toml"),b"").unwrap();
 if let Some(bytes)=config{std::fs::write(root.join("SpacemanDMM.toml"),bytes).unwrap();}
 let args=vec!["prepare-query".to_owned(),project.to_string_lossy().into_owned()];let Command::Build(request)=crate::cli::parse(&args).unwrap()else{panic!("actual PrepareQuery parser")};let mut request=*request;request.no_cache=true;request.exact_inputs=true;request.workers=1;request.progress_enabled=false;request.cache_root=Some(root.join("cache"));let mut intent=PolicyInputRequest::default();intent.analysis_context=Some(AnalysisContext::OriginalChecker0290);intent.files=vec![PolicyInputFile{path:root.join("scopes.toml"),role:PolicyInputRole::Configuration,required:true},PolicyInputFile{path:root.join("SpacemanDMM.toml"),role:PolicyInputRole::Configuration,required:false}];request.policy_inputs=Some(intent);let mut host=crate::runner_host::BuildHost::default();let outcome=crate::request_runner::run_build_with_host(request,&mut host).unwrap();assert!(matches!(outcome,BuildOutcome::QueryPrepared{retained:true,..}));{let current=host.query_state();let state=current.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();snapshot.require_analysis_context(Some(AnalysisContext::OriginalChecker0290)).unwrap();assert!(snapshot.resolved.is_none());assert!(snapshot.native_policy_inputs.is_some());assert!(snapshot.native_workspace.is_none());let profile=snapshot.tree.checker_builtin_profile().unwrap();snapshot.tree.validate_checker_builtin_profile(profile).unwrap();} (host,project)
}
#[test]fn original_declared_types_actual_io_quota_writer_cancel_and_unwind_leave_no_partial_result(){
 let(host,env)=original_declared_types_host(include_bytes!("../../../fixtures/unified_checks/undefined_declared_type/project.dme"),None);let current=host.query_state();let state=current.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let ordinal=filter_ordinal(snapshot,"probe");let db=snapshot.native_raw_queries.as_ref().unwrap();let mut output=Vec::new();let injected=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));assert_eq!(snapshot.write_native_configured_checker(ordinal,"undefined_type",&env,None,&snapshot.tree,&mut output).unwrap_err().raw_os_error(),Some(1450));assert!(output.is_empty());drop(injected);let quota=db.effect_graph_headroom_for_test(1).unwrap();let held=db.effect_graph_work_for_test();assert_eq!(snapshot.write_native_configured_checker(ordinal,"undefined_type",&env,None,&snapshot.tree,&mut output).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert!(output.is_empty());assert_eq!(db.effect_graph_work_for_test(),held);drop(quota);let mut healthy=Vec::new();snapshot.write_native_configured_checker(ordinal,"undefined_type",&env,None,&snapshot.tree,&mut healthy).unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;
 struct Fail(crate::daemon::control::Cancellation);impl io::Write for Fail{fn write(&mut self,_:&[u8])->io::Result<usize>{self.0.cancel();Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}let cancellation=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(cancellation.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));assert_eq!(snapshot.write_native_configured_checker(ordinal,"undefined_type",&env,None,&snapshot.tree,&mut Fail(cancellation)).unwrap_err().raw_os_error(),Some(1450));drop(binding);assert_eq!(db.effect_graph_work_for_test(),0);struct Panic;impl io::Write for Panic{fn write(&mut self,_:&[u8])->io::Result<usize>{panic!("static reference output unwind")}fn flush(&mut self)->io::Result<()>{Ok(())}}assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(||snapshot.write_native_configured_checker(ordinal,"undefined_type",&env,None,&snapshot.tree,&mut Panic))).is_err());assert_eq!(db.effect_graph_work_for_test(),0);let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"undefined_type",&env,None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,healthy);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);
}

#[test]fn original_declared_type_strict_dispatch_preserves_untagged_errors_and_refuses_mixed_model_role(){use crate::daemon::query::{self,SourceQuery};use crate::policy_request::AnalysisContext;let(host,environment)=original_declared_types_host(include_bytes!("../../../fixtures/unified_checks/undefined_declared_type/project.dme"),None);let current=host.query_state();let state=current.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let ordinal=filter_ordinal(snapshot,"probe");let db=snapshot.native_raw_queries.as_ref().unwrap();let request=query::QueryRequest{analysis_context:Some(AnalysisContext::OriginalChecker0290),timeout_seconds:Some(300),project:environment.clone(),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",snapshot.tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal,family:"undefined_type".into(),environment:environment.clone(),configuration:None}]};let reply=query::evaluate_snapshot(&request,&snapshot.tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let mut forged=reply.clone();let mut row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();row["diagnostics"][0]["severity"]="warning".into();forged.jsonl=format!("{row}\n");assert!(query::validate_effect_batch_for_test(&request,&forged).is_err());let before=db.db().stats(dm_query::Kind(4)).computed;let mut mixed=request.clone();mixed.source_queries.push(SourceQuery::NativeConfiguredChecker{ordinal,family:"undefined_variable".into(),environment:environment.clone(),configuration:None});assert!(query::evaluate_snapshot(&mixed,&snapshot.tree,&state).is_err());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);let mut wrong=request;wrong.analysis_context=None;assert!(query::evaluate_snapshot(&wrong,&snapshot.tree,&state).is_err());let foreign=call_argument_snapshot(None,b"",b"/proc/probe()\n    return 0\n");let mut bytes=b"prefix".to_vec();assert!(snapshot.write_native_configured_checker(ordinal,"undefined_type",&environment,None,&foreign.tree,&mut bytes).is_err());assert_eq!(bytes,b"prefix");}

#[test]fn original_undefined_type_strips_modifiers_at_each_list_recursion_and_keeps_known_terminal(){let(host,environment)=original_declared_types_host(include_bytes!("../../../fixtures/unified_checks/undefined_recursive_modifiers/project.dme"),None);let current=host.query_state();let state=current.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let ordinal=filter_ordinal(snapshot,"probe");let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,"undefined_type",&environment,None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let rows=row["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),3,"{row}");for(row,(line,column))in rows.iter().zip([(2,59),(2,95),(4,5)]){assert_eq!(row["line"],line);assert_eq!(row["column"],column);assert_eq!(row["message"],"undefined type: /missing");}let db=snapshot.native_raw_queries.as_ref().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"undefined_type",&environment,None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);assert_eq!(db.effect_graph_work_for_test(),0);}

fn original_switch_case_host(source:&[u8],children:&[(&str,&[u8])],config:Option<&[u8]>)->(crate::runner_host::BuildHost,PathBuf){
 use crate::policy_request::AnalysisContext;use crate::request::{Command,BuildOutcome};
 let root=crate::test_scratch::dir("original-switch-case-context");let project=root.join("project.dme");std::fs::write(&project,source).unwrap();std::fs::write(root.join("scopes.toml"),b"").unwrap();
 if let Some(bytes)=config{std::fs::write(root.join("SpacemanDMM.toml"),bytes).unwrap();}
 for(name,bytes)in children{std::fs::write(root.join(name),bytes).unwrap();}
 let args=vec!["prepare-query".to_owned(),project.to_string_lossy().into_owned()];let Command::Build(request)=crate::cli::parse(&args).unwrap()else{panic!("actual PrepareQuery parser")};let mut request=*request;request.no_cache=true;request.exact_inputs=true;request.workers=1;request.progress_enabled=false;request.cache_root=Some(root.join("cache"));let mut intent=PolicyInputRequest::default();intent.analysis_context=Some(AnalysisContext::OriginalChecker0290);intent.files=vec![PolicyInputFile{path:root.join("scopes.toml"),role:PolicyInputRole::Configuration,required:true},PolicyInputFile{path:root.join("SpacemanDMM.toml"),role:PolicyInputRole::Configuration,required:false}];request.policy_inputs=Some(intent);let mut host=crate::runner_host::BuildHost::default();let outcome=crate::request_runner::run_build_with_host(request,&mut host).unwrap();assert!(matches!(outcome,BuildOutcome::QueryPrepared{retained:true,..}));{let current=host.query_state();let state=current.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();snapshot.require_analysis_context(Some(AnalysisContext::OriginalChecker0290)).unwrap();assert!(snapshot.resolved.is_none());assert!(snapshot.native_policy_inputs.is_some());assert!(snapshot.native_workspace.is_none());let profile=snapshot.tree.checker_builtin_profile().unwrap();snapshot.tree.validate_checker_builtin_profile(profile).unwrap();} (host,project)
}
#[test]fn original_switch_or_warning_keeps_newline_brace_and_final_reader_locations(){
 for(source,children,line,column,kind)in[(include_bytes!("../../../fixtures/unified_checks/switch_case_inline_try/project.dme").as_slice(),Vec::<(&str,&[u8])>::new(),6,21,"source"),(include_bytes!("../../../fixtures/unified_checks/switch_case_inline_if_default/project.dme").as_slice(),Vec::<(&str,&[u8])>::new(),6,21,"source"),(include_bytes!("../../../fixtures/unified_checks/switch_case_inline_if_else/project.dme").as_slice(),Vec::<(&str,&[u8])>::new(),8,21,"source"),(include_bytes!("../../../fixtures/unified_checks/switch_case_inline_simple/project.dme").as_slice(),Vec::<(&str,&[u8])>::new(),1,57,"source"),(include_bytes!("../../../fixtures/unified_checks/switch_case_inline_if/project.dme").as_slice(),Vec::<(&str,&[u8])>::new(),5,9,"source"),(include_bytes!("../../../fixtures/unified_checks/switch_case_inline_while/project.dme").as_slice(),Vec::<(&str,&[u8])>::new(),4,21,"source"),(include_bytes!("../../../fixtures/unified_checks/switch_case_mixed_unit/project.dme").as_slice(),Vec::<(&str,&[u8])>::new(),5,2,"source"),(include_bytes!("../../../fixtures/unified_checks/switch_case_explicit_indented/project.dme").as_slice(),Vec::new(),5,9,"source"),(include_bytes!("../../../fixtures/unified_checks/switch_case_next/project.dme").as_slice(),Vec::<(&str,&[u8])>::new(),4,21,"source"),(include_bytes!("../../../fixtures/unified_checks/switch_case_dedent/project.dme").as_slice(),Vec::new(),4,21,"source"),(include_bytes!("../../../fixtures/unified_checks/switch_case_explicit/project.dme").as_slice(),Vec::new(),1,61,"source"),(include_bytes!("../../../fixtures/unified_checks/switch_case_included/project.dme").as_slice(),vec![("child.dm",include_bytes!("../../../fixtures/unified_checks/switch_case_included/child.dm").as_slice())],2,1,"reader_cursor"),(include_bytes!("../../../fixtures/unified_checks/switch_case_include_then_proc/project.dme").as_slice(),vec![("child.dm",include_bytes!("../../../fixtures/unified_checks/switch_case_include_then_proc/child.dm").as_slice())],4,21,"source")]{let(host,environment)=original_switch_case_host(source,&children,Some(b"[diagnostics]\nswitch_case_or='off'"));let current=host.query_state();let state=current.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let ordinal=filter_ordinal(snapshot,"probe");let db=snapshot.native_raw_queries.as_ref().unwrap();let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,"switch_case",&environment,None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let rows=row["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),1,"{row}");assert_eq!(rows[0]["severity"],"warning");assert_eq!(rows[0]["line"],line);assert_eq!(rows[0]["column"],column);assert_eq!(rows[0]["location_kind"],kind);assert_eq!(rows[0]["message"],"Elements in a switch-case branch separated by ||, this is likely in error and should be replaced by a comma");if !children.is_empty()&&kind=="source"{assert!(rows[0]["file"].as_str().unwrap().ends_with("child.dm"));}if kind=="reader_cursor"{assert!(rows[0]["expanded_span"].is_null());let physical=std::fs::canonicalize(&environment).unwrap();assert_eq!(rows[0]["file"],physical.to_string_lossy().as_ref());}let before=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"switch_case",&environment,None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);assert_eq!(db.effect_graph_work_for_test(),0);}
}

#[test]fn original_switch_case_actual_io_quota_writer_cancel_and_unwind_leave_no_partial_result(){
 let(host,env)=original_switch_case_host(include_bytes!("../../../fixtures/unified_checks/switch_case_next/project.dme"),&[],None);let current=host.query_state();let state=current.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let ordinal=filter_ordinal(snapshot,"probe");let db=snapshot.native_raw_queries.as_ref().unwrap();let mut output=Vec::new();let injected=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));assert_eq!(snapshot.write_native_configured_checker(ordinal,"switch_case",&env,None,&snapshot.tree,&mut output).unwrap_err().raw_os_error(),Some(1450));assert!(output.is_empty());drop(injected);let quota=db.effect_graph_headroom_for_test(1).unwrap();let held=db.effect_graph_work_for_test();assert_eq!(snapshot.write_native_configured_checker(ordinal,"switch_case",&env,None,&snapshot.tree,&mut output).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert!(output.is_empty());assert_eq!(db.effect_graph_work_for_test(),held);drop(quota);let mut healthy=Vec::new();snapshot.write_native_configured_checker(ordinal,"switch_case",&env,None,&snapshot.tree,&mut healthy).unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;
 struct Fail(crate::daemon::control::Cancellation);impl io::Write for Fail{fn write(&mut self,_:&[u8])->io::Result<usize>{self.0.cancel();Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}let cancellation=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(cancellation.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));assert_eq!(snapshot.write_native_configured_checker(ordinal,"switch_case",&env,None,&snapshot.tree,&mut Fail(cancellation)).unwrap_err().raw_os_error(),Some(1450));drop(binding);assert_eq!(db.effect_graph_work_for_test(),0);struct Panic;impl io::Write for Panic{fn write(&mut self,_:&[u8])->io::Result<usize>{panic!("switch diagnostic output unwind")}fn flush(&mut self)->io::Result<()>{Ok(())}}assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(||snapshot.write_native_configured_checker(ordinal,"switch_case",&env,None,&snapshot.tree,&mut Panic))).is_err());assert_eq!(db.effect_graph_work_for_test(),0);let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"switch_case",&env,None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,healthy);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);
}


#[test]fn original_switch_case_strict_reply_binds_reader_cursor_without_fabricating_a_byte_span(){use crate::daemon::query::{self,SourceQuery};use crate::policy_request::AnalysisContext;let(host,environment)=original_switch_case_host(include_bytes!("../../../fixtures/unified_checks/switch_case_included/project.dme"),&[("child.dm",include_bytes!("../../../fixtures/unified_checks/switch_case_included/child.dm").as_slice())],None);let current=host.query_state();let state=current.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let ordinal=filter_ordinal(snapshot,"probe");let db=snapshot.native_raw_queries.as_ref().unwrap();let request=query::QueryRequest{analysis_context:Some(AnalysisContext::OriginalChecker0290),timeout_seconds:Some(300),project:environment.clone(),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",snapshot.tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal,family:"switch_case".into(),environment:environment.clone(),configuration:None}]};let reply=query::evaluate_snapshot(&request,&snapshot.tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let mut forged=reply.clone();let mut row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();assert_eq!(row["diagnostics"][0]["location_kind"],"reader_cursor");assert!(row["diagnostics"][0]["expanded_span"].is_null());row["diagnostics"][0]["location_kind"]="source".into();forged.jsonl=format!("{row}\n");assert!(query::validate_effect_batch_for_test(&request,&forged).is_err());let before=db.db().stats(dm_query::Kind(4)).computed;let mut mixed=request.clone();mixed.source_queries.push(SourceQuery::NativeConfiguredChecker{ordinal,family:"undefined_variable".into(),environment:environment.clone(),configuration:None});assert!(query::evaluate_snapshot(&mixed,&snapshot.tree,&state).is_err());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);let mut wrong=request;wrong.analysis_context=None;assert!(query::evaluate_snapshot(&wrong,&snapshot.tree,&state).is_err());let foreign=call_argument_snapshot(None,b"",b"/proc/probe()\n    return 0\n");let mut bytes=b"prefix".to_vec();assert!(snapshot.write_native_configured_checker(ordinal,"switch_case",&environment,None,&foreign.tree,&mut bytes).is_err());assert_eq!(bytes,b"prefix");}

#[test]fn original_switch_do_warning_precedes_distinct_fixed_flow_error_and_strict_reply(){
 use crate::daemon::query::{self,SourceQuery};use crate::policy_request::AnalysisContext;
 let(host,environment)=original_switch_case_host(include_bytes!("../../../fixtures/unified_checks/switch_case_inline_do/project.dme"),&[],Some(b"[diagnostics]\nswitch_case_or='off'\ndo_while_unreachable='off'"));let current=host.query_state();let state=current.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let ordinal=filter_ordinal(snapshot,"probe");let db=snapshot.native_raw_queries.as_ref().unwrap();let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,"switch_case",&environment,None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let rows=row["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),2,"{row}");assert_eq!(row["untagged_companions"],serde_json::json!(["do_while_unreachable"]));assert_eq!((&rows[0]["family"],&rows[0]["severity"],&rows[0]["line"],&rows[0]["column"]),(&serde_json::json!("switch_case_or"),&serde_json::json!("warning"),&serde_json::json!(5),&serde_json::json!(21)));assert_eq!((&rows[1]["family"],&rows[1]["severity"],&rows[1]["line"],&rows[1]["column"]),(&serde_json::json!("do_while_unreachable"),&serde_json::json!("error"),&serde_json::json!(3),&serde_json::json!(20)));assert_eq!(rows[1]["message"],"do while terminates without ever reaching condition");assert_eq!(rows[1]["location_kind"],"source");
 let before=db.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"switch_case",&environment,None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);assert_eq!(db.effect_graph_work_for_test(),0);
 let request=query::QueryRequest{analysis_context:Some(AnalysisContext::OriginalChecker0290),timeout_seconds:Some(300),project:environment.clone(),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",snapshot.tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:vec![SourceQuery::NativeConfiguredChecker{ordinal,family:"switch_case".into(),environment,configuration:None}]};let reply=query::evaluate_snapshot(&request,&snapshot.tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();for(field,value)in[("severity",serde_json::json!("warning")),("family",serde_json::json!("switch_case_or")),("location_kind",serde_json::json!("parser_synthetic")),("location_kind",serde_json::json!("reader_cursor"))]{let mut forged=reply.clone();let mut document:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();document["diagnostics"][1][field]=value;forged.jsonl=format!("{document}\n");assert!(query::validate_effect_batch_for_test(&request,&forged).is_err(),"forged fixed flow {field}");}
}
#[test]fn original_switch_fixed_companion_obeys_only_global_display_threshold(){for(config,count)in[(b"[display]\nerror_level='error'".as_slice(),1usize),(b"[display]\nerror_level='off'".as_slice(),0usize)]{let(host,environment)=original_switch_case_host(include_bytes!("../../../fixtures/unified_checks/switch_case_inline_do/project.dme"),&[],Some(config));let current=host.query_state();let state=current.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;let mut bytes=Vec::new();snapshot.write_native_configured_checker(filter_ordinal(snapshot,"probe"),"switch_case",&environment,None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert_eq!(row["diagnostics"].as_array().unwrap().len(),count,"{row}");if count==1{assert_eq!(row["diagnostics"][0]["family"],"do_while_unreachable");assert_eq!(row["diagnostics"][0]["severity"],"error");}assert!(db.db().stats(dm_query::Kind(4)).computed>before);assert_eq!(db.effect_graph_work_for_test(),0);}}

#[test]fn original_declared_type_negative_dependency_changes_on_actual_source_declaration_same_db(){
 use crate::policy_request::AnalysisContext;use crate::request::{Command,BuildOutcome};
 let source=b"/proc/probe(missing/value)\n    return value\n";let(mut host,environment)=original_declared_types_host(source,None);let queries=host.query_db().clone();
 let first_revision={let current=host.query_state();let state=current.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let mut bytes=Vec::new();snapshot.write_native_configured_checker(filter_ordinal(snapshot,"probe"),"undefined_type",&environment,None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert_eq!(row["diagnostics"].as_array().unwrap().len(),1,"{row}");assert_eq!(row["diagnostics"][0]["message"],"undefined type: /missing");let profile=snapshot.tree.checker_builtin_profile().unwrap();assert!(!snapshot.tree.checker_source_type_presence(profile,"/missing").unwrap());snapshot.source_revision};
 std::fs::write(&environment,[source.as_slice(),b"\n/missing\n"].concat()).unwrap();let root=environment.parent().unwrap();let args=vec!["prepare-query".to_owned(),environment.to_string_lossy().into_owned()];let Command::Build(request)=crate::cli::parse(&args).unwrap()else{panic!("actual PrepareQuery parser")};let mut request=*request;request.no_cache=true;request.exact_inputs=true;request.workers=1;request.progress_enabled=false;request.cache_root=Some(root.join("cache"));let mut intent=PolicyInputRequest::default();intent.analysis_context=Some(AnalysisContext::OriginalChecker0290);intent.files=vec![PolicyInputFile{path:root.join("scopes.toml"),role:PolicyInputRole::Configuration,required:true},PolicyInputFile{path:root.join("SpacemanDMM.toml"),role:PolicyInputRole::Configuration,required:false}];request.policy_inputs=Some(intent);assert!(matches!(crate::request_runner::run_build_with_host(request,&mut host).unwrap(),BuildOutcome::QueryPrepared{retained:true,..}));assert!(std::sync::Arc::ptr_eq(&queries,host.query_db()));
 let current=host.query_state();let state=current.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();assert_ne!(snapshot.source_revision,first_revision);let profile=snapshot.tree.checker_builtin_profile().unwrap();assert!(snapshot.tree.checker_source_type_presence(profile,"/missing").unwrap());let id=dm_ir::SymbolId::of("/missing");assert!(snapshot.tree.lookup_type(id).is_some());assert_eq!(dm_ir::Resolver::resolve(snapshot.tree.as_ref(),dm_ir::ResolveQuery::Type(id)),dm_ir::ResolvedMeaning::Symbol(id));let ordinal=filter_ordinal(snapshot,"probe");let mut bytes=Vec::new();snapshot.write_native_configured_checker(ordinal,"undefined_type",&environment,None,&snapshot.tree,&mut bytes).unwrap();let row:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert!(row["diagnostics"].as_array().unwrap().is_empty(),"{row}");let computed=queries.db().stats(dm_query::Kind(4)).computed;let mut warm=Vec::new();snapshot.write_native_configured_checker(ordinal,"undefined_type",&environment,None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(queries.db().stats(dm_query::Kind(4)).computed,computed);assert_eq!(queries.effect_graph_work_for_test(),0);
}

#[cfg(debug_assertions)]#[test]fn actual_original_body_union_page_checker_and_effects_share_one_evaluation(){
 let source=b"/proc/probe()\n    if(1)\n        filter(type=5)\n    return 0\n/proc/other()\n    return 1\n";let(host,environment)=original_filter_flags_host(source);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let tree=&snapshot.tree;let db=snapshot.native_raw_queries.as_ref().unwrap();let input=snapshot.original_checker_request_input(tree).unwrap().input();let source=dm_analysis::checker_effects::EffectSource::new(input.archive(),input.profile()).unwrap();
 let evaluations=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();let before=db.db().stats(dm_query::Kind(17)).computed;let page=snapshot.native_effect_source_page(input,0,2,&environment,None,tree).unwrap();assert_eq!(page.len(),2);assert_eq!(db.db().stats(dm_query::Kind(17)).computed-before,2);assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-evaluations,2);for index in 0..page.len(){assert_eq!(page.with_original_body(index,input,|body|body.original_evaluation_count()).unwrap(),1);}
 let ordinal=filter_ordinal(snapshot,"probe")as usize;let rows=snapshot.with_original_checker_body(ordinal,&environment,None,tree,|body|{assert_eq!(body.original_evaluation_count(),1);Ok(body.with_original_diagnostics(input,|rows|rows.iter().map(|row|(row.diagnostic().family.to_owned(),row.registration_tag(),row.default_level())).collect::<Vec<_>>()).unwrap())}).unwrap();
 let flow=rows.iter().position(|row|row.0=="control_condition_static").expect("actual flow diagnostic");let filter=rows.iter().position(|row|row.0=="filter_call").expect("actual filter diagnostic");assert!(flow<filter,"interleaved SAME evaluation must preserve flow-before-body diagnostic order: {rows:?}");
 let report=snapshot.native_effect_source_report(input,2,dm_analysis::checker_effects::EffectReportPhase::Purity,&environment,None,tree).unwrap();let _=report;let mut keywords=Vec::new();snapshot.write_native_keyword_overrides(&environment,None,tree,&mut keywords).unwrap();assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-evaluations,2,"whole keyword finalization must not re-enter any evaluator");assert_eq!(db.db().stats(dm_query::Kind(17)).computed-before,2,"PAGE, checker and whole graph/report reuse the SAME actual BODY");let parsed=db.db().stats(dm_query::Kind(4)).computed;let computed=db.db().stats(dm_query::Kind(17)).computed;
 let again=snapshot.native_effect_source_page(input,0,2,&environment,None,tree).unwrap();assert_eq!(again.len(),2);snapshot.with_original_checker_body(ordinal,&environment,None,tree,|body|{assert_eq!(body.original_evaluation_count(),1);Ok(())}).unwrap();assert_eq!(db.db().stats(dm_query::Kind(17)).computed,computed);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,parsed);assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-evaluations,2);assert_eq!(db.effect_graph_work_for_test(),0);
}

#[cfg(debug_assertions)]#[test]fn original_body_union_keeps_one_ordered_setting_prelude_and_real_body_events(){
 use dm_analysis::checker_effects::OriginalDiagnosticPhase;let source=b"/proc/probe()\n    set SpacemanDMM_private_proc=2\n    set mystery=1\n    set SpacemanDMM_not_known=1\n    if(1)\n        filter(type=5)\n";let(host,environment)=original_filter_flags_host(source);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let ordinal=filter_ordinal(snapshot,"probe")as usize;let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();let rows=snapshot.with_original_checker_body(ordinal,&environment,None,&snapshot.tree,|body|{Ok(body.with_original_diagnostics(input,|rows|rows.iter().map(|row|(row.phase(),row.diagnostic().family,row.diagnostic().message.clone(),row.registration_tag(),row.default_level())).collect::<Vec<_>>()).unwrap())}).unwrap();
 let profile=snapshot.tree.checker_builtin_profile().unwrap();let identity=input.archive().callables().identity_for_member(input.archive().occurrences().get(ordinal).unwrap().member).unwrap();let strict=dm_analysis::checker_return_facts::PuritySettingsPermit::issue(input.archive(),profile,identity).err().expect("ordinary effect-only prefix contract must stay strict");assert!(strict.contains("effect mode has no exact policy"),"{strict}");
 let prelude=rows.iter().filter(|row|row.0==OriginalDiagnosticPhase::Prelude).collect::<Vec<_>>();assert_eq!(prelude.len(),3,"{rows:?}");assert_eq!((prelude[0].1,prelude[0].2.as_str(),prelude[0].3),("invalid_lint_directive_value","invalid value for set Base { term: Spanned { location: Location { file: FileId(1), line: 2, column: 34 }, elem: Int(2) }, follow: [] }",None));assert_eq!(prelude[1].1,"unknown_setting");assert_eq!(prelude[1].3,None);assert_eq!(prelude[2].1,"unknown_linter_setting");assert_eq!(prelude[2].3,Some("unknown_linter_setting"));assert!(prelude.iter().all(|row|row.4==dm_analysis::check_policy::DiagnosticSeverity::Warning));let last_prefix=rows.iter().rposition(|row|row.0==OriginalDiagnosticPhase::Prelude).unwrap();let flow=rows.iter().position(|row|row.1=="control_condition_static").unwrap();let filter=rows.iter().position(|row|row.1=="filter_call").unwrap();assert!(last_prefix<flow&&flow<filter,"{rows:?}");assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,1);
 // Exact complete message/default sequence from the pinned same-byte source
 // in setting-prelude-exact-pinned-probe.json; no body family is filtered out.
 assert_eq!(rows.iter().map(|row|(row.2.as_str(),row.4)).collect::<Vec<_>>(),[
  ("invalid value for set Base { term: Spanned { location: Location { file: FileId(1), line: 2, column: 34 }, elem: Int(2) }, follow: [] }",dm_analysis::check_policy::DiagnosticSeverity::Warning),
  ("unknown setting \"mystery\"",dm_analysis::check_policy::DiagnosticSeverity::Warning),
  ("unknown linter setting \"SpacemanDMM_not_known\"",dm_analysis::check_policy::DiagnosticSeverity::Warning),
  ("control flow condition is a static term",dm_analysis::check_policy::DiagnosticSeverity::Error),
  ("filter() called with non-string type keyword parameter value 'Some(Float(5.0))'",dm_analysis::check_policy::DiagnosticSeverity::Error),
  ("if condition is always true",dm_analysis::check_policy::DiagnosticSeverity::Error),
 ]);

}

#[cfg(debug_assertions)]#[test]fn original_body_union_fixed_warning_precedes_error_and_effect_report_borrows_same_diagnostic(){
 let(host,environment)=original_filter_flags_host(b"/proc/probe()\n    spawn(0)\n        return missing_in_spawn\n");let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let ordinal=filter_ordinal(snapshot,"probe")as usize;let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();let rows=snapshot.with_original_checker_body(ordinal,&environment,None,&snapshot.tree,|body|Ok(body.with_original_diagnostics(input,|rows|rows.iter().map(|row|(row.diagnostic().family,row.diagnostic().message.clone(),row.default_level())).collect::<Vec<_>>()).unwrap())).unwrap();
 let warning=rows.iter().position(|row|row.0=="spawn_return").unwrap();let error=rows.iter().position(|row|row.0=="undefined_variable").unwrap();assert!(warning<error,"{rows:?}");assert_eq!(rows[warning].2,dm_analysis::check_policy::DiagnosticSeverity::Warning);assert_eq!(rows[error].2,dm_analysis::check_policy::DiagnosticSeverity::Error);
 let report=snapshot.native_effect_source_report(input,1,dm_analysis::checker_effects::EffectReportPhase::Purity,&environment,None,&snapshot.tree).unwrap();assert_eq!(report.iter().filter(|row|row.diagnostic.family=="spawn_return").count(),1);assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,1,"the report must borrow the existing single physical diagnostic owner");
}

#[test]fn original_body_input_does_not_retain_the_diagnostic_receipt_or_retired_analysis_payload(){
 let(input,receipt)={let(host,_environment)=original_filter_flags_host(b"/proc/probe()\n    return 1\n");let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=Arc::clone(snapshot.original_checker_request_input(&snapshot.tree).unwrap().input());let receipt=Arc::downgrade(snapshot.diagnostic_declarations.as_ref().unwrap());input.require_original_checker_source().unwrap();(input,receipt)};
 assert_eq!(receipt.strong_count(),0,"an escaped input cannot keep the actual diagnostic receipt/records alive");assert!(input.require_original_checker_source().is_err(),"expired original proof must refuse before any body result");let called=std::cell::Cell::new(0);let admission=dm_analysis::checker_effects::ExecutionAdmission::default();let direct=input.compute_original_body_checked_using_admitted_controlled(0,input.archive().tree(),&admission,&|_,_|{called.set(called.get()+1);Err(dm_tree::frontend::BodySyntaxFailure::Operational(io::Error::from_raw_os_error(1450)))},&||Ok(()));assert!(direct.is_err(),"expired direct typed path must refuse");assert_eq!(called.get(),0,"expiry must refuse BEFORE any supplied actual body callback");let mut weak=0;input.visit_storage(&mut|view|if let dm_analysis::checker_effects::Storage::Buffer{owner,logical,capacity,..}=view{if owner=="checker.original_receipt_weak_backing"{assert_eq!(logical,0);assert!(capacity>=std::mem::size_of::<dm_tree::diagnostic_declarations::DiagnosticDeclarationReceipt>());weak+=1}});assert_eq!(weak,1);
}

#[cfg(debug_assertions)]#[test]fn original_body_diagnostic_sweep_orders_all_settings_before_bodies_and_reuses_actual_contributions(){
 let source=b"/proc/first()\n    filter(type=5)\n/proc/second()\n    set mystery=1\n    doesnotexist\n";let(host,environment)=original_filter_flags_host(source);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();let mut rows=Vec::new();snapshot.visit_original_body_diagnostics(&environment,None,&snapshot.tree,|ordinal,row|{rows.push((ordinal,row.phase(),row.diagnostic().family,row.diagnostic().message.clone()));Ok(())}).unwrap();
 assert_eq!(rows.iter().map(|row|row.2).collect::<Vec<_>>(),["unknown_setting","filter_call","undefined_variable"],"{rows:?}");assert_eq!(rows[0].0,filter_ordinal(snapshot,"second")as usize);assert_eq!(rows[1].0,filter_ordinal(snapshot,"first")as usize);assert_eq!(rows[2].0,filter_ordinal(snapshot,"second")as usize);assert_eq!(rows[0].1,dm_analysis::checker_effects::OriginalDiagnosticPhase::Prelude);assert!(rows[1..].iter().all(|row|row.1==dm_analysis::checker_effects::OriginalDiagnosticPhase::Body));assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,2);
 let computed=db.db().stats(dm_query::Kind(17)).computed;let mut invoked=0;let error=snapshot.visit_original_body_diagnostics(&environment,None,&snapshot.tree,|_,_|{invoked+=1;Err(std::io::Error::from_raw_os_error(1450))}).unwrap_err();assert_eq!(invoked,1);assert_eq!(error.raw_os_error(),Some(1450));let mut retry=Vec::new();snapshot.visit_original_body_diagnostics(&environment,None,&snapshot.tree,|ordinal,row|{retry.push((ordinal,row.phase(),row.diagnostic().family,row.diagnostic().message.clone()));Ok(())}).unwrap();assert_eq!(retry,rows);assert_eq!(db.db().stats(dm_query::Kind(17)).computed,computed);assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,2);assert_eq!(db.effect_graph_work_for_test(),0);
}

#[cfg(debug_assertions)]#[test]fn original_body_missing_prefab_and_procpath_fields_preserve_real_rows_and_skipped_arguments(){
 let source=b"/datum/path_control\n    var/value\n    proc/work()\n        return 0\n/proc/probe()\n    var/value = /datum/not_declared\n    new /datum/not_declared(doesnotexist)\n    var/callee/C\n    C.proc.not_a_proc_field\n    C.proc:not_a_proc_field\n/proc/constructors()\n    new /datum/path_control(doesnotexist)\n    new /world(doesnotexist)\n";
 let(host,environment)=original_filter_flags_host(source);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let db=snapshot.native_raw_queries.as_ref().unwrap();let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();
 let mut rows=Vec::new();for name in ["probe","constructors"]{let ordinal=filter_ordinal(snapshot,name)as usize;snapshot.with_original_checker_body(ordinal,&environment,None,&snapshot.tree,|body|{body.with_original_diagnostics(input,|found|{for row in found{rows.push((row.diagnostic().family,row.diagnostic().message.clone(),row.registration_tag(),row.default_level()));}}).map_err(std::io::Error::other)?;Ok(())}).unwrap();}
 assert_eq!(rows.iter().map(|row|row.1.as_str()).collect::<Vec<_>>(),["failed to resolve path /datum/not_declared","failed to resolve path /datum/not_declared","undefined field: \"not_a_proc_field\" on procpath","undefined var: \"doesnotexist\"","undefined var: \"doesnotexist\""]);assert_eq!(rows.iter().map(|row|row.0).collect::<Vec<_>>(),["unresolved_prefab","unresolved_prefab","undefined_field_procpath","undefined_variable","undefined_variable"]);assert!(rows.iter().take(3).all(|row|row.2.is_none()&&row.3==dm_analysis::check_policy::DiagnosticSeverity::Error));assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,2);
 let computed=db.db().stats(dm_query::Kind(17)).computed;for name in ["probe","constructors"]{snapshot.with_original_checker_body(filter_ordinal(snapshot,name)as usize,&environment,None,&snapshot.tree,|body|{assert_eq!(body.original_evaluation_count(),1);Ok(())}).unwrap();}assert_eq!(db.db().stats(dm_query::Kind(17)).computed,computed);assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,2);assert_eq!(db.effect_graph_work_for_test(),0);
 let mut prefix=b"actual-prefix".to_vec();let error=snapshot.write_native_configured_checker(filter_ordinal(snapshot,"probe"),"filter_call",&environment,None,&snapshot.tree,&mut prefix).unwrap_err();assert!(error.to_string().contains("fixed original diagnostic needs the actual combined BODY observer"),"{error}");assert_eq!(prefix,b"actual-prefix");
}

#[cfg(debug_assertions)]#[test]fn original_body_delivery_uses_actual_checker_type_order_over_authored_contribution_order(){
 let source=b"/datum/z/proc/zeta()\n    filter(type=5)\n/datum/a/proc/alpha()\n    set mystery=1\n    doesnotexist\n";let(host,environment)=original_filter_flags_host(source);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();let page=snapshot.native_effect_source_page(input,0,1,&environment,None,&snapshot.tree).unwrap();assert_eq!(page.len(),1);assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,1);let alpha=original_callable_ordinal(snapshot,"/datum/a","alpha")as usize;let zeta=original_callable_ordinal(snapshot,"/datum/z","zeta")as usize;let mut rows=Vec::new();snapshot.visit_original_body_diagnostics(&environment,None,&snapshot.tree,|ordinal,row|{rows.push((ordinal,row.phase(),row.diagnostic().family,row.diagnostic().message.clone()));Ok(())}).unwrap();assert_eq!(rows.iter().map(|row|(row.0,row.2)).collect::<Vec<_>>(),[(alpha,"unknown_setting"),(alpha,"undefined_variable"),(zeta,"filter_call")]);assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,2);let computed=db.db().stats(dm_query::Kind(17)).computed;let mut retry=Vec::new();snapshot.visit_original_body_diagnostics(&environment,None,&snapshot.tree,|ordinal,row|{retry.push((ordinal,row.phase(),row.diagnostic().family,row.diagnostic().message.clone()));Ok(())}).unwrap();assert_eq!(retry,rows);assert_eq!(db.db().stats(dm_query::Kind(17)).computed,computed);assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,2);assert_eq!(db.effect_graph_work_for_test(),0);
}

#[cfg(all(windows,debug_assertions))]#[test]fn original_body_environment_requires_real_requested_acquired_alias_before_kind4(){
 let source=b"/proc/probe()\n    return 0\n";let(host,environment)=original_filter_flags_host_purpose(source,false);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let capture=snapshot.named_policy_capture(&snapshot.tree).unwrap();let actual=std::fs::canonicalize(&environment).unwrap();assert_ne!(actual,environment);assert!(capture.compiled_source_file(&actual).is_some(),"real opened primary is compiled source");assert!(capture.compiled_source_file(&environment).is_none(),"equal filesystem spelling does not fabricate a requested acquired alias");let db=snapshot.native_raw_queries.as_ref().unwrap();let before=db.db().stats(dm_query::Kind(4)).computed;let mut called=false;let error=snapshot.with_original_checker_body(filter_ordinal(snapshot,"probe")as usize,&environment,None,&snapshot.tree,|_|{called=true;Ok(())}).unwrap_err();assert!(error.to_string().contains("purity environment is not an original compiled source"),"{error}");assert!(!called);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before);assert_eq!(db.effect_graph_work_for_test(),0);drop(state);
 let(host,environment)=original_filter_flags_host(source);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let capture=snapshot.named_policy_capture(&snapshot.tree).unwrap();let compiled=capture.compiled_source_file(&environment).expect("actual requested provider/acquisition alias is recorded");assert!(compiled.is_compiled());assert_eq!(compiled.role(),dm_analysis::policy_inputs::PolicyRole::DmSource);snapshot.with_original_checker_body(filter_ordinal(snapshot,"probe")as usize,&environment,None,&snapshot.tree,|body|{assert_eq!(body.original_evaluation_count(),1);Ok(())}).unwrap();
}

#[cfg(debug_assertions)]#[test]fn original_switch_rand_range_runs_before_selector_and_shares_the_actual_body_contribution(){
 let(host,environment)=original_filter_flags_host(b"/proc/probe()\n    switch(rand(1,3))\n        if(5)\n            return missing_after_rand\n");let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let ordinal=filter_ordinal(snapshot,"probe")as usize;let db=snapshot.native_raw_queries.as_ref().unwrap();let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();
 let read=||snapshot.with_original_checker_body(ordinal,&environment,None,&snapshot.tree,|body|{assert_eq!(body.original_evaluation_count(),1);Ok(body.with_original_diagnostics(input,|rows|rows.iter().map(|row|(row.diagnostic().family,row.diagnostic().message.clone(),row.default_level())).collect::<Vec<_>>()).unwrap())}).unwrap();let rows=read();let random=rows.iter().enumerate().filter(|(_,row)|row.0=="switch_rand_range").collect::<Vec<_>>();assert_eq!(random.len(),2,"{rows:?}");assert_eq!(random[0].1.1,"Case range '5 to 5' will never trigger as it is outside the rand() range 1 to 3");assert_eq!(random[1].1.1,"Switch branches on rand() with range 1 to 3 but no case branch triggers for 1");let missing=rows.iter().position(|row|row.0=="undefined_variable").unwrap();assert!(random[1].0<missing,"the complete simple range phase precedes ordinary selector/case evaluation: {rows:?}");assert!(random.iter().all(|(_,row)|row.2==dm_analysis::check_policy::DiagnosticSeverity::Warning));assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,1);let parsed=db.db().stats(dm_query::Kind(4)).computed;assert_eq!(read(),rows);let _=snapshot.native_effect_source_report(input,1,dm_analysis::checker_effects::EffectReportPhase::Purity,&environment,None,&snapshot.tree).unwrap();assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,1);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,parsed);assert_eq!(db.effect_graph_work_for_test(),0);
}
#[cfg(debug_assertions)]#[test]fn original_switch_rand_range_preserves_explicit_empty_default_and_simple_scalar_mode(){
 let(host,environment)=original_filter_flags_host(b"/proc/probe()\n    switch(rand(1,3))\n        if(5)\n            return 0\n        else\n/proc/scalar()\n    switch(rand(5.5 % 2,3))\n        if(2 to 3)\n            return 0\n");let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();for(name,count)in[("probe",1),("scalar",0)]{let ordinal=filter_ordinal(snapshot,name)as usize;let rows=snapshot.with_original_checker_body(ordinal,&environment,None,&snapshot.tree,|body|Ok(body.with_original_diagnostics(input,|rows|rows.iter().filter(|row|row.diagnostic().family=="switch_rand_range").map(|row|row.diagnostic().message.clone()).collect::<Vec<_>>()).unwrap())).unwrap();assert_eq!(rows.len(),count,"{name}: {rows:?}");}
}
#[cfg(debug_assertions)]#[test]fn original_switch_rand_range_refuses_unrepresented_simple_constants_instead_of_publishing_empty_findings(){
 let(host,environment)=original_filter_flags_host(b"/proc/probe()\n    switch(rand(1, rgb(1,2,3) == \"text\"))\n        if(1)\n            return 0\n");let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let ordinal=filter_ordinal(snapshot,"probe")as usize;let result=snapshot.with_original_checker_body(ordinal,&environment,None,&snapshot.tree,|_|Ok(()));let error=result.unwrap_err();assert!(error.to_string().contains("original simple constructed/named constant is not yet represented"),"{error:?}");assert_eq!(snapshot.native_raw_queries.as_ref().unwrap().effect_graph_work_for_test(),0);
}

#[cfg(debug_assertions)]#[test]fn original_switch_rand_range_complete_eight_reference_sources_keep_all_body_rows_and_points(){
 use sha2::Digest;for(name,source)in[("switch_rand_complete",include_bytes!("../../../fixtures/unified_checks/switch_rand_complete/project.dme").as_slice()),("switch_rand_default",include_bytes!("../../../fixtures/unified_checks/switch_rand_default/project.dme").as_slice()),("switch_rand_fractional",include_bytes!("../../../fixtures/unified_checks/switch_rand_fractional/project.dme").as_slice()),("switch_rand_gap",include_bytes!("../../../fixtures/unified_checks/switch_rand_gap/project.dme").as_slice()),("switch_rand_outside",include_bytes!("../../../fixtures/unified_checks/switch_rand_outside/project.dme").as_slice()),("switch_rand_overflow",include_bytes!("../../../fixtures/unified_checks/switch_rand_overflow/project.dme").as_slice()),("switch_rand_single",include_bytes!("../../../fixtures/unified_checks/switch_rand_single/project.dme").as_slice()),("switch_rand_unknown",include_bytes!("../../../fixtures/unified_checks/switch_rand_unknown/project.dme").as_slice())]{let(host,environment)=original_filter_flags_host(source);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let ordinal=filter_ordinal(snapshot,"probe")as usize;let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();let read=||snapshot.with_original_checker_body(ordinal,&environment,None,&snapshot.tree,|body|Ok(body.with_original_diagnostics(input,|rows|rows.iter().map(|row|{assert!(row.diagnostic().notes.is_empty(),"the complete transport must grow if an actual note appears");let point=match row.location(){dm_analysis::checker_effects::OriginalDiagnosticLocation::Expanded=>input.archive().borrowed_source_note_point(row.diagnostic().span.start).unwrap(),dm_analysis::checker_effects::OriginalDiagnosticLocation::Reader(point)=>input.archive().source_mapping().borrow_stored_original_reported_point(point).unwrap(),dm_analysis::checker_effects::OriginalDiagnosticLocation::ParserSynthetic=>panic!("unissued synthetic point in actual numeric fixture")};let(_,line,column)=point.reported_coordinates();serde_json::json!({"message":row.diagnostic().message,"level":format!("{:?}",row.default_level()).to_ascii_lowercase(),"line":line,"column":column,"notes":[]})}).collect::<Vec<_>>()).unwrap())).unwrap();let rows=read();let warm=read();assert_eq!(warm,rows);assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,1);println!("ORIGINAL_SWITCH_RAND_NATIVE {}",serde_json::json!({"case":name,"source_sha256":format!("{:x}",sha2::Sha256::digest(source)),"diagnostics":rows}));assert_eq!(snapshot.native_raw_queries.as_ref().unwrap().effect_graph_work_for_test(),0);}
}

#[cfg(debug_assertions)]#[test]fn original_return_type_expression_errors_are_in_the_same_ordered_initial_setting_prelude(){
 use dm_analysis::checker_effects::OriginalDiagnosticPhase;
 for(value,expected)in[("1 + 2","type expr: bad expression node"),("missing","type expr: no such parameter \"missing\""),("42","type expr: bad term node"),("x[1]","type expr: cannot index by anything but `_`"),("null[_]","type expr: cannot index non-parameters"),("null.type","type expr: cannot take .type of non-parameters"),("x.hello","type expr: bad follow node Field(Dot, \"hello\")"),("missing || absent","type expr: no such parameter \"missing\"")]{
  let source=format!("/proc/probe(x)\n    set mystery=1\n    set SpacemanDMM_return_type={value}\n    set another_unknown=1\n    return 0\n");let(host,environment)=original_filter_flags_host(source.as_bytes());let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let ordinal=filter_ordinal(snapshot,"probe")as usize;let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();let read=||snapshot.with_original_checker_body(ordinal,&environment,None,&snapshot.tree,|body|Ok(body.with_original_diagnostics(input,|rows|rows.iter().map(|row|(row.phase(),row.diagnostic().family,row.diagnostic().message.clone(),row.registration_tag(),row.default_level())).collect::<Vec<_>>()).unwrap())).unwrap();let rows=read();assert_eq!(rows.len(),3,"{value}: {rows:?}");assert!(rows.iter().all(|row|row.0==OriginalDiagnosticPhase::Prelude));assert_eq!(rows[1].1,"return_type_expression");assert_eq!(rows[1].2,expected);assert_eq!(rows[1].3,None);assert_eq!(rows[1].4,dm_analysis::check_policy::DiagnosticSeverity::Error);assert_eq!(rows,read());assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,1);
 }
}
#[cfg(debug_assertions)]#[test]fn original_return_type_expression_valid_grammar_produces_no_compile_error_and_keeps_parenthesis_semantics(){
 for value in["null","/datum","x","x[_]","x[_].type","x.type","x || null","x && /datum","x ? /datum : null","(x).type"]{
  let source=format!("/proc/probe(x)\n    set SpacemanDMM_return_type={value}\n    return 0\n");let(host,environment)=original_filter_flags_host(source.as_bytes());let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let ordinal=filter_ordinal(snapshot,"probe")as usize;let rows=snapshot.with_original_checker_body(ordinal,&environment,None,&snapshot.tree,|body|Ok(body.with_original_diagnostics(input,|rows|rows.iter().map(|row|row.diagnostic().message.clone()).collect::<Vec<_>>()).unwrap())).unwrap();assert!(rows.is_empty(),"{value}: {rows:?}");
 }
}

#[cfg(debug_assertions)]#[test]fn original_dynamic_return_binding_uses_once_evaluated_arguments_and_preserves_all_source_case_rows(){
 for(name,source,wanted)in[
  ("parameter_value",include_bytes!("../../../fixtures/unified_checks/return_binding_parameter_value/project.dme").as_slice(),0),
  ("keyword_overrides_position",include_bytes!("../../../fixtures/unified_checks/return_binding_keyword_overrides_position/project.dme").as_slice(),0),
  ("last_keyword_wins",include_bytes!("../../../fixtures/unified_checks/return_binding_last_keyword_wins/project.dme").as_slice(),0),
  ("index_count_ignored_on_value",include_bytes!("../../../fixtures/unified_checks/return_binding_index_count_ignored_on_value/project.dme").as_slice(),0),
  ("parameter_static_type",include_bytes!("../../../fixtures/unified_checks/return_binding_parameter_static_type/project.dme").as_slice(),0),
  ("conditional_type_presence",include_bytes!("../../../fixtures/unified_checks/return_binding_conditional_type_presence/project.dme").as_slice(),0),
  ("conditional_none_falls_through",include_bytes!("../../../fixtures/unified_checks/return_binding_conditional_none_falls_through/project.dme").as_slice(),0),
  ("invalid_later_preserves_binding",include_bytes!("../../../fixtures/unified_checks/return_binding_invalid_later_preserves_binding/project.dme").as_slice(),0),
  ("invalid_only_keeps_unannotated",include_bytes!("../../../fixtures/unified_checks/return_binding_invalid_only_keeps_unannotated/project.dme").as_slice(),1),
  ("index_strip_on_static_type",include_bytes!("../../../fixtures/unified_checks/return_binding_index_strip_on_static_type/project.dme").as_slice(),0),
 ]{
  let(host,environment)=original_filter_flags_host(source);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let choose=filter_ordinal(snapshot,"choose")as usize;let identity=input.archive().callables().identity_for_member(input.archive().occurrences().get(choose).unwrap().member).unwrap();let strict=dm_analysis::checker_return_facts::PuritySettingsPermit::issue(input.archive(),snapshot.tree.checker_builtin_profile().unwrap(),identity).err().expect("ordinary effect-only return binding remains strict");assert!(strict.contains("return prefix TypeExpr requires shared argument value/type facts"),"{name}: {strict}");let ordinal=filter_ordinal(snapshot,"probe")as usize;let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();let read=||snapshot.with_original_checker_body(ordinal,&environment,None,&snapshot.tree,|body|Ok(body.with_original_diagnostics(input,|rows|rows.iter().map(|row|(row.diagnostic().family,row.diagnostic().message.clone(),row.diagnostic().notes.clone())).collect::<Vec<_>>()).unwrap())).unwrap();let rows=read();assert_eq!(rows.len(),wanted,"{name}: {rows:?}");let parsed=snapshot.native_raw_queries.as_ref().unwrap().db().stats(dm_query::Kind(4)).computed;assert_eq!(rows,read());assert_eq!(snapshot.native_raw_queries.as_ref().unwrap().db().stats(dm_query::Kind(4)).computed,parsed);assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,1,"{name} repeated actual expression evaluation");
  let mut complete=Vec::new();
  for phase in [dm_analysis::checker_effects::OriginalDiagnosticPhase::Prelude,dm_analysis::checker_effects::OriginalDiagnosticPhase::Body]{
   for procedure in ["choose","probe"]{
    let ordinal=filter_ordinal(snapshot,procedure)as usize;
    let rows=snapshot.with_original_checker_body(ordinal,&environment,None,&snapshot.tree,|body|Ok(body.with_original_diagnostics(input,|rows|rows.iter().filter(|row|row.phase()==phase).map(|row|{
     let point=match row.location(){dm_analysis::checker_effects::OriginalDiagnosticLocation::Expanded=>input.archive().borrowed_source_note_point(row.diagnostic().span.start).unwrap(),dm_analysis::checker_effects::OriginalDiagnosticLocation::Reader(point)=>input.archive().source_mapping().borrow_stored_original_reported_point(point).unwrap(),dm_analysis::checker_effects::OriginalDiagnosticLocation::ParserSynthetic=>panic!("unrepresented synthetic return fixture point")};let(_,line,column)=point.reported_coordinates();
     serde_json::json!({"message":row.diagnostic().message,"level":format!("{:?}",row.default_level()).to_ascii_lowercase(),"line":line,"column":column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()})
    }).collect::<Vec<_>>()).unwrap())).unwrap();complete.extend(rows);
   }
  }
  assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,2,"{name}: source prefix borrowing must not evaluate either body a second time");
  use sha2::Digest;println!("ORIGINAL_RETURN_BINDING_NATIVE {}",serde_json::json!({"case":name,"source_sha256":format!("{:x}",sha2::Sha256::digest(source)),"diagnostics":complete}));
 }
}

#[cfg(debug_assertions)]#[test]fn original_return_missing_prefab_uses_statement_point_only_for_direct_top_level_prefab(){
 for(name,source,wanted)in[("direct",include_bytes!("../../../fixtures/unified_checks/return_expression_direct_missing_prefab/project.dme").as_slice(),(2,5)),("grouped",include_bytes!("../../../fixtures/unified_checks/return_expression_grouped_missing_prefab/project.dme").as_slice(),(2,34)),("nested",include_bytes!("../../../fixtures/unified_checks/return_expression_nested_missing_prefab/project.dme").as_slice(),(2,38))]{
  let(host,environment)=original_filter_flags_host(source);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let ordinal=filter_ordinal(snapshot,"probe")as usize;let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();let rows=snapshot.with_original_checker_body(ordinal,&environment,None,&snapshot.tree,|body|Ok(body.with_original_diagnostics(input,|rows|rows.iter().map(|row|{let point=input.archive().borrowed_source_note_point(row.diagnostic().span.start).unwrap();let(_,line,column)=point.reported_coordinates();(row.diagnostic().message.clone(),line,column,row.default_level())}).collect::<Vec<_>>()).unwrap())).unwrap();assert_eq!(rows,[("undefined type: /datum/missing".into(),wanted.0,wanted.1,dm_analysis::check_policy::DiagnosticSeverity::Error)],"{name}");assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,1);
 }
}

#[cfg(debug_assertions)]#[test]fn original_global_declarations_precede_all_settings_and_bodies_without_evaluating_a_body(){
 use super::super::purity::OriginalDeclarationAndBody;
 for(name,source)in[
  ("final_override",include_bytes!("../../../fixtures/unified_checks/global_declarations_final_override/project.dme").as_slice()),
  ("private_override",include_bytes!("../../../fixtures/unified_checks/global_declarations_private_override/project.dme").as_slice()),
  ("inherited_redeclaration",include_bytes!("../../../fixtures/unified_checks/global_declarations_inherited_redeclaration/project.dme").as_slice()),
  ("combined_flags",include_bytes!("../../../fixtures/unified_checks/global_declarations_combined_flags/project.dme").as_slice()),
  ("multiple_ancestors",include_bytes!("../../../fixtures/unified_checks/global_declarations_multiple_ancestors/project.dme").as_slice()),
  ("lexical_type_order",include_bytes!("../../../fixtures/unified_checks/global_declarations_lexical_type_order/project.dme").as_slice()),
  ("vars_exception",include_bytes!("../../../fixtures/unified_checks/global_declarations_vars_exception/project.dme").as_slice()),
 ]{
  let(host,environment)=original_filter_flags_host(source);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let db=snapshot.native_raw_queries.as_ref().unwrap();let parsed=db.db().stats(dm_query::Kind(4)).computed;let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();let mut saw_body=false;let mut globals=0;let mut rows=Vec::new();
  snapshot.visit_original_declarations_and_bodies(&environment,None,&snapshot.tree,|row|{
   let diagnostic=match row{
    OriginalDeclarationAndBody::Declaration(row)=>{assert!(!saw_body,"{name}: global declaration after a body phase");assert_eq!(db.db().stats(dm_query::Kind(4)).computed,parsed,"{name}: global declarations parsed a body");assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread(),before);globals+=1;let point=row.origin();serde_json::json!({"message":row.diagnostic().message,"level":format!("{:?}",row.default_severity()).to_ascii_lowercase(),"line":point.line,"column":point.byte_column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()})},
    OriginalDeclarationAndBody::Body{ordinal:_,row}=>{saw_body=true;let point=match row.location(){dm_analysis::checker_effects::OriginalDiagnosticLocation::Expanded=>input.archive().borrowed_source_note_point(row.diagnostic().span.start).unwrap(),dm_analysis::checker_effects::OriginalDiagnosticLocation::Reader(point)=>input.archive().source_mapping().borrow_stored_original_reported_point(point).unwrap(),dm_analysis::checker_effects::OriginalDiagnosticLocation::ParserSynthetic=>panic!("unrepresented synthetic global source point")};let(_,line,column)=point.reported_coordinates();serde_json::json!({"message":row.diagnostic().message,"level":format!("{:?}",row.default_level()).to_ascii_lowercase(),"line":line,"column":column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()})},
   };rows.push(diagnostic);Ok(())
  }).unwrap();
  assert!(saw_body);if name=="vars_exception"{assert_eq!(globals,0)}else{assert!(globals>0,"{name}")};assert_eq!(rows.len(),globals+2,"{name}: {rows:?}");assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,1,"{name}: one real probe BODY should serve both settings/body phases");
  let computed=db.db().stats(dm_query::Kind(17)).computed;let mut retry=Vec::new();snapshot.visit_original_declarations_and_bodies(&environment,None,&snapshot.tree,|row|{retry.push(match row{OriginalDeclarationAndBody::Declaration(row)=>row.diagnostic().message.clone(),OriginalDeclarationAndBody::Body{row,..}=>row.diagnostic().message.clone()});Ok(())}).unwrap();assert_eq!(retry,rows.iter().map(|row|row["message"].as_str().unwrap().to_owned()).collect::<Vec<_>>());assert_eq!(db.db().stats(dm_query::Kind(17)).computed,computed);assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,1);
  use sha2::Digest;println!("ORIGINAL_GLOBAL_DECLARATIONS_NATIVE {}",serde_json::json!({"case":name,"source_sha256":format!("{:x}",sha2::Sha256::digest(source)),"diagnostics":rows}));
 }
}
#[cfg(debug_assertions)]#[test]fn original_global_declaration_delivery_preserves_first_callback_io_and_does_not_start_body(){
 let(host,environment)=original_filter_flags_host(include_bytes!("../../../fixtures/unified_checks/global_declarations_combined_flags/project.dme"));let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let _=snapshot.original_checker_request_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let parsed=db.db().stats(dm_query::Kind(4)).computed;let mut invoked=0;let failure=snapshot.visit_original_declarations_and_bodies(&environment,None,&snapshot.tree,|row|{assert!(matches!(row,super::super::purity::OriginalDeclarationAndBody::Declaration(_)));invoked+=1;Err(std::io::Error::from_raw_os_error(1450))}).unwrap_err();assert_eq!(failure.raw_os_error(),Some(1450));assert_eq!(invoked,1);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,parsed);
 let mut rows=0;snapshot.visit_original_declarations_and_bodies(&environment,None,&snapshot.tree,|_|{rows+=1;Ok(())}).unwrap();assert!(rows>=3);
}

#[cfg(debug_assertions)]#[test]fn original_global_declarations_refuse_foreign_owner_and_typed_resource_failure_before_publication(){
 struct Work{fail:bool,calls:usize}impl dm_analysis::checker_effects::EffectReportWork for Work{type Mark=();fn mark(&mut self)->std::io::Result<()>{Ok(())}fn reconcile(&mut self,_:(),_:usize)->std::io::Result<()>{Ok(())}fn reserve(&mut self,_:usize)->std::io::Result<()>{self.calls+=1;if self.fail{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}}}
 let source=include_bytes!("../../../fixtures/unified_checks/global_declarations_combined_flags/project.dme");let(host,_)=original_filter_flags_host(source);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let(foreign_host,_)=original_filter_flags_host(source);let foreign=foreign_host.query_state();let foreign=foreign.lock().unwrap();let foreign=foreign.snapshot.as_ref().unwrap();assert_eq!(snapshot.tree.identity(),foreign.tree.identity(),"foreign-owner negative must not rely on different semantic data");let checkpoint=||Ok(());let admission=dm_analysis::checker_effects::ExecutionAdmission::with_limit(1<<24);let mut work=Work{fail:false,calls:0};let mut emitted=false;
 let bad=dm_analysis::checks_variable_visibility::with_original_declarations(input,foreign.tree.as_ref(),&admission,&mut work,&checkpoint,|_|{emitted=true;Ok(())});assert!(bad.is_err());assert!(!emitted);assert_eq!(work.calls,0,"equal bytes/tree identities do not grant the foreign resolver authority");
 let admission=dm_analysis::checker_effects::ExecutionAdmission::with_limit(1<<24);let mut work=Work{fail:true,calls:0};let bad=dm_analysis::checks_variable_visibility::with_original_declarations(input,snapshot.tree.as_ref(),&admission,&mut work,&checkpoint,|_|{emitted=true;Ok(())});assert!(matches!(bad,Err(dm_analysis::policy_body_demand::PolicyFailure::Operational(ref e))if e.raw_os_error()==Some(1450)));assert!(!emitted);assert_eq!(work.calls,1);
 let admission=dm_analysis::checker_effects::ExecutionAdmission::with_limit(1<<24);let mut work=Work{fail:false,calls:0};let mut rows=0;dm_analysis::checks_variable_visibility::with_original_declarations(input,snapshot.tree.as_ref(),&admission,&mut work,&checkpoint,|findings|{assert!(findings.belongs_to(input));rows=findings.rows().len();Ok(())}).unwrap();assert!(rows>0);assert!(work.calls>0);
}

#[cfg(debug_assertions)]#[test]fn original_multiple_procedure_phases_deliver_all_settings_before_all_bodies_then_cached_keyword_final(){
 use super::super::purity::{OriginalDeclarationAndBody,OriginalThroughKeywords};
 for(name,source)in[("all_settings_before_bodies",include_bytes!("../../../fixtures/unified_checks/final_keywords_all_settings_before_bodies/project.dme").as_slice()),("keyword_after_bodies",include_bytes!("../../../fixtures/unified_checks/final_keywords_keyword_after_bodies/project.dme").as_slice()),("keyword_two_children_and_calls",include_bytes!("../../../fixtures/unified_checks/final_keywords_keyword_two_children_and_calls/project.dme").as_slice())]{
  let(host,environment)=original_filter_flags_host(source);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let db=snapshot.native_raw_queries.as_ref().unwrap();let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();let mut rows=Vec::new();let mut phases=Vec::new();let mut final_before=None;
  snapshot.visit_original_through_keywords(&environment,None,&snapshot.tree,|row|{
   let(phase,record)=match row{
    OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Declaration(row))=>{let point=row.origin();(0,serde_json::json!({"message":row.diagnostic().message,"level":format!("{:?}",row.default_severity()).to_ascii_lowercase(),"line":point.line,"column":point.byte_column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()}))},
    OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Body{row,..})=>{let phase=match row.phase(){dm_analysis::checker_effects::OriginalDiagnosticPhase::Prelude=>1,dm_analysis::checker_effects::OriginalDiagnosticPhase::Body=>2};let point=match row.location(){dm_analysis::checker_effects::OriginalDiagnosticLocation::Expanded=>input.archive().borrowed_source_note_point(row.diagnostic().span.start).unwrap(),dm_analysis::checker_effects::OriginalDiagnosticLocation::Reader(point)=>input.archive().source_mapping().borrow_stored_original_reported_point(point).unwrap(),dm_analysis::checker_effects::OriginalDiagnosticLocation::ParserSynthetic=>panic!("unrepresented phase source point")};let(_,line,column)=point.reported_coordinates();(phase,serde_json::json!({"message":row.diagnostic().message,"level":format!("{:?}",row.default_level()).to_ascii_lowercase(),"line":line,"column":column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()}))},
    OriginalThroughKeywords::Keyword{findings,row}=>{let count=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();assert_eq!(count-before,input.archive().len()as u64,"{name}: keyword finalization reevaluated a BODY");final_before.get_or_insert(count);let(_,line,column)=findings.point(row.point).unwrap().coordinates();(3,serde_json::json!({"message":row.message,"level":"error","line":line,"column":column,"notes":row.notes.iter().map(|note|findings.legacy_note(row.point,note).unwrap().to_string()).collect::<Vec<_>>()}))},
   };if let Some(previous)=phases.last(){assert!(*previous<=phase,"{name}: phase interleaving {phases:?} then {phase}")};phases.push(phase);rows.push(record);Ok(())
  }).unwrap();
  assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,input.archive().len()as u64,"{name}");
  if name=="all_settings_before_bodies"{assert_eq!(phases,[1,1,1,2,2,2]);assert_eq!(rows.iter().map(|r|r["message"].as_str().unwrap()).collect::<Vec<_>>(),["unknown setting \"mystery_root\"","unknown setting \"mystery_a\"","unknown setting \"mystery_z\"","undefined var: \"missing_root\"","undefined var: \"missing_a\"","undefined var: \"missing_z\""]);}else{assert!(final_before.is_some());assert_eq!(phases.last(),Some(&3));}
  let parsed=db.db().stats(dm_query::Kind(4)).computed;let body_count=db.db().stats(dm_query::Kind(17)).computed;let mut retry=Vec::new();snapshot.visit_original_through_keywords(&environment,None,&snapshot.tree,|row|{retry.push(match row{OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Declaration(row))=>row.diagnostic().message.clone(),OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Body{row,..})=>row.diagnostic().message.clone(),OriginalThroughKeywords::Keyword{row,..}=>row.message.clone()});Ok(())}).unwrap();assert_eq!(retry,rows.iter().map(|r|r["message"].as_str().unwrap().to_owned()).collect::<Vec<_>>());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,parsed);assert_eq!(db.db().stats(dm_query::Kind(17)).computed,body_count);assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,input.archive().len()as u64);
  use sha2::Digest;println!("ORIGINAL_FINAL_KEYWORDS_NATIVE {}",serde_json::json!({"case":name,"source_sha256":format!("{:x}",sha2::Sha256::digest(source)),"diagnostics":rows}));
 }
}

#[cfg(debug_assertions)]#[test]fn original_semantic_phases_through_graph_keep_once_body_scc_order_and_full_diagnostics(){
 use super::super::purity::{OriginalDeclarationAndBody,OriginalThroughKeywords,OriginalThroughGraph};
 for(name,source)in[("sleep_then_purity",include_bytes!("../../../fixtures/unified_checks/final_graph_sleep_then_purity/project.dme").as_slice()),("kwargs_before_graph",include_bytes!("../../../fixtures/unified_checks/final_graph_kwargs_before_graph/project.dme").as_slice()),("cycle_graph",include_bytes!("../../../fixtures/unified_checks/final_graph_cycle_graph/project.dme").as_slice()),("empty_graph",include_bytes!("../../../fixtures/unified_checks/final_graph_empty_graph/project.dme").as_slice()),("immediate_not_repeated",include_bytes!("../../../fixtures/unified_checks/final_graph_immediate_not_repeated/project.dme").as_slice())]{
  let(host,environment)=original_filter_flags_host(source);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let db=snapshot.native_raw_queries.as_ref().unwrap();let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();let mut rows=Vec::new();let mut phases=Vec::new();let mut final_before=None;
  snapshot.visit_original_through_graph(&environment,None,&snapshot.tree,|row|{
   let(phase,record)=match row{
    OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Declaration(row)))=>{let point=row.origin();(0,serde_json::json!({"message":row.diagnostic().message,"level":format!("{:?}",row.default_severity()).to_ascii_lowercase(),"line":point.line,"column":point.byte_column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()}))},
    OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Body{row,..}))=>{let phase=match row.phase(){dm_analysis::checker_effects::OriginalDiagnosticPhase::Prelude=>1,dm_analysis::checker_effects::OriginalDiagnosticPhase::Body=>2};let point=match row.location(){dm_analysis::checker_effects::OriginalDiagnosticLocation::Expanded=>input.archive().borrowed_source_note_point(row.diagnostic().span.start).unwrap(),dm_analysis::checker_effects::OriginalDiagnosticLocation::Reader(point)=>input.archive().source_mapping().borrow_stored_original_reported_point(point).unwrap(),dm_analysis::checker_effects::OriginalDiagnosticLocation::ParserSynthetic=>panic!("unrepresented phase source point")};let(_,line,column)=point.reported_coordinates();(phase,serde_json::json!({"message":row.diagnostic().message,"level":format!("{:?}",row.default_level()).to_ascii_lowercase(),"line":line,"column":column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()}))},
    OriginalThroughGraph::Source(OriginalThroughKeywords::Keyword{findings,row})=>{let count=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();assert_eq!(count-before,input.archive().len()as u64,"{name}: keyword finalization reevaluated a BODY");final_before.get_or_insert(count);let(_,line,column)=findings.point(row.point).unwrap().coordinates();(3,serde_json::json!({"message":row.message,"level":"error","line":line,"column":column,"notes":row.notes.iter().map(|note|findings.legacy_note(row.point,note).unwrap().to_string()).collect::<Vec<_>>()}))},
    OriginalThroughGraph::Graph(row)=>{let count=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();assert_eq!(count-before,input.archive().len()as u64,"{name}: graph report reevaluated a BODY");let phase=match row.phase(){dm_analysis::checker_effects::ProducedPhase::SleepGraph=>4,dm_analysis::checker_effects::ProducedPhase::PurityGraph=>5,dm_analysis::checker_effects::ProducedPhase::BodyImmediate=>panic!("immediate BODY effect was delivered twice")};(phase,serde_json::json!({"message":row.diagnostic.message,"level":format!("{:?}",row.severity).to_ascii_lowercase(),"line":row.origin.line,"column":row.origin.byte_column,"notes":row.diagnostic.notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()}))},
   };if let Some(previous)=phases.last(){assert!(*previous<=phase,"{name}: phase interleaving {phases:?} then {phase}")};phases.push(phase);rows.push(record);Ok(())
  }).unwrap();
  assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,input.archive().len()as u64,"{name}");
  let expected:&[u8]=match name{"sleep_then_purity"=>&[1,2,4,5],"kwargs_before_graph"=>&[1,2,3,4,5],"cycle_graph"=>&[1,4,5],"empty_graph"=>&[1,1,2],"immediate_not_repeated"=>&[1,2,4,5],_=>unreachable!()};assert_eq!(phases,expected,"{name}");
  let parsed=db.db().stats(dm_query::Kind(4)).computed;let body_count=db.db().stats(dm_query::Kind(17)).computed;let mut retry=Vec::new();snapshot.visit_original_through_graph(&environment,None,&snapshot.tree,|row|{retry.push(match row{OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Declaration(row)))=>row.diagnostic().message.clone(),OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Body{row,..}))=>row.diagnostic().message.clone(),OriginalThroughGraph::Source(OriginalThroughKeywords::Keyword{row,..})=>row.message.clone(),OriginalThroughGraph::Graph(row)=>row.diagnostic.message.clone()});Ok(())}).unwrap();assert_eq!(retry,rows.iter().map(|r|r["message"].as_str().unwrap().to_owned()).collect::<Vec<_>>());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,parsed);assert_eq!(db.db().stats(dm_query::Kind(17)).computed,body_count);assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,input.archive().len()as u64);
  if name!="empty_graph"{let mut graph_calls=0;let failure=snapshot.visit_original_through_graph(&environment,None,&snapshot.tree,|row|{if let OriginalThroughGraph::Graph(_)=row{graph_calls+=1;return Err(std::io::Error::from_raw_os_error(1450))}Ok(())});assert_eq!(failure.unwrap_err().raw_os_error(),Some(1450));assert_eq!(graph_calls,1,"actual first consumer error must stop graph delivery");assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,input.archive().len()as u64);}
  use sha2::Digest;println!("ORIGINAL_FINAL_GRAPH_NATIVE {}",serde_json::json!({"case":name,"source_sha256":format!("{:x}",sha2::Sha256::digest(source)),"diagnostics":rows}));
 }
}

#[cfg(debug_assertions)]#[test]fn original_reader_duplicate_formals_precede_all_semantic_phases_and_continue_exactly(){
 use super::super::purity::{OriginalDeclarationAndBody,OriginalThroughKeywords,OriginalThroughGraph,OriginalThroughReaderDeclarations};
 for(name,source)in[("duplicate_then_global_settings_body",include_bytes!("../../../fixtures/unified_checks/reader_declarations_duplicate_then_global_settings_body/project.dme").as_slice()),("encounter_before_lexical",include_bytes!("../../../fixtures/unified_checks/reader_declarations_encounter_before_lexical/project.dme").as_slice()),("bodyless_duplicate",include_bytes!("../../../fixtures/unified_checks/reader_declarations_bodyless_duplicate/project.dme").as_slice()),("clean_two_procs",include_bytes!("../../../fixtures/unified_checks/reader_declarations_clean_two_procs/project.dme").as_slice())]{
  let(host,environment)=original_filter_flags_host(source);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let db=snapshot.native_raw_queries.as_ref().unwrap();let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();let mut rows=Vec::new();let mut phases=Vec::new();let mut final_before=None;
  snapshot.visit_original_cli_diagnostics(&environment,None,&snapshot.tree,|row,reported_level|{
   let(phase,mut record)=match row{
    OriginalThroughReaderDeclarations::Declaration(row)=>{assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread(),before,"frontend declaration must not evaluate BODY");let(_,line,column)=row.borrowed_reported_point().unwrap().coordinates();(0,serde_json::json!({"message":row.diagnostic().message,"level":"error","line":line,"column":column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()}))},
    OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Declaration(row))))=>{let point=row.origin();(1,serde_json::json!({"message":row.diagnostic().message,"level":format!("{:?}",row.default_severity()).to_ascii_lowercase(),"line":point.line,"column":point.byte_column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()}))},
    OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Body{row,..})))=>{let phase=match row.phase(){dm_analysis::checker_effects::OriginalDiagnosticPhase::Prelude=>2,dm_analysis::checker_effects::OriginalDiagnosticPhase::Body=>3};let point=match row.location(){dm_analysis::checker_effects::OriginalDiagnosticLocation::Expanded=>input.archive().borrowed_source_note_point(row.diagnostic().span.start).unwrap(),dm_analysis::checker_effects::OriginalDiagnosticLocation::Reader(point)=>input.archive().source_mapping().borrow_stored_original_reported_point(point).unwrap(),dm_analysis::checker_effects::OriginalDiagnosticLocation::ParserSynthetic=>panic!("unrepresented phase source point")};let(_,line,column)=point.reported_coordinates();(phase,serde_json::json!({"message":row.diagnostic().message,"level":format!("{:?}",row.default_level()).to_ascii_lowercase(),"line":line,"column":column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()}))},
    OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Keyword{findings,row}))=>{let count=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();assert_eq!(count-before,input.archive().len()as u64,"{name}: keyword finalization reevaluated a BODY");final_before.get_or_insert(count);let(_,line,column)=findings.point(row.point).unwrap().coordinates();(4,serde_json::json!({"message":row.message,"level":"error","line":line,"column":column,"notes":row.notes.iter().map(|note|findings.legacy_note(row.point,note).unwrap().to_string()).collect::<Vec<_>>()}))},
    OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Graph(row))=>{let count=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();assert_eq!(count-before,input.archive().len()as u64,"{name}: graph report reevaluated a BODY");let phase=match row.phase(){dm_analysis::checker_effects::ProducedPhase::SleepGraph=>5,dm_analysis::checker_effects::ProducedPhase::PurityGraph=>6,dm_analysis::checker_effects::ProducedPhase::BodyImmediate=>panic!("immediate BODY effect was delivered twice")};(phase,serde_json::json!({"message":row.diagnostic.message,"level":format!("{:?}",row.severity).to_ascii_lowercase(),"line":row.origin.line,"column":row.origin.byte_column,"notes":row.diagnostic.notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()}))},
   };record["level"]=format!("{:?}",reported_level).to_ascii_lowercase().into();if let Some(previous)=phases.last(){assert!(*previous<=phase,"{name}: phase interleaving {phases:?} then {phase}")};phases.push(phase);rows.push(record);Ok(())
  }).unwrap();
  assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,input.archive().len()as u64,"{name}");
  {use sha2::Digest;println!("ORIGINAL_READER_DECLARATIONS_TRACE {}",serde_json::json!({"case":name,"source_sha256":format!("{:x}",sha2::Sha256::digest(source)),"phases":&phases,"diagnostics":&rows}));}
  let expected:&[u8]=match name{"duplicate_then_global_settings_body"=>&[0,1,2,2,2,3,3,3],"encounter_before_lexical"=>&[0,0,2,2,3,3,3,3],"bodyless_duplicate"=>&[0,2,3],"clean_two_procs"=>&[2,2,3,3],_=>unreachable!()};assert_eq!(phases,expected,"{name}");
  let parsed=db.db().stats(dm_query::Kind(4)).computed;let body_count=db.db().stats(dm_query::Kind(17)).computed;let mut retry=Vec::new();snapshot.visit_original_cli_diagnostics(&environment,None,&snapshot.tree,|row,_reported_level|{retry.push(match row{OriginalThroughReaderDeclarations::Declaration(row)=>row.diagnostic().message.clone(),OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Declaration(row))))=>row.diagnostic().message.clone(),OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Body{row,..})))=>row.diagnostic().message.clone(),OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Keyword{row,..}))=>row.message.clone(),OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Graph(row))=>row.diagnostic.message.clone()});Ok(())}).unwrap();assert_eq!(retry,rows.iter().map(|r|r["message"].as_str().unwrap().to_owned()).collect::<Vec<_>>());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,parsed);assert_eq!(db.db().stats(dm_query::Kind(17)).computed,body_count);assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,input.archive().len()as u64);
  use sha2::Digest;println!("ORIGINAL_READER_DECLARATIONS_NATIVE {}",serde_json::json!({"case":name,"source_sha256":format!("{:x}",sha2::Sha256::digest(source)),"diagnostics":rows}));
 }
}

#[cfg(debug_assertions)]#[test]fn original_reader_declaration_consumer_error_stops_before_body_and_real_retry_continues(){
 use super::super::purity::OriginalThroughReaderDeclarations;let source=include_bytes!("../../../fixtures/unified_checks/reader_declarations_duplicate_then_global_settings_body/project.dme");let(host,environment)=original_filter_flags_host(source);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();let mut calls=0;
 let failed=snapshot.visit_original_cli_diagnostics(&environment,None,&snapshot.tree,|row,_reported_level|{assert!(matches!(row,OriginalThroughReaderDeclarations::Declaration(_)));calls+=1;Err(std::io::Error::from_raw_os_error(1450))});assert_eq!(failed.unwrap_err().raw_os_error(),Some(1450));assert_eq!(calls,1);assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread(),before);
 let mut rows=0;snapshot.visit_original_cli_diagnostics(&environment,None,&snapshot.tree,|_,_|{rows+=1;Ok(())}).unwrap();assert_eq!(rows,8);let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,input.archive().len()as u64);
}

#[cfg(debug_assertions)]#[test]fn original_reader_declarations_require_real_purpose_and_keep_operational_failure_identity(){
 struct Work{calls:usize,fail:bool}impl dm_analysis::checker_effects::EffectReportWork for Work{type Mark=();fn mark(&mut self)->std::io::Result<()>{Ok(())}fn reconcile(&mut self,_:(),_:usize)->std::io::Result<()>{Ok(())}fn reserve(&mut self,_:usize)->std::io::Result<()>{self.calls+=1;if self.fail{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}}}
 let(host,_)=original_filter_flags_host(include_bytes!("../../../fixtures/unified_checks/reader_declarations_bodyless_duplicate/project.dme"));let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let ordinary=dm_analysis::checker_effects::EffectInput::source_pages(std::sync::Arc::clone(input.archive()),input.profile()).unwrap();let admission=dm_analysis::checker_effects::ExecutionAdmission::with_limit(1<<24);let mut work=Work{calls:0,fail:false};let mut rows=0;
 assert!(dm_analysis::checks_proc_visibility::visit_original_declaration_redeclarations(&ordinary,&admission,&mut work,&||Ok(()),|_|{rows+=1;Ok(())}).is_err());assert_eq!(rows,0);assert_eq!(work.calls,0,"equal actual source cannot grant an ordinary purpose authority");
 let admission=dm_analysis::checker_effects::ExecutionAdmission::with_limit(1<<24);let mut work=Work{calls:0,fail:true};let failed=dm_analysis::checks_proc_visibility::visit_original_declaration_redeclarations(input,&admission,&mut work,&||Ok(()),|_|{rows+=1;Ok(())});assert!(matches!(failed,Err(dm_analysis::policy_body_demand::PolicyFailure::Operational(ref actual))if actual.raw_os_error()==Some(1450)));assert_eq!(work.calls,1);assert_eq!(rows,0);
 let admission=dm_analysis::checker_effects::ExecutionAdmission::with_limit(1<<24);let mut work=Work{calls:0,fail:false};dm_analysis::checks_proc_visibility::visit_original_declaration_redeclarations(input,&admission,&mut work,&||Ok(()),|_|{rows+=1;Ok(())}).unwrap();assert_eq!(rows,2,"genuine duplicate Error followed by parser override-precedes-definition Hint");
}

#[cfg(debug_assertions)]#[test]fn original_global_declarations_keep_actual_node_creation_order_not_lexical_or_source_line_sort(){
 for(source,expected)in[(include_bytes!("../../../fixtures/unified_checks/global_declarations_lexical_type_order/project.dme").as_slice(),["/datum/z/child overrides final var \"value\"","/datum/a/child overrides private var \"secret\""]),(include_bytes!("../../../fixtures/unified_checks/global_declarations_builtin_creation_order/project.dme").as_slice(),["/obj overrides final var \"shared\"","/mob overrides final var \"shared\""]) ]{
  let(host,environment)=original_filter_flags_host(source);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();let mut actual=Vec::new();snapshot.visit_original_declarations_and_bodies(&environment,None,&snapshot.tree,|row|{if let super::super::purity::OriginalDeclarationAndBody::Declaration(row)=row{assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread(),before);actual.push(row.diagnostic().message.clone());}Ok(())}).unwrap();assert_eq!(actual,expected,"genuine original type creation order: source z before a; builtin obj before mob despite source mob before obj");assert!(db.db().stats(dm_query::Kind(17)).computed>0);
 }
}

#[cfg(debug_assertions)]#[test]fn original_cli_visibility_preserves_raw_hints_and_real_configuration_can_promote_them(){
 use super::super::purity::{OriginalThroughReaderDeclarations,OriginalThroughGraph,OriginalThroughKeywords,OriginalDeclarationAndBody};use dm_analysis::check_policy::DiagnosticSeverity as S;
 let source=include_bytes!("../../../fixtures/unified_checks/reader_declarations_duplicate_then_global_settings_body/project.dme");
 let(host,environment)=original_filter_flags_host(source);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let mut raw=Vec::new();let mut raw_rows=Vec::new();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();snapshot.visit_original_through_reader_declarations(&environment,None,&snapshot.tree,|row|{
 let record=match &row{
  OriginalThroughReaderDeclarations::Declaration(row)=>{let(_,line,column)=row.borrowed_reported_point().unwrap().coordinates();serde_json::json!({"message":row.diagnostic().message,"level":format!("{:?}",row.original_fixed_level().unwrap_or(S::Error)).to_ascii_lowercase(),"line":line,"column":column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()})},
  OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Declaration(row))))=>{let point=row.origin();serde_json::json!({"message":row.diagnostic().message,"level":format!("{:?}",row.default_severity()).to_ascii_lowercase(),"line":point.line,"column":point.byte_column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()})},
  OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Body{row,..})))=>{let point=match row.location(){dm_analysis::checker_effects::OriginalDiagnosticLocation::Expanded=>input.archive().borrowed_source_note_point(row.diagnostic().span.start).unwrap(),dm_analysis::checker_effects::OriginalDiagnosticLocation::Reader(point)=>input.archive().source_mapping().borrow_stored_original_reported_point(point).unwrap(),_=>panic!("source-only fixture")};let(_,line,column)=point.reported_coordinates();serde_json::json!({"message":row.diagnostic().message,"level":format!("{:?}",row.default_level()).to_ascii_lowercase(),"line":line,"column":column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()})},_=>panic!("no keyword/graph fixture rows")};raw_rows.push(record);
 if let OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Body{row,..})))=row{if row.default_level()==S::Hint{raw.push((row.registration_tag(),row.diagnostic().message.clone()));}}Ok(())}).unwrap();{use sha2::Digest;println!("ORIGINAL_READER_RAW_TRACE {}",serde_json::json!({"case":"raw_default_context","source_sha256":format!("{:x}",sha2::Sha256::digest(source)),"diagnostics":&raw_rows}));}assert_eq!(raw,[(Some("redefined_proc"),"redefining proc /datum/base/work".to_owned())],"raw producer's genuine hint must remain available");
 let configuration=include_bytes!("../../../fixtures/unified_checks/reader_cli_redefined_info/SpacemanDMM.toml");let(host,environment)=original_filter_flags_host_configuration(source,true,Some(configuration));let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let mut rows=Vec::new();snapshot.visit_original_cli_diagnostics(&environment,None,&snapshot.tree,|row,level|{let record=match row{
  OriginalThroughReaderDeclarations::Declaration(row)=>{let(_,line,column)=row.borrowed_reported_point().unwrap().coordinates();serde_json::json!({"message":row.diagnostic().message,"line":line,"column":column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()})},
  OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Declaration(row))))=>{let at=row.origin();serde_json::json!({"message":row.diagnostic().message,"line":at.line,"column":at.byte_column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()})},
  OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Body{row,..})))=>{let point=match row.location(){dm_analysis::checker_effects::OriginalDiagnosticLocation::Expanded=>input.archive().borrowed_source_note_point(row.diagnostic().span.start).unwrap(),dm_analysis::checker_effects::OriginalDiagnosticLocation::Reader(point)=>input.archive().source_mapping().borrow_stored_original_reported_point(point).unwrap(),_=>panic!("actual source-only fixture")};let(_,line,column)=point.reported_coordinates();serde_json::json!({"message":row.diagnostic().message,"line":line,"column":column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()})},_=>panic!("fixture has no kwargs/graph findings")};let mut record=record;record["level"]=format!("{:?}",level).to_ascii_lowercase().into();rows.push(record);Ok(())}).unwrap();assert_eq!(rows.len(),9,"actual configured CLI promotes one genuine hint, never discards it by family");assert_eq!(rows.iter().filter(|row|row["level"]=="info").count(),1);use sha2::Digest;println!("ORIGINAL_READER_CLI_INFO_NATIVE {}",serde_json::json!({"case":"redefined_info","source_sha256":format!("{:x}",sha2::Sha256::digest(source)),"configuration_sha256":format!("{:x}",sha2::Sha256::digest(configuration)),"diagnostics":rows}));
}


#[cfg(debug_assertions)]#[test]fn original_cli_duplicate_formal_has_real_producer_error_registration(){
 use super::super::purity::OriginalThroughReaderDeclarations;use dm_analysis::check_policy::DiagnosticSeverity as S;
 let(host,environment)=original_filter_flags_host(include_bytes!("../../../fixtures/unified_checks/reader_declarations_bodyless_duplicate/project.dme"));let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();let mut declarations=Vec::new();snapshot.visit_original_cli_diagnostics(&environment,None,&snapshot.tree,|row,level|{if let OriginalThroughReaderDeclarations::Declaration(finding)=row{assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread(),before);assert_eq!(finding.original_fixed_level(),Some(S::Error));assert_eq!(finding.registration_tag(),None);assert_eq!(level,S::Error);declarations.push(finding.diagnostic().message.clone());}Ok(())}).unwrap();assert_eq!(declarations,["duplicate definition of proc/work"]);
}
#[cfg(debug_assertions)]#[test]fn original_missing_parent_outcomes_keep_root_recovery_and_full_reader_phase_order(){
 use super::super::purity::{OriginalDeclarationAndBody,OriginalThroughKeywords,OriginalThroughGraph,OriginalThroughReaderDeclarations};
 for(name,source)in[("missing_parent_continuation",include_bytes!("../../../fixtures/unified_checks/missing_parent_outcome_missing_parent_continuation/project.dme").as_slice()),("lexical_parent_then_encounter_constants",include_bytes!("../../../fixtures/unified_checks/missing_parent_outcome_lexical_parent_then_encounter_constants/project.dme").as_slice()),("root_fallback_removes_datum_inheritance",include_bytes!("../../../fixtures/unified_checks/missing_parent_outcome_root_fallback_removes_datum_inheritance/project.dme").as_slice()),("duplicate_before_parent_outcomes",include_bytes!("../../../fixtures/unified_checks/missing_parent_outcome_duplicate_before_parent_outcomes/project.dme").as_slice()),("many_missing_parents",include_bytes!("../../../fixtures/unified_checks/missing_parent_outcome_many_missing_parents/project.dme").as_slice())]{
  let(host,environment)=original_filter_flags_host(source);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let db=snapshot.native_raw_queries.as_ref().unwrap();let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();let mut rows=Vec::new();let mut phases=Vec::new();let mut final_before=None;
  snapshot.visit_original_cli_diagnostics(&environment,None,&snapshot.tree,|row,reported_level|{
   let(phase,mut record)=match row{
    OriginalThroughReaderDeclarations::Declaration(row)=>{assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread(),before,"frontend declaration must not evaluate BODY");let(_,line,column)=row.borrowed_reported_point().unwrap().coordinates();(0,serde_json::json!({"message":row.diagnostic().message,"level":"error","line":line,"column":column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()}))},
    OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Declaration(row))))=>{let point=row.origin();(1,serde_json::json!({"message":row.diagnostic().message,"level":format!("{:?}",row.default_severity()).to_ascii_lowercase(),"line":point.line,"column":point.byte_column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()}))},
    OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Body{row,..})))=>{let phase=match row.phase(){dm_analysis::checker_effects::OriginalDiagnosticPhase::Prelude=>2,dm_analysis::checker_effects::OriginalDiagnosticPhase::Body=>3};let point=match row.location(){dm_analysis::checker_effects::OriginalDiagnosticLocation::Expanded=>input.archive().borrowed_source_note_point(row.diagnostic().span.start).unwrap(),dm_analysis::checker_effects::OriginalDiagnosticLocation::Reader(point)=>input.archive().source_mapping().borrow_stored_original_reported_point(point).unwrap(),dm_analysis::checker_effects::OriginalDiagnosticLocation::ParserSynthetic=>panic!("unrepresented phase source point")};let(_,line,column)=point.reported_coordinates();(phase,serde_json::json!({"message":row.diagnostic().message,"level":format!("{:?}",row.default_level()).to_ascii_lowercase(),"line":line,"column":column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()}))},
    OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Keyword{findings,row}))=>{let count=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();assert_eq!(count-before,input.archive().len()as u64,"{name}: keyword finalization reevaluated a BODY");final_before.get_or_insert(count);let(_,line,column)=findings.point(row.point).unwrap().coordinates();(4,serde_json::json!({"message":row.message,"level":"error","line":line,"column":column,"notes":row.notes.iter().map(|note|findings.legacy_note(row.point,note).unwrap().to_string()).collect::<Vec<_>>()}))},
    OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Graph(row))=>{let count=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();assert_eq!(count-before,input.archive().len()as u64,"{name}: graph report reevaluated a BODY");let phase=match row.phase(){dm_analysis::checker_effects::ProducedPhase::SleepGraph=>5,dm_analysis::checker_effects::ProducedPhase::PurityGraph=>6,dm_analysis::checker_effects::ProducedPhase::BodyImmediate=>panic!("immediate BODY effect was delivered twice")};(phase,serde_json::json!({"message":row.diagnostic.message,"level":format!("{:?}",row.severity).to_ascii_lowercase(),"line":row.origin.line,"column":row.origin.byte_column,"notes":row.diagnostic.notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()}))},
   };record["level"]=format!("{:?}",reported_level).to_ascii_lowercase().into();if let Some(previous)=phases.last(){assert!(*previous<=phase,"{name}: phase interleaving {phases:?} then {phase}")};phases.push(phase);rows.push(record);Ok(())
  }).unwrap();
  assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,input.archive().len()as u64,"{name}");
  let expected:Vec<u8>=match name{"missing_parent_continuation"=>vec![0,0,2,3],"lexical_parent_then_encounter_constants"=>vec![0,0,0,0,2,3],"root_fallback_removes_datum_inheritance"=>vec![0,0,2,3],"duplicate_before_parent_outcomes"=>vec![0,0,0,2,3],"many_missing_parents"=>std::iter::repeat_n(0,32).chain([2,3]).collect(),_=>unreachable!()};assert_eq!(phases,expected,"{name}");
  let parsed=db.db().stats(dm_query::Kind(4)).computed;let body_count=db.db().stats(dm_query::Kind(17)).computed;let mut retry=Vec::new();snapshot.visit_original_cli_diagnostics(&environment,None,&snapshot.tree,|row,_reported_level|{retry.push(match row{OriginalThroughReaderDeclarations::Declaration(row)=>row.diagnostic().message.clone(),OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Declaration(row))))=>row.diagnostic().message.clone(),OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Body{row,..})))=>row.diagnostic().message.clone(),OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Keyword{row,..}))=>row.message.clone(),OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Graph(row))=>row.diagnostic.message.clone()});Ok(())}).unwrap();assert_eq!(retry,rows.iter().map(|r|r["message"].as_str().unwrap().to_owned()).collect::<Vec<_>>());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,parsed);assert_eq!(db.db().stats(dm_query::Kind(17)).computed,body_count);assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,input.archive().len()as u64);
  use sha2::Digest;println!("ORIGINAL_MISSING_PARENT_OUTCOME_NATIVE {}",serde_json::json!({"case":name,"source_sha256":format!("{:x}",sha2::Sha256::digest(source)),"diagnostics":rows}));
 }
}


#[cfg(debug_assertions)]#[test]fn original_missing_parent_projection_is_peak_funded_and_keeps_typed_poll_oom_failures(){
 struct Work{calls:usize,fail_at:Option<usize>}impl dm_analysis::checker_effects::EffectReportWork for Work{type Mark=();fn mark(&mut self)->std::io::Result<()>{Ok(())}fn reconcile(&mut self,_:(),_:usize)->std::io::Result<()>{Ok(())}fn reserve(&mut self,_:usize)->std::io::Result<()>{self.calls+=1;if self.fail_at==Some(self.calls){Err(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"actual parent projection escrow refusal"))}else{Ok(())}}}
 let(host,_)=original_filter_flags_host(include_bytes!("../../../fixtures/unified_checks/missing_parent_outcome_many_missing_parents/project.dme"));let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();
 for stop in [2usize,15,40,80]{let polls=std::cell::Cell::new(0);let poll=||{let next=polls.get()+1;polls.set(next);if next==stop{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}};let mut work=Work{calls:0,fail_at:None};let admission=dm_analysis::checker_effects::ExecutionAdmission::with_limit(1<<24);let mut emitted=0;let bad=dm_analysis::checks_proc_visibility::visit_original_declaration_redeclarations(input,&admission,&mut work,&poll,|_|{emitted+=1;Ok(())});assert!(matches!(bad,Err(dm_analysis::policy_body_demand::PolicyFailure::Operational(ref actual))if actual.raw_os_error()==Some(1450)),"stop={stop}");assert_eq!(polls.get(),stop);assert_eq!(emitted,0);}
 let mut work=Work{calls:0,fail_at:Some(2)};let admission=dm_analysis::checker_effects::ExecutionAdmission::with_limit(1<<24);let mut emitted=0;let bad=dm_analysis::checks_proc_visibility::visit_original_declaration_redeclarations(input,&admission,&mut work,&||Ok(()),|_|{emitted+=1;Ok(())});assert!(matches!(bad,Err(dm_analysis::policy_body_demand::PolicyFailure::Operational(ref actual))if actual.kind()==std::io::ErrorKind::OutOfMemory));assert_eq!(emitted,0);
 let mut work=Work{calls:0,fail_at:None};let admission=dm_analysis::checker_effects::ExecutionAdmission::with_limit(1<<24);dm_analysis::checks_proc_visibility::visit_original_declaration_redeclarations(input,&admission,&mut work,&||Ok(()),|_|{emitted+=1;Ok(())}).unwrap();assert_eq!(emitted,32);assert_eq!(work.calls,3,"one duplicate scratch peak, one projection, one shared path/output peak, independent of row count");assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread(),before);
}

#[cfg(debug_assertions)]#[test]fn original_parser_override_precedes_definition_hint_uses_real_events_and_config_promotions(){
 use super::super::purity::{OriginalThroughReaderDeclarations,OriginalThroughGraph,OriginalThroughKeywords,OriginalDeclarationAndBody};use sha2::Digest;
 for(name,source,configuration)in[("global_formals",include_bytes!("../../../fixtures/unified_checks/reader_hint_global_formals/project.dme").as_slice(),include_bytes!("../../../fixtures/unified_checks/reader_hint_global_formals/SpacemanDMM.toml").as_slice()),("override_info",include_bytes!("../../../fixtures/unified_checks/reader_hint_override_info/project.dme").as_slice(),include_bytes!("../../../fixtures/unified_checks/reader_hint_override_info/SpacemanDMM.toml").as_slice()),("override_warning",include_bytes!("../../../fixtures/unified_checks/reader_hint_override_warning/project.dme").as_slice(),include_bytes!("../../../fixtures/unified_checks/reader_hint_override_warning/SpacemanDMM.toml").as_slice()),("both_info",include_bytes!("../../../fixtures/unified_checks/reader_hint_both_info/project.dme").as_slice(),include_bytes!("../../../fixtures/unified_checks/reader_hint_both_info/SpacemanDMM.toml").as_slice()),("override_before_formal",include_bytes!("../../../fixtures/unified_checks/reader_hint_override_before_formal/project.dme").as_slice(),include_bytes!("../../../fixtures/unified_checks/reader_hint_override_before_formal/SpacemanDMM.toml").as_slice()),("three_formals",include_bytes!("../../../fixtures/unified_checks/reader_hint_three_formals/project.dme").as_slice(),include_bytes!("../../../fixtures/unified_checks/reader_hint_three_formals/SpacemanDMM.toml").as_slice()),("distinct_owner_negative",include_bytes!("../../../fixtures/unified_checks/reader_hint_distinct_owner_negative/project.dme").as_slice(),include_bytes!("../../../fixtures/unified_checks/reader_hint_distinct_owner_negative/SpacemanDMM.toml").as_slice())]{
  let(host,environment)=original_filter_flags_host_configuration(source,true,Some(configuration));let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let db=snapshot.native_raw_queries.as_ref().unwrap();let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();let mut rows=Vec::new();snapshot.visit_original_cli_diagnostics(&environment,None,&snapshot.tree,|row,level|{let record=match row{
  OriginalThroughReaderDeclarations::Declaration(row)=>{let(_,line,column)=row.borrowed_reported_point().unwrap().coordinates();serde_json::json!({"message":row.diagnostic().message,"line":line,"column":column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()})},
  OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Declaration(row))))=>{let at=row.origin();serde_json::json!({"message":row.diagnostic().message,"line":at.line,"column":at.byte_column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()})},
  OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Body{row,..})))=>{let point=match row.location(){dm_analysis::checker_effects::OriginalDiagnosticLocation::Expanded=>input.archive().borrowed_source_note_point(row.diagnostic().span.start).unwrap(),dm_analysis::checker_effects::OriginalDiagnosticLocation::Reader(point)=>input.archive().source_mapping().borrow_stored_original_reported_point(point).unwrap(),_=>panic!("actual source-only fixture")};let(_,line,column)=point.reported_coordinates();serde_json::json!({"message":row.diagnostic().message,"line":line,"column":column,"notes":row.diagnostic().notes.iter().map(|note|note.legacy_text()).collect::<Vec<_>>()})},_=>panic!("fixture has no kwargs/graph findings")};let mut record=record;record["level"]=format!("{:?}",level).to_ascii_lowercase().into();rows.push(record);Ok(())}).unwrap();
  println!("ORIGINAL_READER_HINT_NATIVE {}",serde_json::json!({"case":name,"source_sha256":format!("{:x}",sha2::Sha256::digest(source)),"configuration_sha256":format!("{:x}",sha2::Sha256::digest(configuration)),"diagnostics":&rows}));
  let count=match name{"override_info"|"override_warning"=>9,"both_info"=>10,"override_before_formal"=>1,"three_formals"=>4,"global_formals"=>2,"distinct_owner_negative"=>0,_=>unreachable!()};assert_eq!(rows.len(),count,"{name}");
  if name=="three_formals"{assert_eq!(rows.iter().map(|row|(row["line"].as_u64().unwrap(),row["level"].as_str().unwrap())).collect::<Vec<_>>(),[(3,"error"),(1,"info"),(5,"error"),(3,"info")]);}
  assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before,input.archive().len()as u64,"genuine declaration Hint must never evaluate BODY itself");
  let q4=db.db().stats(dm_query::Kind(4)).computed;let q17=db.db().stats(dm_query::Kind(17)).computed;let mut retry=Vec::new();snapshot.visit_original_cli_diagnostics(&environment,None,&snapshot.tree,|row,level|{let message=match row{OriginalThroughReaderDeclarations::Declaration(row)=>row.diagnostic().message.clone(),OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Declaration(row))))=>row.diagnostic().message.clone(),OriginalThroughReaderDeclarations::Semantic(OriginalThroughGraph::Source(OriginalThroughKeywords::Source(OriginalDeclarationAndBody::Body{row,..})))=>row.diagnostic().message.clone(),_=>panic!("fixture has no kwargs/graph findings")};retry.push((message,format!("{:?}",level).to_ascii_lowercase()));Ok(())}).unwrap();assert_eq!(retry,rows.iter().map(|row|(row["message"].as_str().unwrap().to_owned(),row["level"].as_str().unwrap().to_owned())).collect::<Vec<_>>());assert_eq!(q4,db.db().stats(dm_query::Kind(4)).computed);assert_eq!(q17,db.db().stats(dm_query::Kind(17)).computed);
 }
}

#[cfg(debug_assertions)]#[test]fn original_builtin_declaration_hints_use_pinned_own_registration_and_real_builtin_location(){
 use super::super::purity::OriginalThroughReaderDeclarations;use sha2::Digest;
 for(name,source,configuration)in[("obj_new_override",include_bytes!("../../../fixtures/unified_checks/reader_hint_builtin_obj_new_override/project.dme").as_slice(),include_bytes!("../../../fixtures/unified_checks/reader_hint_builtin_obj_new_override/SpacemanDMM.toml").as_slice()),("obj_new_formal",include_bytes!("../../../fixtures/unified_checks/reader_hint_builtin_obj_new_formal/project.dme").as_slice(),include_bytes!("../../../fixtures/unified_checks/reader_hint_builtin_obj_new_formal/SpacemanDMM.toml").as_slice()),("list_add_override",include_bytes!("../../../fixtures/unified_checks/reader_hint_builtin_list_add_override/project.dme").as_slice(),include_bytes!("../../../fixtures/unified_checks/reader_hint_builtin_list_add_override/SpacemanDMM.toml").as_slice()),("list_add_formal",include_bytes!("../../../fixtures/unified_checks/reader_hint_builtin_list_add_formal/project.dme").as_slice(),include_bytes!("../../../fixtures/unified_checks/reader_hint_builtin_list_add_formal/SpacemanDMM.toml").as_slice()),("mob_login_formal",include_bytes!("../../../fixtures/unified_checks/reader_hint_builtin_mob_login_formal/project.dme").as_slice(),include_bytes!("../../../fixtures/unified_checks/reader_hint_builtin_mob_login_formal/SpacemanDMM.toml").as_slice())]{
  let(host,environment)=original_filter_flags_host_configuration(source,true,Some(configuration));let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let before=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();let mut rows=Vec::new();let fixture_physical=environment.canonicalize().unwrap();let mut fixture_registration:Option<PathBuf>=None;snapshot.visit_original_cli_diagnostics(&environment,None,&snapshot.tree,|row,level|{let OriginalThroughReaderDeclarations::Declaration(row)=row else{panic!("builtin source controls have no semantic findings")};assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread(),before,"actual catalog registration does not evaluate BODY");let point=row.borrowed_reported_point().unwrap();let(path,line,column)=point.coordinates();let file=if path==std::path::Path::new("(builtins)"){"(builtins)"}else{let dm_analysis::checks_proc_visibility::BorrowedReportedPoint::Source(source)=&point else{panic!("genuine fixture source cursor")};assert_eq!(source.physical_path().canonicalize().unwrap(),fixture_physical);if let Some(prior)=&fixture_registration{assert_eq!(prior.as_path(),path)}else{fixture_registration=Some(path.to_path_buf())}"project.dme"};let notes=row.diagnostic().notes.iter().map(|note|{let note=note.legacy_text();match fixture_registration.as_deref(){Some(fixture)=>exact_original_fixture_note(note,fixture),None=>note}}).collect::<Vec<_>>();rows.push(serde_json::json!({"file":file,"message":row.diagnostic().message,"level":format!("{:?}",level).to_ascii_lowercase(),"line":line,"column":column,"notes":notes}));Ok(())}).unwrap();println!("ORIGINAL_BUILTIN_READER_HINT_NATIVE {}",serde_json::json!({"case":name,"source_sha256":format!("{:x}",sha2::Sha256::digest(source)),"configuration_sha256":format!("{:x}",sha2::Sha256::digest(configuration)),"diagnostics":&rows}));let expected=if matches!(name,"list_add_formal"|"mob_login_formal"){2}else{0};assert_eq!(rows.len(),expected,"{name}: inherited New is not an own builtin registration; override is not formal declaration");if expected==2{assert_eq!(rows[0]["level"],"error");assert_eq!(rows[0]["notes"],serde_json::json!(["(builtins):1:1: previous definition"]));assert_eq!(rows[1]["file"],"(builtins)");assert_eq!(rows[1]["line"],1);assert_eq!(rows[1]["column"],1);assert_eq!(rows[1]["level"],"info");}
 }
}

#[cfg(debug_assertions)]#[test]fn original_cli_aggregate_borrows_one_real_current_configuration_scope_for_all_phases(){
 use super::super::purity::{OriginalThroughReaderDeclarations as Reader,OriginalThroughGraph as Graph,OriginalThroughKeywords as Keywords,OriginalDeclarationAndBody as Source};
 for(name,source,configuration)in[("reader_and_global",include_bytes!("../../../fixtures/unified_checks/reader_declarations_duplicate_then_global_settings_body/project.dme").as_slice(),None),("nonempty_kwargs_and_both_graphs",include_bytes!("../../../fixtures/unified_checks/final_graph_kwargs_before_graph/project.dme").as_slice(),None),("real_configured_hint",include_bytes!("../../../fixtures/unified_checks/reader_cli_redefined_info/project.dme").as_slice(),Some(include_bytes!("../../../fixtures/unified_checks/reader_cli_redefined_info/SpacemanDMM.toml").as_slice()))]{
  let(host,environment)=original_filter_flags_host_configuration(source,true,configuration);let state=host.query_state();let state=state.lock().unwrap();let snapshot=state.snapshot.as_ref().unwrap();let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap().input();let db=snapshot.native_raw_queries.as_ref().unwrap();let before_scope=super::super::purity::original_scope_loads_on_current_thread();let before_body=dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();
  let read=||{let mut rows=Vec::new();snapshot.visit_original_cli_diagnostics(&environment,None,&snapshot.tree,|row,level|{let(phase,message)=match row{Reader::Declaration(row)=>(0,row.diagnostic().message.clone()),Reader::Semantic(Graph::Source(Keywords::Source(Source::Declaration(row))))=>(1,row.diagnostic().message.clone()),Reader::Semantic(Graph::Source(Keywords::Source(Source::Body{row,..})))=>(match row.phase(){dm_analysis::checker_effects::OriginalDiagnosticPhase::Prelude=>2,dm_analysis::checker_effects::OriginalDiagnosticPhase::Body=>3},row.diagnostic().message.clone()),Reader::Semantic(Graph::Source(Keywords::Keyword{row,..}))=>(4,row.message.clone()),Reader::Semantic(Graph::Graph(row))=>(match row.phase(){dm_analysis::checker_effects::ProducedPhase::SleepGraph=>5,dm_analysis::checker_effects::ProducedPhase::PurityGraph=>6,dm_analysis::checker_effects::ProducedPhase::BodyImmediate=>panic!("immediate diagnostics cannot be replayed as final graph")},row.diagnostic.message.clone())};rows.push((phase,message,level));Ok(())}).unwrap();rows};
  let rows=read();assert!(!rows.is_empty());assert_eq!(super::super::purity::original_scope_loads_on_current_thread(),before_scope+1,"{name}: every real phase borrows one loaded current scope");assert!(rows.windows(2).all(|pair|pair[0].0<=pair[1].0),"{name}: {rows:?}");if name=="nonempty_kwargs_and_both_graphs"{for phase in [2,3,4,5,6]{assert!(rows.iter().any(|row|row.0==phase),"{name}: phase {phase} missing {rows:?}");}}
  assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before_body,input.archive().len()as u64);let q4=db.db().stats(dm_query::Kind(4)).computed;let q17=db.db().stats(dm_query::Kind(17)).computed;assert_eq!(read(),rows);assert_eq!(super::super::purity::original_scope_loads_on_current_thread(),before_scope+2);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,q4);assert_eq!(db.db().stats(dm_query::Kind(17)).computed,q17);assert_eq!(dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()-before_body,input.archive().len()as u64,"one scope must not change once-only BODY reuse");
  let mut calls=0;let failed=snapshot.visit_original_cli_diagnostics(&environment,None,&snapshot.tree,|_,_|{calls+=1;Err(std::io::Error::from_raw_os_error(1450))});assert_eq!(failed.unwrap_err().raw_os_error(),Some(1450));assert_eq!(calls,1);assert_eq!(super::super::purity::original_scope_loads_on_current_thread(),before_scope+3);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,q4);assert_eq!(db.db().stats(dm_query::Kind(17)).computed,q17);
 }
}

#[cfg(debug_assertions)]
fn exact_original_fixture_note(note:String,fixture:&std::path::Path)->String{
 let prefix=format!("{}:",fixture.display());
 match note.strip_prefix(&prefix){Some(point)=>format!("<fixture>/project.dme:{point}"),None=>note}
}
#[cfg(debug_assertions)]#[test]fn builtin_fixture_note_transport_normalizes_only_its_genuine_exact_registered_filename(){
 let fixture=std::path::Path::new(r"\\?\E:\dq-cache\test-scratch\owned\project.dme");
 let owned=format!("{}:1:15: /list/proc/Add is defined here",fixture.display());
 assert_eq!(exact_original_fixture_note(owned,fixture),"<fixture>/project.dme:1:15: /list/proc/Add is defined here");
 for note in ["(builtins):1:1: previous definition",r"\\?\E:\dq-cache\test-scratch\another\project.dme:1:15: different source",r"\\?\E:\dq-cache\test-scratch\owned\project.dme.extra:1:15: different filename",r"message mentioning \\?\E:\dq-cache\test-scratch\owned\project.dme inside text"]{
  assert_eq!(exact_original_fixture_note(note.to_owned(),fixture),note);
 }
}
