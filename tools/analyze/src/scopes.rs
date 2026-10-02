//! `tools/ci/lint_scopes.toml`: where each lint's path exemptions and named lists live, instead of
//! being hard-coded in the lint.
//!
//! ```toml
//! [lint.scheduler]
//! exempt_prefixes = ["code/modules/tgs/"]   # rel path starts with
//! exempt_contains = ["/unit_tests/"]        # rel path contains
//! exempt_files    = ["code/__defines/tgs.dm"]
//!
//! [lint.scheduler.lists]                    # anything else a rule needs by name
//! core_dirs = ["code/datums/om/"]
//! ```
//!
//! A lint's section is found by lint name, then by its group (`[lint.sys]` serves `sys/emag`).

use std::collections::HashMap;
use std::path::Path;

#[derive(Clone, Debug, Default)]
pub struct LintScope {
    pub exempt_prefixes: Vec<String>,
    pub exempt_contains: Vec<String>,
    pub exempt_files: Vec<String>,
    pub lists: HashMap<String, Vec<String>>,
}

static EMPTY: Vec<String> = Vec::new();

impl LintScope {
    pub fn exempt(&self, rel: &str) -> bool {
        self.exempt_prefixes.iter().any(|p| rel.starts_with(p.as_str()))
            || self.exempt_contains.iter().any(|c| rel.contains(c.as_str()))
            || self.exempt_files.iter().any(|f| f == rel)
    }

    pub fn list(&self, key: &str) -> &[String] {
        self.lists.get(key).unwrap_or(&EMPTY)
    }
}

#[derive(Clone, Debug, Default)]
pub struct Scopes {
    lints: HashMap<String, LintScope>,
    /// ALLOW names for lints that read the annotation but are not (yet) engine lints.
    pub known_allow: Vec<String>,
    /// Hash of the file text (cache key).
    pub hash: String,
}

fn strings(v: Option<&toml::Value>) -> Vec<String> {
    v.and_then(|v| v.as_array())
        .map(|a| a.iter().filter_map(|x| x.as_str().map(|s| s.to_string())).collect())
        .unwrap_or_default()
}

impl Scopes {
    pub fn load(path: &Path) -> Result<Scopes, String> {
        let text = match std::fs::read_to_string(path) {
            Ok(t) => t,
            Err(_) => return Ok(Scopes::default()),
        };
        Self::parse(&text)
    }

    pub fn parse(text: &str) -> Result<Scopes, String> {
        let value: toml::Value = text.parse().map_err(|e| format!("lint_scopes.toml: {}", e))?;
        let mut s = Scopes { hash: blake3::hash(text.as_bytes()).to_hex().to_string(), ..Scopes::default() };
        if let Some(allow) = value.get("allow") {
            s.known_allow = strings(allow.get("known"));
        }
        if let Some(lints) = value.get("lint").and_then(|v| v.as_table()) {
            for (name, section) in lints {
                let mut scope = LintScope {
                    exempt_prefixes: strings(section.get("exempt_prefixes")),
                    exempt_contains: strings(section.get("exempt_contains")),
                    exempt_files: strings(section.get("exempt_files")),
                    lists: HashMap::new(),
                };
                if let Some(lists) = section.get("lists").and_then(|v| v.as_table()) {
                    for (k, v) in lists {
                        scope.lists.insert(k.clone(), strings(Some(v)));
                    }
                }
                s.lints.insert(name.clone(), scope);
            }
        }
        Ok(s)
    }

    /// The scope for a lint: its own section, else its group's, else empty.
    pub fn for_lint(&self, name: &str, group: &str) -> LintScope {
        if let Some(s) = self.lints.get(name) {
            return s.clone();
        }
        if !group.is_empty() {
            if let Some(s) = self.lints.get(group) {
                return s.clone();
            }
        }
        LintScope::default()
    }

    pub fn has(&self, name: &str) -> bool {
        self.lints.contains_key(name)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_exemptions_and_lists() {
        let s = Scopes::parse(
            r#"
[allow]
known = ["x"]
[lint.sys]
exempt_prefixes = ["code/modules/unit_tests/"]
[lint.scheduler]
exempt_contains = ["/unit_tests/"]
[lint.scheduler.lists]
core = ["a", "b"]
"#,
        )
        .unwrap();
        assert!(s.for_lint("sys/emag", "sys").exempt("code/modules/unit_tests/a.dm"));
        let sc = s.for_lint("scheduler", "");
        assert!(sc.exempt("code/x/unit_tests/a.dm"));
        assert!(!sc.exempt("code/x/a.dm"));
        assert_eq!(sc.list("core"), &["a".to_string(), "b".to_string()]);
        assert_eq!(s.known_allow, vec!["x".to_string()]);
    }
}
