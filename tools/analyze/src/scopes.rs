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
    /// `[lint.<name>.ceilings]`: per-rule count ceilings. A rule with a ceiling is judged by its
    /// count (more sites than the ceiling fails) instead of the lint's baseline; `analyze baseline
    /// --update` lowers it, never raises it.
    pub ceilings: std::collections::BTreeMap<String, i64>,
    /// `reason_codes = [...]`: the codes `ALLOW(<lint>/CODE)` may carry for this lint. Empty means
    /// the lint declares none (any code is accepted).
    pub reason_codes: Vec<String>,
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
                    ceilings: Default::default(),
                    reason_codes: strings(section.get("reason_codes")),
                };
                if let Some(c) = section.get("ceilings").and_then(|v| v.as_table()) {
                    for (k, v) in c {
                        if let Some(n) = v.as_integer() {
                            scope.ceilings.insert(k.clone(), n);
                        }
                    }
                }
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

/// The TOML table key for a lint name (`sys/emag` needs quotes).
fn toml_key(name: &str) -> String {
    if name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-') {
        name.to_string()
    } else {
        format!("\"{}\"", name)
    }
}

/// Sets `[lint.<lint>.ceilings] <rule> = <n>` in the scopes file, editing only that line (comments
/// and every other table are left byte for byte); appends the table when it is missing.
pub fn write_ceiling(path: &Path, lint: &str, rule: &str, n: i64) -> std::io::Result<()> {
    let text = std::fs::read_to_string(path).unwrap_or_default();
    let header = format!("[lint.{}.ceilings]", toml_key(lint));
    let mut lines: Vec<String> = text.split('\n').map(|l| l.to_string()).collect();
    let had_trailing_newline = text.ends_with('\n');
    if had_trailing_newline {
        lines.pop();
    }
    let key_line = format!("{} = {}", rule, n);
    if let Some(h) = lines.iter().position(|l| l.trim() == header) {
        let mut end = lines.len();
        for (i, l) in lines.iter().enumerate().skip(h + 1) {
            if l.trim_start().starts_with('[') {
                end = i;
                break;
            }
        }
        let mut replaced = false;
        for l in lines.iter_mut().take(end).skip(h + 1) {
            let t = l.trim_start();
            if let Some(rest) = t.strip_prefix(rule) {
                if rest.trim_start().starts_with('=') {
                    *l = key_line.clone();
                    replaced = true;
                    break;
                }
            }
        }
        if !replaced {
            // insert after the last non-blank line of the table
            let mut at = end;
            while at > h + 1 && lines[at - 1].trim().is_empty() {
                at -= 1;
            }
            lines.insert(at, key_line);
        }
    } else {
        if lines.last().map(|l| !l.trim().is_empty()).unwrap_or(false) {
            lines.push(String::new());
        }
        lines.push(header);
        lines.push(key_line);
    }
    let mut out = lines.join("\n");
    out.push('\n');
    std::fs::write(path, out)
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

    #[test]
    fn ceilings_parse_and_rewrite_in_place() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("s.toml");
        std::fs::write(&p, "# keep me\n[lint.check_grep]\nexempt_files = [\"a\"]\n\n[lint.check_grep.ceilings]\n# why\nfire_act = 6\nother = 1\n\n[lint.x]\nexempt_files = []\n").unwrap();
        let s = Scopes::load(&p).unwrap();
        assert_eq!(s.for_lint("check_grep", "").ceilings["fire_act"], 6);
        write_ceiling(&p, "check_grep", "fire_act", 4).unwrap();
        write_ceiling(&p, "check_grep", "new_rule", 9).unwrap();
        write_ceiling(&p, "sys/emag", "emag_act", 2).unwrap();
        let text = std::fs::read_to_string(&p).unwrap();
        assert!(text.starts_with("# keep me\n"));
        assert!(text.contains("# why\nfire_act = 4\nother = 1\nnew_rule = 9\n"), "{}", text);
        assert!(text.contains("[lint.\"sys/emag\".ceilings]\nemag_act = 2\n"), "{}", text);
        let s = Scopes::load(&p).unwrap();
        assert_eq!(s.for_lint("check_grep", "").ceilings["new_rule"], 9);
        assert_eq!(s.for_lint("sys/emag", "sys").ceilings["emag_act"], 2);
        assert!(s.for_lint("x", "").exempt_files.is_empty());
    }

    #[test]
    fn reason_codes_list_parses() {
        let s = Scopes::parse("[lint.scheduler]\nreason_codes = [\"BLOCKING_IO\", \"MC\"]\n").unwrap();
        assert_eq!(s.for_lint("scheduler", "").reason_codes, vec!["BLOCKING_IO", "MC"]);
    }
}
