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
fn checker_borrows_the_same_issued_statement_owner_as_the_compiler() {
    let frontend = build(
        Path::new("project.dme"),
        &Source("/proc/test(x, y)\n    return !x & y\n"),
        &Default::default(),
        1,
    )
    .unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            let view = BodyView::new(&frontend, body).unwrap();
            assert!(std::ptr::eq(view.syntax(), body.statement_body().unwrap()));
            let diagnostics = view.ambiguous_not_bitwise(Severity::Warning);
            assert_eq!(diagnostics.len(), 1);
            assert_eq!(diagnostics[0].family, "ambiguous_not_bitwise");
            assert_eq!(diagnostics[0].notes[1].message, "Did you mean `!x && y`?");
            assert_eq!(view.location(&diagnostics[0]).unwrap().line, 2);
            assert!(view.ambiguous_not_bitwise(Severity::Disabled).is_empty());
        })
        .unwrap();
    let compiler_body = arena.take_parsed(&frontend.bodies[0]).unwrap();
    assert_eq!(
        compiler_body
            .statement_body()
            .unwrap()
            .parsed()
            .statements
            .len(),
        1
    );
}

#[test]
fn parentheses_rhs_negation_and_xor_match_the_reference() {
    let frontend = build(Path::new("project.dme"), &Source(
        "/proc/test(x, y)\n    var/a = (!x) & y\n    var/b = x & !y\n    var/c = !x ^ y\n    return !x | y\n"), &Default::default(), 1).unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            let view = BodyView::new(&frontend, body).unwrap();
            let diagnostics = view.ambiguous_not_bitwise(Severity::Error);
            assert_eq!(diagnostics.len(), 2);
            assert_eq!(diagnostics[0].severity, Severity::Error);
            assert_eq!(diagnostics[0].notes[1].message, "Did you mean `!x != y`?");
            assert_eq!(diagnostics[1].notes[1].message, "Did you mean `!x || y`?");
        })
        .unwrap();
}

#[test]
fn equal_source_does_not_authorize_a_foreign_issuance() {
    let input = Source("/proc/test(x, y)\n    return !x & y\n");
    let frontend = build(Path::new("project.dme"), &input, &Default::default(), 1).unwrap();
    let foreign = build(Path::new("project.dme"), &input, &Default::default(), 1).unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            assert!(BodyView::new(&foreign, body).is_err());
        })
        .unwrap();
}
