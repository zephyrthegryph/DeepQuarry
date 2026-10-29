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
fn ordered_conditions_share_one_walk_and_ignore_request_family_order() {
    let f = build(
        Path::new("control.dme"),
        &Source("/proc/a()\n    if(1)\n        return\n    return\n"),
        &Default::default(),
        1,
    )
    .unwrap();
    let arena = BodyArena::new_typed(&f, |_| true);
    arena
        .with_parsed(&f.bodies[0], |body| {
            let v = BodyView::new(&f, body).unwrap();
            let policies = [
                (Family::IfDeterminate, Severity::Error),
                (Family::Static, Severity::Warning),
            ];
            let found = check(&v, &policies).unwrap();
            assert_eq!(
                found.iter().map(|d| d.family).collect::<Vec<_>>(),
                ["control_condition_static", "if_condition_determinate"]
            );
            assert_eq!(found[0].span, found[1].span);
            assert_eq!(found[0].severity, Severity::Warning);
            assert_eq!(found[1].severity, Severity::Error);
        })
        .unwrap();
}
#[test]
fn duplicate_policy_selection_is_rejected_before_traversal() {
    assert!(validate(&[
        (Family::Static, Severity::Error),
        (Family::Static, Severity::Disabled)
    ])
    .is_err());
    assert!(validate(&[
        (Family::Static, Severity::Error),
        (Family::IfDeterminate, Severity::Error)
    ])
    .is_ok());
}

#[path = "checks_original_byte_positions_tests.rs"]
mod original_byte_positions;
