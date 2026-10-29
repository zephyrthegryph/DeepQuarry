use super::*;
use crate::checks::BodyView;
use dm_tree::frontend::{build, BodyArena};
use std::path::Path;

struct Source(String);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.clone())
    }
}
fn observe(expression: &str) -> Result<Option<ControlConstant>, String> {
    let frontend = build(
        Path::new("shape.dme"),
        &Source(format!("/proc/probe(a)\n    return {expression}\n")),
        &Default::default(),
        1,
    )
    .map_err(|e| format!("{e:?}"))?;
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            let view = BodyView::new(&frontend, body)?;
            let dm_syntax::StatementKind::Return(Some(value)) =
                &view.syntax().parsed().statements[0].kind
            else {
                return Err("expected issued return".into());
            };
            classify(value)
        })
        .map_err(|e| e.message)?
}

#[test]
fn static_terms_match_pinned_kind_test_without_value_folding() {
    for expression in ["0", "1.0", "null", "\"\"", "/datum", "\"\\[literal]\""] {
        assert_eq!(
            observe(expression).unwrap(),
            Some(ControlConstant::StaticTerm),
            "{expression}"
        );
    }
    for expression in [
        "a",
        "(1)",
        "-1",
        "list()",
        "new /datum",
        "'resource.dmi'",
        "\"[a]\"",
        "a.value",
        "1 + 2",
    ] {
        assert_eq!(observe(expression).unwrap(), None, "{expression}");
    }
}

#[test]
fn only_shallow_static_binary_comparisons_and_boolean_ops_qualify() {
    for expression in [
        "1 == 2", "1 != 2", "1 <> 2", "1 < 2", "1 > 2", "1 <= 2", "1 >= 2", "1 && 2", "1 || 2",
    ] {
        assert_eq!(
            observe(expression).unwrap(),
            Some(ControlConstant::ConstantEvaluation),
            "{expression}"
        );
    }
    for expression in [
        "1 + 2 == 3",
        "(1) == 2",
        "1 == (2)",
        "a == 2",
        "!1 == 2",
        "1 & 2",
        "1 ~= 2",
    ] {
        assert_eq!(observe(expression).unwrap(), None, "{expression}");
    }
}

#[test]
fn malformed_syntax_does_not_become_a_dynamic_clean_fact() {
    assert!(observe("(1").is_err());
    assert!(observe("\"[broken(]\"").is_err());
}

#[test]
fn empty_interpolation_does_not_masquerade_as_a_plain_static_string() {
    assert_eq!(observe(r#""[]""#).unwrap(), None);
    assert_eq!(observe(r#""[ ]""#).unwrap(), None);
    assert_eq!(observe(r#""\ []""#).unwrap(), None);
    assert_eq!(observe(r#"@"[]""#).unwrap(), Some(ControlConstant::StaticTerm));
}
