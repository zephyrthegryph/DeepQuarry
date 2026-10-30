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
fn check(declaration: &str, expected: Option<&str>) {
    let text = format!("/datum/holder\n    var/saved\n    proc/check()\n        saved = new /datum\n        {declaration}\n");
    let provider = Original(AcquiredSource::from_original_bytes(text.into_bytes(), ()));
    let frontend = build(
        Path::new("original-local-scope.dme"),
        &provider,
        &Default::default(),
        1,
    )
    .unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    let occurrence = frontend
        .bodies
        .iter()
        .find(|b| {
            frontend
                .snapshot
                .tree
                .symbols()
                .text(frontend.snapshot.tree.member(b.member).unwrap().name)
                == Some("check")
        })
        .unwrap();
    arena
        .with_parsed(occurrence, |body| {
            let _syntax = body.statement_body().unwrap();
            let gate = body
                .source_locals()
                .map_err(Unsupported)
                .and_then(require_local_source_projection);
            match expected {
                Some(reason) => assert!(gate.unwrap_err().0.contains(reason)),
                None => assert!(gate.is_ok()),
            }
            let result = contributions(&frontend, body, frontend.snapshot.tree.as_ref(), &[]);
            match expected {
                Some(_) => assert!(
                    result.is_err(),
                    "early saved assignment cannot escape as a clean partial report"
                ),
                None => assert_eq!(result.unwrap().len(), 1),
            }
        })
        .unwrap();
    let archive = frontend.body_archive().unwrap();
    let ordinal = archive
        .occurrences()
        .iter()
        .position(|b| b.member == occurrence.member)
        .unwrap();
    if expected.is_some() {
        let live_ordinal = frontend
            .bodies
            .iter()
            .position(|b| b.member == occurrence.member)
            .unwrap();
        for (origin, original_arena, index) in [
            (
                crate::native_program::Origin::Live(&frontend),
                Some(&arena),
                live_ordinal,
            ),
            (
                crate::native_program::Origin::Archive(&archive),
                None,
                ordinal,
            ),
        ] {
            let mut published = false;
            let result = origin.with_body(original_arena, index, |_, _, _, _| {
                published = true;
                Ok(())
            });
            assert!(
                result.is_err(),
                "value-program callback must not observe an uncertified local scope"
            );
            assert!(
                !published,
                "original local gate runs before every value callback"
            );
        }
    }
    let body = archive.parse(ordinal).unwrap();
    let result = archived_scope(&body, frontend.snapshot.tree.as_ref(), &[]);
    match expected {
        Some(reason) => assert!(result.err().unwrap().0.contains(reason)),
        None => assert!(result.is_ok()),
    }
}
#[test]
fn issued_array_and_embedded_qualifier_projection_preserves_earlier_findings() {
    for declaration in ["var/list/datum/L[2]", "var/datum/L[2][3]"] {
        check(declaration, None);
    }
    for declaration in ["var/datum/tmp/L", "var/datum/static/L", "var/var/datum/L"] {
        check(declaration, None);
    }
}
#[test]
fn ordinary_and_leading_qualifier_locals_keep_existing_behavior() {
    for declaration in [
        "var/datum/L",
        "var/static/datum/L",
        "var/global/datum/L",
        "var/tmp/datum/L",
    ] {
        check(declaration, None);
    }
}

#[test]
fn unissued_original_local_syntax_is_not_a_normalized_scope_receipt() {
    let source = "/proc/check()\n    var/list/L[2]\n";
    let provider = Original(AcquiredSource::from_original_bytes(
        source.as_bytes().to_vec(),
        (),
    ));
    let frontend = build(
        Path::new("unissued-original-locals.dme"),
        &provider,
        &Default::default(),
        1,
    )
    .unwrap();
    let arena = BodyArena::new(&frontend);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            assert!(body.statement_body().is_none());
            assert!(body.source_locals().is_err());
        })
        .unwrap();
}
