use super::*;
use dm_tree::frontend::{build, BodyArena};
use std::path::Path;

struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}

#[test]
fn adversarial_reference_order_anchors_and_ignored_values() {
    let source = include_str!("../../../fixtures/unified_checks/bitwise_adversarial.dm");
    let frontend = build(
        Path::new("adversarial.dme"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    let mut observed = Vec::new();
    for occurrence in frontend.bodies.iter() {
        arena
            .with_parsed(occurrence, |body| {
                let view = BodyView::new(&frontend, body).unwrap();
                for diagnostic in view.ambiguous_not_bitwise(Severity::Warning) {
                    let line = view.location(&diagnostic).unwrap().line;
                    let column = frontend.expanded.text[..diagnostic.span.start]
                        .rsplit('\n')
                        .next()
                        .unwrap()
                        .chars()
                        .count()
                        + 1;
                    observed.push((line, column, diagnostic.message));
                }
            })
            .unwrap();
    }
    // Independently captured from pinned suite-1.11, including diagnostic
    // multiplicity/order. No warning comes from the set/prefab field values.
    assert_eq!(
        observed,
        [
            (
                5,
                17,
                "Ambiguous `!` on left side of bitwise `|` operator".into()
            ),
            (
                5,
                5,
                "Ambiguous `!` on left side of bitwise `&` operator".into()
            ),
            (
                8,
                7,
                "Ambiguous `!` on left side of bitwise `&` operator".into()
            ),
            (
                15,
                10,
                "Ambiguous `!` on left side of bitwise `^` operator".into()
            ),
        ]
    );
}

#[test]
fn both_policies_use_primary_parenthesis_origins_not_token_minus_one() {
    for (source, membership) in [
        (
            include_str!("../../../fixtures/unified_checks/bitwise_control_origins.dm"),
            false,
        ),
        (
            include_str!("../../../fixtures/unified_checks/membership_control_origins.dm"),
            true,
        ),
    ] {
        let frontend = build(
            Path::new("controls.dme"),
            &Source(source),
            &Default::default(),
            1,
        )
        .unwrap();
        let arena = BodyArena::new_typed(&frontend, |_| true);
        arena
            .with_parsed(&frontend.bodies[0], |body| {
                let view = BodyView::new(&frontend, body).unwrap();
                assert_eq!(view.syntax().parsed().control_origins.len(), 5);
                let diagnostics = if membership {
                    view.ambiguous_in_lhs(Severity::Warning).unwrap()
                } else {
                    view.ambiguous_not_bitwise(Severity::Warning)
                };
                let actual: Vec<_> = diagnostics
                    .iter()
                    .map(|diagnostic| {
                        (
                            view.location(diagnostic).unwrap().line,
                            frontend.expanded.text[..diagnostic.span.start]
                                .rsplit('\n')
                                .next()
                                .unwrap()
                                .chars()
                                .count()
                                + 1,
                        )
                    })
                    .collect();
                assert_eq!(actual, [(2, 10), (4, 13), (6, 8), (12, 14), (13, 9)]);
            })
            .unwrap();
    }
}
