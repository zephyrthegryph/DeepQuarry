//! Host integration: borrowed checker context keeps primary syntax, source owner
//! and existing scalar answer world. This is not a second query database.
use super::*;
use dm_analysis::{checker_context::CheckerContext, checks::Severity};
use dm_ir::{ResolveQuery as Q, Resolver, SymbolId};
use dm_tree::frontend::{build_with_config, ColdFrontend, FrontendConfig};
#[path = "../../../dm-analysis/examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn build(source: &'static str, db: &Arc<QueryDb>) -> ColdFrontend {
    let seed = reference_hierarchy::seed();
    build_with_config(
        std::path::Path::new("checker-context.dme"),
        &Source(source),
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap()
    .with_body_queries(db.clone())
}
const SOURCE: &str = "/datum/example/proc/probe()\n    return ..()\n";

#[test]
fn original_owner_and_answer_world_survive_checker_queries_and_primary_eviction() {
    let db = Arc::new(QueryDb::default());
    let frontend = build(SOURCE, &db);
    let tree = &frontend.snapshot.tree;
    let identity = tree.identity();
    let world = tree.answer_world();
    let normal = Q::Ancestry(SymbolId::of("/datum/example"));
    let expected = Resolver::resolve(tree.as_ref(), normal);
    let resolve = |query: &Q| Resolver::resolve(tree.as_ref(), *query);
    db.next_request();
    db.begin_answers(tree, world, &resolve);
    db.request_answers(&resolve)
        .current(query_id(&normal), &normal);
    let held = db.answer_counts().2;
    let archive = frontend.body_archive().unwrap();
    assert!(archive.matches_tree(tree));
    let profile = tree.checker_builtin_profile().unwrap();
    let context = CheckerContext::archived(&archive, db.as_ref(), tree.as_ref(), profile).unwrap();
    assert!(std::ptr::eq(context.tree(), tree.as_ref()));
    assert!(std::ptr::eq(context.resolver(), tree.as_ref()));
    let first = archive.parse(0).unwrap();
    let first_rows = context.parent_archived(&first, Severity::Error).unwrap();
    assert_eq!(first_rows.len(), 1);
    assert_eq!(
        first_rows[0].message,
        "proc has no parent: /datum/example/proc/probe"
    );
    db.db.evict_values(&[body_syntax::BODY_SYNTAX]);
    let rebuilt = archive.parse(0).unwrap();
    assert!(!std::ptr::eq(
        first.statement_body(),
        rebuilt.statement_body()
    ));
    let rows = context.parent_archived(&rebuilt, Severity::Error).unwrap();
    assert_eq!(rows[0].message, first_rows[0].message);
    assert_eq!(rows[0].span, first_rows[0].span);
    assert_eq!(tree.identity(), identity);
    assert_eq!(tree.answer_world(), world);
    assert_eq!(Resolver::resolve(tree.as_ref(), normal), expected);
    // Re-enter the SAME native answer world: fixed catalog selection did not
    // invalidate/re-key any common source answer or change the held normal key.
    db.next_request();
    db.begin_answers(tree, world, &resolve);
    db.request_answers(&resolve)
        .current(query_id(&normal), &normal);
    assert_eq!(db.answer_counts().2, held);
    assert!(db.answer_counts().1 >= 1);
}

#[test]
fn equal_bytes_cannot_rebind_foreign_archive_or_compiler_query_graph() {
    let db = Arc::new(QueryDb::default());
    let a = build(SOURCE, &db);
    let b = build(SOURCE, &db);
    let archive = a.body_archive().unwrap();
    let foreign = b.body_archive().unwrap();
    let profile = archive.tree().checker_builtin_profile().unwrap();
    let context = CheckerContext::archived(&archive, db.as_ref(), archive.tree(), profile).unwrap();
    // Equal source/answers do not authenticate a different native owner.
    assert_eq!(a.snapshot.tree.identity(), b.snapshot.tree.identity());
    assert!(
        CheckerContext::archived(&archive, db.as_ref(), b.snapshot.tree.as_ref(), profile)
            .err()
            .unwrap()
            .contains("provenance")
    );
    assert!(CheckerContext::live(&a, b.snapshot.tree.as_ref(), profile)
        .err()
        .unwrap()
        .contains("provenance"));
    let copied_tree = a.snapshot.tree.as_ref().clone();
    assert!(CheckerContext::live(&a, &copied_tree, profile).is_err());
    assert!(context
        .parent_archived(&foreign.parse(0).unwrap(), Severity::Error)
        .unwrap_err()
        .contains("another compiler archive"));
    let other_db = QueryDb::default();
    assert!(CheckerContext::archived(&archive, &other_db, archive.tree(), profile).is_err());
    assert!(CheckerContext::archived(
        &archive,
        db.as_ref(),
        archive.tree(),
        dm_ir::PackedU128::new(profile.get() ^ 1)
    )
    .is_err());
}

#[test]
fn body_edit_retracts_parent_result_without_rebinding_old_archive() {
    let db = Arc::new(QueryDb::default());
    let old = build(SOURCE, &db);
    let new = build("/datum/example/proc/probe()\n    return 1\n", &db);
    let old_archive = old.body_archive().unwrap();
    let new_archive = new.body_archive().unwrap();
    let profile = old_archive.tree().checker_builtin_profile().unwrap();
    let old_context =
        CheckerContext::archived(&old_archive, db.as_ref(), old_archive.tree(), profile).unwrap();
    let new_context =
        CheckerContext::archived(&new_archive, db.as_ref(), new_archive.tree(), profile).unwrap();
    assert_eq!(
        old_context
            .parent_archived(&old_archive.parse(0).unwrap(), Severity::Error)
            .unwrap()
            .len(),
        1
    );
    assert!(new_context
        .parent_archived(&new_archive.parse(0).unwrap(), Severity::Error)
        .unwrap()
        .is_empty());
    assert!(new_context
        .parent_archived(&old_archive.parse(0).unwrap(), Severity::Error)
        .is_err());
}

#[test]
fn transparent_answers_without_compiler_owner_provenance_are_not_authority() {
    struct Unproven<'a>(&'a dm_tree::SemanticTree);
    impl Resolver for Unproven<'_> {
        fn answer_world(&self) -> Option<u128> {
            self.0.answer_world()
        }
        fn resolve(&self, query: Q) -> dm_ir::ResolvedMeaning {
            Resolver::resolve(self.0, query)
        }
    }
    let db = Arc::new(QueryDb::default());
    let frontend = build(SOURCE, &db);
    let archive = frontend.body_archive().unwrap();
    let profile = archive.tree().checker_builtin_profile().unwrap();
    let wrapper = Unproven(archive.tree());
    assert_eq!(wrapper.answer_world(), archive.tree().answer_world());
    assert!(CheckerContext::live(&frontend, &wrapper, profile).is_err());
    assert!(CheckerContext::archived(&archive, db.as_ref(), &wrapper, profile).is_err());
}

fn prefix_identity(
    archive: &dm_tree::frontend::BodyArchive,
    name: &str,
) -> dm_ir::ProcedureIdentity {
    for occurrence in archive.occurrences() {
        let member = archive.tree().member(occurrence.member).unwrap();
        if member.name == SymbolId::of(name) {
            return dm_ir::ProcedureIdentity {
                owner: archive.tree().type_node(member.owner).unwrap().path,
                name: member.name,
                verb: member.kind == dm_tree::MemberKind::Verb,
                occurrence: archive.tree().member_occurrence(occurrence.member).unwrap(),
            };
        }
    }
    panic!("missing issued prefix fixture {name}")
}
#[test]
fn initial_settings_are_a_contiguous_primary_syntax_prefix_not_a_flat_metadata_list() {
    const SOURCE:&str="/datum/target\n/proc/early()\n    set SpacemanDMM_return_type=/datum/target\n    return null\n/proc/late()\n    . = null\n    set SpacemanDMM_return_type=/datum/target\n    return null\n/proc/conditional()\n    if(1)\n        set SpacemanDMM_return_type=/datum/target\n    return null\n";
    let db = Arc::new(QueryDb::default());
    let frontend = build(SOURCE, &db);
    let archive = frontend.body_archive().unwrap();
    for (name, count) in [("early", 1), ("late", 0), ("conditional", 0)] {
        let id = prefix_identity(&archive, name);
        let first = archive
            .with_initial_setting_prefix(id, |proof| {
                assert!(proof.belongs_to(&archive));
                assert!(std::ptr::eq(proof.tree(), archive.tree()));
                assert_eq!(proof.identity(), id);
                assert_eq!(proof.settings().len(), count);
                (
                    proof
                        .settings()
                        .iter()
                        .map(|s| s.header_span)
                        .collect::<Vec<_>>(),
                    proof.first_non_setting(),
                )
            })
            .unwrap();
        db.db.evict_values(&[body_syntax::BODY_SYNTAX]);
        let rebuilt = archive
            .with_initial_setting_prefix(id, |proof| {
                (
                    proof
                        .settings()
                        .iter()
                        .map(|s| s.header_span)
                        .collect::<Vec<_>>(),
                    proof.first_non_setting(),
                )
            })
            .unwrap();
        assert_eq!(first, rebuilt);
    }
    let profile = archive.tree().checker_builtin_profile().unwrap();
    for (name, expected) in [
        ("early", Some(SymbolId::of("/datum/target"))),
        ("late", None),
        ("conditional", None),
    ] {
        let hint = dm_analysis::checker_return_facts::return_hint_with_prefix(
            archive.tree(),
            archive.tree(),
            profile,
            SymbolId::of("/"),
            SymbolId::of(name),
            Some(&archive),
        )
        .unwrap();
        assert_eq!(hint.declared_type, expected, "{name}");
    }
    let foreign = build(SOURCE, &db).body_archive().unwrap();
    assert!(dm_analysis::checker_return_facts::return_hint_with_prefix(
        archive.tree(),
        archive.tree(),
        profile,
        SymbolId::of("/"),
        SymbolId::of("early"),
        Some(&foreign)
    )
    .is_err());
    assert!(dm_analysis::checker_return_facts::return_hint(
        archive.tree(),
        archive.tree(),
        profile,
        SymbolId::of("/"),
        SymbolId::of("early")
    )
    .is_err());
    let wrong = dm_ir::ProcedureIdentity {
        occurrence: u32::MAX,
        ..prefix_identity(&archive, "early")
    };
    assert!(archive.with_initial_setting_prefix(wrong, |_| ()).is_err());
}
#[test]
fn initial_return_settings_override_headers_in_order_and_null_clears_the_hint() {
    const SOURCE:&str="/datum/target\n/proc/last() as /datum/target\n    set name=\"last\"\n    set SpacemanDMM_return_type=/turf\n    set SpacemanDMM_return_type=/datum/target\n    return null\n/proc/clear() as /datum/target\n    set SpacemanDMM_return_type=null\n    return null\n";
    let db = Arc::new(QueryDb::default());
    let frontend = build(SOURCE, &db);
    let archive = frontend.body_archive().unwrap();
    let profile = archive.tree().checker_builtin_profile().unwrap();
    for (name, expected) in [
        ("last", Some(SymbolId::of("/datum/target"))),
        ("clear", None),
    ] {
        assert_eq!(
            dm_analysis::checker_return_facts::return_hint_with_prefix(
                archive.tree(),
                archive.tree(),
                profile,
                SymbolId::of("/"),
                SymbolId::of(name),
                Some(&archive)
            )
            .unwrap()
            .declared_type,
            expected
        );
    }
}
#[test]
fn source_edit_retracts_prefix_without_mutating_the_old_issued_archive() {
    let db = Arc::new(QueryDb::default());
    let old = build(
        "/proc/probe()\n    set SpacemanDMM_return_type=/turf\n    return null\n",
        &db,
    );
    let new = build(
        "/proc/probe()\n    . = null\n    set SpacemanDMM_return_type=/turf\n    return null\n",
        &db,
    );
    let a = old.body_archive().unwrap();
    let b = new.body_archive().unwrap();
    assert_eq!(
        a.with_initial_setting_prefix(prefix_identity(&a, "probe"), |p| p.settings().len())
            .unwrap(),
        1
    );
    assert_eq!(
        b.with_initial_setting_prefix(prefix_identity(&b, "probe"), |p| p.settings().len())
            .unwrap(),
        0
    );
    assert_eq!(
        a.with_initial_setting_prefix(prefix_identity(&a, "probe"), |p| p.settings().len())
            .unwrap(),
        1
    );
}
#[test]
fn independent_three_row_prefix_fixture_retains_the_unimplemented_warning_as_unsupported() {
    const SOURCE: &str = include_str!("../../../../fixtures/unified_checks/return_prefix/probe.dm");
    let db = Arc::new(QueryDb::default());
    let frontend = build(SOURCE, &db);
    let archive = frontend.body_archive().unwrap();
    let profile = archive.tree().checker_builtin_profile().unwrap();
    let context = CheckerContext::archived(&archive, db.as_ref(), archive.tree(), profile).unwrap();
    for (ordinal, occurrence) in archive.occurrences().iter().enumerate() {
        let name = archive.tree().member(occurrence.member).unwrap().name;
        let body = archive.parse(ordinal).unwrap();
        if name == SymbolId::of("late") {
            let rows = dm_analysis::checks_set_no_effect::archived(&body, Severity::Error).unwrap();
            assert_eq!(rows.len(), 1);
            assert_eq!(rows[0].message, "set statement not at the top of the proc");
            assert_eq!(archive.location(rows[0].span.start).unwrap().line, 7);
        }
        if name == SymbolId::of("probe") {
            // Do NOT drop late().absent_late or filter the independent oracle's
            // warning. Atomic failure explicitly admits incomplete coverage.
            assert_eq!(context.variables_archived(&body, true).unwrap().len(), 1);
            // This OLD read(String)-only fixture has no authentic acquisition;
            // missing note-source proof remains Unsupported. New acquired-source
            // tests below prove the positive path instead of weakening guards.
            assert!(context.fields_archived(&body, Severity::Warning).is_err());
        }
    }
    let hint = dm_analysis::checker_return_facts::return_hint_with_prefix(
        archive.tree(),
        archive.tree(),
        profile,
        SymbolId::of("/"),
        SymbolId::of("early"),
        Some(&archive),
    )
    .unwrap();
    assert_eq!(hint.declared_type, Some(SymbolId::of("/datum/target")));
}

fn build_note_source(source: &'static str, db: &Arc<QueryDb>) -> ColdFrontend {
    struct Issued(dm_preprocess::AcquiredSource);
    impl dm_preprocess::SourceProvider for Issued {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Err("original acquisition required".into())
        }
        fn acquired_source(
            &self,
            _: &std::path::Path,
        ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
            Ok(Some(self.0.clone()))
        }
        fn source_acquisition(
            &self,
            _: &std::path::Path,
            text: &dm_preprocess::SourceText,
        ) -> Option<dm_preprocess::AcquiredSource> {
            self.0
                .prepared()
                .original()
                .same_view(text)
                .then(|| self.0.clone())
        }
    }
    let source = Issued(dm_preprocess::AcquiredSource::from_original_bytes(
        source.as_bytes().to_vec(),
        (),
    ));
    let seed = reference_hierarchy::seed();
    build_with_config(
        std::path::Path::new("source-notes.dme"),
        &source,
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap()
    .with_body_queries(db.clone())
}
#[test]
fn original_callable_note_survives_frontend_drop_and_primary_eviction_without_copying_source() {
    let db = Arc::new(QueryDb::default());
    let front = build_note_source(
        "/proc/untyped()\n    return null\n/proc/probe()\n    untyped().field\n",
        &db,
    );
    let archive = front.body_archive().unwrap();
    let id = prefix_identity(&archive, "untyped");
    let expected = archive.callable_note_origin(id).unwrap();
    assert_eq!((expected.line, expected.byte_column), (1, 14));
    drop(front);
    db.db.evict_values(&[body_syntax::BODY_SYNTAX]);
    assert_eq!(archive.callable_note_origin(id).unwrap(), expected);
    let profile = archive.tree().checker_builtin_profile().unwrap();
    let context = CheckerContext::archived(&archive, db.as_ref(), archive.tree(), profile).unwrap();
    let body = archive.parse(1).unwrap();
    let rows = context.fields_archived(&body, Severity::Warning).unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(
        rows[0].notes[0].legacy_text(),
        "1:14: add a return type annotation to /proc/untyped"
    );
}
#[test]
fn acquired_return_prefix_fixture_emits_the_exact_previously_unimplemented_third_note() {
    let db = Arc::new(QueryDb::default());
    let front = build_note_source(
        include_str!("../../../../fixtures/unified_checks/return_prefix/probe.dm"),
        &db,
    );
    let archive = front.body_archive().unwrap();
    let profile = archive.tree().checker_builtin_profile().unwrap();
    let context = CheckerContext::archived(&archive, db.as_ref(), archive.tree(), profile).unwrap();
    let mut findings = Vec::new();
    for (ordinal, _) in dm_analysis::checker_order::bodies(&front).unwrap() {
        let body = archive.parse(ordinal).unwrap();
        for row in dm_analysis::checks_set_no_effect::archived(&body, Severity::Error)
            .unwrap()
            .into_iter()
            .chain(context.variables_archived(&body, true).unwrap())
            .chain(context.fields_archived(&body, Severity::Warning).unwrap())
        {
            findings.push((
                archive.location(row.span.start).unwrap().line,
                row.message,
                row.notes
                    .iter()
                    .map(|n| n.legacy_text())
                    .collect::<Vec<_>>(),
            ));
        }
    }
    assert_eq!(
        findings,
        vec![
            (7, "set statement not at the top of the proc".into(), vec![]),
            (
                10,
                "undefined field: \"absent_early\" on /datum/target".into(),
                vec![]
            ),
            (
                11,
                "field access requires static type: \"absent_late\"".into(),
                vec!["5:11: add a return type annotation to /proc/late".into()]
            ),
        ]
    );
}
#[test]
fn source_return_hints_index_propagation_and_failed_follow_hint_reset_match_reference() {
    let db = Arc::new(QueryDb::default());
    let front = build_note_source(
        include_str!("../../../../fixtures/unified_checks/field_static_calls/probe.dm"),
        &db,
    );
    let archive = front.body_archive().unwrap();
    let profile = archive.tree().checker_builtin_profile().unwrap();
    let context = CheckerContext::archived(&archive, db.as_ref(), archive.tree(), profile).unwrap();
    let body = archive.parse(2).unwrap();
    let rows = context.fields_archived(&body, Severity::Warning).unwrap();
    assert_eq!(rows.len(), 7);
    let notes: Vec<_> = rows
        .iter()
        .map(|r| r.notes.iter().map(|n| n.legacy_text()).collect::<Vec<_>>())
        .collect();
    assert_eq!(
        notes,
        vec![
            vec!["1:14: add a return type annotation to /proc/untyped"],
            vec!["8:5: return type evaluated to None"],
            vec![],
            vec![],
            vec!["1:14: add a return type annotation to /proc/untyped"],
            vec!["1:14: add a return type annotation to /proc/untyped"],
            vec![],
        ]
    );
}
#[test]
fn utf8_byte_note_columns_and_missing_transform_proofs_remain_explicit() {
    let db = Arc::new(QueryDb::default());
    let front = build_note_source(
        "/proc/late/* é漢 */()\n    return null\n/proc/p()\n    late().field\n",
        &db,
    );
    let archive = front.body_archive().unwrap();
    let pos = archive
        .callable_note_origin(prefix_identity(&archive, "late"))
        .unwrap();
    assert_eq!((pos.line, pos.byte_column), (1, 22));
    let unproven = build("/proc/late()\n    return null\n", &db)
        .body_archive()
        .unwrap();
    assert!(unproven
        .callable_note_origin(prefix_identity(&unproven, "late"))
        .is_err());
}
#[test]
fn original_callable_byte_notes_match_valid_utf8_and_tab_reference_capture() {
    let db = Arc::new(QueryDb::default());
    let front = build_note_source(
        include_str!("../../../../fixtures/unified_checks/field_static_byte_notes/probe.dm"),
        &db,
    );
    let archive = front.body_archive().unwrap();
    let profile = archive.tree().checker_builtin_profile().unwrap();
    let context = CheckerContext::archived(&archive, db.as_ref(), archive.tree(), profile).unwrap();
    let rows = context
        .fields_archived(&archive.parse(2).unwrap(), Severity::Warning)
        .unwrap();
    assert_eq!(rows.len(), 2);
    assert_eq!(
        rows[0].notes[0].legacy_text(),
        "1:27: add a return type annotation to /proc/unicode"
    );
    assert_eq!(
        rows[1].notes[0].legacy_text(),
        "3:14: add a return type annotation to /proc/tabbed"
    );
}
#[test]
fn inherited_override_and_null_source_hints_use_selected_body_not_receiver_formal_guess() {
    let db = Arc::new(QueryDb::default());
    let front = build_note_source(
        include_str!("../../../../fixtures/unified_checks/field_static_inherited/probe.dm"),
        &db,
    );
    let archive = front.body_archive().unwrap();
    let profile = archive.tree().checker_builtin_profile().unwrap();
    let context = CheckerContext::archived(&archive, db.as_ref(), archive.tree(), profile).unwrap();
    let rows = context
        .fields_archived(&archive.parse(5).unwrap(), Severity::Warning)
        .unwrap();
    assert_eq!(rows.len(), 3);
    assert_eq!(
        rows[0].notes[0].legacy_text(),
        "1:27: add a return type annotation to /datum/base/proc/inherited"
    );
    assert_eq!(
        rows[1].notes[0].legacy_text(),
        "7:29: add a return type annotation to /datum/base/child/proc/overridden"
    );
    assert_eq!(
        rows[2].notes[0].legacy_text(),
        "15:6: return type evaluated to None"
    );
}
