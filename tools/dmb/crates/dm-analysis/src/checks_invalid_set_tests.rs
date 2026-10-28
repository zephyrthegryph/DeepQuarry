use super::*;
use dm_tree::frontend::{build, BodyArena};
use std::path::Path;

struct Source<'a>(&'a str);
impl dm_preprocess::SourceProvider for Source<'_> {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}

fn observe(body: &str, severity: Severity) -> Result<(String, Vec<Diagnostic>), String> {
    let source = format!("/proc/test(a)\n{body}");
    let frontend = build(Path::new("p.dme"), &Source(&source), &Default::default(), 1)
        .map_err(|error| format!("{error:?}"))?;
    let bodies = BodyArena::new_typed(&frontend, |_| true);
    let diagnostics = bodies
        .with_parsed(&frontend.bodies[0], |body| {
            check(&BodyView::new(&frontend, body)?, severity)
        })
        .map_err(|error| error.message)??;
    Ok((source, diagnostics))
}

#[test]
fn exact_messages_order_and_statement_origins() {
    let (source, found) = observe(
        concat!(
            "    set background = 2\n",
            "    set waitfor = 1.0\n",
            "    set name = 1\n",
            "    set category = /datum\n",
            "    set desc = null\n",
            "    set invisibility = 101\n",
        ),
        Severity::Warning,
    )
    .unwrap();
    assert_eq!(
        found.iter().map(|d| d.message.as_str()).collect::<Vec<_>>(),
        [
            "set background must be 0/1/TRUE/FALSE",
            "set waitfor must be 0/1/TRUE/FALSE",
            "set name must have a string value",
            "set category must have a string value",
            "set desc must have a string value",
            "set invisibility must be 0-100",
        ]
    );
    let starts: Vec<_> = source
        .match_indices("set ")
        .map(|(offset, _)| offset)
        .collect();
    assert_eq!(
        found.iter().map(|d| d.span.start).collect::<Vec<_>>(),
        starts
    );
    assert!(found.iter().all(|d| d.family == "invalid_set_value"
        && d.severity == Severity::Warning
        && d.notes.is_empty()));
}

#[test]
fn integer_tokens_are_not_float_values_or_grouped_terms() {
    for value in ["0", "1", "01", "0x1", "TRUE", "FALSE"] {
        let (_, found) =
            observe(&format!("    set hidden = {value}\n"), Severity::Warning).unwrap();
        assert!(found.is_empty(), "{value}");
    }
    for value in ["1.0", "1e0", "(1)", "!0", "2", "null"] {
        let (_, found) =
            observe(&format!("    set hidden = {value}\n"), Severity::Warning).unwrap();
        assert_eq!(found.len(), 1, "{value}");
    }
    for value in ["0", "100", "0144", "0x64"] {
        assert!(
            observe(
                &format!("    set invisibility = {value}\n"),
                Severity::Warning
            )
            .unwrap()
            .1
            .is_empty(),
            "{value}"
        );
    }
    for value in ["100.0", "(100)", "-1", "101", "2147483648"] {
        assert_eq!(
            observe(
                &format!("    set invisibility = {value}\n"),
                Severity::Warning
            )
            .unwrap()
            .1
            .len(),
            1,
            "{value}"
        );
    }
}

#[test]
fn string_policy_preserves_reference_term_only_boundary() {
    for value in ["\"title\"", "\"[a]\"", "{\"title\"}"] {
        assert!(
            observe(&format!("    set name = {value}\n"), Severity::Warning)
                .unwrap()
                .1
                .is_empty(),
            "{value}"
        );
    }
    assert!(observe("    set category = null\n", Severity::Warning)
        .unwrap()
        .1
        .is_empty());
    for value in ["a + 1", "!a", "a.name", "a[1]"] {
        assert!(
            observe(&format!("    set desc = {value}\n"), Severity::Warning)
                .unwrap()
                .1
                .is_empty(),
            "{value}"
        );
    }
    for value in ["(\"title\")", "a", "f()", "'file.dmi'", "new /datum"] {
        assert_eq!(
            observe(&format!("    set desc = {value}\n"), Severity::Warning)
                .unwrap()
                .1
                .len(),
            1,
            "{value}"
        );
    }
}

#[test]
fn only_initial_contiguous_top_level_settings_are_checked() {
    let (_, found) = observe(
        concat!(
            "    set hidden = 2\n",
            "    set category = null\n",
            "    set popup_menu in 2\n",
            "    a = 1\n",
            "    set instant = 2\n",
            "    if(a)\n",
            "        set waitfor = 2\n",
        ),
        Severity::Warning,
    )
    .unwrap();
    assert_eq!(found.len(), 2);
}

#[test]
fn caller_policy_controls_suppression_and_severity() {
    assert!(observe("    set hidden = 2\n", Severity::Disabled)
        .unwrap()
        .1
        .is_empty());
    assert_eq!(
        observe("    set hidden = 2\n", Severity::Error).unwrap().1[0].severity,
        Severity::Error
    );
}

#[test]
fn incomplete_syntax_is_not_a_clean_observation() {
    assert!(observe("    set hidden = (\n", Severity::Warning).is_err());
}

#[test]
fn uncaptured_term_follow_distinctions_are_not_silently_clean() {
    assert!(observe("    set name = a::name\n", Severity::Warning).is_err());
}
