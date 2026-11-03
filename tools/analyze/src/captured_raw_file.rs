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
    allow_digest: std::sync::OnceLock<[u8;20]>,
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
    // As-of report data derived from the same admitted raw source, not source authority.
    source_text: Vec<String>,
    // Original whole-file digest used only for the existing ALLOW usage report.
    allow_source_digest: Option<[u8;20]>,
}
/// Operation-local failures never become reusable source findings.
#[derive(Debug)]
pub enum ScanFailure { Policy(String), Admission(String) }
impl ScanFailure { pub fn into_message(self)->String { match self { Self::Policy(s)|Self::Admission(s)=>s } } }
impl From<String> for ScanFailure { fn from(s:String)->Self {Self::Policy(s)} }
impl From<&str> for ScanFailure { fn from(s:&str)->Self {Self::Policy(s.into())} }
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

/// Borrowed policy-only text views of ONE existing admitted original file.
/// These strings grant no compiled source/AST/occurrence authority.
#[cfg(feature="native-policy")]
pub struct RawPolicyViews<'a>{file:&'a SourceFile,allocation:Option<&'a crate::captured_generator_budget::Budget>}
#[cfg(feature="native-policy")]
impl<'a> RawPolicyViews<'a>{
 /// Private policy-only view; grants no original AST/occurrence authority.
 pub(crate) fn source_file(&self)->Result<&'a SourceFile,crate::reactive_reads_native::Failure>{self.require()?;Ok(self.file)}
 pub(crate) fn from_source(file:&'a SourceFile)->Self{Self{file,allocation:None}}

 pub(crate) fn allocation_budget<'b>(&'b self,fallback:&'b crate::captured_generator_budget::Budget)->&'b crate::captured_generator_budget::Budget{self.allocation.unwrap_or(fallback)}
 fn require(&self)->Result<(),crate::reactive_reads_native::Failure>{self.file.captured_budget_error().map_or(Ok(()),|error|Err(crate::reactive_reads_native::Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,error))))}
 pub fn raw(&self)->Result<&'a str,crate::reactive_reads_native::Failure>{self.require()?;let value=self.file.text();self.require()?;Ok(value)}
 pub fn marker(&self)->Result<&'a str,crate::reactive_reads_native::Failure>{self.require()?;let value=self.file.marker();self.require()?;Ok(value.as_str())}
 /// Exact original clean (comments/strings projected by SourceFile), data only.
 pub fn clean(&self,fallback:&crate::captured_generator_budget::Budget)->Result<&'a str,crate::reactive_reads_native::Failure>{let budget=self.allocation_budget(fallback);self.require()?;let bytes=SourceFile::raw_policy_clean_bound(self.file.text()).ok_or_else(||{budget.deny();crate::reactive_reads_native::Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"original clean view admission overflow"))})?;budget.charge(bytes).map_err(|message|crate::reactive_reads_native::Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))?;let value=self.file.clean();self.require()?;Ok(&value.text)}
 pub fn code(&self)->Result<&'a crate::tree::View,crate::reactive_reads_native::Failure>{self.require()?;let value=self.file.code();self.require()?;Ok(value)}
}
/// Exact existing CODE_DM path policy, including hidden-component exclusion.
#[cfg(feature="native-policy")]
pub fn is_code_dm(relative:&str)->bool{crate::tree::CODE_DM.matches_path(relative)}
#[cfg(feature="native-policy")]
pub fn code_dm_roots()-> &'static [(&'static str,&'static str)]{crate::tree::CODE_DM.roots}

/// Generator CLI test-only classification has a distinct discovery role:
/// unlike CODE_DM consumers it sees dot paths, and excludes generated outputs.
#[cfg(feature="native-policy")]
pub fn generator_cli_test_roots()-> &'static [(&'static str,&'static str)]{crate::generator_test_scope::cli_source_roots()}
#[cfg(feature="native-policy")]
pub fn is_generator_cli_test_source(relative:&str)->bool{crate::generator_test_scope::cli_test_source(relative)}

impl File {
    /// Loan the SAME lazy source views. The boolean only controls traversal;
    /// no source reference is returned by this callback API.
    #[cfg(feature="native-policy")]
    pub fn with_policy_views(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,crate::reactive_reads_native::Failure>)->Result<bool,crate::reactive_reads_native::Failure>{self.with_policy_views_budget(None,visit)}
    #[cfg(feature="native-policy")]
    fn with_policy_views_budget(&self,allocation:Option<&crate::captured_generator_budget::Budget>,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,crate::reactive_reads_native::Failure>)->Result<bool,crate::reactive_reads_native::Failure>{
        let views=RawPolicyViews{file:&self.tree.files[0],allocation};views.require()?;
        let pending=visit(&self.tree.files[0].rel,views);
        if matches!(&pending,Err(crate::reactive_reads_native::Failure::Operational(_))){return pending}
        RawPolicyViews{file:&self.tree.files[0],allocation}.require()?;pending
    }

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
            allow_digest: std::sync::OnceLock::new(),
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
        self.scan_budgeted_checked(scope,rows,bytes).map_err(ScanFailure::into_message)
    }
    pub fn scan_budgeted_checked(&self,scope:&Scope,rows:usize,bytes:usize)->Result<Findings,ScanFailure> {
        self.require_view_budget().map_err(ScanFailure::Admission)?;
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
        self.require_view_budget().map_err(ScanFailure::Admission)?;
        if let Some(error) = sink.admission_error() {
            return Err(ScanFailure::Admission(error));
        }
        if let Some(error) = self.tree.captured_violation() {
            return Err(ScanFailure::Admission(error));
        }
        if result.is_err() {
            return Err("raw policy panicked; findings discarded".into());
        }
        if sink.sites.len() > captured_raw_policy::MAX_FIXTURE_SITES {
            return Err("raw policy exceeds finding fixture admission".into());
        }
        let mut findings = Findings {
            source_text: Vec::new(),
            allow_source_digest: None,
            name: scope.name.into(),
            run: Run {
                sites: sink.sites,
                notes: sink.notes,
            },
            allow_used: sink.allow_used,
        };
        if !findings.allow_used.is_empty() {
            let source=&self.tree.files[0];
            if findings.allow_used.iter().any(|used|used.rel!=source.rel) {
                return Err("ALLOW usage refers outside its authenticated source".into());
            }
            // Same normalized SourceFile text and trailing-newline treatment as
            // original write_allow_usage; fixed-size hash needs no source copy.
            findings.allow_source_digest=Some(*self.allow_digest.get_or_init(||{source_allow_digest(source)}));
            self.require_view_budget().map_err(ScanFailure::Admission)?;
        }
        findings.source_text = self.report_source_text(
            &findings.run.sites, bytes.saturating_sub(findings.budget_charge()),
        )?;
        if findings.budget_charge() > bytes {
            return Err(ScanFailure::Admission("raw report evidence exceeds admitted result headroom".into()));
        }
        Ok(findings)
    }
    fn report_source_text(&self, sites: &[crate::lint::Site], available: usize) -> Result<Vec<String>, ScanFailure> {
        let file = &self.tree.files[0];
        let raw = file.raw();
        self.require_view_budget().map_err(ScanFailure::Admission)?;
        // normalize_ws reserves the original line length. Count that allocation,
        // including repeated line uses, before allocating any output strings.
        let mut bound = sites.len().checked_mul(std::mem::size_of::<String>())
            .ok_or_else(|| ScanFailure::Admission("raw report evidence metadata overflow".into()))?;
        for site in sites {
            if site.rel != file.rel {
                return Err("raw finding refers outside its authenticated source".into());
            }
            bound = bound.checked_add(raw.line(site.line as usize).len())
                .ok_or_else(|| ScanFailure::Admission("raw report evidence byte overflow".into()))?;
        }
        if bound > available {
            return Err(ScanFailure::Admission("raw report evidence exceeds admitted result headroom".into()));
        }
        let mut out = Vec::with_capacity(sites.len());
        for site in sites {
            out.push(crate::util::normalize_ws(raw.line(site.line as usize)));
        }
        Ok(out)
    }
}
impl Config {
 /// Interpreted path data only; this does not grant a source or completion role.
 pub fn policy_path_exempt(&self,name:&str,group:&str,relative:&str)->bool{self.scopes.borrowed_for_lint(name,group).is_some_and(|scope|scope.exempt(relative))}
 pub(crate) fn borrowed_policy_scope(&self,name:&str,group:&str)->Option<&crate::scopes::LintScope>{self.scopes.borrowed_for_lint(name,group)}
    /// SAME interpreted config; data alone grants no source or EOF authority.
    pub fn borrowed_report_scope(&self,name:&str,group:&str)->Option<&crate::scopes::LintScope>{self.borrowed_policy_scope(name,group)}
    /// Borrow the unchanged Auto lists from this actual interpreted owner.
    #[cfg(feature="native-policy")]
    pub fn with_auto_tracked_lists<T>(&self,consume:impl FnOnce(&[String],&[&[String]])->T)->T{let scope=self.scopes.borrowed_for_lint("auto_tracked","");let list=|name:&str|scope.map_or(&[][..],|scope|scope.list(name));consume(list("include"),&[list("exclude"),list("exclude_fixtures"),list("exclude_heat"),list("exclude_memo")])}

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
    pub(crate) fn with_allow_known<T>(&self,consume:impl FnOnce(&[String])->T)->T{consume(&self.scopes.known_allow)}
    pub(crate) fn shared_scopes(&self) -> Arc<Scopes> {
        Arc::clone(&self.scopes)
    }
    pub fn scope(&self, name: &str) -> Result<Scope, String> {
        let lint = captured_raw_policy::registry()
            .find(name)
            .filter(|_| captured_raw_policy::RAW_FILE_LINTS.contains(&name))
            .ok_or("raw lint is not admitted")?;
        let meta = lint.meta();
        self.scope_named(meta.name,meta.group)
    }
    /// Interpreted unique multi-file policy configuration; data, not source authority.
    #[cfg(feature="native-policy")]
    pub fn check_grep_scope(&self)->Result<Scope,String>{self.scope_named("check_grep","")}
    fn scope_named(&self,name:&'static str,group:&'static str)->Result<Scope,String>{
        let scope = self.scopes.for_lint(name,group);
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
            name,
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
    /// Captured interpreted configuration for report judgement, never source authority.
    pub fn report_scope(&self)->&LintScope{&self.scope}
    pub fn report_scope_json(&self)->Result<&str,std::str::Utf8Error>{std::str::from_utf8(&self.exact)}
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
            source_text: Vec::new(),
            allow_source_digest: None,
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
    pub fn allow_source_digest(&self)->Option<&[u8;20]>{self.allow_source_digest.as_ref()}
    pub fn site_text(&self, index: usize) -> Option<&str> {
        self.source_text.get(index).map(String::as_str)
    }
    pub fn fingerprint(&self) -> u128 {
        let rows = Self::fingerprint_parts(&self.name, &self.run, &self.allow_used);
        let mut hash = blake3::Hasher::new();
        hash.update(&rows.to_le_bytes());
        if let Some(digest)=&self.allow_source_digest{hash.update(&[1]);hash.update(digest);}else{hash.update(&[0]);}
        for text in &self.source_text {
            hash.update(&(text.len() as u64).to_le_bytes());
            hash.update(text.as_bytes());
        }
        u128::from_le_bytes(hash.finalize().as_bytes()[..16].try_into().unwrap())
    }
    pub fn budget_charge(&self) -> usize {
        Self::budget_charge_parts(&self.name, &self.run, &self.allow_used)
            + self.source_text.capacity() * std::mem::size_of::<String>()
            + self.source_text.iter().map(|text| text.capacity()).sum::<usize>()
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
            source_text: Vec::new(),
            allow_source_digest: None,
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

#[cfg(test)]
mod report_evidence_tests {
    use super::*;
    fn site(rel: &str, line: u32) -> crate::lint::Site {
        crate::lint::Site { rule: "scheduler".into(), rel: rel.into(), line,
            msg: String::new(), key: String::new(), ident: String::new() }
    }
    #[test]
    fn report_evidence_equals_original_fingerprint_normalization_and_stays_as_of_capture() {
        let root = std::env::current_dir().unwrap().join("report-evidence-fixture");
        let file = File::capture(&root, &root.join("code/a.dm"),
            "/proc/p()\n\t sleep(1) \u{1c}\u{a0} // retained é\n".to_owned().into()).unwrap();
        let sites = [site("code/a.dm", 2), site("code/a.dm", 0), site("code/a.dm", 90)];
        let evidence = file.report_source_text(&sites, 4096).unwrap();
        for (s, text) in sites.iter().zip(&evidence) {
            assert_eq!(*text, file.tree.site_text(&s.rel, s.line as usize));
        }
        assert_eq!(evidence[0], "sleep(1) // retained é");
        let changed = File::capture(&root, &root.join("code/a.dm"),
            "/proc/p()\n sleep(99) // newer bytes\n".to_owned().into()).unwrap();
        assert_ne!(changed.report_source_text(&sites, 4096).unwrap()[0], evidence[0]);
        assert_eq!(file.report_source_text(&sites, 4096).unwrap(), evidence);
    }
    #[test]
    fn report_evidence_budget_rejects_repeated_long_lines_and_foreign_paths_before_result() {
        let root = std::env::current_dir().unwrap().join("report-evidence-fixture");
        let source = format!("/proc/p()\n    sleep(1) // {}\n", "x".repeat(1024));
        let file = File::capture(&root, &root.join("code/a.dm"), source.into()).unwrap();
        let sites = [site("code/a.dm", 2), site("code/a.dm", 2)];
        assert!(file.report_source_text(&sites, 1500).is_err());
        assert_eq!(file.report_source_text(&sites, 4096).unwrap().len(), 2);
        assert!(file.report_source_text(&[site("code/foreign.dm", 2)], 4096).is_err());
    }
    #[test]
    fn report_evidence_changes_result_hash_and_owns_all_normalized_string_capacities() {
        let root = std::env::current_dir().unwrap().join("report-evidence-fixture");
        let config = Config::capture(Configuration::ProvenMissing).unwrap();
        let scope = config.scope("scheduler").unwrap();
        let scan = |comment: &str| File::capture(&root, &root.join("code/a.dm"),
            format!("/proc/p()\n    sleep(1) // {comment}\n").into()).unwrap().scan(&scope).unwrap();
        let a = scan("first comment"); let b = scan("second comment");
        assert_eq!(a.run.sites.len(), 1);
        assert_eq!(Findings::fingerprint_parts(&a.name,&a.run,&a.allow_used),
                   Findings::fingerprint_parts(&b.name,&b.run,&b.allow_used));
        assert_ne!(a.fingerprint(), b.fingerprint());
        assert_eq!(a.site_text(0), Some("sleep(1) // first comment"));
        assert_eq!(a.site_text(1), None);
        assert_eq!(a.budget_charge() - Findings::budget_charge_parts(&a.name,&a.run,&a.allow_used),
            a.source_text.capacity()*std::mem::size_of::<String>() + a.source_text.iter().map(String::capacity).sum::<usize>());
    }
}

/// One host-funded, operation-local code loan. The host already authenticated
/// raw bytes and normalized them before calling; no source receipt is minted.
#[cfg(feature="native-policy")]
pub fn with_original_policy_file(root:&Path,path:&Path,text:dm_preprocess::SourceText,live_page_bytes:usize,budget:&Arc<crate::captured_generator_budget::Budget>,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,crate::reactive_reads_native::Failure>)->Result<bool,crate::reactive_reads_native::Failure>{with_original_policy_file_prepared(root,path,live_page_bytes,budget,|_|Ok(text),visit)}
/// Prepare original DATA inside this SAME file scratch. The producer must
/// preadmit its real normalization before allocating; no source role is minted.
#[cfg(feature="native-policy")]
pub fn with_original_policy_file_prepared(root:&Path,path:&Path,live_page_bytes:usize,budget:&Arc<crate::captured_generator_budget::Budget>,prepare:impl FnOnce(&crate::captured_generator_budget::Budget)->Result<dm_preprocess::SourceText,crate::reactive_reads_native::Failure>,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,crate::reactive_reads_native::Failure>)->Result<bool,crate::reactive_reads_native::Failure>{with_original_policy_file_prepared_demand(root,path,live_page_bytes,budget,false,prepare,visit)}
#[cfg(feature="native-policy")]
fn with_original_policy_file_prepared_demand(root:&Path,path:&Path,live_page_bytes:usize,budget:&Arc<crate::captured_generator_budget::Budget>,clean_only:bool,prepare:impl FnOnce(&crate::captured_generator_budget::Budget)->Result<dm_preprocess::SourceText,crate::reactive_reads_native::Failure>,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,crate::reactive_reads_native::Failure>)->Result<bool,crate::reactive_reads_native::Failure>{
 use crate::reactive_reads_native::Failure;
 fn refused(budget:&crate::captured_generator_budget::Budget,message:impl Into<String>)->Failure{budget.deny();Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message.into()))}
 let scratch=crate::captured_generator_budget::Budget::scoped_temporaries(budget).map_err(|message|refused(budget,message))?;
 struct Guard<'a>{scratch:&'a crate::captured_generator_budget::Budget,ok:bool}
 impl Drop for Guard<'_>{fn drop(&mut self){if !self.ok{self.scratch.keep_failed_scratch()}}}
 let mut guard=Guard{scratch:&scratch,ok:false};
 let path_peak=root.as_os_str().len().checked_add(path.as_os_str().len()).and_then(|n|n.checked_mul(16)).and_then(|n|n.checked_add(1024)).ok_or_else(||refused(budget,"original code path peak overflow"))?;
 scratch.charge(path_peak).map_err(|message|refused(budget,message))?;
 let relative=dm_preprocess::regions::relative_filesystem_path(path,root).ok_or_else(||Failure::from("original code file escapes captured root"))?;
 let rel=relative.to_string_lossy().replace('\\',"/");
 let text=prepare(&scratch)?;
 let raw_credit=if clean_only{let mut bytes=Some(0usize);visit_source_storage(&text,|_,n|bytes=bytes.and_then(|total|total.checked_add(n)));bytes.ok_or_else(||refused(budget,"original backing accounting overflow"))?}else{0};
 let extra=(if clean_only{SourceFile::raw_clean_view_extra_bound(&rel,path,&text)}else{SourceFile::raw_policy_view_extra_bound(&rel,path,&text)})
    .and_then(|n|n.checked_add(std::mem::size_of::<Tree>()+std::mem::size_of::<File>()+std::mem::size_of::<SourceFile>()+256))
    .and_then(|n|n.checked_add(root.as_os_str().len().checked_mul(4)?))
    .ok_or_else(||refused(budget,"original code view peak overflow"))?;
 let reserve=live_page_bytes.checked_add(extra).ok_or_else(||refused(budget,"original code live peak overflow"))?;
 scratch.charge(reserve).map_err(|message|refused(budget,message))?;
 // The local source-view budget includes this file's already-funded backing.
 // All other page originals remain funded by the SAME scratch reservation.
 // The optional clean getter separately charges its exact transform bound to
 // the selecting operation BEFORE construction. Merely granting local capacity
 // here allocates nothing and does not charge raw-only consumers.
 let local=extra.checked_add(live_page_bytes).and_then(|n|n.checked_add(raw_credit)).and_then(|n|n.checked_add(SourceFile::raw_policy_clean_bound(&text)?)).ok_or_else(||refused(budget,"original code local bound overflow"))?;
 let file=File::capture_budgeted(root,path,text,local).map_err(|message|refused(budget,message))?;
 if clean_only{file.tree.files[0].restrict_to_raw_clean();}
 let pending=file.with_policy_views_budget(Some(&scratch),visit);drop(file);
 if matches!(&pending,Err(Failure::Operational(_))){return pending}
 budget.require().map_err(|message|refused(budget,message))?;
 guard.ok=pending.is_ok();pending
}

#[cfg(all(test,feature="native-policy"))]mod required_file_scope_tests{
 use super::*;use crate::{captured_generator_budget::Budget,captured_reactive_reads::Failure};
 #[test]fn prepared_original_file_normalization_is_funded_before_allocation_and_released_after_physical_file(){
  let root=std::env::current_dir().unwrap();let path=root.join("code/required-reader.dm");let budget=Budget::new(4*1024*1024).unwrap();let before=budget.used();let fixed=std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>();
  for page in 0..80{let raw=with_original_policy_file_prepared(&root,&path,0,&budget,|scratch|{scratch.charge(4096).map_err(|message|Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))?;Ok(dm_preprocess::SourceText::from("/datum/probe/proc/reactions()\n    return \"required\"\n"))},&mut|relative,views|{assert_eq!(relative,"code/required-reader.dm");assert!(views.raw()?.contains("required"));Ok(true)}).unwrap();assert!(raw);assert_eq!(budget.used(),before+(page+1)*fixed,"only the known fixed scratch metadata survives each local File");}
  let tiny=Budget::new(fixed).unwrap();let prepared=std::cell::Cell::new(false);let actual=with_original_policy_file_prepared(&root,&path,0,&tiny,|_|{prepared.set(true);Ok(dm_preprocess::SourceText::from(""))},&mut|_,_|panic!("quota must refuse before file loan"));assert!(matches!(actual,Err(Failure::Operational(ref error))if error.kind()==std::io::ErrorKind::OutOfMemory));assert!(!prepared.get());
 }
}

#[cfg(test)]mod whole_file_allow_evidence_tests{
 use super::*;
 #[test]fn captured_allow_digest_uses_original_universal_newlines_and_entire_file_even_without_sites(){
  let root=std::env::current_dir().unwrap().join("whole-file-allow-evidence");
  let config=Config::capture(Configuration::ProvenMissing).unwrap();let scope=config.scope("scheduler").unwrap();
  let text="/proc/p()\r\n    sleep(1) // ALLOW(scheduler): synchronous external operation requires an actual wait\r\n// unrelated é\r\n\r\n";
  // capture() loans an already-normalized AnalyzeRaw view, like the real
  // host. Compare with the original SourceFile constructor rather than passing
  // unnormalized bytes through that host-only precondition.
  let original=SourceFile::from_text("code/probe.dm",text);
  assert!(!original.text().contains('\r'));
  let file=File::capture(&root,&root.join("code/probe.dm"),original.text().to_owned().into()).unwrap();
  let rows=file.scan(&scope).unwrap();assert!(rows.run.sites.is_empty());assert_eq!(rows.allow_used.len(),1);
  assert_eq!(rows.allow_source_digest().copied(),Some([175, 61, 94, 70, 156, 222, 31, 127, 239, 23, 200, 11, 25, 171, 207, 143, 1, 107, 116, 166]));
  let changed_text=SourceFile::from_text("code/probe.dm",&text.replace("unrelated é","new unrelated line"));
  let changed=File::capture(&root,&root.join("code/probe.dm"),changed_text.text().to_owned().into()).unwrap().scan(&scope).unwrap();
  assert_eq!(Findings::fingerprint_parts(&rows.name,&rows.run,&rows.allow_used),Findings::fingerprint_parts(&changed.name,&changed.run,&changed.allow_used));
  assert_ne!(rows.fingerprint(),changed.fingerprint());assert_ne!(rows.allow_source_digest(),changed.allow_source_digest());
  assert!(file.scan_budgeted_checked(&scope,100,1).is_err());assert_eq!(file.scan(&scope).unwrap().allow_source_digest(),rows.allow_source_digest());
 }
}

/// Exact original ALLOW fingerprint; called only inside an actual source loan.
pub(crate) fn source_allow_digest(source:&SourceFile)->[u8;20]{source_allow_digest_text(source.text())}
/// Exact old whole-file annotation digest over an actual borrowed original view.
pub(crate) fn source_allow_digest_text(text:&str)->[u8;20]{use sha1::{Digest,Sha1};Sha1::digest(text.trim_end_matches('\n').as_bytes()).into()}

impl Config{
 /// Full original registry metadata against THIS same captured configuration.
 /// The result is metadata/configuration DATA, never source/execution coverage.
 pub fn validate_complete_registry_scopes<C:crate::key_policy_control::Control>(&self,control:&mut C)->Result<crate::required_scope_registry::CompleteRequiredScopeValidation,C::Error>{crate::required_scope_registry::validate_complete_registry_scopes(&self.scopes,control)}
}

/// The selecting Doc operation funds clean separately; code/marker are denied
/// before any lazy transform. Actual raw owners remain in the input family.
#[cfg(feature="native-policy")]
pub fn with_original_policy_file_clean(root:&Path,path:&Path,text:dm_preprocess::SourceText,live_page_bytes:usize,budget:&Arc<crate::captured_generator_budget::Budget>,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,crate::reactive_reads_native::Failure>)->Result<bool,crate::reactive_reads_native::Failure>{with_original_policy_file_prepared_demand(root,path,live_page_bytes,budget,true,|_|Ok(text),visit)}

#[cfg(all(test,feature="native-policy"))]mod doc_clean_loan_tests{
 use super::*;use crate::{captured_generator_budget::Budget,captured_reactive_reads::Failure};
 #[test]fn clean_only_loan_denies_unfunded_code_and_marker_even_through_original_file_handle(){
  let root=std::env::temp_dir().join("doc-clean-only-negative");let path=root.join("code/a.dm");let text:dm_preprocess::SourceText="/proc/known()\n    return \"value\"\n".into();
  for marker in [false,true]{let budget=Budget::new(1024*1024).unwrap();let error=with_original_policy_file_clean(&root,&path,text.clone(),0,&budget,&mut|_,views|{let file=views.source_file()?;if marker{file.marker();}else{file.code();}Ok(true)}).unwrap_err();assert!(matches!(error,Failure::Operational(e)if e.kind()==std::io::ErrorKind::OutOfMemory),"existing postcallback require must reject, never publish empty transformed text");}
  let budget=Budget::new(1024*1024).unwrap();with_original_policy_file_clean(&root,&path,text.clone(),0,&budget,&mut|_,views|{let clean=views.clean(&budget)?;assert!(clean.contains("/proc/known()"));Ok(true)}).unwrap();let budget=Budget::new(1024*1024).unwrap();with_original_policy_file(&root,&path,text,0,&budget,&mut|_,views|{assert!(views.code()?.text.contains("/proc/known()"));Ok(true)}).unwrap();
 }
 #[test]fn clean_loan_quota_refuses_before_callback_and_does_not_poison_a_later_operation(){let root=std::env::temp_dir().join("doc-clean-quota");let path=root.join("code/a.dm");let text:dm_preprocess::SourceText="/proc/known()\n    return\n".into();let budget=Budget::new(128).unwrap();let entered=std::cell::Cell::new(false);let error=with_original_policy_file_clean(&root,&path,text.clone(),0,&budget,&mut|_,_|{entered.set(true);Ok(true)}).unwrap_err();assert!(matches!(error,Failure::Operational(e)if e.kind()==std::io::ErrorKind::OutOfMemory));assert!(!entered.get());let budget=Budget::new(1024*1024).unwrap();with_original_policy_file_clean(&root,&path,text,0,&budget,&mut|_,views|{assert!(views.clean(&budget)?.contains("known"));Ok(true)}).unwrap();}
}
