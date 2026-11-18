//! `tools/ci/lint_scopes.toml`: where each lint's path exemptions and named lists live, instead of
//! being hard-coded in the lint.
//!
//! ```toml
//! [lint.scheduler]
//! exempt_prefixes = ["code/world/tgs/"]   # rel path starts with
//! exempt_contains = ["/unit_tests/"]        # rel path contains
//! exempt_files    = ["code/__defines/tgs.dm"]
//!
//! [lint.scheduler.lists]                    # anything else a rule needs by name
//! core_dirs = ["code/datums/om/"]
//! ```
//!
//! A lint's section is found by lint name, then by its group (`[lint.sys]` serves `sys/emag`).

use std::collections::BTreeMap;

use serde::{Deserialize, Deserializer, Serialize, Serializer, ser::SerializeMap};

/// Small owned configuration tables. Iteration and map serialization use
/// lexical key order, independently of TOML source order.
#[derive(Clone, Debug)]
pub struct ScopeMap<V> {
    rows: Vec<(String, V)>,
}
impl<V> Default for ScopeMap<V> {
    fn default() -> Self { Self { rows: Vec::new() } }
}
impl<V> ScopeMap<V> {
    fn index(&self, key: &str) -> Result<usize, usize> {
        self.rows.binary_search_by(|(name, _)| name.as_str().cmp(key))
    }
    pub fn get(&self, key: &str) -> Option<&V> {
        self.index(key).ok().map(|index| &self.rows[index].1)
    }
    pub fn contains_key(&self, key: &str) -> bool { self.index(key).is_ok() }
    pub fn len(&self) -> usize { self.rows.len() }
    pub fn is_empty(&self) -> bool { self.rows.is_empty() }
    pub fn iter(&self) -> impl ExactSizeIterator<Item = (&String, &V)> {
        self.rows.iter().map(|(key, value)| (key, value))
    }
    pub fn values(&self) -> impl ExactSizeIterator<Item = &V> {
        self.rows.iter().map(|(_, value)| value)
    }
    pub fn insert(&mut self, key: String, value: V) -> Option<V> {
        match self.index(&key) {
            Ok(index) => Some(std::mem::replace(&mut self.rows[index].1, value)),
            Err(index) => { self.rows.insert(index, (key, value)); None }
        }
    }
    /// SAME lexical insertion; native fixture callers fund actual row growth.
    pub(crate) fn insert_using<C:crate::key_policy_control::Control>(&mut self,key:String,value:V,control:&mut C)->Result<Option<V>,C::Error>{
        control.checkpoint()?;
        match self.index(&key){
            Ok(index)=>Ok(Some(std::mem::replace(&mut self.rows[index].1,value))),
            Err(index)=>{crate::key_policy_control::row(control,&mut self.rows)?;self.rows.insert(index,(key,value));Ok(None)}
        }
    }
    fn from_unique_rows(rows: impl Iterator<Item = (String, V)>) -> Self {
        let mut rows: Vec<_> = rows.collect();
        rows.sort_unstable_by(|(left, _), (right, _)| left.cmp(right));
        Self { rows }
    }
    #[cfg(feature = "native-policy")]
    fn storage_bytes(&self) -> Option<usize> {
        self.rows.iter().try_fold(self.rows.capacity().checked_mul(std::mem::size_of::<(String, V)>())?,
            |bytes, (key, _)| bytes.checked_add(key.capacity()))
    }
}
impl<V> std::ops::Index<&str> for ScopeMap<V> {
    type Output = V;

    fn index(&self, key: &str) -> &Self::Output {
        self.get(key).expect("no entry found for key")
    }
}
impl<V: Serialize> Serialize for ScopeMap<V> {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let mut map = serializer.serialize_map(Some(self.len()))?;
        for (key, value) in self.iter() { map.serialize_entry(key, value)?; }
        map.end()
    }
}
impl<'de, V: Deserialize<'de>> Deserialize<'de> for ScopeMap<V> {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct MapVisitor<V>(std::marker::PhantomData<V>);
        impl<'de, V: Deserialize<'de>> serde::de::Visitor<'de> for MapVisitor<V> {
            type Value = ScopeMap<V>;
            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("a named lint scope map")
            }
            fn visit_map<A: serde::de::MapAccess<'de>>(self, mut input: A) -> Result<Self::Value, A::Error> {
                let mut rows: Vec<(String, V)> = Vec::new();
                while let Some(row) = input.next_entry()? { rows.push(row); }
                // The old map decoder kept the last value for duplicate
                // wire keys. Stable sorting preserves that input order.
                rows.sort_by(|(left, _), (right, _)| left.cmp(right));
                rows.dedup_by(|later, earlier| {
                    if later.0 != earlier.0 { return false; }
                    std::mem::swap(&mut earlier.1, &mut later.1);
                    true
                });
                Ok(ScopeMap { rows })
            }
        }
        deserializer.deserialize_map(MapVisitor(std::marker::PhantomData))
    }
}

use std::path::Path;

#[derive(Clone, Debug, Default)]
pub struct LintScope {
    pub exempt_prefixes: Vec<String>,
    pub exempt_contains: Vec<String>,
    pub exempt_files: Vec<String>,
    pub lists: ScopeMap<Vec<String>>,
    /// `[lint.<name>.tables.<key>]`: named string-to-string tables (a key and the reason it is listed).
    pub tables: ScopeMap<ScopeMap<String>>,
    /// `[lint.<name>.ceilings]`: per-rule count ceilings. A rule with a ceiling is judged by its
    /// count (more sites than the ceiling fails) instead of the lint's baseline; `analyze baseline
    /// --update` lowers it, never raises it.
    pub ceilings: ScopeMap<i64>,
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

    pub fn table(&self, key: &str) -> Option<&ScopeMap<String>> {
        self.tables.get(key)
    }

    pub(crate) fn owned_table(&self, key: &str) -> BTreeMap<String, String> {
        self.table(key).into_iter().flat_map(|table| table.iter())
            .map(|(key, value)| (key.clone(), value.clone())).collect()
    }
}

#[derive(Clone, Debug, Default)]
pub struct Scopes {
    lints: ScopeMap<LintScope>,
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
            // The TOML parser guarantees unique keys. Collect then sort
            // each table once, even when source order is preserved.
            s.lints = ScopeMap::from_unique_rows(lints.iter().map(|(name, section)| {
                let ceilings = ScopeMap::from_unique_rows(
                    section.get("ceilings").and_then(toml::Value::as_table).into_iter().flatten()
                        .filter_map(|(key, value)| value.as_integer().map(|value| (key.clone(), value))),
                );
                let lists = ScopeMap::from_unique_rows(
                    section.get("lists").and_then(toml::Value::as_table).into_iter().flatten()
                        .map(|(key, value)| (key.clone(), strings(Some(value)))),
                );
                let tables = ScopeMap::from_unique_rows(
                    section.get("tables").and_then(toml::Value::as_table).into_iter().flatten()
                        .filter_map(|(key, value)| value.as_table().map(|table| {
                            let rows = ScopeMap::from_unique_rows(table.iter().filter_map(|(key, value)| {
                                value.as_str().map(|value| (key.clone(), value.to_owned()))
                            }));
                            (key.clone(), rows)
                        })),
                );
                (name.clone(), LintScope {
                    exempt_prefixes: strings(section.get("exempt_prefixes")),
                    exempt_contains: strings(section.get("exempt_contains")),
                    exempt_files: strings(section.get("exempt_files")),
                    lists,
                    tables,
                    ceilings,
                    reason_codes: strings(section.get("reason_codes")),
                })
            }));
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

    /// Borrow the same selection used by for_lint without cloning captured
    /// configuration tables before the operation's temporary admission.
    pub(crate) fn borrowed_for_lint(&self, name: &str, group: &str) -> Option<&LintScope> {
        self.lints.get(name).or_else(|| if group.is_empty() { None } else { self.lints.get(group) })
    }

    pub fn has(&self, name: &str) -> bool {
        self.lints.contains_key(name)
    }
}

/// Retained allocation-request bytes, excluding the discarded TOML value.
#[cfg(feature = "native-policy")]
pub(crate) fn retained_scope_allocation_bound(scopes: &Scopes) -> Option<usize> {
    use std::mem::size_of;

    fn strings(values: &Vec<String>) -> Option<usize> {
        values.iter().try_fold(values.capacity().checked_mul(size_of::<String>())?,
            |bytes, value| bytes.checked_add(value.capacity()))
    }

    let mut bytes = size_of::<Scopes>().checked_add(2 * size_of::<usize>())?
        .checked_add(scopes.lints.storage_bytes()?)?
        .checked_add(strings(&scopes.known_allow)?)?.checked_add(scopes.hash.capacity())?;
    for (_, scope) in scopes.lints.iter() {
        bytes = bytes.checked_add(scope.lists.storage_bytes()?)?
            .checked_add(scope.tables.storage_bytes()?)?.checked_add(scope.ceilings.storage_bytes()?)?;
        for values in [&scope.exempt_prefixes, &scope.exempt_contains, &scope.exempt_files, &scope.reason_codes] {
            bytes = bytes.checked_add(strings(values)?)?;
        }
        for values in scope.lists.values() {
            bytes = bytes.checked_add(strings(values)?)?;
        }
        for table in scope.tables.values() {
            bytes = bytes.checked_add(table.storage_bytes()?)?;
            for value in table.values() {
                bytes = bytes.checked_add(value.capacity())?;
            }
        }
    }
    Some(bytes)
}

#[cfg(all(test, feature = "native-policy"))]
#[test]
fn flat_scope_maps_keep_ordered_wire_and_exact_backing() {
    let mut scopes = Scopes::parse(concat!(
        "[lint.z.lists]\nz = ['last']\na = ['first', 'second']\n",
        "[lint.z.tables.hot]\nz = 'last'\na = 'first'\n",
        "[lint.z.ceilings]\nz = 2\na = 1\n",
    )).unwrap();
    let scope = scopes.borrowed_for_lint("z", "").unwrap();
    assert_eq!(serde_json::to_string(&(&scope.lists, &scope.tables, &scope.ceilings)).unwrap(),
        r#"[{"a":["first","second"],"z":["last"]},{"hot":{"a":"first","z":"last"}},{"a":1,"z":2}]"#);
    assert_eq!(scope.owned_table("hot"), BTreeMap::from([("a".into(),"first".into()),("z".into(),"last".into())]));
    let decoded: ScopeMap<i64> = serde_json::from_str(r#"{"z":2,"a":1,"z":3}"#).unwrap();
    assert_eq!(serde_json::to_string(&decoded).unwrap(),r#"{"a":1,"z":3}"#);
    let full = retained_scope_allocation_bound(&scopes).unwrap();
    let lists = std::mem::take(&mut scopes.lints.rows[0].1.lists);
    let removed = lists.rows.capacity() * std::mem::size_of::<(String, Vec<String>)>()
        + lists.iter().map(|(key, values)| key.capacity() + values.capacity() * std::mem::size_of::<String>()
            + values.iter().map(String::capacity).sum::<usize>()).sum::<usize>();
    assert_eq!(full - retained_scope_allocation_bound(&scopes).unwrap(), removed);
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
pub fn write_ceiling(path:&Path,lint:&str,rule:&str,n:i64)->std::io::Result<()>{
    let text=std::fs::read_to_string(path).unwrap_or_default();
    std::fs::write(path,render_ceiling(&text,lint,rule,n))
}

/// SAME exact line-preserving ceiling edit over captured configuration DATA.
/// No path/currentness/producer grant; caller must fund all output/scratch.
pub fn render_ceiling(text:&str,lint:&str,rule:&str,n:i64)->String{
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
    out
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
exempt_prefixes = ["code/tests/unit_tests/", "code/tests/unit_tests/"]
[lint.scheduler]
exempt_contains = ["/unit_tests/"]
[lint.scheduler.lists]
core = ["a", "b"]
"#,
        )
        .unwrap();
        assert!(s.for_lint("sys/emag", "sys").exempt("code/tests/unit_tests/a.dm"));
        let sc = s.for_lint("scheduler", "");
        assert!(sc.exempt("code/x/unit_tests/a.dm"));
        assert!(!sc.exempt("code/x/a.dm"));
        assert_eq!(sc.list("core"), &["a".to_string(), "b".to_string()]);
        assert_eq!(s.known_allow, vec!["x".to_string()]);
    }

    #[test]
    fn tables_parse() {
        let s = Scopes::parse("[lint.x.tables.hot]\n\"/atom/a\" = \"why\"\n").unwrap();
        assert_eq!(s.for_lint("x", "").table("hot").unwrap().get("/atom/a").map(String::as_str), Some("why"));
        assert!(s.for_lint("x", "").table("none").is_none());
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

/// The macro library: `code/__defines/` (generated Verdigris bindings and the files not yet moved) and the five module folders of
/// `code/defines/` (doc section 22). `code/defines/` itself also holds old type-definition files, which are not macros.
pub const DEFINES_ROOTS: [&str; 6] = [
    "code/__defines/",
    "code/defines/engine/",
    "code/defines/library/",
    "code/defines/host/",
    "code/defines/base/",
    "code/defines/content/",
];

pub fn is_defines(rel: &str) -> bool {
    DEFINES_ROOTS.iter().any(|p| rel.starts_with(p))
}
