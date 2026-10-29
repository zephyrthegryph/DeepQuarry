//! Per-file adapter for the audited raw-only cohort. This is data/finding work
//! over shared SourceText and common source views, never another DM parser.
use crate::{
    captured_raw_policy::{self, Configuration},
    lint::{AllowUse, Cx, Run, ScanKind, Sink},
    scopes::{LintScope, Scopes},
    tree::{SourceFile, Tree},
};
use std::{
    collections::BTreeMap,
    panic::{catch_unwind, AssertUnwindSafe},
    path::Path,
};
pub struct File {
    tree: Tree,
    charge: usize,
}
pub struct Config {
    scopes: Scopes,
    charge: usize,
}
pub struct Scope {
    name: &'static str,
    scope: LintScope,
    hash: u128,
    charge: usize,
}
#[derive(Clone, Debug)]
pub struct Findings {
    pub name: String,
    pub run: Run,
    pub allow_used: Vec<AllowUse>,
}
pub fn ordered_names(names: &[String]) -> Result<Vec<&'static str>, String> {
    if names.is_empty() {
        return Err("explicit raw-policy lint list required".into());
    }
    for name in names {
        if !captured_raw_policy::RAW_FILE_LINTS.contains(&name.as_str()) {
            return Err(format!(
                "lint {name} has not been admitted as raw-file-only"
            ));
        }
    }
    Ok(captured_raw_policy::registry()
        .lints
        .iter()
        .filter(|lint| names.iter().any(|n| n == lint.meta().name))
        .map(|lint| lint.meta().name)
        .collect())
}
impl File {
    pub fn capture(
        root: &Path,
        path: &Path,
        text: dm_preprocess::SourceText,
    ) -> Result<Self, String> {
        if !root.is_absolute() || !path.is_absolute() {
            return Err("raw file/root must be absolute".into());
        }
        let root = dm_preprocess::regions::canonical_path(root);
        // Retain the issued provider key; filesystem equivalence is report-only.
        let path = path.to_path_buf();
        let relative = dm_preprocess::regions::relative_filesystem_path(&path, &root)
            .ok_or("captured raw source lies outside policy root")?;
        if text.len() > captured_raw_policy::MAX_FIXTURE_FILE_BYTES {
            return Err("raw source exceeds per-file fixture admission".into());
        }
        let rel = relative.to_string_lossy().replace('\\', "/");
        let charge = text.len().saturating_mul(32).saturating_add(
            4 * (rel.len()
                + path.as_os_str().as_encoded_bytes().len()
                + root.as_os_str().as_encoded_bytes().len())
                + 2048,
        );
        Ok(Self {
            tree: Tree::from_captured_files(
                root,
                vec![SourceFile::from_shared_text(&rel, path, text)],
            ),
            charge,
        })
    }
    pub fn root(&self) -> &Path {
        &self.tree.root
    }
    pub fn path(&self) -> &Path {
        &self.tree.files[0].abs
    }
    pub fn fingerprint(&self) -> u128 {
        self.tree.files[0].fkey
    }
    /// Conservative cache admission estimate; not allocator/RSS accounting.
    pub fn budget_charge(&self) -> usize {
        self.charge
    }
    pub fn scan(&self, scope: &Scope) -> Result<Findings, String> {
        let lint = captured_raw_policy::registry()
            .find(scope.name)
            .ok_or("raw lint registry entry missing")?;
        if lint.meta().scan != ScanKind::File {
            return Err("raw lint changed its per-file contract".into());
        }
        let cx = Cx {
            tree: &self.tree,
            meta: lint.meta(),
            scope: &scope.scope,
        };
        let mut sink = Sink::new();
        let result = catch_unwind(AssertUnwindSafe(|| {
            for file in cx.files() {
                sink.cur = file.rel.clone();
                lint.scan_file(&cx, file, &mut sink);
            }
        }));
        if let Some(error) = self.tree.captured_violation() {
            return Err(error);
        }
        if result.is_err() {
            return Err("raw policy panicked; findings discarded".into());
        }
        if sink.sites.len() > captured_raw_policy::MAX_FIXTURE_SITES {
            return Err("raw policy exceeds finding fixture admission".into());
        }
        Ok(Findings {
            name: scope.name.into(),
            run: Run {
                sites: sink.sites,
                notes: sink.notes,
            },
            allow_used: sink.allow_used,
        })
    }
}
impl Config {
    pub fn capture(config: Configuration<'_>) -> Result<Self, String> {
        let (bytes, scopes) = match config {
            Configuration::ProvenMissing => (0, Scopes::default()),
            Configuration::Captured(bytes) => {
                if bytes.len() > captured_raw_policy::MAX_FIXTURE_FILE_BYTES {
                    return Err("raw configuration exceeds fixture admission".into());
                }
                (
                    bytes.len(),
                    match std::str::from_utf8(bytes) {
                        Ok(text) => Scopes::parse(text)?,
                        Err(_) => Scopes::default(),
                    },
                )
            }
        };
        Ok(Self {
            scopes,
            charge: bytes.saturating_mul(64).saturating_add(1024),
        })
    }
    pub fn budget_charge(&self) -> usize {
        self.charge
    }
    pub fn scope(&self, name: &str) -> Result<Scope, String> {
        let lint = captured_raw_policy::registry()
            .find(name)
            .filter(|_| captured_raw_policy::RAW_FILE_LINTS.contains(&name))
            .ok_or("raw lint is not admitted")?;
        let meta = lint.meta();
        let scope = self.scopes.for_lint(meta.name, meta.group);
        // HashMaps are ordered for the semantic fingerprint; TOML comments and
        // unrelated lint sections do not invalidate this interpreted projection.
        let lists: BTreeMap<_, _> = scope.lists.iter().collect();
        let tables: BTreeMap<_, _> = scope.tables.iter().collect();
        let bytes = serde_json::to_vec(&(
            &scope.exempt_prefixes,
            &scope.exempt_contains,
            &scope.exempt_files,
            lists,
            tables,
            &scope.ceilings,
            &scope.reason_codes,
        ))
        .map_err(|e| e.to_string())?;
        let hash = u128::from_le_bytes(blake3::hash(&bytes).as_bytes()[..16].try_into().unwrap());
        Ok(Scope {
            name: meta.name,
            scope,
            hash,
            charge: bytes.len().saturating_mul(32).saturating_add(2048),
        })
    }
}
impl Scope {
    pub fn fingerprint(&self) -> u128 {
        self.hash
    }
    pub fn budget_charge(&self) -> usize {
        self.charge
    }
}
impl Findings {
    pub fn fingerprint(&self) -> u128 {
        let bytes = serde_json::to_vec(&(
            &self.name,
            &self.run.sites,
            &self.run.notes,
            &self.allow_used,
        ))
        .expect("raw finding fields serialize");
        u128::from_le_bytes(blake3::hash(&bytes).as_bytes()[..16].try_into().unwrap())
    }
    pub fn budget_charge(&self) -> usize {
        let site_text = self
            .run
            .sites
            .iter()
            .map(|s| {
                s.rule.capacity()
                    + s.rel.capacity()
                    + s.msg.capacity()
                    + s.key.capacity()
                    + s.ident.capacity()
            })
            .sum::<usize>();
        let allow_text = self
            .allow_used
            .iter()
            .map(|a| a.rel.capacity() + a.name.capacity() + a.code.capacity())
            .sum::<usize>();
        self.name.capacity()
            + self.run.sites.capacity() * std::mem::size_of::<crate::lint::Site>()
            + site_text
            + self.allow_used.capacity() * std::mem::size_of::<AllowUse>()
            + allow_text
            + self.run.notes.capacity() * std::mem::size_of::<String>()
            + self.run.notes.iter().map(|n| n.capacity()).sum::<usize>()
            + 1024
    }
}
#[cfg(test)]
#[path = "captured_raw_file_tests.rs"]
mod tests;
