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
    sync::Arc,
};
pub struct File {
    tree: Tree,
    charge: usize,
}
pub struct Config {
    scopes: Arc<Scopes>,
    charge: usize,
}
pub struct Scope {
    name: &'static str,
    scope: LintScope,
    hash: u128,
    charge: usize,
    exact: Arc<[u8]>,
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
        if text.len() > captured_raw_policy::MAX_FIXTURE_FILE_BYTES {
            return Err("raw source exceeds per-file fixture admission".into());
        }
        let length = text.len();
        let mut file = Self::capture_budgeted(root, path, text, usize::MAX)?;
        // The bounded fixture cache keeps its existing conservative estimate.
        file.charge = length
            .checked_mul(32)
            .and_then(|n| {
                n.checked_add(8192 + 4 * (root.as_os_str().len() + path.as_os_str().len()))
            })
            .ok_or("fixture source accounting overflow")?;
        Ok(file)
    }
    /// Production source batches derive admission from the host's existing
    /// input-family resource budget. The fixture constructor keeps its limit.
    /// Each raw index/lazy reserves before allocation and records its actual
    /// retained capacities afterward; this is not an RSS or CPU guarantee.
    pub fn capture_budgeted(
        root: &Path,
        path: &Path,
        text: dm_preprocess::SourceText,
        available: usize,
    ) -> Result<Self, String> {
        if !root.is_absolute() || !path.is_absolute() {
            return Err("raw file/root must be absolute".into());
        }
        let root = dm_preprocess::regions::canonical_path(root);
        // Retain the issued provider key; filesystem equivalence is report-only.
        let path = path.to_path_buf();
        let relative = dm_preprocess::regions::relative_filesystem_path(&path, &root)
            .ok_or("captured raw source lies outside policy root")?;
        let rel = relative.to_string_lossy().replace('\\', "/");
        let file = SourceFile::from_shared_budgeted(&rel, path, text, available)?;
        let charge = file.captured_budget_charge();
        Ok(Self {
            tree: Tree::from_captured_files(root, vec![file]),
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
        self.charge.max(self.tree.files[0].captured_budget_charge())
    }
    pub fn require_view_budget(&self) -> Result<(), String> {
        self.tree.files[0]
            .captured_budget_error()
            .map_or(Ok(()), Err)
    }
    /// Equal cache fingerprints permit reuse only after exact current content
    /// and path verification; this proves content reuse, not source issuance.
    pub fn require_current_source(
        &self,
        path: &Path,
        raw: &dm_preprocess::SourceText,
    ) -> Result<(), String> {
        self.require_view_budget()?;
        let file = &self.tree.files[0];
        if file.abs != path || file.raw().text.as_bytes() != raw.as_bytes() {
            return Err("cached raw source path/bytes contradict current capture".into());
        }
        Ok(())
    }
    pub(crate) fn rebound_source(
        &self,
        path: &Path,
        raw: dm_preprocess::SourceText,
    ) -> Result<SourceFile, String> {
        self.tree.files[0].rebind_captured(path, raw)
    }
    pub fn visit_policy_storage(&self, visit: impl FnMut(crate::tree::PolicyStorageKey, usize)) {
        self.tree.files[0].visit_policy_storage(visit);
    }
    pub fn scan(&self, scope: &Scope) -> Result<Findings, String> {
        self.scan_budgeted(
            scope,
            captured_raw_policy::MAX_FIXTURE_SITES,
            64 * 1024 * 1024,
        )
    }
    /// The caller reserves the current page/family headroom before a policy
    /// can retain any findings; fixed per-file caps do not license that much
    /// additional memory when prior page/cache/output owners remain alive.
    pub fn scan_budgeted(
        &self,
        scope: &Scope,
        rows: usize,
        bytes: usize,
    ) -> Result<Findings, String> {
        self.require_view_budget()?;
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
        let mut sink = Sink::bounded(
            rows.min(captured_raw_policy::MAX_FIXTURE_SITES),
            bytes.min(64 * 1024 * 1024),
        );
        let result = catch_unwind(AssertUnwindSafe(|| {
            for file in cx.files() {
                sink.set_current(&file.rel);
                lint.scan_file(&cx, file, &mut sink);
            }
        }));
        // A denied lazy must never escape as an empty clean scan, including
        // callers that do not otherwise demand any view on this invocation.
        self.require_view_budget()?;
        if let Some(error) = sink.admission_error() {
            return Err(error);
        }
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
            scopes: Arc::new(scopes),
            charge: bytes.saturating_mul(64).saturating_add(1024),
        })
    }
    pub fn budget_charge(&self) -> usize {
        self.charge
    }
    /// Same interpreted scopes as typed adapters; not the raw-only roster.
    pub fn typed_policy_list(&self, name: &str, list: &str) -> Result<Vec<String>, String> {
        let meta = crate::captured_policy_metadata::metadata(name)
            .ok_or("typed policy is not admitted")?;
        Ok(self
            .scopes
            .for_lint(meta.name, meta.group)
            .list(list)
            .to_vec())
    }
    pub(crate) fn shared_scopes(&self) -> Arc<Scopes> {
        Arc::clone(&self.scopes)
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
            exact: bytes.into(),
        })
    }
}
/// Actual live source storage; identities are census/dedup keys, never authority.
pub fn visit_source_storage(
    text: &dm_preprocess::SourceText,
    visit: impl FnMut(crate::tree::PolicyStorageKey, usize),
) {
    crate::tree::visit_source_storage(text, visit)
}
impl Scope {
    /// Exactly the existing Cx::files metadata selection, before any source view.
    pub fn excludes_path(&self, rel: &str) -> Result<bool, String> {
        let lint = captured_raw_policy::registry()
            .find(self.name)
            .ok_or("raw lint registry entry missing")?;
        if lint.meta().scan != ScanKind::File {
            return Err("raw lint changed its per-file contract".into());
        }
        Ok(!lint.meta().select.matches_path(rel) || self.scope.exempt(rel))
    }
    pub fn empty_findings_if_excluded(&self, rel: &str) -> Result<Option<Findings>, String> {
        Ok(self.excludes_path(rel)?.then(|| Findings {
            name: self.name.into(),
            run: Run::default(),
            allow_used: Vec::new(),
        }))
    }
    /// Exact interpreted policy, not its cache hash, authenticates reuse.
    pub fn equivalent_to(&self, other: &Self) -> bool {
        self.name == other.name && self.exact.as_ref() == other.exact.as_ref()
    }
    pub fn fingerprint(&self) -> u128 {
        self.hash
    }
    pub fn budget_charge(&self) -> usize {
        self.charge
    }
}
impl Findings {
    pub fn fingerprint(&self) -> u128 {
        Self::fingerprint_parts(&self.name, &self.run, &self.allow_used)
    }
    pub fn budget_charge(&self) -> usize {
        Self::budget_charge_parts(&self.name, &self.run, &self.allow_used)
    }
    pub fn fingerprint_parts(name: &str, run: &Run, allow_used: &[AllowUse]) -> u128 {
        struct HashWriter(blake3::Hasher);
        impl std::io::Write for HashWriter {
            fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
                self.0.update(bytes);
                Ok(bytes.len())
            }
            fn flush(&mut self) -> std::io::Result<()> {
                Ok(())
            }
        }
        let mut writer = HashWriter(blake3::Hasher::new());
        serde_json::to_writer(&mut writer, &(name, &run.sites, &run.notes, allow_used))
            .expect("raw finding fields serialize");
        u128::from_le_bytes(writer.0.finalize().as_bytes()[..16].try_into().unwrap())
    }
    pub fn budget_charge_parts(name: &String, run: &Run, allow_used: &Vec<AllowUse>) -> usize {
        let site_text = run
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
        let allow_text = allow_used
            .iter()
            .map(|a| a.rel.capacity() + a.name.capacity() + a.code.capacity())
            .sum::<usize>();
        name.capacity()
            + run.sites.capacity() * std::mem::size_of::<crate::lint::Site>()
            + site_text
            + allow_used.capacity() * std::mem::size_of::<AllowUse>()
            + allow_text
            + run.notes.capacity() * std::mem::size_of::<String>()
            + run.notes.iter().map(|n| n.capacity()).sum::<usize>()
            + 1024
    }
}
#[cfg(test)]
#[path = "captured_raw_file_tests.rs"]
mod tests;

/// Exact byte length of Analyze's lossy UTF8 + universal-newline view, without
/// allocating a transformed source. No DM tokenization/parser is performed.
pub fn analyze_raw_len(bytes: &[u8]) -> Result<usize, String> {
    fn valid(bytes: &[u8], total: &mut usize, prior_cr: &mut bool) -> Result<(), String> {
        for byte in bytes {
            if !(*byte == b'\n' && *prior_cr) {
                *total = total.checked_add(1).ok_or("raw length overflow")?;
            }
            *prior_cr = *byte == b'\r';
        }
        Ok(())
    }
    let mut rest = bytes;
    let mut total = 0usize;
    let mut cr = false;
    loop {
        match std::str::from_utf8(rest) {
            Ok(_) => {
                valid(rest, &mut total, &mut cr)?;
                return Ok(total);
            }
            Err(error) => {
                let good = error.valid_up_to();
                valid(&rest[..good], &mut total, &mut cr)?;
                total = total.checked_add(3).ok_or("raw length overflow")?;
                cr = false;
                match error.error_len() {
                    Some(bad) => rest = &rest[good + bad..],
                    None => return Ok(total),
                }
            }
        }
    }
}
#[cfg(test)]
mod workspace_budget_tests {
    use super::*;
    #[test]
    fn fixture_limit_stays_while_resource_constructor_can_admit_borrowed_oversized_file() {
        let root = std::env::current_dir().unwrap();
        let path = root.join("code/large.dm");
        let text: dm_preprocess::SourceText = "x"
            .repeat(captured_raw_policy::MAX_FIXTURE_FILE_BYTES + 1)
            .into();
        assert!(File::capture(&root, &path, text.clone()).is_err());
        assert!(File::capture_budgeted(&root, &path, text.clone(), 256 * 1024 * 1024).is_ok());
        assert!(File::capture_budgeted(&root, &path, text, 1024).is_err());
    }
    #[test]
    fn normalization_preflight_matches_unchanged_reference_transform_on_encoding_edges() {
        for bytes in [
            b"".as_slice(),
            b"a\r\nb\rc\n",
            b"\xef\xbb\xbf/atom\n",
            b"\x80\xff",
            b"x\xe2\x82",
            b"\r\xc3\xa9\r\n",
            b"\xe2\x28\xa1",
            b"\xf0\x90\x80\x80",
        ] {
            assert_eq!(
                analyze_raw_len(bytes).unwrap(),
                String::from_utf8_lossy(bytes)
                    .replace("\r\n", "\n")
                    .replace('\r', "\n")
                    .len()
            );
        }
    }
}

#[cfg(test)]
mod result_headroom_tests {
    use super::*;
    #[test]
    fn scan_refuses_exhausted_result_headroom_instead_of_using_the_fixture_limit() {
        let root = std::env::current_dir().unwrap();
        let path = root.join("code/headroom.dm");
        let source: dm_preprocess::SourceText = "/proc/p()\n    sleep(1)\n".to_owned().into();
        let file = File::capture(&root, &path, source).unwrap();
        let scope = Config::capture(Configuration::ProvenMissing)
            .unwrap()
            .scope("scheduler")
            .unwrap();
        assert_eq!(file.scan(&scope).unwrap().run.sites.len(), 1);
        assert!(file.scan_budgeted(&scope, 0, 65536).is_err());
        assert!(file.scan_budgeted(&scope, 1, 1024).is_err());
        assert_eq!(
            file.scan_budgeted(&scope, 1, 65536)
                .unwrap()
                .run
                .sites
                .len(),
            1
        );
        // Even an excluded path cannot turn an exhausted resource latch into
        // a successful empty finding container.
        let excluded = Config::capture(Configuration::Captured(
            b"[lint.scheduler]\nexempt_prefixes=['code/']\n",
        ))
        .unwrap()
        .scope("scheduler")
        .unwrap();
        assert!(file.scan_budgeted(&excluded, 10, 1).is_err());
    }
}

#[cfg(test)]
mod borrowed_metric_tests {
    use super::*;
    #[test]
    fn borrowed_metrics_preserve_original_canonical_tuple_and_actual_capacities() {
        let mut name = String::with_capacity(64);
        name.push_str("pool");
        let rows = Findings {
            name,
            run: Run {
                sites: vec![crate::lint::Site {
                    rule: "new_pooled".into(),
                    rel: "code/é.dm".into(),
                    line: 2,
                    msg: "a \"message\"".into(),
                    key: String::new(),
                    ident: String::new(),
                }],
                notes: vec!["pool_lint: 1 problem(s)".into()],
            },
            allow_used: Vec::new(),
        };
        let bytes = serde_json::to_vec(&(
            &rows.name,
            &rows.run.sites,
            &rows.run.notes,
            &rows.allow_used,
        ))
        .unwrap();
        let expected =
            u128::from_le_bytes(blake3::hash(&bytes).as_bytes()[..16].try_into().unwrap());
        assert_eq!(
            Findings::fingerprint_parts(&rows.name, &rows.run, &rows.allow_used),
            expected
        );
        assert_eq!(
            Findings::budget_charge_parts(&rows.name, &rows.run, &rows.allow_used),
            rows.budget_charge()
        );
        assert!(
            rows.budget_charge()
                >= 64 + rows.run.sites.capacity() * std::mem::size_of::<crate::lint::Site>()
        );
    }
}
