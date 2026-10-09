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
use std::sync::{Mutex, OnceLock};

use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use walkdir::WalkDir;

use crate::strip;
use crate::util;

pub type Hash = u128;

/// Text plus its line index. Lines are 1-based and follow Python's `text.split("\n")`: a text that
/// ends in a newline has a final empty line.
pub struct View {
    pub text: String,
    starts: Vec<u32>,
}

impl View {
    pub fn new(text: String) -> View {
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
        let e = if n < self.starts.len() { self.starts[n] as usize - 1 } else { self.text.len() };
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

struct Data {
    raw: View,
    code: OnceLock<View>,
    clean: OnceLock<View>,
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
    fn data(&self) -> &Data {
        self.data.get_or_init(|| {
            if std::env::var("DQ_ANALYZE_TRACE_LOAD").is_ok() {
                static N: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
                if N.fetch_add(1, std::sync::atomic::Ordering::Relaxed) == 300 {
                    eprintln!("analyze: 300th lazy file load, from: {}", std::backtrace::Backtrace::force_capture());
                }
            }
            Data { raw: View::new(read_text(&self.abs)), code: OnceLock::new(), clean: OnceLock::new() }
        })
    }

    /// The file's text as the Python lints saw it (universal newlines).
    pub fn text(&self) -> &str {
        &self.data().raw.text
    }

    pub fn raw(&self) -> &View {
        &self.data().raw
    }

    /// Comments and string contents removed (`state_schema_lint.code_only`).
    pub fn code(&self) -> &View {
        let d = self.data();
        d.code.get_or_init(|| View::new(strip::code_only(&d.raw.text)))
    }

    /// Same-length sanitized text (`_dx_dm.sanitize_text`).
    pub fn clean(&self) -> &View {
        let d = self.data();
        d.clean.get_or_init(|| View::new(strip::sanitize(&d.raw.text)))
    }

    /// 1-based raw line.
    pub fn line(&self, n: usize) -> &str {
        self.raw().line(n)
    }

    pub fn ext(&self) -> &str {
        self.rel.rsplit_once('.').map(|x| x.1).unwrap_or("")
    }

    /// Builds an in-memory file (tests and fixtures): no disk access.
    pub fn from_text(rel: &str, text: &str) -> SourceFile {
        let text = util::universal_newlines(text.to_string());
        let hash = blake3::hash(text.as_bytes());
        let cell = OnceLock::new();
        let _ = cell.set(Data { raw: View::new(text), code: OnceLock::new(), clean: OnceLock::new() });
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
        self.entries.insert((dir.trim_end_matches('/').to_string(), ext.trim_start_matches('.').to_string()));
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
        Select { roots, hidden: false }
    }

    pub fn matches(&self, f: &SourceFile) -> bool {
        if f.hidden && !self.hidden {
            return false;
        }
        let ext = f.ext();
        self.roots.iter().any(|(dir, e)| *e == ext && (dir.is_empty() || (f.rel.starts_with(dir) && f.rel.as_bytes().get(dir.len()) == Some(&b'/'))))
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
                let n = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4).min(16);
                let pool = rayon::ThreadPoolBuilder::new().num_threads(n).stack_size(16 << 20).build().expect("init pool");
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
    let Some(secs) = std::env::var("DQ_ANALYZE_WATCHDOG").ok().and_then(|s| s.parse::<u64>().ok()) else { return };
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
    pub root: PathBuf,
    pub files: Vec<SourceFile>,
    index: HashMap<String, usize>,
    extra: Mutex<HashMap<String, Option<std::sync::Arc<String>>>>,
    memo_cells: Mutex<HashMap<String, std::sync::Arc<OnceLock<std::sync::Arc<dyn std::any::Any + Send + Sync>>>>>,
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
    pub fn load(root: &Path, plan: &Plan, prior: &HashMap<String, FileMeta>, force_rehash: bool) -> (Tree, HashMap<String, FileMeta>) {
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
            let base = if dir.is_empty() { root.to_path_buf() } else { root.join(dir) };
            jobs.push(Job { base: base.clone(), exts, shallow: true });
            if let Ok(rd) = std::fs::read_dir(&base) {
                for e in rd.filter_map(|e| e.ok()) {
                    if e.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                        jobs.push(Job { base: e.path(), exts, shallow: false });
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
                    let Some(ext) = path.extension().and_then(|e| e.to_str()) else { continue };
                    if !job.exts.contains(&ext) {
                        continue;
                    }
                    let Ok(meta) = entry.metadata() else { continue };
                    out.push((util::rel_slash(path, root), path.to_path_buf(), meta.len(), mtime_ns(&meta)));
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
                        let text = util::universal_newlines(String::from_utf8_lossy(&bytes).into_owned());
                        let cell = OnceLock::new();
                        let _ = cell.set(Data { raw: View::new(text), code: OnceLock::new(), clean: OnceLock::new() });
                        SourceFile { fkey: file_key(&rel, hash), rel, abs, size, mtime_ns: mt, hash, hidden, data: cell }
                    }
                }
            })
            .collect();
        let index = files.iter().enumerate().map(|(i, f)| (f.rel.clone(), i)).collect();
        let meta = files.iter().map(|f| (f.rel.clone(), FileMeta { size: f.size, mtime_ns: f.mtime_ns, hash: f.hash })).collect();
        (Tree { root: root.to_path_buf(), files, index, extra: Mutex::new(HashMap::new()), memo_cells: Mutex::new(HashMap::new()), prewarm_once: OnceLock::new(), prewarm_dm_once: OnceLock::new(), line_cache: Mutex::new(HashMap::new()), line_cache_dirty: std::sync::atomic::AtomicBool::new(false) }, meta)
    }

    /// A tree over in-memory files (tests and fixtures).
    pub fn from_files(files: Vec<SourceFile>) -> Tree {
        let mut files = files;
        files.sort_by(|a, b| a.rel.cmp(&b.rel));
        let index = files.iter().enumerate().map(|(i, f)| (f.rel.clone(), i)).collect();
        Tree { root: PathBuf::from("."), files, index, extra: Mutex::new(HashMap::new()), memo_cells: Mutex::new(HashMap::new()), prewarm_once: OnceLock::new(), prewarm_dm_once: OnceLock::new(), line_cache: Mutex::new(HashMap::new()), line_cache_dirty: std::sync::atomic::AtomicBool::new(false) }
    }

    /// A value built once per run and shared by every lint that asks for the same `key` (a parsed
    /// proc table, a type index, ...). `init` runs under the key's own lock, so concurrent lints
    /// wait for one build instead of racing to do it twice. The value must own its data (it is
    /// `'static`): refer to files by index or path and read them back through the tree.
    ///
    /// `init` runs on its own thread against a private rayon pool ([`run_isolated`]), so it may use
    /// `par_iter` freely: the waiting caller is blocked, not stealing, and the pool only ever holds
    /// the work of inits (never a lint job that needs the cell being built).
    pub fn memo<T: std::any::Any + Send + Sync>(&self, key: &str, init: impl FnOnce() -> T + Send) -> std::sync::Arc<T> {
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
                let v = std::sync::Arc::new(run_isolated(init)) as std::sync::Arc<dyn std::any::Any + Send + Sync>;
                if memo_trace() && t0.elapsed().as_millis() >= 5 {
                    eprintln!("analyze: memo {:?} built in {:.0?}", if key.len() > 40 { &key[..40] } else { key }, t0.elapsed());
                }
                v
            })
            .clone();
        if tracing {
            watch_set(key, "done");
        }
        any.downcast::<T>().expect("memo key reused with a different type")
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
                self.files.par_iter().filter(|f| f.rel.ends_with(".dm")).for_each(|f| {
                    let _ = f.raw();
                    let _ = f.code();
                })
            })
        });
    }

    /// Loads the persisted line texts (entries of files that no longer exist or changed are simply never asked for).
    pub fn load_line_cache(&self, path: &Path, stamp: &str) {
        let Ok(bytes) = std::fs::read(path) else { return };
        let Ok((st, map)) = crate::incr::de::<(String, Vec<((Hash, u32), String)>)>(&bytes) else { return };
        if st == stamp {
            *self.line_cache.lock().unwrap() = map.into_iter().collect();
        }
    }

    /// Persists the line texts of the files this tree holds when any was added.
    pub fn save_line_cache(&self, path: &Path, stamp: &str) {
        if !self.line_cache_dirty.swap(false, std::sync::atomic::Ordering::Relaxed) {
            return;
        }
        let live: std::collections::HashSet<Hash> = self.files.iter().map(|f| f.fkey).collect();
        let g = self.line_cache.lock().unwrap();
        let mut rows: Vec<((Hash, u32), String)> = g.iter().filter(|(k, _)| live.contains(&k.0)).map(|(k, v)| (*k, v.clone())).collect();
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
        if let Some(f) = self.get(rel) {
            return Some(std::sync::Arc::new(f.text().to_string()));
        }
        let mut g = self.extra.lock().unwrap();
        if let Some(v) = g.get(rel) {
            return v.clone();
        }
        let p = self.root.join(rel);
        let v = std::fs::read(&p).ok().map(|b| std::sync::Arc::new(util::universal_newlines(String::from_utf8_lossy(&b).into_owned())));
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
            let t = if n >= 1 && n <= raw.num_lines() { util::normalize_ws(raw.line(n)) } else { String::new() };
            self.line_cache.lock().unwrap().insert(key, t.clone());
            self.line_cache_dirty.store(true, std::sync::atomic::Ordering::Relaxed);
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
        assert!(Select { roots: &[("code", "dm")], hidden: true }.matches(&b));
        assert!(CODE_MAPS_DM.matches(&c));
    }
}
