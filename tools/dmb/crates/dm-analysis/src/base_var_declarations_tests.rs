use super::*;
use dm_tree::frontend::build;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn archive(source: &'static str) -> Arc<BodyArchive> {
    build(
        Path::new("code/base_vars.dm"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap()
    .body_archive()
    .unwrap()
}
fn names<'a>(
    a: &'a BodyArchive,
    rows: &[BaseVarDeclaration<'a>],
) -> Vec<(&'a str, &'a str, usize, bool, bool)> {
    rows.iter()
        .map(|r| {
            (
                a.tree().symbols().text(r.owner).unwrap(),
                a.tree().symbols().text(r.name).unwrap(),
                r.source.line,
                r.base,
                r.list_init,
            )
        })
        .collect()
}

#[test]
fn base_vars_skip_globals_static_const_and_global_modifiers_but_keep_tmp() {
    let a = archive("var/list/root_global = list()\n/datum/base\n    var/plain\n    var/tmp/temporary\n    var/static/shared = list()\n    var/const/fixed = 1\n    var/global/world_shared = list()\n/datum/other\n    var/plain\n    var/list/items = list()\n");
    let rows = base_var_declarations(&a, &["/datum/base"], Path::new(".")).unwrap();
    assert_eq!(
        names(&a, &rows),
        [
            ("/datum/base", "plain", 3, true, false),
            ("/datum/base", "temporary", 4, true, false),
            ("/datum/other", "items", 10, false, true)
        ]
    );
}

#[test]
fn effective_same_owner_default_controls_candidate_but_origin_is_the_formal() {
    let a = archive("/datum/first\n    var/list/items = null\n    items = list()\n/datum/second\n    var/list/items = list()\n    items = null\n");
    let rows = base_var_declarations(&a, &[], Path::new(".")).unwrap();
    assert_eq!(
        names(&a, &rows),
        [("/datum/first", "items", 2, false, true)]
    );
    assert_ne!(rows[0].declaration, rows[0].effective);
    assert!(rows[0]
        .metadata
        .initializer
        .as_ref()
        .is_some_and(|x| x.tokens.len() == 1));
}

#[test]
fn override_before_formal_preserves_the_native_formal_first_selection_contract() {
    let a = archive("/datum/base\n    items = list()\n    var/list/items = null\n");
    let rows = base_var_declarations(&a, &[], Path::new(".")).unwrap();
    assert_eq!(names(&a, &rows), [("/datum/base", "items", 3, false, true)]);
    assert_ne!(rows[0].declaration, rows[0].effective);
}

#[test]
fn inherited_default_never_manufactures_a_child_declaration_row() {
    let a =
        archive("/datum/base\n    var/list/items = null\n/datum/base/child\n    items = list()\n");
    let rows =
        base_var_declarations(&a, &["/datum/base", "/datum/base/child"], Path::new(".")).unwrap();
    assert_eq!(names(&a, &rows), [("/datum/base", "items", 2, true, false)]);
}

#[test]
fn list_candidate_requires_the_exact_ungrouped_empty_list_term() {
    let a = archive("/datum/base\n    var/a = list()\n    var/b = (list())\n    var/c = list(1)\n    var/d = new /list()\n    var/e = list() || list()\n    var/f[0]\n    var/g = list(/* comments do not add arguments */)\n");
    let rows = base_var_declarations(&a, &["/datum/base"], Path::new(".")).unwrap();
    assert_eq!(
        rows.iter().map(|r| r.list_init).collect::<Vec<_>>(),
        [true, false, false, false, false, false, true]
    );
    assert_eq!(rows.len(), 7);
}

#[test]
fn declared_type_text_preserves_legacy_list_and_array_annotations() {
    let a = archive("/datum/base\n    var/list/datum/items\n    var/datum/sized[2]\n    var/list/datum/nested[2]\n    var/plain\n    var/number\n");
    let rows = base_var_declarations(&a, &["/datum/base"], Path::new(".")).unwrap();
    assert_eq!(
        rows.iter()
            .map(|r| r.declared_type_text().unwrap())
            .collect::<Vec<_>>(),
        ["/list/datum", "/list/datum", "/list/list/datum", "", ""]
    );
    let original = a.tree().member(rows[0].declaration).unwrap();
    assert!(std::ptr::eq(rows[0].metadata, original.metadata.as_ref()));
}

#[test]
fn record_roster_is_lexical_and_contains_only_authored_bodies() {
    let a = archive("/datum/record\n    proc/read()\n        return\n/datum/record/child\n/datum/record/other\n    read()\n        return\n/datum/record/detached\n    parent_type = /datum\n    proc/detached()\n        return\n/datum/elsewhere\n    parent_type = /datum/record\n    proc/not_a_record()\n        return\n/datum/recording\n    proc/not_a_record_either()\n        return\n");
    let rows = record_procedures(&a, Path::new(".")).unwrap();
    assert_eq!(
        rows.iter()
            .map(|r| (
                a.tree().symbols().text(r.owner).unwrap(),
                a.tree().symbols().text(r.name).unwrap(),
                r.source.line
            ))
            .collect::<Vec<_>>(),
        [
            ("/datum/record", "read", 2),
            ("/datum/record/other", "read", 6),
            ("/datum/record/detached", "detached", 10)
        ]
    );
    for row in rows {
        assert!(a
            .occurrences()
            .iter()
            .any(|occurrence| occurrence.member == row.member
                && std::ptr::eq(&occurrence.source, row.source)));
    }
}

#[test]
fn captured_macro_origins_and_rows_survive_frontend_release() {
    let a =
        archive("#define DECLARE_ITEMS var/list/items = list()\n/datum/base\n    DECLARE_ITEMS\n");
    let rows = base_var_declarations(&a, &[], Path::new(".")).unwrap();
    assert_eq!(names(&a, &rows), [("/datum/base", "items", 3, false, true)]);
    assert!(!rows[0].source.macro_expansions.is_empty());
}

#[test]
fn missing_symbolic_initializer_spelling_is_incomplete_not_a_clean_non_list() {
    let a = archive("/datum/base\n    var/plain\n");
    let bad = SymbolicExpression {
        tokens: vec![dm_ir::ExpressionToken {
            kind: TokenKind::Ident,
            text: SymbolId::of("absent_native_symbol"),
            relative_span: dm_syntax::Span::new(0, 20),
        }]
        .into(),
    };
    assert!(empty_list(a.tree(), Some(&bad)).is_err());
}
