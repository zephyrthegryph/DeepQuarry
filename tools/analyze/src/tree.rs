//! The source tree, loaded once and shared by every lint.
//!
//! * Files are found by one walk per requested root and extension ([`Plan`]), sorted by repo
//!   path (`/`-separated), with a `hidden` flag (any path component starting with `.`) so a lint
//!   ported from `glob.glob` (skips dotfiles) and one ported from `os.walk` (includes them) can
//!   both be matched.
//! * File text is read lazily and at most once. A content hash per file comes from a
//!   `(size, mtime)` shortcut against the on-disk meta cache, so a warm run that changes nothing
//!   reads no file at all.
//! * Text is normalized like Python's `open().read()` (universal newlines, lossy UTF-8), so line
//!   numbers and text match what the old lints saw.
//! * Each file offers three line-indexed [`View`]s: `raw()`, `code()` ([`crate::strip::code_only`])
//!   and `clean()` ([`crate::strip::sanitize`]), computed on first use.

use std::collections::{BTreeSet, HashMap};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};

use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use walkdir::WalkDir;

use crate::strip;
use crate::util;
#[path = "tree_captured_budget.rs"]
mod captured_budget;
pub(crate) use captured_budget::visit_source_storage;

pub type Hash = u128;
/// Namespaced live-allocation keys; these are storage observations, never authority.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub enum PolicyStorageClass {
    Record,
    TextBacking,
    OriginalPayload,
    TransformedPayload,
    FingerprintMemo,
    LineStarts,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub struct PolicyStorageKey(pub PolicyStorageClass, pub usize);

/// Text plus its line index. Lines are 1-based and follow Python's `text.split("\n")`: a text that
/// ends in a newline has a final empty line.
pub struct View {
    pub text: dm_preprocess::SourceText,
    starts: Vec<u32>,
}

impl View {
    pub fn new(text: String) -> View {
        Self::shared(text.into())
    }
    pub fn shared(text: dm_preprocess::SourceText) -> View {
        let mut starts = Vec::with_capacity(text.len() / 32 + 2);
        starts.push(0u32);
        for (i, b) in text.bytes().enumerate() {
            if b == b'\n' {
                starts.push((i + 1) as u32);
            }
        }
        View { text, starts }
    }

    /// Number of lines (`len(text.split("\n"))`).
    pub fn num_lines(&self) -> usize {
        self.starts.len()
    }

    /// 1-based line without its newline; "" when out of range.
    pub fn line(&self, n: usize) -> &str {
        if n == 0 || n > self.starts.len() {
            return "";
        }
        let s = self.starts[n - 1] as usize;
        let e = if n < self.starts.len() {
            self.starts[n] as usize - 1
        } else {
            self.text.len()
        };
        &self.text[s..e]
    }

    /// Every line, in order (`text.split("\n")`).
    pub fn lines(&self) -> impl Iterator<Item = &str> + '_ {
        (1..=self.starts.len()).map(move |n| self.line(n))
    }

    /// `(1-based number, line)` pairs (`enumerate(lines, 1)`).
    pub fn numbered(&self) -> impl Iterator<Item = (usize, &str)> + '_ {
        (1..=self.starts.len()).map(move |n| (n, self.line(n)))
    }

    pub fn lines_vec(&self) -> Vec<&str> {
        self.lines().collect()
    }

    /// 1-based line number containing byte offset `off`.
    pub fn line_of(&self, off: usize) -> usize {
        match self.starts.binary_search(&(off as u32)) {
            Ok(i) => i + 1,
            Err(i) => i,
        }
    }

    /// Byte offset where 1-based line `n` starts.
    pub fn line_start(&self, n: usize) -> usize {
        self.starts[(n.max(1) - 1).min(self.starts.len() - 1)] as usize
    }
}

#[derive(Default)]
struct DerivedViews {
    code: OnceLock<View>,
    clean: OnceLock<View>,
    marker: OnceLock<dm_preprocess::SourceText>,
}
struct Data {
    // Cache-I/O policy only; never native source/capture authority.
    captured_input: bool,
    captured_budget: Option<Arc<captured_budget::Budget>>,
    // Current-capture authority and derived-content reuse have distinct owners.
    raw: View,
    views: Arc<DerivedViews>,
}

pub struct SourceFile {
    /// Repo-relative path, `/`-separated.
    pub rel: String,
    pub abs: PathBuf,
    pub size: u64,
    pub mtime_ns: i128,
    pub hash: Hash,
    /// Cache key mixing the path and the content hash: a moved or edited file is a new key.
    pub fkey: Hash,
    /// Some path component starts with `.`.
    pub hidden: bool,
    data: OnceLock<Data>,
}

/// `blake3(rel ++ content hash)`, the per-file cache key.
pub fn file_key(rel: &str, hash: Hash) -> Hash {
    let mut h = blake3::Hasher::new();
    h.update(rel.as_bytes());
    h.update(&hash.to_le_bytes());
    u128::from_le_bytes(h.finalize().as_bytes()[..16].try_into().unwrap())
}

fn read_text(path: &Path) -> String {
    match std::fs::read(path) {
        Ok(bytes) => util::universal_newlines(String::from_utf8_lossy(&bytes).into_owned()),
        Err(_) => String::new(),
    }
}

impl SourceFile {
    /// Disable old global/disk incremental caches for captured input work.
    /// This observes only a prefilled constructor tag: no lazy read, path probe,
    /// ownership receipt or permission to use this source is issued here.
    pub(crate) fn is_captured_input(&self) -> bool {
        self.data.get().is_some_and(|data| data.captured_input)
    }
    fn data(&self) -> &Data {
        self.data.get_or_init(|| {
            if std::env::var("DQ_ANALYZE_TRACE_LOAD").is_ok() {
                static N: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
                if N.fetch_add(1, std::sync::atomic::Ordering::Relaxed) == 300 {
                    eprintln!(
                        "analyze: 300th lazy file load, from: {}",
                        std::backtrace::Backtrace::force_capture()
                    );
                }
            }
            Data {
                captured_input: false,
                captured_budget: None,
                raw: View::new(read_text(&self.abs)),
                views: Arc::new(DerivedViews::default()),
            }
        })
    }

    /// The file's text as the Python lints saw it (universal newlines).
    pub fn text(&self) -> &str {
        &self.data().raw.text
    }

    pub fn raw(&self) -> &View {
        &self.data().raw
    }

    /// The text, raw (no probe).
    pub fn raw_quiet(&self) -> &View {
        &self.data().raw
    }

    /// Comments and string contents removed (`state_schema_lint.code_only`).
    pub fn code(&self) -> &View {
        let d = self.data();
        d.views.code.get_or_init(|| {
            text_probe();
            if let Some(budget) = &d.captured_budget {
                if !budget.require_general_view(){return captured_budget::empty_view();}
                let Some(permit) =
                    budget.reserve(captured_budget::code_transform_bound(&d.raw.text))
                else {
                    return captured_budget::empty_view();
                };
                let view = match captured_budget::indexed(strip::code_only(&d.raw.text).into()) {
                    Ok(view) => view,
                    Err(error) => {
                        budget.fail(error);
                        return captured_budget::empty_view();
                    }
                };
                permit.complete(|visit| captured_budget::view_storage(&view, visit));
                view
            } else {
                View::new(strip::code_only(&d.raw.text))
            }
        })
    }

    /// Same-length sanitized text (`_dx_dm.sanitize_text`).
    pub fn clean(&self) -> &View {
        let d = self.data();
        d.views.clean.get_or_init(|| {
            if let Some(budget) = &d.captured_budget {
                let Some(permit) = budget.reserve(captured_budget::transform_bound(&d.raw.text, 6))
                else {
                    return captured_budget::empty_view();
                };
                let view = match captured_budget::indexed(strip::sanitize(&d.raw.text).into()) {
                    Ok(view) => view,
                    Err(error) => {
                        budget.fail(error);
                        return captured_budget::empty_view();
                    }
                };
                permit.complete(|visit| captured_budget::view_storage(&view, visit));
                view
            } else {
                View::new(strip::sanitize(&d.raw.text))
            }
        })
    }

    /// Same-length comment-masked marker text, acquired once from captured raw.
    pub(crate) fn marker(&self) -> &dm_preprocess::SourceText {
        let data = self.data();
        data.views.marker.get_or_init(|| {
            if let Some(budget) = &data.captured_budget {
                if !budget.require_general_view(){return String::new().into();}
                let Some(permit) =
                    budget.reserve(captured_budget::marker_transform_bound(&data.raw.text))
                else {
                    return String::new().into();
                };
                let text: dm_preprocess::SourceText =
                    crate::raw_marker_policy::strip_comments_keep_strings(&data.raw.text).into();
                permit.complete(|visit| captured_budget::source_storage(&text, visit));
                text
            } else {
                crate::raw_marker_policy::strip_comments_keep_strings(&data.raw.text).into()
            }
        })
    }

    /// 1-based raw line.
    pub fn line(&self, n: usize) -> &str {
        self.raw().line(n)
    }

    pub fn ext(&self) -> &str {
        self.rel.rsplit_once('.').map(|x| x.1).unwrap_or("")
    }

    /// Host-authenticated AnalyzeRaw text, shared with the native source owner.
    /// The caller supplies canonical paths and the already-normalized view.
    pub(crate) fn from_shared_text(
        rel: &str,
        abs: PathBuf,
        text: dm_preprocess::SourceText,
    ) -> SourceFile {
        let hash = hash_bytes(text.as_bytes());
        let size = text.len() as u64;
        let data = OnceLock::new();
        let _ = data.set(Data {
            captured_input: true,
            captured_budget: None,
            raw: View::shared(text),
            views: Arc::new(DerivedViews::default()),
        });
        SourceFile {
            rel: rel.into(),
            abs,
            size,
            mtime_ns: 0,
            hash,
            fkey: file_key(rel, hash),
            hidden: rel.split('/').any(|component| component.starts_with('.')),
            data,
        }
    }

    /// Capture-only constructor: raw index and every later lazy reserve their
    /// own allocations. Authority is still supplied by the native acquisition.
    pub(crate) fn from_shared_budgeted(
        rel: &str,
        abs: PathBuf,
        text: dm_preprocess::SourceText,
        limit: usize,
    ) -> Result<SourceFile, String> {
        let metadata = std::mem::size_of::<SourceFile>()
            + std::mem::size_of::<Data>()
            + std::mem::size_of::<DerivedViews>()
            + rel.len()
            + abs.capacity();
        let budget = captured_budget::Budget::new(limit, metadata)?;
        budget.remember(|visit| captured_budget::source_storage(&text, visit));
        if let Some(error) = budget.error() {
            return Err(error);
        }
        let lines = text
            .bytes()
            .filter(|b| *b == b'\n')
            .count()
            .checked_add(1)
            .and_then(|n| n.checked_mul(4));
        let permit = budget.reserve(lines).ok_or_else(|| {
            budget
                .error()
                .unwrap_or_else(|| "captured raw index budget unavailable".into())
        })?;
        let size = text.len() as u64;
        let hash = hash_bytes(text.as_bytes());
        let raw = captured_budget::indexed(text)?;
        permit.complete(|visit| captured_budget::view_storage(&raw, visit));
        if let Some(error) = budget.error() {
            return Err(error);
        }
        let data = OnceLock::new();
        let _ = data.set(Data {
            captured_input: true,
            captured_budget: Some(budget),
            raw,
            views: Arc::new(DerivedViews::default()),
        });
        Ok(SourceFile {
            rel: rel.into(),
            abs,
            size,
            mtime_ns: 0,
            hash,
            fkey: file_key(rel, hash),
            hidden: rel.split('/').any(|c| c.starts_with('.')),
            data,
        })
    }
    /// Poll the SAME existing captured-view budget before/after a lazy loan.
    /// This is admission status only; it grants no source/compiled authority.
    pub(crate) fn require_view_budget(&self) -> Result<(), String> {
        self.captured_budget_error().map_or(Ok(()), Err)
    }


    /// Peak for only the existing raw/marker/code views. The source backing
    /// itself is counted by the host's live-original census, not this amount.
    #[cfg(feature="native-policy")]
    pub(crate) fn restrict_to_raw_clean(&self){if let Some(budget)=&self.data().captured_budget{budget.restrict_to_raw_clean()}}
    pub(crate) fn raw_clean_view_extra_bound(rel:&str,abs:&Path,text:&str)->Option<usize>{let lines=text.bytes().filter(|b|*b==b'\n').count().checked_add(1)?;std::mem::size_of::<SourceFile>().checked_add(std::mem::size_of::<Data>())?.checked_add(std::mem::size_of::<DerivedViews>())?.checked_add(captured_budget::OWNER_METADATA)?.checked_add(rel.len())?.checked_add(abs.as_os_str().len().checked_mul(4)?)?.checked_add(lines.checked_mul(4)?)?.checked_add(4096)}
    pub(crate) fn raw_policy_clean_bound(text:&str)->Option<usize>{captured_budget::transform_bound(text,6)}
    pub(crate) fn raw_policy_view_extra_bound(rel:&str,abs:&Path,text:&str)->Option<usize>{
        let lines=text.bytes().filter(|b|*b==b'\n').count().checked_add(1)?;
        std::mem::size_of::<SourceFile>().checked_add(std::mem::size_of::<Data>())?
            .checked_add(std::mem::size_of::<DerivedViews>())?
            .checked_add(captured_budget::OWNER_METADATA)?
            .checked_add(rel.len())?.checked_add(abs.as_os_str().len().checked_mul(4)?)?
            .checked_add(lines.checked_mul(4)?)?
            .checked_add(captured_budget::code_transform_bound(text)?)?
            .checked_add(captured_budget::marker_transform_bound(text)?)
    }
    pub(crate) fn captured_budget_error(&self) -> Option<String> {
        let data = self.data();
        let budget = data.captured_budget.as_ref()?;
        budget.remember(|visit| self.visit_policy_storage(visit));
        budget.error()
    }
    pub(crate) fn captured_budget_charge(&self) -> usize {
        self.data()
            .captured_budget
            .as_ref()
            .map_or(0, |budget| budget.charge())
    }
    /// Rebind an equal-content cache view to this capture's raw SourceText.
    /// This is content reuse only; the private native host must authenticate the
    /// current capture BEFORE calling this method. No hash grants authority.
    pub(crate) fn rebind_captured(
        &self,
        path: &Path,
        text: dm_preprocess::SourceText,
    ) -> Result<SourceFile, String> {
        if self
            .data()
            .captured_budget
            .as_ref()
            .is_some_and(|budget| budget.scoped())
        {
            return Err(
                "a scoped source-view budget cannot be detached by content rebinding".into(),
            );
        }
        if self.abs != path || self.raw().text.as_bytes() != text.as_bytes() {
            return Err("cached source path/content contradicts current capture".into());
        }
        let data = OnceLock::new();
        let _ = data.set(Data {
            captured_input: true,
            captured_budget: self.data().captured_budget.clone(),
            raw: View::shared(text),
            views: Arc::clone(&self.data().views),
        });
        Ok(SourceFile {
            rel: self.rel.clone(),
            abs: self.abs.clone(),
            size: self.size,
            mtime_ns: self.mtime_ns,
            hash: self.hash,
            fkey: self.fkey,
            hidden: self.hidden,
            data,
        })
    }
    /// Report actual retained storage identities/capacities after lazy use.
    /// The native owner deduplicates IDs with the captured-source census. This
    /// is not a heap/RSS measurement and must be paired with preflight limits.
    pub(crate) fn visit_policy_storage(&self, mut visit: impl FnMut(PolicyStorageKey, usize)) {
        use PolicyStorageClass as K;
        let data = self.data();
        visit(
            PolicyStorageKey(K::Record, data as *const Data as usize),
            std::mem::size_of::<Data>(),
        );
        captured_budget::view_storage(&data.raw, &mut visit);
        visit(
            PolicyStorageKey(K::Record, Arc::as_ptr(&data.views) as usize),
            std::mem::size_of::<DerivedViews>().saturating_add(2 * std::mem::size_of::<usize>()),
        );
        if let Some(code) = data.views.code.get() {
            captured_budget::view_storage(code, &mut visit);
        }
        if let Some(clean) = data.views.clean.get() {
            captured_budget::view_storage(clean, &mut visit);
        }
        if let Some(marker) = data.views.marker.get() {
            captured_budget::source_storage(marker, &mut visit);
        }
    }

    /// Builds an in-memory file (tests and fixtures): no disk access.
    pub fn from_text(rel: &str, text: &str) -> SourceFile {
        let text = util::universal_newlines(text.to_string());
        let hash = blake3::hash(text.as_bytes());
        let cell = OnceLock::new();
        let _ = cell.set(Data {
            captured_input: false,
            captured_budget: None,
            raw: View::new(text),
            views: Arc::new(DerivedViews::default()),
        });
        let h = u128::from_le_bytes(hash.as_bytes()[..16].try_into().unwrap());
        SourceFile {
            rel: rel.to_string(),
            abs: PathBuf::from(rel),
            size: 0,
            mtime_ns: 0,
            hash: h,
            fkey: file_key(rel, h),
            hidden: rel.split('/').any(|c| c.starts_with('.')),
            data: cell,
        }
    }
}

/// What to load: for each directory (relative to the repo root), the file extensions wanted.
#[derive(Clone, Debug, Default)]
pub struct Plan {
    pub entries: BTreeSet<(String, String)>,
}

impl Plan {
    pub fn add(&mut self, dir: &str, ext: &str) {
        self.entries.insert((
            dir.trim_end_matches('/').to_string(),
            ext.trim_start_matches('.').to_string(),
        ));
    }
}

/// A lint's file selection.
#[derive(Clone, Copy, Debug)]
pub struct Select {
    /// (directory, extension) pairs; a file is selected when under one directory with its extension.
    pub roots: &'static [(&'static str, &'static str)],
    /// Include dot-files and files under dot-directories (`os.walk`/`rglob`), not just `glob.glob`.
    pub hidden: bool,
}

impl Select {
    pub const fn dm(roots: &'static [(&'static str, &'static str)]) -> Select {
        Select {
            roots,
            hidden: false,
        }
    }

    pub fn matches(&self, f: &SourceFile) -> bool {
        self.matches_parts(&f.rel, f.hidden)
    }
    pub(crate) fn matches_path(&self, rel: &str) -> bool {
        self.matches_parts(rel, rel.split('/').any(|c| c.starts_with('.')))
    }
    fn matches_parts(&self, rel: &str, hidden: bool) -> bool {
        if hidden && !self.hidden {
            return false;
        }
        let ext = rel.rsplit_once('.').map_or("", |(_, ext)| ext);
        self.roots.iter().any(|(dir, e)| {
            *e == ext
                && (dir.is_empty()
                    || (rel.starts_with(dir) && rel.as_bytes().get(dir.len()) == Some(&b'/')))
        })
    }
}

/// `code/**/*.dm` by `glob.glob`.
pub const CODE_DM: Select = Select::dm(&[("code", "dm")]);
/// `code/**/*.dm` and `maps/**/*.dm`.
pub const CODE_MAPS_DM: Select = Select::dm(&[("code", "dm"), ("maps", "dm")]);

#[derive(Serialize, Deserialize, Default, Clone, PartialEq)]
pub struct FileMeta {
    pub size: u64,
    pub mtime_ns: i128,
    pub hash: Hash,
}

/// Runs `f` where rayon calls cannot deadlock against the lint fan-out or against other inits (the
/// latent hazard the README described): on a fresh OS thread, inside a rayon pool of its own. The
/// calling thread blocks in a plain join, so it never steals a lint job while it holds a memo cell
/// or a `OnceLock` init, and the pool holds only this call's own work, so a worker waiting inside
/// `f` can never steal another init's closure (which could need the cell `f` is building).
pub fn run_isolated<T: Send>(f: impl FnOnce() -> T + Send) -> T {
    std::thread::scope(|s| {
        let h = std::thread::Builder::new()
            .stack_size(16 << 20)
            .spawn_scoped(s, || {
                let n = std::thread::available_parallelism()
                    .map(|n| n.get())
                    .unwrap_or(4)
                    .min(16);
                let pool = rayon::ThreadPoolBuilder::new()
                    .num_threads(n)
                    .stack_size(16 << 20)
                    .build()
                    .expect("init pool");
                pool.install(f)
            })
            .expect("spawn init thread");
        match h.join() {
            Ok(v) => v,
            Err(e) => std::panic::resume_unwind(e),
        }
    })
}

fn memo_trace() -> bool {
    static ON: OnceLock<bool> = OnceLock::new();
    *ON.get_or_init(|| std::env::var("DQ_ANALYZE_TRACE").is_ok())
}

/// Debug aid (`DQ_ANALYZE_WATCHDOG=<seconds>`): when set, memo state is tracked and dumped if the run is still going
/// after that long, then the process exits with status 99.
static WATCH: OnceLock<Mutex<HashMap<String, Vec<&'static str>>>> = OnceLock::new();

fn watch_set(key: &str, state: &'static str) {
    if let Some(w) = WATCH.get() {
        let mut g = w.lock().unwrap();
        let e = g.entry(key.to_string()).or_default();
        if state == "done" || state == "initializing" {
            // one waiter fewer
            if let Some(i) = e.iter().position(|s| *s == "waiting") {
                e.remove(i);
            }
        }
        if state == "done" {
            e.retain(|s| *s != "initializing");
        } else if state != "done" {
            e.push(state);
        }
    }
}

/// Starts the watchdog when `DQ_ANALYZE_WATCHDOG` is set.
pub fn start_watchdog() {
    let Some(secs) = std::env::var("DQ_ANALYZE_WATCHDOG")
        .ok()
        .and_then(|s| s.parse::<u64>().ok())
    else {
        return;
    };
    let _ = WATCH.set(Mutex::new(HashMap::new()));
    std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_secs(secs));
        if let Some(w) = WATCH.get() {
            for (k, v) in w.lock().unwrap().iter() {
                if !v.is_empty() {
                    eprintln!("watchdog: memo {:?}: {:?}", k, v);
                }
            }
        }
        eprintln!("watchdog: still running after {}s", secs);
        std::process::exit(99);
    });
}

pub struct Tree {
    captured_only: bool,
    captured_violation: Mutex<Option<String>>,
    pub root: PathBuf,
    pub files: Vec<SourceFile>,
    index: HashMap<String, usize>,
    extra: Mutex<HashMap<String, Option<std::sync::Arc<String>>>>,
    memo_cells: Mutex<
        HashMap<String, std::sync::Arc<OnceLock<std::sync::Arc<dyn std::any::Any + Send + Sync>>>>,
    >,
    prewarm_once: OnceLock<()>,
    prewarm_dm_once: OnceLock<()>,
    /// `(file key, line)` -> the normalized line text a baseline fingerprint uses, persisted so a
    /// warm run never has to load a file just to compare a baselined site.
    line_cache: Mutex<HashMap<(Hash, u32), String>>,
    line_cache_dirty: std::sync::atomic::AtomicBool,
}

fn mtime_ns(meta: &std::fs::Metadata) -> i128 {
    meta.modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_nanos() as i128)
        .unwrap_or(0)
}

fn hash_bytes(b: &[u8]) -> Hash {
    u128::from_le_bytes(blake3::hash(b).as_bytes()[..16].try_into().unwrap())
}

impl Tree {
    /// Walks the plan's roots and builds the file table. `prior` is the persisted meta cache; a file
    /// whose size and mtime match it keeps its hash without being read. Returns the tree and the
    /// updated meta table (to persist).
    pub fn load(
        root: &Path,
        plan: &Plan,
        prior: &HashMap<String, FileMeta>,
        force_rehash: bool,
    ) -> (Tree, HashMap<String, FileMeta>) {
        // One walk per directory; the extension filter is per (dir, ext) entry.
        let mut by_dir: HashMap<&str, Vec<&str>> = HashMap::new();
        for (dir, ext) in &plan.entries {
            by_dir.entry(dir.as_str()).or_default().push(ext.as_str());
        }
        let dirs: Vec<(&str, Vec<&str>)> = by_dir.into_iter().collect();
        // One job per (root, immediate subdirectory), so a big root like `code/` is walked by many threads.
        // A file directly in a root is its own job's business: the root job lists those and the subdirectories.
        struct Job<'a> {
            base: PathBuf,
            exts: &'a [&'a str],
            shallow: bool,
        }
        let mut jobs: Vec<Job> = Vec::new();
        for (dir, exts) in &dirs {
            let base = if dir.is_empty() {
                root.to_path_buf()
            } else {
                root.join(dir)
            };
            jobs.push(Job {
                base: base.clone(),
                exts,
                shallow: true,
            });
            if let Ok(rd) = std::fs::read_dir(&base) {
                for e in rd.filter_map(|e| e.ok()) {
                    if e.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                        jobs.push(Job {
                            base: e.path(),
                            exts,
                            shallow: false,
                        });
                    }
                }
            }
        }
        let found: Vec<Vec<(String, PathBuf, u64, i128)>> = jobs
            .par_iter()
            .map(|job| {
                let mut out = Vec::new();
                let mut walker = WalkDir::new(&job.base).follow_links(false);
                if job.shallow {
                    walker = walker.max_depth(1);
                }
                for entry in walker.into_iter().filter_map(|e| e.ok()) {
                    if !entry.file_type().is_file() {
                        continue;
                    }
                    let path = entry.path();
                    let Some(ext) = path.extension().and_then(|e| e.to_str()) else {
                        continue;
                    };
                    if !job.exts.contains(&ext) {
                        continue;
                    }
                    let Ok(meta) = entry.metadata() else { continue };
                    out.push((
                        util::rel_slash(path, root),
                        path.to_path_buf(),
                        meta.len(),
                        mtime_ns(&meta),
                    ));
                }
                out
            })
            .collect();
        let mut seen: HashMap<String, (PathBuf, u64, i128)> = HashMap::new();
        for group in found {
            for (rel, abs, size, mt) in group {
                seen.entry(rel).or_insert((abs, size, mt));
            }
        }
        let mut entries: Vec<(String, (PathBuf, u64, i128))> = seen.into_iter().collect();
        entries.sort_by(|a, b| a.0.cmp(&b.0));

        let files: Vec<SourceFile> = entries
            .into_par_iter()
            .map(|(rel, (abs, size, mt))| {
                let hidden = rel.split('/').any(|c| c.starts_with('.'));
                match prior.get(&rel) {
                    Some(m) if !force_rehash && m.size == size && m.mtime_ns == mt => SourceFile {
                        fkey: file_key(&rel, m.hash),
                        rel,
                        abs,
                        size,
                        mtime_ns: mt,
                        hash: m.hash,
                        hidden,
                        data: OnceLock::new(),
                    },
                    _ => {
                        // Changed or new: read it now, hash the bytes, and keep the text.
                        let bytes = std::fs::read(&abs).unwrap_or_default();
                        let hash = hash_bytes(&bytes);
                        let text =
                            util::universal_newlines(String::from_utf8_lossy(&bytes).into_owned());
                        let cell = OnceLock::new();
                        let _ = cell.set(Data {
                            captured_input: false,
                            captured_budget: None,
                            raw: View::new(text),
                            views: Arc::new(DerivedViews::default()),
                        });
                        SourceFile {
                            fkey: file_key(&rel, hash),
                            rel,
                            abs,
                            size,
                            mtime_ns: mt,
                            hash,
                            hidden,
                            data: cell,
                        }
                    }
                }
            })
            .collect();
        let index = files
            .iter()
            .enumerate()
            .map(|(i, f)| (f.rel.clone(), i))
            .collect();
        let meta = files
            .iter()
            .map(|f| {
                (
                    f.rel.clone(),
                    FileMeta {
                        size: f.size,
                        mtime_ns: f.mtime_ns,
                        hash: f.hash,
                    },
                )
            })
            .collect();
        (
            Tree {
                captured_only: false,
                captured_violation: Mutex::new(None),
                root: root.to_path_buf(),
                files,
                index,
                extra: Mutex::new(HashMap::new()),
                memo_cells: Mutex::new(HashMap::new()),
                prewarm_once: OnceLock::new(),
                prewarm_dm_once: OnceLock::new(),
                line_cache: Mutex::new(HashMap::new()),
                line_cache_dirty: std::sync::atomic::AtomicBool::new(false),
            },
            meta,
        )
    }

    /// A tree over in-memory files (tests and fixtures).
    pub fn from_files(files: Vec<SourceFile>) -> Tree {
        let mut files = files;
        files.sort_by(|a, b| a.rel.cmp(&b.rel));
        let index = files
            .iter()
            .enumerate()
            .map(|(i, f)| (f.rel.clone(), i))
            .collect();
        Tree {
            captured_only: false,
            captured_violation: Mutex::new(None),
            root: PathBuf::from("."),
            files,
            index,
            extra: Mutex::new(HashMap::new()),
            memo_cells: Mutex::new(HashMap::new()),
            prewarm_once: OnceLock::new(),
            prewarm_dm_once: OnceLock::new(),
            line_cache: Mutex::new(HashMap::new()),
            line_cache_dirty: std::sync::atomic::AtomicBool::new(false),
        }
    }

    pub(crate) fn from_captured_files(root: PathBuf, files: Vec<SourceFile>) -> Self {
        let mut tree = Self::from_files(files);
        tree.root = root;
        tree.captured_only = true;
        tree
    }
    pub(crate) fn captured_violation(&self) -> Option<String> {
        self.captured_violation
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }
    pub(crate) fn require_legacy_semantics(&self, operation: &str) -> Result<(), String> {
        if !self.captured_only {
            return Ok(());
        }
        let error = format!("captured raw policy forbids {operation}");
        let mut first = self
            .captured_violation
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if first.is_none() {
            *first = Some(error.clone())
        }
        Err(error)
    }

    /// A value built once per run and shared by every lint that asks for the same `key` (a parsed
    /// proc table, a type index, ...). `init` runs under the key's own lock, so concurrent lints
    /// wait for one build instead of racing to do it twice. The value must own its data (it is
    /// `'static`): refer to files by index or path and read them back through the tree.
    ///
    /// `init` runs on its own thread against a private rayon pool ([`run_isolated`]), so it may use
    /// `par_iter` freely: the waiting caller is blocked, not stealing, and the pool only ever holds
    /// the work of inits (never a lint job that needs the cell being built).
    pub fn memo<T: std::any::Any + Send + Sync>(
        &self,
        key: &str,
        init: impl FnOnce() -> T + Send,
    ) -> std::sync::Arc<T> {
        if let Err(error) = self.require_legacy_semantics("semantic/index memoization") {
            std::panic::panic_any(error)
        }
        // Per-key once-cell, so building one value never blocks lookups of another.
        let cell: std::sync::Arc<OnceLock<std::sync::Arc<dyn std::any::Any + Send + Sync>>> = {
            let mut g = self.memo_cells.lock().unwrap();
            g.entry(key.to_string()).or_default().clone()
        };
        let tracing = WATCH.get().is_some();
        if tracing {
            watch_set(key, "waiting");
        }
        let any = cell
            .get_or_init(|| {
                if tracing {
                    watch_set(key, "initializing");
                }
                let t0 = std::time::Instant::now();
                let v = std::sync::Arc::new(run_isolated(init))
                    as std::sync::Arc<dyn std::any::Any + Send + Sync>;
                if memo_trace() && t0.elapsed().as_millis() >= 5 {
                    eprintln!(
                        "analyze: memo {:?} built in {:.0?} (cpu {} ms)",
                        if key.len() > 40 { &key[..40] } else { key },
                        t0.elapsed(),
                        crate::util::cpu_ms()
                    );
                }
                v
            })
            .clone();
        if tracing {
            watch_set(key, "done");
        }
        any.downcast::<T>()
            .expect("memo key reused with a different type")
    }

    /// Reads every file and builds its code/clean views in parallel, once. A whole-tree lint walks
    /// the files sequentially; without this its first touch of each file would load, strip and
    /// sanitize it on that one thread (seconds), while every other lint waited on the same cells.
    pub fn prewarm(&self) {
        self.prewarm_once.get_or_init(|| {
            run_isolated(|| {
                self.files.par_iter().for_each(|f| {
                    let _ = f.raw();
                    let _ = f.code();
                    let _ = f.clean();
                })
            })
        });
    }

    /// Reads every `.dm` file and builds its code view in parallel, once: the generators scan the whole tree several times, and
    /// the first touch of a file would otherwise read and strip it on that one thread. (`prewarm` also builds the sanitized
    /// views and covers every extension, which the generators do not need.)
    pub fn prewarm_dm(&self) {
        self.prewarm_dm_once.get_or_init(|| {
            run_isolated(|| {
                self.files
                    .par_iter()
                    .filter(|f| f.rel.ends_with(".dm"))
                    .for_each(|f| {
                        let _ = f.raw();
                        let _ = f.code();
                    })
            })
        });
    }

    /// Loads the persisted line texts (entries of files that no longer exist or changed are simply never asked for).
    pub fn load_line_cache(&self, path: &Path, stamp: &str) {
        let Ok(bytes) = std::fs::read(path) else {
            return;
        };
        let Ok((st, map)) = crate::incr::de::<(String, Vec<((Hash, u32), String)>)>(&bytes) else {
            return;
        };
        if st == stamp {
            *self.line_cache.lock().unwrap() = map.into_iter().collect();
        }
    }

    /// Persists the line texts of the files this tree holds when any was added.
    pub fn save_line_cache(&self, path: &Path, stamp: &str) {
        if !self
            .line_cache_dirty
            .swap(false, std::sync::atomic::Ordering::Relaxed)
        {
            return;
        }
        let live: std::collections::HashSet<Hash> = self.files.iter().map(|f| f.fkey).collect();
        let g = self.line_cache.lock().unwrap();
        let mut rows: Vec<((Hash, u32), String)> = g
            .iter()
            .filter(|(k, _)| live.contains(&k.0))
            .map(|(k, v)| (*k, v.clone()))
            .collect();
        rows.sort();
        if let Ok(bytes) = crate::incr::ser(&(stamp.to_string(), rows)) {
            if let Some(dir) = path.parent() {
                let _ = std::fs::create_dir_all(dir);
            }
            let tmp = path.with_extension(format!("tmp{}", std::process::id()));
            if std::fs::write(&tmp, &bytes).is_ok() {
                let _ = std::fs::rename(&tmp, path);
            }
        }
    }

    /// How many files were read at load time (new or changed since the last run): the cue for
    /// whether reading the whole tree up front is worth it.
    pub fn fresh_count(&self) -> usize {
        self.files.iter().filter(|f| f.data.get().is_some()).count()
    }

    pub fn get(&self, rel: &str) -> Option<&SourceFile> {
        self.index.get(rel).map(|&i| &self.files[i])
    }

    /// Files a lint selected, sorted by path.
    pub fn select<'a>(&'a self, sel: &Select) -> Vec<&'a SourceFile> {
        self.files.iter().filter(|f| sel.matches(f)).collect()
    }

    /// Reads any repo file by relative path (not necessarily in the plan); cached. None if absent.
    pub fn read_extra(&self, rel: &str) -> Option<std::sync::Arc<String>> {
        if self
            .require_legacy_semantics("uncaptured read_extra access")
            .is_err()
        {
            return None;
        }
        if let Some(f) = self.get(rel) {
            return Some(std::sync::Arc::new(f.text().to_string()));
        }
        let mut g = self.extra.lock().unwrap();
        if let Some(v) = g.get(rel) {
            return v.clone();
        }
        let p = self.root.join(rel);
        let v = std::fs::read(&p).ok().map(|b| {
            std::sync::Arc::new(util::universal_newlines(
                String::from_utf8_lossy(&b).into_owned(),
            ))
        });
        g.insert(rel.to_string(), v.clone());
        v
    }

    /// Whitespace-normalized text of 1-based line `n` of repo file `rel` (the baseline fingerprint
    /// text, `allow_annotations.site_text`).
    pub fn site_text(&self, rel: &str, n: usize) -> String {
        if let Some(f) = self.get(rel) {
            let key = (f.fkey, n as u32);
            if let Some(t) = self.line_cache.lock().unwrap().get(&key) {
                return t.clone();
            }
            let raw = f.raw();
            let t = if n >= 1 && n <= raw.num_lines() {
                util::normalize_ws(raw.line(n))
            } else {
                String::new()
            };
            self.line_cache.lock().unwrap().insert(key, t.clone());
            self.line_cache_dirty
                .store(true, std::sync::atomic::Ordering::Relaxed);
            return t;
        }
        match self.read_extra(rel) {
            Some(t) => {
                let lines: Vec<&str> = t.split('\n').collect();
                if n >= 1 && n <= lines.len() {
                    util::normalize_ws(lines[n - 1])
                } else {
                    String::new()
                }
            }
            None => String::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn view_lines_follow_python_split() {
        let v = View::new("a\nb\n".to_string());
        assert_eq!(v.num_lines(), 3);
        assert_eq!(v.line(1), "a");
        assert_eq!(v.line(2), "b");
        assert_eq!(v.line(3), "");
        assert_eq!(v.line(4), "");
        assert_eq!(v.line_of(2), 2);
    }

    #[test]
    fn select_respects_hidden_and_roots() {
        let a = SourceFile::from_text("code/x/a.dm", "");
        let b = SourceFile::from_text("code/x/.b.dm", "");
        let c = SourceFile::from_text("maps/m.dm", "");
        assert!(CODE_DM.matches(&a));
        assert!(!CODE_DM.matches(&b));
        assert!(!CODE_DM.matches(&c));
        assert!(Select {
            roots: &[("code", "dm")],
            hidden: true
        }
        .matches(&b));
        assert!(CODE_MAPS_DM.matches(&c));
    }
}

/// `DQ_TEXT_PROBE=1`: who strips files (counts by the first analyzer frame outside the tree), printed at exit.
pub fn text_probe() {
    static ON: OnceLock<bool> = OnceLock::new();
    if !*ON.get_or_init(|| std::env::var_os("DQ_TEXT_PROBE").is_some()) {
        return;
    }
    let bt = std::backtrace::Backtrace::force_capture().to_string();
    let frame = bt
        .lines()
        .map(|l| l.trim())
        .filter(|l| l.contains("dq_analyze::") && !l.contains("dq_analyze::tree::"))
        .take(4)
        .collect::<Vec<_>>()
        .join(" <- ");
    let mut g = TEXT_PROBE.lock().unwrap();
    *g.entry(frame).or_default() += 1;
}

pub static TEXT_PROBE: std::sync::Mutex<std::collections::BTreeMap<String, usize>> =
    std::sync::Mutex::new(std::collections::BTreeMap::new());

#[cfg(test)]
mod captured_owner_reuse_tests {
    use super::*;
    #[test]
    fn current_raw_authority_is_distinct_from_derived_content_reuse() {
        let path = PathBuf::from("captured-source.dm");
        let old = SourceFile::from_shared_text(
            "captured-source.dm",
            path.clone(),
            "/obj/foo // note\n".to_string().into(),
        );
        let current: dm_preprocess::SourceText = "/obj/foo // note\n".to_string().into();
        assert!(!old.raw().text.same_view(&current));
        let rebound = old.rebind_captured(&path, current.clone()).unwrap();
        assert!(rebound.raw().text.same_view(&current));
        assert!(Arc::ptr_eq(&old.data().views, &rebound.data().views));
        assert!(old.data().views.code.get().is_none());
        assert!(std::ptr::eq(old.code(), rebound.code()));
        assert!(std::ptr::eq(old.clean(), rebound.clean()));
        assert!(old.marker().same_view(rebound.marker()));
    }
    #[test]
    fn contradictory_path_or_content_never_reuses_cached_projections() {
        let path = PathBuf::from("a.dm");
        let old = SourceFile::from_shared_text("a.dm", path.clone(), "/obj/a".to_string().into());
        assert!(old
            .rebind_captured(Path::new("b.dm"), old.raw().text.clone())
            .is_err());
        assert!(old
            .rebind_captured(&path, "/obj/b".to_string().into())
            .is_err());
    }
    #[test]
    fn lazy_projection_storage_enters_census_once_by_identity() {
        let path = PathBuf::from("a.dm");
        let old = SourceFile::from_shared_text(
            "a.dm",
            path.clone(),
            "/obj/a // comment\n".to_string().into(),
        );
        let rebound = old.rebind_captured(&path, old.raw().text.clone()).unwrap();
        let census = |source: &SourceFile| {
            let mut rows = std::collections::BTreeMap::new();
            source.visit_policy_storage(|id, bytes| {
                rows.insert(id, bytes);
            });
            rows
        };
        let before = census(&old);
        old.code();
        old.clean();
        old.marker();
        let after = census(&old);
        assert!(after.values().sum::<usize>() > before.values().sum::<usize>());
        let alias = census(&rebound);
        let shared = after.keys().filter(|id| alias.contains_key(id)).count();
        assert!(
            shared >= 4,
            "derived projections and raw backing must deduplicate"
        );
    }
}

#[cfg(test)]
mod policy_storage_alias_tests {
    use super::*;
    fn observe(file: &SourceFile, into: &mut std::collections::BTreeMap<PolicyStorageKey, usize>) {
        file.visit_policy_storage(|key, bytes| {
            into.entry(key)
                .and_modify(|old| *old = (*old).max(bytes))
                .or_insert(bytes);
        });
    }
    #[test]
    fn distinct_backings_share_original_payload_but_not_memo_or_header() {
        let payload: Arc<str> = Arc::from("/obj/alias // retained shared original payload\n");
        let a = SourceFile::from_shared_text("a.dm", PathBuf::from("a.dm"), payload.clone().into());
        let b = SourceFile::from_shared_text("b.dm", PathBuf::from("b.dm"), payload.clone().into());
        assert!(!a.raw().text.same_view(&b.raw().text));
        a.raw().text.span_fingerprint(0..1);
        b.raw().text.span_fingerprint(0..2);
        let mut rows = std::collections::BTreeMap::new();
        observe(&a, &mut rows);
        observe(&b, &mut rows);
        let count = |class| rows.keys().filter(|key| key.0 == class).count();
        assert_eq!(count(PolicyStorageClass::OriginalPayload), 1);
        assert_eq!(count(PolicyStorageClass::TextBacking), 2);
        assert_eq!(count(PolicyStorageClass::FingerprintMemo), 2);
        assert_eq!(
            rows[&PolicyStorageKey(
                PolicyStorageClass::OriginalPayload,
                payload.as_ptr() as usize
            )],
            payload.len() + 2 * std::mem::size_of::<usize>()
        );
    }
    #[test]
    fn memo_growth_reuses_stable_backing_key_without_counting_retired_buffer() {
        let file = SourceFile::from_shared_text(
            "a.dm",
            PathBuf::from("a.dm"),
            "abcdefghijklmnopqrstuvwxyz".to_string().into(),
        );
        file.raw().text.span_fingerprint(0..1);
        let mut rows = std::collections::BTreeMap::new();
        observe(&file, &mut rows);
        let key = *rows
            .keys()
            .find(|key| key.0 == PolicyStorageClass::FingerprintMemo)
            .unwrap();
        let before = rows[&key];
        for end in 2..=26 {
            file.raw().text.span_fingerprint(0..end);
        }
        observe(&file, &mut rows);
        assert_eq!(
            rows.keys()
                .filter(|key| key.0 == PolicyStorageClass::FingerprintMemo)
                .count(),
            1
        );
        assert!(rows[&key] > before);
        file.raw()
            .text
            .visit_fingerprint_storage(|_, _, capacity| assert_eq!(rows[&key], capacity));
    }
}

#[cfg(test)]
mod captured_input_tag_tests {
    use super::*;
    #[test]
    fn captured_cache_policy_tag_never_loads_source_or_grants_identity() {
        let ordinary=SourceFile{rel:"code/unread.dm".into(),abs:PathBuf::from("unread-only-tag-control.dm"),
            size:0,mtime_ns:0,hash:0,fkey:0,hidden:false,data:OnceLock::new()};
        assert!(!ordinary.is_captured_input());
        assert!(ordinary.data.get().is_none(),"predicate cannot trigger disk/lazy data access");
        let path=PathBuf::from("shared-tag.dm");
        let captured=SourceFile::from_shared_text("code/shared-tag.dm",path.clone(),"/datum/a\n".into());
        assert!(captured.is_captured_input());
        let rebound=captured.rebind_captured(&path,"/datum/a\n".into()).unwrap();
        assert!(rebound.is_captured_input());
        assert!(!SourceFile::from_text("code/ordinary-memory.dm","/datum/a\n").is_captured_input(),
            "ordinary fixture/cache behavior is unchanged; populated data alone is not the tag");
    }
}
