use super::*;
use dm_tree::frontend::{build, BodyArena};
use std::path::Path;
struct Source(String);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.clone())
    }
}

fn observe(
    source: &str,
    severity: Severity,
) -> Result<Vec<(usize, usize, String, Severity)>, String> {
    let frontend = build(
        Path::new("control.dme"),
        &Source(source.into()),
        &Default::default(),
        1,
    )
    .map_err(|e| format!("{e:?}"))?;
    let arena = BodyArena::new_typed(&frontend, |_| true);
    let mut rows = Vec::new();
    for occurrence in frontend.bodies.iter() {
        arena
            .with_parsed(occurrence, |body| {
                let view = BodyView::new(&frontend, body)?;
                for diagnostic in check(&view, severity)? {
                    assert_eq!(diagnostic.family, "control_condition_static");
                    assert!(diagnostic.notes.is_empty());
                    rows.push((
                        view.location(&diagnostic).unwrap().line,
                        frontend.expanded.text[..diagnostic.span.start]
                            .rsplit('\n')
                            .next()
                            .unwrap()
                            .chars()
                            .count()
                            + 1,
                        diagnostic.message,
                        diagnostic.severity,
                    ));
                }
                Ok::<_, String>(())
            })
            .map_err(|e| e.message)??;
    }
    Ok(rows)
}

#[test]
fn adversarial_reference_flow_fixture_has_exact_order_origins_and_wording() {
    let source = include_str!("../../../fixtures/control_static_flow/control.dm");
    let rows = observe(source, Severity::Error).unwrap();
    let static_term = "control flow condition is a static term";
    let constant_eval = "control flow condition is a constant evalutation";
    let expected = [
        (11, 7, static_term),
        (12, 9, static_term),
        (17, 5, static_term),
        (24, 5, static_term),
        (31, 11, static_term),
        (37, 5, static_term),
        (42, 5, constant_eval),
        (50, 7, constant_eval),
        (54, 5, static_term),
    ];
    assert_eq!(
        rows.iter()
            .map(|(line, column, message, _)| (*line, *column, message.as_str()))
            .collect::<Vec<_>>(),
        expected
    );
    assert!(rows
        .iter()
        .all(|(_, _, _, severity)| *severity == Severity::Error));
}

#[test]
fn grouped_arithmetic_and_interpolated_switch_values_are_not_static_terms() {
    let source = include_str!("../../../fixtures/unified_checks/control_constant_shapes.dm");
    let rows = observe(source, Severity::Warning).unwrap();
    assert_eq!(rows.iter().map(|r| r.0).collect::<Vec<_>>(), [2, 5, 14, 20]);
    assert!(rows.iter().all(|r| r.3 == Severity::Warning));
}

#[test]
fn disabled_family_does_not_require_unknown_truthiness_contracts() {
    let source = "/proc/probe(a)\n    if(\"\\\r[a]\")\n        return\n";
    assert!(observe(source, Severity::Disabled).unwrap().is_empty());
    assert!(observe(source, Severity::Error).is_err());
}

#[test]
fn unsupported_later_flow_discards_all_earlier_findings() {
    let source="/proc/probe(a)\n    switch(1)\n        if(0)\n            a=1\n    if(\"\\\r[a]\")\n        return\n";
    assert!(observe(source, Severity::Error).is_err());
}

#[test]
fn unsupported_cr_boundary_fixture_really_retains_the_primary_raw_origin() {
    let source = "/proc/probe(a)\n    if(\"\\\r[a]\")\n        return\n";
    let frontend = build(
        Path::new("cr.dme"),
        &Source(source.into()),
        &Default::default(),
        1,
    )
    .unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            let view = BodyView::new(&frontend, body).unwrap();
            let dm_syntax::StatementKind::If { condition, .. } =
                &view.syntax().parsed().statements[0].kind
            else {
                panic!("issued if expected");
            };
            let dm_syntax::ExprKind::Literal(text) = &condition.kind else {
                panic!("issued literal expected");
            };
            assert!(
                text.as_str().contains('\r'),
                "the fixture must prove retained CR, not assume it"
            );
            assert_eq!(
                text.parts().unwrap().unwrap().lexical,
                Err(dm_syntax::literal::LiteralLexicalError::InterpolationBoundaryNormalization)
            );
            assert!(check(&view, Severity::Error).is_err());
        })
        .unwrap();
}
