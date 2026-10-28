use super::*;
use dm_tree::frontend::{build, BodyArena};
use std::path::Path;

struct Source<'a>(&'a str);
impl dm_preprocess::SourceProvider for Source<'_> {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}

fn observe(expression: &str, severity: Severity) -> Result<(String, Vec<Diagnostic>), String> {
    let source = format!("/proc/test(a, b, c, d)\n    return {expression}\n");
    let frontend = build(Path::new("p.dme"), &Source(&source), &Default::default(), 1)
        .map_err(|error| format!("{error:?}"))?;
    let bodies = BodyArena::new_typed(&frontend, |_| true);
    let found = bodies
        .with_parsed(&frontend.bodies[0], |body| {
            let view = BodyView::new(&frontend, body)?;
            check(&view, severity)
        })
        .map_err(|error| error.message)??;
    Ok((source, found))
}

#[test]
fn all_four_reference_shapes_keep_exact_messages_and_ordered_notes() {
    for (expression, message, notes) in [
        (
            "!a in b",
            "ambiguous `!` on left side of an `in`",
            [
                "add parentheses to fix: `!(a in b)`",
                "add parentheses to disambiguate: `(!a) in b`",
            ],
        ),
        (
            "a + b in c",
            "ambiguous `+` on left side of an `in`",
            [
                "add parentheses to fix: `a + (b in c)`",
                "add parentheses to disambiguate: `(a + b) in c`",
            ],
        ),
        (
            "a = b in c",
            "ambiguous `=` on left side of an `in`",
            [
                "add parentheses to fix: `a = (b in c)`",
                "add parentheses to disambiguate: `(a = b) in c`",
            ],
        ),
        (
            "a ? b : c in d",
            "ambiguous ternary on left side of an `in`",
            [
                "add parentheses to fix: `a ? b : (c in d)`",
                "add parentheses to disambiguate: `(a ? b : c) in d`",
            ],
        ),
    ] {
        let (source, found) = observe(expression, Severity::Warning).unwrap();
        assert_eq!(found.len(), 1, "{expression}");
        assert_eq!(found[0].family, "ambiguous_in_lhs");
        assert_eq!(found[0].severity, Severity::Warning);
        assert_eq!(found[0].message, message);
        assert_eq!(
            found[0]
                .notes
                .iter()
                .map(|note| note.message.as_str())
                .collect::<Vec<_>>(),
            notes
        );
        assert_eq!(found[0].span.start, source.find("return").unwrap());
    }
}

#[test]
fn unary_selection_follows_the_base_chain_from_the_term_outward() {
    for (expression, spelling, fix) in [
        ("!~a in b", "~", "~(a in b)"),
        ("~!a in b", "!", "!(a in b)"),
        ("!a++ in b", "++", "(a in b)++"),
        ("--a in b", "--", "--(a in b)"),
        ("a++.field in b", "++", "(a in b)++"),
    ] {
        let (_, found) = observe(expression, Severity::Warning).unwrap();
        assert_eq!(found.len(), 1, "{expression}");
        assert_eq!(
            found[0].message,
            format!("ambiguous `{spelling}` on left side of an `in`")
        );
        assert_eq!(
            found[0].notes[0].message,
            format!("add parentheses to fix: `{fix}`")
        );
    }
}

#[test]
fn groups_disambiguate_only_the_lhs_and_do_not_hide_inner_memberships() {
    for expression in ["(!a) in b", "(a + b) in c", "a in !b", "a = (b in c)"] {
        assert!(
            observe(expression, Severity::Warning).unwrap().1.is_empty(),
            "{expression}"
        );
    }
    let (source, found) = observe("(!a in b)", Severity::Warning).unwrap();
    assert_eq!(found.len(), 1);
    assert_eq!(found[0].span.start, source.find("(!a").unwrap());
}

#[test]
fn interpolation_uses_shared_children_and_the_literal_term_origin() {
    for expression in [r#""[!a in b]""#, r#""["[!a in b]"]""#] {
        let (source, found) = observe(expression, Severity::Warning).unwrap();
        assert_eq!(found.len(), 1, "{expression}");
        let inner_literal = source.rfind("\"[!a").unwrap();
        assert_eq!(found[0].span.start, inner_literal);
        assert_eq!(&source[found[0].expression_span.range()], "!a in b");
    }
}

#[test]
fn alias_spelling_and_nested_diagnostic_order_match_the_reference_policy() {
    let (_, found) = observe("a <> b in c", Severity::Warning).unwrap();
    assert_eq!(found[0].message, "ambiguous `!=` on left side of an `in`");
    let (_, found) = observe("a + b in c in d", Severity::Warning).unwrap();
    assert_eq!(found.len(), 2);
    assert_eq!(found[0].message, "ambiguous `in` on left side of an `in`");
    assert_eq!(found[1].message, "ambiguous `+` on left side of an `in`");
}

#[test]
fn severity_policy_keeps_suppression_separate_from_compiler_acceptance() {
    assert!(observe("!a in b", Severity::Disabled).unwrap().1.is_empty());
    let (_, found) = observe("!a in b", Severity::Error).unwrap();
    assert_eq!(found[0].severity, Severity::Error);
}

#[test]
fn unknown_member_call_and_index_origins_are_not_guessed() {
    for expression in ["a.handler(!b in c)", "a[!b in c]"] {
        assert!(observe(expression, Severity::Warning)
            .unwrap_err()
            .contains("uncaptured"));
    }
    for expression in ["a.handler((!b in c))", "a[(!b in c)]"] {
        let (source, found) = observe(expression, Severity::Warning).unwrap();
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].span.start, source.find("(!b").unwrap());
    }
    let (source, found) = observe("handler(!a in b)", Severity::Warning).unwrap();
    assert_eq!(found[0].span.start, source.find("handler").unwrap());
}

#[test]
fn malformed_issued_syntax_cannot_be_a_clean_result() {
    let source = "/proc/test()\n    return (\n";
    let frontend = build(Path::new("p.dme"), &Source(source), &Default::default(), 1).unwrap();
    let bodies = BodyArena::new_typed(&frontend, |_| true);
    bodies
        .with_parsed(&frontend.bodies[0], |body| {
            assert!(BodyView::new(&frontend, body).is_err());
            assert!(check_syntax(body.statement_body().unwrap(), Severity::Warning).is_err());
        })
        .unwrap();
}
