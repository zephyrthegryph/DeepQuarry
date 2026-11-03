//! Immutable original whole-registration validation method; unsealed test reference.
use crate::{lint::Registry,scopes::Scopes};
pub struct Original<'a>{pub reg:&'a Registry,pub scopes:&'a Scopes}
impl Original<'_>{
    pub fn validate_scopes(&self) -> Vec<String> {
        let mut problems = Vec::new();
        for l in &self.reg.lints {
            let m = l.meta();
            let scope = self.scopes.for_lint(m.name, m.group);
            for key in m.lists {
                if !scope.lists.contains_key(*key) {
                    problems.push(format!("lint_scopes.toml: [lint.{}.lists] is missing `{}`", m.name, key));
                }
            }
        }
        problems
    }
}
