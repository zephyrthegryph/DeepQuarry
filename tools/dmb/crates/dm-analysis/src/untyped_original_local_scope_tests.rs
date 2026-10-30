//! Original source receipts, never normalized declaration text, supply locals.
use super::*;
use dm_preprocess::{AcquiredSource, SourceProvider, SourceText};
use dm_tree::frontend::{build, BodyArena};
use std::path::Path;
struct Original(AcquiredSource);
impl SourceProvider for Original {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("original acquisition required".into())
    }
    fn acquired_source(&self, _: &Path) -> Result<Option<AcquiredSource>, String> {
        Ok(Some(self.0.clone()))
    }
    fn source_acquisition(&self, _: &Path, text: &SourceText) -> Option<AcquiredSource> {
        self.0
            .lease()
            .source_text()
            .same_view(text)
            .then(|| self.0.clone())
    }
}
#[test]
fn generic_scope_uses_original_list_depth_qualifiers_comma_and_old_collection_forms() {
    let source="/datum/T\n/proc/check(datum/T/parameter)\n    var/list/L[2]\n    var/list/datum/LL[2][3]\n    var/datum/static/embedded\n    var/var/datum/repeated\n    var/static/datum/first, second\n    for(var/parameter in list())\n        var/datum/inside\n    for(var/datum/range_only = 1 to 2)\n        continue\n    for(var/datum/cstyle; 0;)\n        continue\n    try\n        return\n    catch(var/datum/caught)\n        return\n";
    let provider = Original(AcquiredSource::from_original_bytes(
        source.as_bytes().to_vec(),
        (),
    ));
    let front = build(
        Path::new("original-local-projection.dme"),
        &provider,
        &Default::default(),
        1,
    )
    .unwrap();
    let arena = BodyArena::new_typed(&front, |_| true);
    arena
        .with_parsed(&front.bodies[0], |body| {
            let scope = scope(&front, body, front.snapshot.tree.as_ref(), &[]).unwrap();
            for (name, ty) in [
                ("parameter", "/datum/T"),
                ("L", "/list/list"),
                ("LL", "/list/list/datum"),
                ("embedded", "/datum/static"),
                ("repeated", "/var/datum"),
                ("first", "/datum"),
                ("second", ""),
                ("inside", "/datum"),
                ("cstyle", "/datum"),
            ] {
                assert_eq!(
                    scope.locals.get(name).map(String::as_str),
                    Some(ty),
                    "{name}"
                );
            }
            assert!(
                !scope.locals.contains_key("range_only"),
                "old collect_locals has no ForRange arm"
            );
            assert!(
                !scope.locals.contains_key("caught"),
                "old collect_locals ignores catch binder"
            );
        })
        .unwrap();
    let archive = front.body_archive().unwrap();
    let body = archive.parse(0).unwrap();
    let scope = archived_scope(&body, archive.tree(), &[]).unwrap();
    assert_eq!(
        scope.locals.get("L").map(String::as_str),
        Some("/list/list")
    );
    assert_eq!(scope.locals.get("second").map(String::as_str), Some(""));
}
#[test]
fn local_receipt_rejects_foreign_occurrence_syntax_and_copied_fact() {
    let source = "/proc/a()\n    var/list/A[2]\n/proc/b()\n    var/list/B[2]\n";
    let provider = Original(AcquiredSource::from_original_bytes(
        source.as_bytes().to_vec(),
        (),
    ));
    let front = build(
        Path::new("local-receipt-identity.dme"),
        &provider,
        &Default::default(),
        1,
    )
    .unwrap();
    let archive = front.body_archive().unwrap();
    let a = archive.parse(0).unwrap();
    let b = archive.parse(1).unwrap();
    let view = a.source_locals().unwrap();
    assert!(view
        .require_for(archive.tree(), a.occurrence(), a.statement_body())
        .is_ok());
    assert!(view
        .require_for(archive.tree(), b.occurrence(), b.statement_body())
        .is_err());
    assert!(view
        .require_for(archive.tree(), a.occurrence(), b.statement_body())
        .is_err());
    let copied = view.entries().unwrap()[0].clone();
    assert!(view.type_path(&copied).is_err());
    assert!(scope_from(
        archive.tree(),
        a.occurrence(),
        a.statement_body(),
        archive.tree(),
        &[]
    )
    .err()
    .unwrap()
    .0
    .contains("unissued local source"));
}

#[test]
fn original_local_ledger_finalizes_try_catch_order_once_without_a_second_index() {
    let source="/proc/check()\n    try\n        var/list/in_try[2]\n    catch(var/datum/caught)\n        var/list/in_catch[2]\n";
    let syntax = dm_syntax::parse(source);
    let body = dm_syntax::parse_proc_body(&syntax.items[0]);
    let facts = body.local_variables.entries().unwrap();
    assert_eq!(
        facts
            .iter()
            .map(|f| &source[f.name.range()])
            .collect::<Vec<_>>(),
        ["in_try", "caught", "in_catch"]
    );
    for fact in facts {
        let slice = body.local_variables.in_span(fact.name).unwrap();
        assert_eq!(slice.len(), 1);
        assert!(
            std::ptr::eq(&slice[0], fact),
            "borrow original ledger storage"
        );
    }
}
