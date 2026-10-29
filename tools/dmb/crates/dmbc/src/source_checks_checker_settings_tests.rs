//! Shared frontend accepts checker metadata; Compile admission does not.
use super::*;
use std::path::Path;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> { Ok(self.0.into()) }
}
#[test]
fn compile_refuses_retained_checker_settings_even_when_unreachable() {
    let frontend = dm_tree::frontend::build(Path::new("checker.dme"), &Source(
        "/proc/read()\n    set SpacemanDMM_should_be_pure = 1\n    if(0)\n        set SpacemanDMM_other = candidate\n    return 1\n"
    ), &Default::default(), 1).unwrap();
    let errors = checker_setting_errors(&frontend);
    assert_eq!(errors.iter().map(|d| d.message.as_str()).collect::<Vec<_>>(), [
        "unknown procedure setting: SpacemanDMM_should_be_pure",
        "unknown procedure setting: SpacemanDMM_other",
    ]);
    assert!(errors.iter().all(|d| d.kind == DiagnosticKind::SourceError && d.location.is_some()));
    assert_eq!(check(&frontend).iter().filter(|d| d.message.starts_with("unknown procedure setting:")).count(), 2);
}
#[test]
fn ordinary_unknown_setting_still_fails_frontend() {
    assert!(dm_tree::frontend::build(Path::new("checker.dme"), &Source(
        "/proc/read()\n    set imaginary = 1\n"
    ), &Default::default(), 1).is_err());
}
