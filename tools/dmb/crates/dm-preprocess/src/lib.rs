//! Ordered DME/DM preprocessing with explicit dependencies and source maps.
//!
//! This is a prototype front end. Unsupported conditional syntax is diagnosed; it is never
//! silently interpreted as false. The source provider makes this usable with Salsa inputs,
//! in-memory fixtures, and the filesystem without hiding reads from the incremental engine.

mod origin_map;
pub use origin_map::{OriginMap, SourceMapBuilder};

use dm_syntax::{lex, lex_spans, visit_tokens, quoted_end, Span, SpanToken, TokenKind};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::borrow::Cow;
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct Diagnostic {
    pub path: PathBuf,
    pub line: usize,
    pub kind: DiagnosticKind,
    pub message: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash, Serialize, Deserialize)]
pub enum DiagnosticKind {
    Io,
    Include,
    Conditional,
    Macro,
    Directive,
    UserError,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct Origin {
    pub output_line: usize,
    pub path: Arc<PathBuf>,
    pub source_line: usize,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Unit {
    pub path: PathBuf,
    pub output_span: Span,
    pub source_lines: usize,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct PreprocessedProject {
    pub text: String,
    pub units: Vec<Unit>,
    /// Exact expanded content identities, in the same order as `units`.
    pub unit_digests: Vec<[u8; 32]>,
    pub origins: Vec<Origin>,
    /// Canonical source map; legacy callers may retain explicit origins.
    pub origin_map: Option<Arc<OriginMap>>,
    pub dependencies: BTreeSet<PathBuf>,
    /// Active DMM includes in source order, after conditional evaluation.
    pub map_includes: Vec<PathBuf>,
    /// Active interface skins; these are assets rather than DM source.
    pub skin_includes: Vec<PathBuf>,
    /// Active FILE_DIR search roots in directive order. BYOND retains each
    /// definition rather than only the last macro value.
    pub file_dirs: Vec<PathBuf>,
    pub diagnostics: Vec<Diagnostic>,
    pub final_macros: BTreeMap<String, Macro>,
}

impl PreprocessedProject {
    pub fn origin_count(&self)->usize { self.origin_map.as_ref().map_or(self.origins.len(),|map|map.len()) }
    pub fn origin_get(&self,index:usize)->Option<Origin> { self.origin_map.as_ref().map_or_else(||self.origins.get(index).cloned(),|map|map.get(index)) }
    pub fn origin_at_line(&self,line:usize)->Option<Origin> {
        self.origin_map.as_ref().map_or_else(|| {
            let index=self.origins.partition_point(|origin|origin.output_line<=line).checked_sub(1)?;
            self.origins.get(index).filter(|origin|origin.output_line==line).cloned()
        },|map|map.at_line(line))
    }
    pub fn origin_iter(&self)->Box<dyn Iterator<Item=Origin>+'_> {
        if let Some(map)=&self.origin_map {Box::new(map.iter())} else {Box::new(self.origins.iter().cloned())}
    }
    pub fn compact_origins(&mut self) {
        if self.origin_map.is_none() {
            self.origin_map=Some(Arc::new(OriginMap::from_origins(std::mem::take(&mut self.origins))));
        }
    }
    pub fn origin_paths(&self)->Box<dyn Iterator<Item=&Arc<PathBuf>>+'_> {
        if let Some(map)=&self.origin_map {Box::new(map.paths())} else {Box::new(self.origins.iter().map(|origin|&origin.path))}
    }
    pub fn origin_resident_bytes(&self)->usize { self.origin_map.as_ref().map_or(self.origins.capacity()*std::mem::size_of::<Origin>(),|map|map.resident_bytes()) }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
enum FileDirChange {
    Push(PathBuf, Macro),
    Pop,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct Macro {
    pub parameters: Option<Vec<String>>,
    pub variadic: bool,
    pub replacement: String,
}

pub trait SourceProvider {
    fn read(&self, path: &Path) -> Result<String, String>;

    /// Immutable source snapshots can share text with preprocessing without a
    /// full file clone for every include occurrence. Existing providers retain
    /// their ordinary read contract through this default adapter.
    fn read_shared(&self, path: &Path) -> Result<Arc<str>, String> {
        self.read(path).map(Arc::from)
    }

    /// Identity of the exact text returned by the preceding read. Snapshot
    /// providers can reuse their recorded digest; ordinary providers hash bytes.
    fn fingerprint_read(&self, _path: &Path, source: &str) -> [u8; 32] {
        Sha256::digest(source.as_bytes()).into()
    }

    /// Exact source-content identity. Providers retaining a verified input snapshot
    /// can return its saved digest without cloning and hashing the entire source.
    fn fingerprint(&self, path: &Path) -> Result<[u8; 32], String> {
        self.read(path)
            .map(|source| Sha256::digest(source.as_bytes()).into())
    }
}

/// DM sources may contain legacy Windows-1252 bytes alongside UTF-8 text.
/// Preserve valid UTF-8 sequences and decode only invalid bytes as legacy text.
pub fn decode_source_bytes(mut bytes: &[u8]) -> String {
    if bytes.starts_with(&[0xef, 0xbb, 0xbf]) {
        bytes = &bytes[3..];
    }
    let mut output = String::new();
    const C1: [char; 32] = [
        '\u{20ac}', '\u{81}', '\u{201a}', '\u{192}', '\u{201e}', '\u{2026}', '\u{2020}',
        '\u{2021}', '\u{2c6}', '\u{2030}', '\u{160}', '\u{2039}', '\u{152}', '\u{8d}', '\u{17d}',
        '\u{8f}', '\u{90}', '\u{2018}', '\u{2019}', '\u{201c}', '\u{201d}', '\u{2022}', '\u{2013}',
        '\u{2014}', '\u{2dc}', '\u{2122}', '\u{161}', '\u{203a}', '\u{153}', '\u{9d}', '\u{17e}',
        '\u{178}',
    ];
    while !bytes.is_empty() {
        match std::str::from_utf8(bytes) {
            Ok(text) => {
                output.push_str(text);
                break;
            }
            Err(error) => {
                let valid = error.valid_up_to();
                output.push_str(std::str::from_utf8(&bytes[..valid]).unwrap());
                let invalid = error.error_len().unwrap_or(bytes.len() - valid);
                for &byte in &bytes[valid..valid + invalid] {
                    output.push(if (0x80..=0x9f).contains(&byte) {
                        C1[(byte - 0x80) as usize]
                    } else {
                        char::from(byte)
                    });
                }
                bytes = &bytes[valid + invalid..];
            }
        }
    }
    output
}

pub fn read_source_file(path: &Path) -> std::io::Result<String> {
    fs::read(path).map(|bytes| decode_source_bytes(&bytes))
}

pub struct FileSystem;
impl SourceProvider for FileSystem {
    fn read(&self, path: &Path) -> Result<String, String> {
        read_source_file(path).map_err(|e| e.to_string())
    }
}

/// Bounded reusable file and include-subtree expansions. Exact source identities
/// and incoming macro dependencies gate replay. Leaf units track only relevant
/// transitive macro names; nested units conservatively checkpoint the whole
/// environment and their exact source closure. Entries retain ordered source
/// origins and macro/FILE_DIR side effects rather than copying full macro maps.
#[derive(Default)]
pub struct PreprocessCache {
    entries: BTreeMap<PathBuf, Vec<CachedUnit>>,
    resident_bytes: usize,
    disk: Option<(PathBuf, BTreeMap<PathBuf, Vec<String>>)>,
    dirty: BTreeSet<PathBuf>,
    pub hits: usize,
    pub misses: usize,
}

struct CachedUnit {
    source_digest: [u8; 32],
    source_len: usize,
    input_digest: [u8; 32],
    macro_dependencies: Option<Vec<String>>,
    dependencies: BTreeMap<PathBuf, [u8; 32]>,
    map_includes: Vec<PathBuf>,
    skin_includes: Vec<PathBuf>,
    manifest_lines: Vec<(String, PathBuf, usize)>,
    output_text: String,
    origins: Vec<DiskOrigin>,
    units: Vec<Unit>,
    unit_digests: Vec<[u8; 32]>,
    diagnostics: Vec<Diagnostic>,
    macro_changes: BTreeMap<String, Option<Macro>>,
    file_dir_changes: Vec<FileDirChange>,
}

const CACHE_FORMAT_VERSION: u32 = 9;
const MAX_CACHED_LEAF_BYTES: usize = 512 * 1024;
const MAX_CACHED_ORIGINS: usize = 8192;
const MAX_CACHED_PATHS: usize = 8192;
// Keep the station's current include closure resident across ordinary edits.
const MAX_CACHE_RESIDENT_BYTES: usize = 160 * 1024 * 1024;
const MAX_CACHE_FILE_BYTES: u64 = 128 * 1024 * 1024;

fn macro_hash(name: &str, definition: &Macro) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(b"dm-preprocess macro state v2\0");
    hasher.update((name.len() as u64).to_le_bytes());
    hasher.update(name.as_bytes());
    hasher.update([u8::from(definition.parameters.is_some())]);
    if let Some(parameters) = &definition.parameters {
        hasher.update((parameters.len() as u64).to_le_bytes());
        for parameter in parameters {
            hasher.update((parameter.len() as u64).to_le_bytes());
            hasher.update(parameter.as_bytes());
        }
    }
    hasher.update([u8::from(definition.variadic)]);
    hasher.update((definition.replacement.len() as u64).to_le_bytes());
    hasher.update(definition.replacement.as_bytes());
    hasher.finalize().into()
}

fn xor_digest(state: &mut [u8; 32], entry: [u8; 32]) {
    for (byte, change) in state.iter_mut().zip(entry) {
        *byte ^= change;
    }
}
static CACHE_TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(0);

// Parser/preprocessor fixes must invalidate saved expansions as well as source edits.
fn cache_compiler_fingerprint() -> String {
    static FINGERPRINT: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    FINGERPRINT
        .get_or_init(|| {
            let mut hash = Sha256::new();
            hash.update(include_str!("lib.rs"));
            hash.update(include_str!("../../dm-syntax/src/lib.rs"));
            format!("{:x}", hash.finalize())
        })
        .clone()
}

#[derive(Serialize, Deserialize)]
struct CacheFile {
    version: u32,
    #[serde(default)]
    compiler_fingerprint: String,
    entries: BTreeMap<PathBuf, Vec<DiskEntry>>,
}

#[derive(Serialize, Deserialize)]
struct DiskEntry {
    source_digest: [u8; 32],
    source_len: usize,
    input_digest: [u8; 32],
    macro_dependencies: Option<Vec<String>>,
    dependencies: BTreeMap<PathBuf, [u8; 32]>,
    map_includes: Vec<PathBuf>,
    skin_includes: Vec<PathBuf>,
    manifest_lines: Vec<(String, PathBuf, usize)>,
    output_text: String,
    origins: Vec<DiskOrigin>,
    units: Vec<DiskUnit>,
    unit_digests: Vec<[u8; 32]>,
    diagnostics: Vec<Diagnostic>,
    macro_changes: BTreeMap<String, Option<Macro>>,
    file_dir_changes: Vec<FileDirChange>,
}

/// A cached leaf has exactly one source path: the cache key. Repeatedly
/// serializing it for every expanded line made the disk cache much larger
/// than its bounded resident size. The current path is restored on replay.
#[derive(Clone, Serialize, Deserialize)]
struct DiskOrigin(usize, usize, Option<PathBuf>);

#[derive(Serialize, Deserialize)]
struct DiskUnit {
    path: PathBuf,
    start: usize,
    end: usize,
    source_lines: usize,
}

impl From<&CachedUnit> for DiskEntry {
    fn from(entry: &CachedUnit) -> Self {
        Self {
            source_digest: entry.source_digest,
            source_len: entry.source_len,
            input_digest: entry.input_digest,
            macro_dependencies: entry.macro_dependencies.clone(),
            dependencies: entry.dependencies.clone(),
            map_includes: entry.map_includes.clone(),
            skin_includes: entry.skin_includes.clone(),
            manifest_lines: entry.manifest_lines.clone(),
            output_text: entry.output_text.clone(),
            origins: entry.origins.clone(),
            unit_digests: entry.unit_digests.clone(),
            units: entry
                .units
                .iter()
                .map(|unit| DiskUnit {
                    path: unit.path.clone(),
                    start: unit.output_span.start,
                    end: unit.output_span.end,
                    source_lines: unit.source_lines,
                })
                .collect(),
            diagnostics: entry.diagnostics.clone(),
            macro_changes: entry.macro_changes.clone(),
            file_dir_changes: entry.file_dir_changes.clone(),
        }
    }
}

impl From<DiskEntry> for CachedUnit {
    fn from(entry: DiskEntry) -> Self {
        Self {
            source_digest: entry.source_digest,
            source_len: entry.source_len,
            input_digest: entry.input_digest,
            macro_dependencies: entry.macro_dependencies,
            dependencies: entry.dependencies,
            map_includes: entry.map_includes,
            skin_includes: entry.skin_includes,
            manifest_lines: entry.manifest_lines,
            output_text: entry.output_text,
            origins: entry.origins,
            unit_digests: entry.unit_digests,
            units: entry
                .units
                .into_iter()
                .map(|unit| Unit {
                    path: unit.path,
                    output_span: Span::new(unit.start, unit.end),
                    source_lines: unit.source_lines,
                })
                .collect(),
            diagnostics: entry.diagnostics,
            macro_changes: entry.macro_changes,
            file_dir_changes: entry.file_dir_changes,
        }
    }
}

impl CachedUnit {
    fn valid_digests(&self) -> bool {
        self.units.len() == self.unit_digests.len()
            && self
                .units
                .iter()
                .zip(&self.unit_digests)
                .all(|(unit, digest)| {
                    self.output_text
                        .get(unit.output_span.start..unit.output_span.end)
                        .is_some_and(|text| {
                            <[u8; 32]>::from(Sha256::digest(text.as_bytes())) == *digest
                        })
                })
    }

    fn resident_bytes(&self) -> usize {
        let paths = self
            .units
            .iter()
            .map(|unit| unit.path.as_os_str().len())
            .sum::<usize>()
            + self
                .diagnostics
                .iter()
                .map(|diagnostic| diagnostic.path.as_os_str().len())
                .sum::<usize>();
        let changes =
            self.macro_changes
                .iter()
                .map(|(name, definition)| {
                    name.len()
                        + definition.as_ref().map_or(0, |definition| {
                            definition.replacement.len()
                                + definition.parameters.as_ref().map_or(0, |parameters| {
                                    parameters.iter().map(String::len).sum()
                                })
                        })
                        + 128
                })
                .sum::<usize>();
        self.dependencies
            .iter()
            .map(|(path, _)| path.as_os_str().len() + 96)
            .sum::<usize>()
            + self
                .map_includes
                .iter()
                .chain(&self.skin_includes)
                .map(|path| path.as_os_str().len() + 32)
                .sum::<usize>()
            + self
                .origins
                .iter()
                .filter_map(|origin| origin.2.as_ref())
                .map(|path| path.as_os_str().len())
                .sum::<usize>()
            + self.macro_dependencies.as_ref().map_or(0, |names| {
                names
                    .iter()
                    .map(|name| name.len() + std::mem::size_of::<String>())
                    .sum::<usize>()
            })
            + self.output_text.len()
            + paths
            + changes
            + self
                .file_dir_changes
                .iter()
                .map(|change| match change {
                    FileDirChange::Push(path, definition) => {
                        path.as_os_str().len() + definition.replacement.len()
                    }
                    FileDirChange::Pop => 1,
                })
                .sum::<usize>()
            + self.origins.len() * std::mem::size_of::<DiskOrigin>()
            + self.units.len() * (std::mem::size_of::<Unit>() + 32)
            + self.diagnostics.len() * std::mem::size_of::<Diagnostic>()
            + self
                .diagnostics
                .iter()
                .map(|diagnostic| diagnostic.message.len())
                .sum::<usize>()
            + std::mem::size_of::<Self>()
    }
}

#[derive(Serialize, Deserialize)]
struct CacheIndex {
    version: u32,
    compiler_fingerprint: String,
    entries: BTreeMap<PathBuf, Vec<String>>,
}

fn write_atomic(path: &Path, bytes: &[u8], durable: bool) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let sequence = CACHE_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    let temp = path.with_extension(format!("tmp-{}-{sequence}", std::process::id()));
    let result = (|| {
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temp)?;
        file.write_all(bytes)?;
        if durable {
            file.sync_all()?;
        }
        drop(file);
        atomic_replace_mode(&temp, path, durable)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result.map_err(|error: std::io::Error| error.to_string())
}

impl PreprocessCache {
    /// Load a small index, then decode expansion chunks only when their files
    /// are visited. Chunks are immutable SHA-256 addressed and shared by worktrees.
    pub fn load_incremental(path: &Path) -> Self {
        let index_path = path.with_extension("index.json");
        let Ok(metadata) = fs::metadata(&index_path) else {
            return Self::load(path);
        };
        if metadata.len() > 4 * 1024 * 1024 {
            return Self::default();
        }
        let Ok(bytes) = fs::read(&index_path) else {
            return Self::default();
        };
        let Ok(index) = serde_json::from_slice::<CacheIndex>(&bytes) else {
            return Self::default();
        };
        if index.version != CACHE_FORMAT_VERSION
            || index.compiler_fingerprint != cache_compiler_fingerprint()
            || index.entries.len() > MAX_CACHED_PATHS
        {
            return Self::default();
        }
        if index.entries.values().any(|keys| {
            keys.len() > 2
                || keys
                    .iter()
                    .any(|key| key.len() != 64 || !key.bytes().all(|byte| byte.is_ascii_hexdigit()))
        }) {
            return Self::default();
        }
        Self {
            disk: Some((path.with_extension("parts"), index.entries)),
            ..Default::default()
        }
    }

    fn load_unit(&mut self, path: &Path) {
        if self.entries.contains_key(path) {
            return;
        }
        let Some((directory, index)) = &self.disk else {
            return;
        };
        let Some(keys) = index.get(path) else {
            return;
        };
        let mut units = Vec::new();
        for key in keys {
            let chunk = directory.join(key);
            if !fs::metadata(&chunk).is_ok_and(|metadata| metadata.len() <= 8 * 1024 * 1024) {
                continue;
            }
            let Ok(bytes) = fs::read(&chunk) else {
                continue;
            };
            if bytes.len() > 8 * 1024 * 1024 || format!("{:x}", Sha256::digest(&bytes)) != *key {
                continue;
            }
            if let Ok(entry) = serde_json::from_slice::<DiskEntry>(&bytes) {
                let unit = CachedUnit::from(entry);
                if unit.output_text.len() <= MAX_CACHED_LEAF_BYTES
                    && unit.origins.len() <= MAX_CACHED_ORIGINS
                    && unit.units.len() <= MAX_CACHED_ORIGINS
                    && unit.dependencies.len() <= MAX_CACHED_PATHS
                    && unit.valid_digests()
                {
                    units.push(unit);
                }
            }
        }
        if !units.is_empty() {
            self.resident_bytes += path.as_os_str().len()
                + units.iter().map(CachedUnit::resident_bytes).sum::<usize>();
            self.entries.insert(path.to_path_buf(), units);
            self.enforce_budget(MAX_CACHE_RESIDENT_BYTES);
        }
    }

    /// Publish only changed file expansion chunks, followed by an atomic small
    /// index. A concurrent worktree can replace the index with its own valid
    /// version; source/environment fingerprints still gate every replay.
    pub fn save_incremental(&mut self, path: &Path) -> Result<(), String> {
        let started=std::time::Instant::now();
        let encoding_ns=AtomicU64::new(0);
        let publication_ns=AtomicU64::new(0);
        let directory = path.with_extension("parts");
        fs::create_dir_all(&directory).map_err(|error| error.to_string())?;
        let mut index = self
            .disk
            .as_ref()
            .map(|(_, index)| index.clone())
            .unwrap_or_default();
        let paths: Vec<_> = if self.disk.is_some() {
            self.dirty.iter().cloned().collect()
        } else {
            self.entries.keys().cloned().collect()
        };
        // Two bounded workers overlap immutable chunk encoding and filesystem
        // publication. Each retains only one serialized expansion at a time;
        // the deterministic index is committed after both workers succeed.
        let entries = &self.entries;
        let publish = |files: &[PathBuf]| -> Result<BTreeMap<PathBuf, Vec<String>>, String> {
            let mut published = BTreeMap::new();
            for file in files {
                let Some(units) = entries.get(file) else {
                    continue;
                };
                let mut keys = Vec::new();
                for entry in units {
                    let encoding_started=std::time::Instant::now();
                    let bytes = serde_json::to_vec(&DiskEntry::from(entry))
                        .map_err(|error| error.to_string())?;
                    encoding_ns.fetch_add(encoding_started.elapsed().as_nanos().min(u64::MAX as u128) as u64, Ordering::Relaxed);
                    if bytes.len() > 8 * 1024 * 1024 {
                        continue;
                    }
                    let publication_started=std::time::Instant::now();
                    let key = format!("{:x}", Sha256::digest(&bytes));
                    let chunk = directory.join(&key);
                    if !fs::read(&chunk).is_ok_and(|old| old == bytes) {
                        write_atomic(&chunk, &bytes, false)?;
                    }
                    publication_ns.fetch_add(publication_started.elapsed().as_nanos().min(u64::MAX as u128) as u64, Ordering::Relaxed);
                    keys.push(key);
                }
                published.insert(file.clone(), keys);
            }
            Ok(published)
        };
        if paths.len() < 32 {
            index.extend(publish(&paths)?);
        } else {
            let (first, second) = paths.split_at(paths.len() / 2);
            let published = std::thread::scope(|scope| {
                let worker = scope.spawn(|| publish(first));
                let second = publish(second);
                let first = worker
                    .join()
                    .map_err(|_| "preprocess chunk publisher panicked".to_owned())?;
                Ok::<_, String>((first?, second?))
            })?;
            index.extend(published.0);
            index.extend(published.1);
        }
        while index.len() > MAX_CACHED_PATHS {
            index.pop_first();
        }
        let bytes = serde_json::to_vec(&CacheIndex {
            version: CACHE_FORMAT_VERSION,
            compiler_fingerprint: cache_compiler_fingerprint(),
            entries: index.clone(),
        })
        .map_err(|error| error.to_string())?;
        write_atomic(&path.with_extension("index.json"), &bytes, true)?;
        self.disk = Some((directory, index));
        self.dirty.clear();
        if std::env::var_os("DM_BUILD_TRACE").is_some() { eprintln!("DM_BUILD_TRACE preprocessing persistence: {} paths, encode workers {:.3}s, hash/read/write workers {:.3}s, wall {:.3}s",paths.len(),encoding_ns.load(Ordering::Relaxed) as f64/1e9,publication_ns.load(Ordering::Relaxed) as f64/1e9,started.elapsed().as_secs_f64()); }
        Ok(())
    }

    pub fn resident_bytes(&self) -> usize {
        self.resident_bytes
    }
    /// Release resident expansions while preserving the disk index for lazy
    /// replay. Coordinators budget this cache together with prepared snapshots.
    pub fn trim_to(&mut self, limit: usize) {
        self.enforce_budget(limit);
    }
    fn enforce_budget(&mut self, limit: usize) {
        // Remove historical variants before evicting another current file.
        if self.resident_bytes > limit {
            for entries in self.entries.values_mut() {
                while entries.len() > 1 && self.resident_bytes > limit {
                    self.resident_bytes -= entries.remove(0).resident_bytes();
                }
            }
        }
        while self.resident_bytes > limit {
            let Some(path) = self.entries.keys().next().cloned() else {
                break;
            };
            let entries = self.entries.get_mut(&path).expect("cache path exists");
            if entries.is_empty() {
                self.entries.remove(&path);
                self.resident_bytes -= path.as_os_str().len();
                continue;
            }
            let removed = entries.remove(0);
            self.resident_bytes -= removed.resident_bytes();
            if entries.is_empty() {
                self.entries.remove(&path);
                self.resident_bytes -= path.as_os_str().len();
            }
        }
    }

    /// Invalid or outdated files are ignored; source and macro keys are checked
    /// again before every replay, even after a successful disk load.
    pub fn load(path: &Path) -> Self {
        if fs::metadata(path).is_ok_and(|metadata| metadata.len() > MAX_CACHE_FILE_BYTES) {
            return Self::default();
        }
        let Ok(bytes) = fs::read(path) else {
            return Self::default();
        };
        if bytes.len() as u64 > MAX_CACHE_FILE_BYTES {
            return Self::default();
        }
        // Saved files have a deterministic envelope. Reject compiler/schema
        // changes before allocating and decoding all cached source bodies.
        // Full JSON validation below remains mandatory for matching envelopes.
        let expected_prefix = format!(
            "{{\"version\":{},\"compiler_fingerprint\":\"{}\",\"entries\":",
            CACHE_FORMAT_VERSION,
            cache_compiler_fingerprint()
        );
        if !bytes.starts_with(expected_prefix.as_bytes()) {
            return Self::default();
        }
        let Ok(file) = serde_json::from_slice::<CacheFile>(&bytes) else {
            return Self::default();
        };
        if file.version != CACHE_FORMAT_VERSION
            || file.compiler_fingerprint != cache_compiler_fingerprint()
        {
            return Self::default();
        }
        let mut cache = Self {
            entries: file
                .entries
                .into_iter()
                .take(MAX_CACHED_PATHS)
                .map(|(path, entries)| {
                    (
                        path,
                        entries
                            .into_iter()
                            .take(2)
                            .map(CachedUnit::from)
                            .filter(CachedUnit::valid_digests)
                            .collect(),
                    )
                })
                .collect(),
            resident_bytes: 0,
            disk: None,
            dirty: BTreeSet::new(),
            hits: 0,
            misses: 0,
        };
        cache.resident_bytes = cache
            .entries
            .iter()
            .map(|(path, entries)| {
                path.as_os_str().len()
                    + entries
                        .iter()
                        .map(CachedUnit::resident_bytes)
                        .sum::<usize>()
            })
            .sum();
        cache.enforce_budget(MAX_CACHE_RESIDENT_BYTES);
        cache
    }

    pub fn save(&self, path: &Path) -> Result<(), String> {
        let file = CacheFile {
            version: CACHE_FORMAT_VERSION,
            compiler_fingerprint: cache_compiler_fingerprint(),
            entries: self
                .entries
                .iter()
                .map(|(path, entries)| {
                    (path.clone(), entries.iter().map(DiskEntry::from).collect())
                })
                .collect(),
        };
        let bytes = serde_json::to_vec(&file).map_err(|error| error.to_string())?;
        if bytes.len() as u64 > MAX_CACHE_FILE_BYTES {
            return Err("preprocess cache exceeds disk size limit".into());
        }
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|error| error.to_string())?;
        }
        let sequence = CACHE_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        let temp = path.with_extension(format!("tmp-{}-{sequence}", std::process::id()));
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temp)
            .map_err(|error| error.to_string())?;
        file.write_all(&bytes)
            .and_then(|()| file.sync_all())
            .map_err(|error| error.to_string())?;
        drop(file);
        let result = atomic_replace(&temp, path);
        if result.is_err() {
            let _ = fs::remove_file(&temp);
        }
        result.map_err(|error| error.to_string())
    }

    pub fn clear(&mut self) {
        self.entries.clear();
        self.disk = None;
        self.dirty.clear();
        self.resident_bytes = 0;
        self.hits = 0;
        self.misses = 0;
    }
}

fn atomic_replace(source: &Path, destination: &Path) -> std::io::Result<()> {
    atomic_replace_mode(source, destination, true)
}

#[cfg(windows)]
fn atomic_replace_mode(source: &Path, destination: &Path, durable: bool) -> std::io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    #[link(name = "Kernel32")]
    unsafe extern "system" {
        fn MoveFileExW(source: *const u16, destination: *const u16, flags: u32) -> i32;
    }
    let source: Vec<u16> = source.as_os_str().encode_wide().chain(Some(0)).collect();
    let destination: Vec<u16> = destination
        .as_os_str()
        .encode_wide()
        .chain(Some(0))
        .collect();
    // Same-directory move with replacement leaves readers seeing either the
    // previous complete file or the new complete file.
    let ok = unsafe {
        MoveFileExW(
            source.as_ptr(),
            destination.as_ptr(),
            0x1 | if durable { 0x8 } else { 0 },
        )
    };
    if ok == 0 {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(())
    }
}

#[cfg(not(windows))]
fn atomic_replace_mode(source: &Path, destination: &Path, _durable: bool) -> std::io::Result<()> {
    fs::rename(source, destination)
}

/// Preprocess a DME root. Each include occurrence is expanded in source order, even when a
/// file was included previously, because macros and declaration overrides are order-sensitive.
pub fn preprocess_project<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
) -> PreprocessedProject {
    preprocess_project_inner(project, provider, defines, None, false).0
}

pub fn preprocess_project_cached<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
    cache: &mut PreprocessCache,
) -> PreprocessedProject {
    preprocess_project_inner(project, provider, defines, Some(cache), false).0
}

/// Production expansion never assembles a project-sized contiguous string.
/// Legacy entry points explicitly materialize text after the same preprocessing.
pub fn preprocess_project_cached_segmented<P: SourceProvider>(
    project: &Path, provider: &P, defines: &BTreeMap<String, String>,
    cache: &mut PreprocessCache,
) -> (PreprocessedProject, Vec<Arc<str>>) {
    preprocess_project_inner(project, provider, defines, Some(cache), true)
}

fn preprocess_project_inner<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
    cache: Option<&mut PreprocessCache>,
    segmented: bool,
) -> (PreprocessedProject, Vec<Arc<str>>) {
    let mut ctx = Context {
        provider,
        cache,
        output: PreprocessedProject::default(),
        expanded: ExpansionWriter::default(),
        stack: Vec::new(),
        output_line: 1,
        macro_digest: [0; 32],
        macro_hashes: BTreeMap::new(),
        file_dir_changes: Vec::new(),
        file_dir_definitions: Vec::new(),
        project_dir: normalize(project.parent().unwrap_or(Path::new("")).to_path_buf()),
        manifest_lines: Vec::new(),
        reads: Vec::new(),
        macro_changes: Vec::new(),
    };
    for (name, replacement) in [
        ("EXCEPTION", "new /exception(message, __FILE__, __LINE__)"),
        ("REGEX_QUOTE", "regex(message, 1)"),
        ("REGEX_QUOTE_REPLACEMENT", "regex(message, 2)"),
    ] {
        ctx.set_macro(
            name.into(),
            Some(Macro {
                parameters: Some(vec!["message".into()]),
                variadic: false,
                replacement: replacement.into(),
            }),
        );
    }
    for (name, replacement) in defines {
        if name == "FILE_DIR" {
            ctx.change_file_dir(FileDirChange::Push(
                PathBuf::from(
                    replacement
                        .trim()
                        .trim_matches(['"', '\''])
                        .replace('\\', "/"),
                ),
                Macro {
                    parameters: None,
                    variadic: false,
                    replacement: replacement.clone(),
                },
            ));
        }
        ctx.set_macro(
            name.clone(),
            Some(Macro {
                parameters: None,
                variadic: false,
                replacement: replacement.clone(),
            }),
        );
    }
    ctx.visit(project.to_path_buf());
    for (text, path, source_line) in std::mem::take(&mut ctx.manifest_lines) {
        ctx.expanded.push_str(&text);
        ctx.expanded.push_str("\n");
        ctx.output.origins.push(Origin {
            output_line: ctx.output_line,
            path,
            source_line,
        });
        ctx.output_line += 1;
    }
    let pieces = ctx.expanded.finish();
    if !segmented {
        ctx.output.text = pieces.iter().map(|piece| piece.as_ref()).collect();
    }
    (ctx.output, pieces)
}

#[derive(Clone, Copy)]
struct Conditional {
    parent_active: bool,
    branch_taken: bool,
    active: bool,
    else_seen: bool,
}

fn macro_defined(name: &str, macros: &BTreeMap<String, Macro>) -> bool {
    matches!(name, "__FILE__" | "__LINE__") || macros.contains_key(name)
}

fn directive_identifier(rest: &str) -> Result<&str, String> {
    let lexed = lex_spans(rest);
    if let Some(diagnostic) = lexed.diagnostics.first() {
        return Err(diagnostic.message.clone());
    }
    let mut identifiers = lexed.tokens.iter().filter(|token| {
        !matches!(
            token.kind,
            TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
        )
    });
    let Some(token) = identifiers.next() else {
        return Err("missing conditional macro name".into());
    };
    if token.kind != TokenKind::Ident || identifiers.next().is_some() {
        return Err("expected one conditional macro name".into());
    }
    Ok(token.text(rest))
}

#[derive(Clone, Copy)]
struct ExpandLocation<'a> {
    file_name: &'a str,
    line: usize,
}

/// Newline-anchored immutable pieces and one bounded unfinished output piece.
#[derive(Default)]
struct ExpansionWriter {
    pieces: Vec<Arc<str>>,
    offsets: Vec<usize>,
    pending: String,
    committed: usize,
}
impl ExpansionWriter {
    fn len(&self) -> usize { self.committed + self.pending.len() }
    fn push_str(&mut self, text: &str) {
        for part in text.split_inclusive('\n') {
            self.pending.push_str(part);
            if part.ends_with('\n') && self.pending.len() >= 64*1024 {
                self.commit();
            }
        }
    }
    fn commit(&mut self) {
        if self.pending.is_empty() { return; }
        let piece: Arc<str> = Arc::from(std::mem::take(&mut self.pending));
        self.offsets.push(self.committed);
        self.committed += piece.len();
        self.pieces.push(piece);
    }
    fn visit_range(&self, start: usize, end: usize, mut visit: impl FnMut(&str)) {
        assert!(start <= end && end <= self.len());
        if start == end { return; }
        let first = self.offsets.partition_point(|offset| *offset <= start).saturating_sub(1);
        for (piece, offset) in self.pieces[first..].iter().zip(&self.offsets[first..]) {
            if *offset >= end { break; }
            let a = start.saturating_sub(*offset);
            let b = (end-*offset).min(piece.len());
            if a < b { visit(&piece[a..b]); }
        }
        if end > self.committed {
            visit(&self.pending[start.saturating_sub(self.committed)..end-self.committed]);
        }
    }
    fn digest(&self, start: usize, end: usize) -> [u8;32] {
        let mut hash = Sha256::new();
        self.visit_range(start,end,|text|hash.update(text.as_bytes()));
        hash.finalize().into()
    }
    fn range(&self, start: usize, end: usize) -> String {
        let mut text = String::with_capacity(end-start);
        self.visit_range(start,end,|part|text.push_str(part));
        text
    }
    fn finish(mut self) -> Vec<Arc<str>> { self.commit(); self.pieces }
}

struct Context<'a, P: SourceProvider> {
    provider: &'a P,
    cache: Option<&'a mut PreprocessCache>,
    output: PreprocessedProject,
    expanded: ExpansionWriter,
    stack: Vec<PathBuf>,
    output_line: usize,
    macro_digest: [u8; 32],
    macro_hashes: BTreeMap<String, [u8; 32]>,
    file_dir_changes: Vec<FileDirChange>,
    file_dir_definitions: Vec<Macro>,
    project_dir: PathBuf,
    manifest_lines: Vec<(String, std::sync::Arc<PathBuf>, usize)>,
    reads: Vec<(PathBuf, [u8; 32])>,
    macro_changes: Vec<(String, Option<Macro>)>,
}

impl<P: SourceProvider> Context<'_, P> {
    fn change_file_dir(&mut self, change: FileDirChange) {
        match &change {
            FileDirChange::Push(path, definition) => {
                self.output.file_dirs.push(path.clone());
                self.file_dir_definitions.push(definition.clone());
            }
            FileDirChange::Pop => {
                self.output.file_dirs.pop();
                self.file_dir_definitions.pop();
            }
        }
        self.file_dir_changes.push(change);
    }

    fn set_macro(&mut self, name: String, definition: Option<Macro>) {
        self.macro_changes.push((name.clone(), definition.clone()));
        self.output.final_macros.remove(&name);
        if let Some(previous) = self.macro_hashes.remove(&name) {
            xor_digest(&mut self.macro_digest, previous);
        }
        if let Some(definition) = definition {
            let hash = macro_hash(&name, &definition);
            xor_digest(&mut self.macro_digest, hash);
            self.macro_hashes.insert(name.clone(), hash);
            self.output.final_macros.insert(name, definition);
        }
    }

    fn error(&mut self, path: &Path, line: usize, message: impl Into<String>) {
        self.error_as(path, line, DiagnosticKind::Directive, message);
    }

    fn error_as(
        &mut self,
        path: &Path,
        line: usize,
        kind: DiagnosticKind,
        message: impl Into<String>,
    ) {
        self.output.diagnostics.push(Diagnostic {
            path: path.to_owned(),
            line,
            kind,
            message: message.into(),
        });
    }

    fn visit(&mut self, path: PathBuf) {
        let path = normalize(path);
        if self.stack.contains(&path) {
            let chain = self
                .stack
                .iter()
                .chain(std::iter::once(&path))
                .map(|p| p.display().to_string())
                .collect::<Vec<_>>()
                .join(" -> ");
            self.error_as(
                &path,
                1,
                DiagnosticKind::Include,
                format!("include cycle: {chain}"),
            );
            return;
        }
        self.output.dependencies.insert(path.clone());
        let source = match self.provider.read_shared(&path) {
            Ok(s) => s,
            Err(e) => {
                self.error_as(
                    &path,
                    1,
                    DiagnosticKind::Io,
                    format!("cannot read source: {e}"),
                );
                return;
            }
        };
        let exact_source_digest = self.provider.fingerprint_read(&path, &source);
        self.reads.push((path.clone(), exact_source_digest));
        let cache_key = path
            .strip_prefix(&self.project_dir)
            .unwrap_or(&path)
            .to_path_buf();
        if let Some(cache) = self.cache.as_deref_mut() {
            cache.load_unit(&cache_key);
        }
        let nested = has_include_directive(&source);
        // Nested units carry exact transitive source fingerprints and all side effects.
        let cacheable = source.len() <= MAX_CACHED_LEAF_BYTES
            && !path
                .extension()
                .is_some_and(|e| e.eq_ignore_ascii_case("dme"))
            && self.cache.as_ref().is_some_and(|cache| {
                cache.entries.contains_key(&cache_key) || cache.entries.len() < MAX_CACHED_PATHS
            });
        // FILE_DIR affects resource resolution and remains an ordered checkpoint.
        let mut directory_hasher = Sha256::new();
        for (directory, definition) in self.output.file_dirs.iter().zip(&self.file_dir_definitions)
        {
            let name = directory.to_string_lossy();
            directory_hasher.update((name.len() as u64).to_le_bytes());
            directory_hasher.update(name.as_bytes());
            directory_hasher.update(macro_hash("FILE_DIR", definition));
        }
        let directory_digest: [u8; 32] = directory_hasher.finalize().into();
        let source_digest: [u8; 32] = if cacheable {
            exact_source_digest
        } else {
            [0; 32]
        };
        if cacheable {
            if let Some(cache) = self.cache.as_deref_mut() {
                if let Some(entry) = cache.entries.get(&cache_key).and_then(|entries| {
                    entries.iter().find(|entry| {
                        entry.source_len == source.len()
                            && entry.source_digest == source_digest
                            && entry.dependencies.iter().all(|(relative, digest)| {
                                let dependency = normalize(self.project_dir.join(relative));
                                !self.stack.contains(&dependency)
                                    && self
                                        .provider
                                        .fingerprint(&dependency)
                                        .is_ok_and(|current| current == *digest)
                            })
                            && entry.input_digest
                                == dependency_digest(
                                    entry.macro_dependencies.as_deref(),
                                    &self.macro_hashes,
                                    self.macro_digest,
                                    directory_digest,
                                )
                    })
                }) {
                    let macro_changes = entry.macro_changes.clone();
                    let file_dir_changes = entry.file_dir_changes.clone();
                    let byte_start = self.expanded.len();
                    let line_start = self.output_line;
                    let origin_path = Arc::new(path.clone());
                    for (relative, digest) in &entry.dependencies {
                        let dependency = normalize(self.project_dir.join(relative));
                        self.output.dependencies.insert(dependency.clone());
                        self.reads.push((dependency, *digest));
                    }
                    self.output.map_includes.extend(
                        entry
                            .map_includes
                            .iter()
                            .map(|path| self.project_dir.join(path)),
                    );
                    self.output.skin_includes.extend(
                        entry
                            .skin_includes
                            .iter()
                            .map(|path| self.project_dir.join(path)),
                    );
                    self.manifest_lines.extend(entry.manifest_lines.iter().map(
                        |(text, relative, line)| {
                            (
                                text.clone(),
                                Arc::new(self.project_dir.join(relative)),
                                *line,
                            )
                        },
                    ));
                    self.expanded.push_str(&entry.output_text);
                    // Source paths are declaration identities, not per-line data.
                    // A replayed subtree may contain hundreds of thousands of lines:
                    // intern its few paths once rather than allocating an Arc and
                    // joined PathBuf for each origin on every procedure edit.
                    let mut origin_paths: BTreeMap<&PathBuf, Arc<PathBuf>> = BTreeMap::new();
                    self.output.origins.extend(entry.origins.iter().map(|origin| {
                        let path = origin.2.as_ref().map_or_else(
                            || Arc::clone(&origin_path),
                            |relative| Arc::clone(origin_paths.entry(relative)
                                .or_insert_with(|| Arc::new(self.project_dir.join(relative)))),
                        );
                        Origin {
                            output_line: origin.0 + line_start - 1,
                            path,
                            source_line: origin.1,
                        }
                    }));
                    self.output
                        .units
                        .extend(entry.units.iter().cloned().map(|mut unit| {
                            unit.output_span.start += byte_start;
                            unit.output_span.end += byte_start;
                            unit.path = self.project_dir.join(&unit.path);
                            unit
                        }));
                    self.output
                        .unit_digests
                        .extend_from_slice(&entry.unit_digests);
                    self.output
                        .diagnostics
                        .extend(entry.diagnostics.iter().cloned().map(|mut diagnostic| {
                            diagnostic.path = self.project_dir.join(&diagnostic.path);
                            diagnostic
                        }));
                    self.output_line += entry.origins.len();
                    cache.hits += 1;
                    for change in file_dir_changes {
                        self.change_file_dir(change);
                    }
                    for (name, definition) in macro_changes {
                        self.set_macro(name, definition);
                    }
                    return;
                }
                cache.misses += 1;
            }
        }
        let macro_dependencies = (cacheable && !nested)
            .then(|| macro_dependencies(&source, &self.output.final_macros))
            .flatten();
        let input_digest = dependency_digest(
            macro_dependencies.as_deref(),
            &self.macro_hashes,
            self.macro_digest,
            directory_digest,
        );
        let macro_change_start = self.macro_changes.len();
        let read_start = self.reads.len();
        let map_start = self.output.map_includes.len();
        let skin_start = self.output.skin_includes.len();
        let manifest_start = self.manifest_lines.len();
        let origin_start = self.output.origins.len();
        let unit_start_index = self.output.units.len();
        let diagnostic_start = self.output.diagnostics.len();
        let file_dir_change_start = self.file_dir_changes.len();
        let line_start = self.output_line;
        self.stack.push(path.clone());
        let unit_start = self.expanded.len();
        let origin_path = Arc::new(path.clone());
        let file_name = path
            .strip_prefix(&self.project_dir)
            .unwrap_or(&path)
            .to_string_lossy()
            .replace('\\', "/");
        let mut conditionals: Vec<Conditional> = Vec::new();
        let mut line_number = 0;
        let uncommented = strip_source_comments(&source);
        for logical in logical_lines(&uncommented) {
            let source_line = line_number + 1;
            line_number += logical.source_lines;
            let raw = logical.text;
            let trimmed = raw.trim_start();
            let directive = trimmed.strip_prefix('#').map(str::trim_start);
            let active = conditionals.last().is_none_or(|c| c.active);
            if let Some(d) = directive {
                let (word, rest) = split_word(d);
                match word {
                    "ifdef" | "ifndef" | "if" => {
                        let yes = if !active {
                            false
                        } else if word == "ifdef" {
                            match directive_identifier(rest) {
                                Ok(name) => macro_defined(name, &self.output.final_macros),
                                Err(error) => {
                                    self.error_as(
                                        &path,
                                        source_line,
                                        DiagnosticKind::Conditional,
                                        error,
                                    );
                                    false
                                }
                            }
                        } else if word == "ifndef" {
                            match directive_identifier(rest) {
                                Ok(name) => !macro_defined(name, &self.output.final_macros),
                                Err(error) => {
                                    self.error_as(
                                        &path,
                                        source_line,
                                        DiagnosticKind::Conditional,
                                        error,
                                    );
                                    false
                                }
                            }
                        } else {
                            match eval_condition(rest, &self.output.final_macros) {
                                Ok(v) => v,
                                Err(e) => {
                                    self.error_as(
                                        &path,
                                        source_line,
                                        DiagnosticKind::Conditional,
                                        e,
                                    );
                                    false
                                }
                            }
                        };
                        conditionals.push(Conditional {
                            parent_active: active,
                            branch_taken: yes,
                            active: active && yes,
                            else_seen: false,
                        });
                    }
                    "elif" => {
                        let Some(mut c) = conditionals.pop() else {
                            self.error_as(
                                &path,
                                source_line,
                                DiagnosticKind::Conditional,
                                "#elif without #if",
                            );
                            continue;
                        };
                        if c.else_seen {
                            self.error_as(
                                &path,
                                source_line,
                                DiagnosticKind::Conditional,
                                "#elif after #else",
                            );
                        }
                        let yes = if !c.parent_active || c.branch_taken {
                            false
                        } else {
                            match eval_condition(rest, &self.output.final_macros) {
                                Ok(v) => v,
                                Err(e) => {
                                    self.error_as(
                                        &path,
                                        source_line,
                                        DiagnosticKind::Conditional,
                                        e,
                                    );
                                    false
                                }
                            }
                        };
                        c.active = c.parent_active && yes;
                        c.branch_taken |= yes;
                        conditionals.push(c);
                    }
                    "else" => {
                        let Some(mut c) = conditionals.pop() else {
                            self.error_as(
                                &path,
                                source_line,
                                DiagnosticKind::Conditional,
                                "#else without #if",
                            );
                            continue;
                        };
                        if c.else_seen {
                            self.error_as(
                                &path,
                                source_line,
                                DiagnosticKind::Conditional,
                                "duplicate #else",
                            );
                        }
                        c.active = c.parent_active && !c.branch_taken;
                        c.branch_taken = true;
                        c.else_seen = true;
                        conditionals.push(c);
                    }
                    "endif" => {
                        if conditionals.pop().is_none() {
                            self.error_as(
                                &path,
                                source_line,
                                DiagnosticKind::Conditional,
                                "#endif without #if",
                            );
                        }
                    }
                    _ if !active => {}
                    "include" => match parse_include(rest) {
                        Some(rel) => {
                            if rel
                                .extension()
                                .is_some_and(|extension| extension.eq_ignore_ascii_case("dmm"))
                            {
                                self.output
                                    .map_includes
                                    .push(path.parent().unwrap_or(Path::new("")).join(rel));
                                continue;
                            }
                            let child = normalize(path.parent().unwrap_or(Path::new("")).join(rel));
                            if child
                                .extension()
                                .is_some_and(|ext| ext.eq_ignore_ascii_case("dmf"))
                            {
                                self.output.dependencies.insert(child.clone());
                                match self.provider.read_shared(&child) {
                                    Ok(text) => {
                                        self.reads.push((
                                            child.clone(),
                                            self.provider.fingerprint_read(&child, &text),
                                        ));
                                        self.output.skin_includes.push(child);
                                    }
                                    Err(error) => {
                                        self.error_as(&path, source_line, DiagnosticKind::Include,
                                            format!("cannot include {}: {error}", child.display()))
                                    }
                                }
                                continue;
                            }
                            let first_diagnostic = self.output.diagnostics.len();
                            self.visit(child.clone());
                            // A missing include belongs to its directive; errors
                            // inside a successfully opened child retain their own origin.
                            for diagnostic in &mut self.output.diagnostics[first_diagnostic..] {
                                if diagnostic.kind == DiagnosticKind::Io
                                    && diagnostic.path == child && diagnostic.line == 1
                                {
                                    diagnostic.message = format!("cannot include {}: {}",
                                        child.display(), diagnostic.message);
                                    diagnostic.path = path.clone();
                                    diagnostic.line = source_line;
                                    // Attribution is now the include directive,
                                    // not a failed read of this child. An ancestor
                                    // must not remap it a second time at line one.
                                    diagnostic.kind = DiagnosticKind::Include;
                                }
                            }
                        }
                        None => self.error_as(
                            &path,
                            source_line,
                            DiagnosticKind::Include,
                            "expected quoted #include path",
                        ),
                    },
                    "define" => match parse_define(rest) {
                        Ok((name, def)) => {
                            if name == "FILE_DIR" && def.parameters.is_none() {
                                let value = def.replacement.trim().trim_matches(['"', '\'']);
                                if !value.is_empty() {
                                    self.change_file_dir(FileDirChange::Push(
                                        PathBuf::from(value.replace('\\', "/")),
                                        def.clone(),
                                    ));
                                }
                            }
                            self.set_macro(name, Some(def));
                        }
                        Err(e) => self.error_as(&path, source_line, DiagnosticKind::Macro, e),
                    },
                    "undef" => {
                        let name = rest.trim().to_owned();
                        if name == "FILE_DIR" && !self.output.file_dirs.is_empty() {
                            self.change_file_dir(FileDirChange::Pop);
                        }
                        let restored = if name == "FILE_DIR" {
                            self.file_dir_definitions.last().cloned()
                        } else {
                            None
                        };
                        self.set_macro(name, restored);
                    }
                    "error" => self.error_as(&path, source_line, DiagnosticKind::UserError, rest),
                    "warning" | "warn" | "pragma" => {}
                    "" => {}
                    other => self.error(
                        &path,
                        source_line,
                        format!("unsupported preprocessor directive #{other}"),
                    ),
                }
            } else if active {
                // Manifests can contain ordinary DM, including startup procedures.
                // Their extension does not change the language of active lines.
                let expanded = match expand(
                    raw.trim_end_matches(['\r', '\n']),
                    &self.output.final_macros,
                    0,
                    ExpandLocation {
                        file_name: &file_name,
                        line: source_line,
                    },
                ) {
                    Ok(s) => s,
                    Err(e) => {
                        self.error_as(&path, source_line, DiagnosticKind::Macro, e);
                        raw.trim_end_matches(['\r', '\n']).to_owned()
                    }
                };
                for (offset, segment) in expanded.split('\n').enumerate() {
                    if offset > 0 && segment.is_empty() && expanded.ends_with('\n') {
                        break;
                    }
                    // DreamMaker parses manifest DM after all ordinary includes,
                    // in manifest encounter order. Directives still act here.
                    if path
                        .extension()
                        .is_some_and(|extension| extension.eq_ignore_ascii_case("dme"))
                    {
                        self.manifest_lines.push((
                            segment.to_owned(),
                            origin_path.clone(),
                            source_line + offset,
                        ));
                        continue;
                    }
                    self.expanded.push_str(segment);
                    self.expanded.push_str("\n");
                    self.output.origins.push(Origin {
                        output_line: self.output_line,
                        path: origin_path.clone(),
                        source_line: source_line + offset,
                    });
                    self.output_line += 1;
                }
            }
        }
        if !conditionals.is_empty() {
            self.error_as(
                &path,
                line_number,
                DiagnosticKind::Conditional,
                "unterminated #if block",
            );
        }
        let unit_end = self.expanded.len();
        self.output
            .unit_digests
            .push(self.expanded.digest(unit_start, unit_end));
        self.output.units.push(Unit {
            path: path.clone(),
            output_span: Span::new(unit_start, unit_end),
            source_lines: line_number,
        });
        self.stack.pop();
        if let Some(cache) = self.cache.as_deref_mut().filter(|_| cacheable) {
            if (nested && self.output.diagnostics.len() != diagnostic_start)
                || unit_end - unit_start > MAX_CACHED_LEAF_BYTES
                || self.output.origins.len() - origin_start > MAX_CACHED_ORIGINS
                || self.output.units.len() - unit_start_index > MAX_CACHED_ORIGINS
                || self.reads.len() - read_start > MAX_CACHED_PATHS
            {
                return;
            }
            let entry = CachedUnit {
                source_digest,
                source_len: source.len(),
                input_digest,
                macro_dependencies,
                dependencies: self.reads[read_start..]
                    .iter()
                    .map(|(path, digest)| {
                        (
                            path.strip_prefix(&self.project_dir)
                                .unwrap_or(path)
                                .to_path_buf(),
                            *digest,
                        )
                    })
                    .collect(),
                map_includes: self.output.map_includes[map_start..]
                    .iter()
                    .map(|path| {
                        path.strip_prefix(&self.project_dir)
                            .unwrap_or(path)
                            .to_path_buf()
                    })
                    .collect(),
                skin_includes: self.output.skin_includes[skin_start..]
                    .iter()
                    .map(|path| {
                        path.strip_prefix(&self.project_dir)
                            .unwrap_or(path)
                            .to_path_buf()
                    })
                    .collect(),
                manifest_lines: self.manifest_lines[manifest_start..]
                    .iter()
                    .map(|(text, path, line)| {
                        (
                            text.clone(),
                            path.strip_prefix(&self.project_dir)
                                .unwrap_or(path.as_ref())
                                .to_path_buf(),
                            *line,
                        )
                    })
                    .collect(),
                output_text: self.expanded.range(unit_start, unit_end),
                unit_digests: self.output.unit_digests[unit_start_index..].to_vec(),
                origins: self.output.origins[origin_start..]
                    .iter()
                    .map(|origin| {
                        DiskOrigin(
                            origin.output_line - line_start + 1,
                            origin.source_line,
                            (origin.path.as_ref() != &path).then(|| {
                                origin
                                    .path
                                    .strip_prefix(&self.project_dir)
                                    .unwrap_or(origin.path.as_ref())
                                    .to_path_buf()
                            }),
                        )
                    })
                    .collect(),
                units: self.output.units[unit_start_index..]
                    .iter()
                    .cloned()
                    .map(|mut unit| {
                        unit.output_span.start -= unit_start;
                        unit.output_span.end -= unit_start;
                        unit.path = unit
                            .path
                            .strip_prefix(&self.project_dir)
                            .unwrap_or(&unit.path)
                            .to_path_buf();
                        unit
                    })
                    .collect(),
                diagnostics: self.output.diagnostics[diagnostic_start..]
                    .iter()
                    .cloned()
                    .map(|mut diagnostic| {
                        diagnostic.path = diagnostic
                            .path
                            .strip_prefix(&self.project_dir)
                            .unwrap_or(&diagnostic.path)
                            .to_path_buf();
                        diagnostic
                    })
                    .collect(),
                macro_changes: self.macro_changes[macro_change_start..]
                    .iter()
                    .cloned()
                    .collect(),
                file_dir_changes: self.file_dir_changes[file_dir_change_start..].to_vec(),
            };
            let key_bytes = cache_key.as_os_str().len();
            let is_new_key = !cache.entries.contains_key(&cache_key);
            cache.dirty.insert(cache_key.clone());
            let entries = cache.entries.entry(cache_key).or_default();
            if is_new_key {
                cache.resident_bytes += key_bytes;
            }
            cache.resident_bytes += entry.resident_bytes();
            entries.push(entry);
            if entries.len() > 2 {
                cache.resident_bytes -= entries.remove(0).resident_bytes();
            }
            cache.enforce_budget(MAX_CACHE_RESIDENT_BYTES);
        }
    }
}

/// Conservative identifier closure includes strings/interpolations, directive operands,
/// undefined names, and identifiers in transitive replacement text. Token pasting can
/// synthesize arbitrary names, so those files retain the whole environment checkpoint.
fn macro_dependencies(source: &str, macros: &BTreeMap<String, Macro>) -> Option<Vec<String>> {
    fn identifiers(text: &str, names: &mut BTreeSet<String>) -> bool {
        let mut chars = text.char_indices().peekable();
        while let Some((start, character)) = chars.next() {
            if character == '#' && text[start + 1..].trim_start().starts_with('#') {
                return false;
            }
            if character == '_' || character.is_alphabetic() {
                let mut end = start + character.len_utf8();
                while let Some(&(index, next)) = chars.peek() {
                    if next == '_' || next.is_alphabetic() || next.is_ascii_digit() {
                        end = index + next.len_utf8();
                        chars.next();
                    } else {
                        break;
                    }
                }
                let name=&text[start..end];
                if !names.contains(name) {names.insert(name.to_owned());}
            }
        }
        true
    }
    let mut names = BTreeSet::new();
    if !identifiers(source, &mut names) || names.len() > 8192 {
        return None;
    }
    let mut visited = BTreeSet::new();
    loop {
        let pending: Vec<_> = names.difference(&visited).cloned().collect();
        if pending.is_empty() {
            break;
        }
        for name in pending {
            visited.insert(name.clone());
            if let Some(definition) = macros.get(&name) {
                if !identifiers(&definition.replacement, &mut names) {
                    return None;
                }
            }
        }
        // Bound metadata and adversarial replacement closures.
        if names.len() > 8192 {
            return None;
        }
    }
    Some(names.into_iter().collect())
}

fn dependency_digest(
    names: Option<&[String]>,
    macro_hashes: &BTreeMap<String, [u8; 32]>,
    full: [u8; 32],
    directories: [u8; 32],
) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(directories);
    if let Some(names) = names {
        hasher.update(b"selective\0");
        for name in names {
            hasher.update((name.len() as u64).to_le_bytes());
            hasher.update(name.as_bytes());
            if let Some(hash) = macro_hashes.get(name) {
                hasher.update([1]);
                hasher.update(hash);
            } else {
                hasher.update([0]);
            }
        }
    } else {
        hasher.update(b"complete\0");
        hasher.update(full);
    }
    hasher.finalize().into()
}

fn has_include_directive(source: &str) -> bool {
    source.lines().any(|line| {
        let Some(directive) = line.trim_start().strip_prefix('#') else {
            return false;
        };
        split_word(directive.trim_start()).0 == "include"
    })
}

fn normalize(path: PathBuf) -> PathBuf {
    let mut out = PathBuf::new();
    for part in path.components() {
        match part {
            std::path::Component::CurDir => {}
            std::path::Component::ParentDir => {
                out.pop();
            }
            _ => out.push(part.as_os_str()),
        }
    }
    out
}

struct LogicalLine {
    text: String,
    source_lines: usize,
}

#[derive(Default)]
struct LogicalState { open_literal: bool, open_block: bool, open_expression: bool }
fn logical_state(source:&str)->LogicalState {
    let mut last=None;
    let mut depth=0isize;
    let diagnostics=visit_tokens(source,|token| {
        match token.text(source) {"("|"["=>depth+=1,")"|"]"=>depth-=1,_=>{}}
        last=Some(token);
    });
    let open_literal=last.is_some_and(|token|token.kind==TokenKind::String && diagnostics.iter().any(|diagnostic|diagnostic.span.start==token.span.start));
    let open_block=last.is_some_and(|token|token.kind==TokenKind::String && token.text(source).starts_with("{\"") && token.span.end==source.len() && !token.text(source).ends_with("\"}"));
    LogicalState {open_literal,open_block,open_expression:depth>0}
}
fn logical_lines(source: &str) -> Vec<LogicalLine> {
    let mut lines = Vec::new();
    let mut joined = String::new();
    let mut source_lines = 0;
    let mut state=LogicalState::default();
    for physical in source.split_inclusive('\n') {
        if physical.trim_start().starts_with('#') && !joined.trim_start().starts_with("#define ") && !joined.is_empty() && !state.open_literal {
            lines.push(LogicalLine {text:std::mem::take(&mut joined),source_lines});
            source_lines=0;state=LogicalState::default();
        }
        source_lines+=1;
        let content=physical.trim_end_matches(['\r','\n']);
        if !state.open_block {
            if let Some(prefix)=content.trim_end().strip_suffix('\\') {
                joined.push_str(prefix);state=logical_state(&joined);continue;
            }
        }
        joined.push_str(physical);
        // One streaming lexical traversal answers all three continuation
        // questions. Ordinary lines previously built up to three token Vecs.
        state=logical_state(&joined);
        if state.open_literal || (!joined.trim_start().starts_with('#') && state.open_expression) {continue;}
        lines.push(LogicalLine {text:std::mem::take(&mut joined),source_lines});
        source_lines=0;state=LogicalState::default();
    }
    if !joined.is_empty() {lines.push(LogicalLine {text:joined,source_lines});}
    lines
}

/// Remove comments with a span visitor; allocate a byte mask only when a
/// comment exists, without retaining tokens for an entire source file.
fn strip_source_comments(source: &str) -> Cow<'_, str> {
    let mut bytes:Option<Vec<u8>>=None;
    visit_tokens(source,|token| {
        if token.kind!=TokenKind::Comment {return;}
        let bytes=bytes.get_or_insert_with(||source.as_bytes().to_vec());
        for byte in &mut bytes[token.span.range()] {if !matches!(*byte,b'\r'|b'\n') {*byte=b' ';}}
    });
    bytes.map_or(Cow::Borrowed(source),|bytes|Cow::Owned(String::from_utf8(bytes).expect("comment removal preserves UTF-8")))
}

fn split_word(input: &str) -> (&str, &str) {
    let end = input.find(char::is_whitespace).unwrap_or(input.len());
    (&input[..end], input[end..].trim_start())
}

fn parse_include(rest: &str) -> Option<PathBuf> {
    let rest = rest.trim();
    let inner = rest.strip_prefix('"')?.split('"').next()?;
    if inner.is_empty() {
        return None;
    }
    Some(PathBuf::from(inner.replace('\\', "/")))
}

fn parse_define(rest: &str) -> Result<(String, Macro), String> {
    let rest = rest.trim_start();
    let end = rest
        .find(|c: char| !(c == '_' || c.is_ascii_alphanumeric()))
        .unwrap_or(rest.len());
    if end == 0 || rest[..end].chars().next().unwrap().is_ascii_digit() {
        return Err("invalid macro name".into());
    }
    let name = rest[..end].to_owned();
    let tail = &rest[end..];
    if let Some(args) = tail.strip_prefix('(') {
        let Some(close) = args.find(')') else {
            return Err("unterminated macro parameter list".into());
        };
        let parameters = if args[..close].trim().is_empty() {
            Vec::new()
        } else {
            args[..close]
                .split(',')
                .map(|s| s.trim().to_owned())
                .collect::<Vec<_>>()
        };
        let variadic = parameters.last().is_some_and(|name| name.ends_with("..."));
        if parameters
            .iter()
            .take(parameters.len().saturating_sub(1))
            .any(|name| name.ends_with("..."))
        {
            return Err("variadic macro parameter must be last".into());
        }
        let parameters = parameters
            .into_iter()
            .map(|name| {
                if name == "..." {
                    "__VA_ARGS__".to_owned()
                } else {
                    name.strip_suffix("...").unwrap_or(&name).to_owned()
                }
            })
            .collect::<Vec<_>>();
        if parameters
            .iter()
            .any(|s| s.is_empty() || !s.chars().all(|c| c == '_' || c.is_ascii_alphanumeric()))
        {
            return Err("invalid macro parameter".into());
        }
        Ok((
            name,
            Macro {
                parameters: Some(parameters),
                variadic,
                replacement: strip_macro_comments(&args[close + 1..]),
            },
        ))
    } else {
        Ok((
            name,
            Macro {
                parameters: None,
                variadic: false,
                replacement: strip_macro_comments(tail),
            },
        ))
    }
}

fn strip_macro_comments(replacement: &str) -> String {
    let lexed = lex_spans(replacement);
    let mut out = String::with_capacity(replacement.len());
    for token in lexed.tokens {
        if token.kind == TokenKind::Comment {
            out.push(' ');
        } else {
            out.push_str(token.text(replacement));
        }
    }
    out.trim().to_owned()
}

fn expand(
    source: &str,
    macros: &BTreeMap<String, Macro>,
    depth: usize,
    location: ExpandLocation<'_>,
) -> Result<String, String> {
    expand_mode(source, macros, depth, location, false)
}

fn expand_mode(
    source: &str,
    macros: &BTreeMap<String, Macro>,
    depth: usize,
    location: ExpandLocation<'_>,
    substitute_only: bool,
) -> Result<String, String> {
    expand_mode_disabled(
        source,
        macros,
        depth,
        location,
        substitute_only,
        &mut Vec::new(),
    )
}

fn expand_mode_disabled<'a>(
    source: &str,
    macros: &'a BTreeMap<String, Macro>,
    depth: usize,
    location: ExpandLocation<'_>,
    substitute_only: bool,
    disabled: &mut Vec<&'a str>,
) -> Result<String, String> {
    if depth > 32 {
        return Err("macro expansion exceeded depth 32".into());
    }
    let lexed = lex_spans(source);
    if let Some(diagnostic) = lexed.diagnostics.first() {
        return Err(format!(
            "{} at byte {}",
            diagnostic.message, diagnostic.span.start
        ));
    }
    let tokens = lexed.tokens;
    let mut out = String::new();
    let mut i = 0;
    while i < tokens.len() {
        let token = &tokens[i];
        let token_text = token.text(source);
        if token.kind == TokenKind::String {
            if token_text.starts_with("@\"") {
                out.push_str(token_text);
                i += 1;
                continue;
            }
            out.push_str(&expand_interpolations(
                token_text,
                macros,
                depth + 1,
                location,
                substitute_only,
                disabled,
            )?);
            i += 1;
            continue;
        }
        if token.kind == TokenKind::Ident {
            // `defined` consumes a macro *name*. Function-like macros may
            // introduce it only after parameter substitution, so protect its
            // operand during the later ordinary expansion pass as well.
            if token_text == "defined" && !substitute_only {
                let mut operand = i + 1;
                while tokens.get(operand).is_some_and(|next| {
                    matches!(next.kind, TokenKind::Whitespace | TokenKind::Newline)
                }) {
                    operand += 1;
                }
                if tokens
                    .get(operand)
                    .is_some_and(|next| next.text(source) == "(")
                {
                    operand += 1;
                    while tokens.get(operand).is_some_and(|next| {
                        matches!(next.kind, TokenKind::Whitespace | TokenKind::Newline)
                    }) {
                        operand += 1;
                    }
                }
                if let Some(name) = tokens
                    .get(operand)
                    .filter(|next| next.kind == TokenKind::Ident)
                {
                    out.push_str(&source[token.span.start..name.span.end]);
                    i = operand + 1;
                    continue;
                }
            }
            if let Some((name, def)) = macros
                .get_key_value(token_text)
                .filter(|_| !disabled.contains(&token_text))
            {
                if let Some(params) = &def.parameters {
                    let Some(open) = tokens.get(i + 1).filter(|t| t.text(source) == "(") else {
                        out.push_str(token_text);
                        i += 1;
                        continue;
                    };
                    let _ = open;
                    let (mut args, after) = parse_arguments(&tokens, source, i + 1)?;
                    if args.is_empty() && params.len() == 1 && !def.variadic {
                        args.push(String::new());
                    }
                    let required = params.len() - usize::from(def.variadic);
                    if args.len() < required || (!def.variadic && args.len() != required) {
                        return Err(format!(
                            "macro {} expects {}{} arguments, got {}",
                            token_text,
                            required,
                            if def.variadic { " or more" } else { "" },
                            args.len()
                        ));
                    }
                    let args = if def.variadic {
                        let mut packed = args[..required].to_vec();
                        packed.push(args[required..].join(","));
                        packed
                    } else {
                        args
                    };
                    // Expand arguments before disabling this invocation. A
                    // nested F(F(x)) is valid; only F inside F's replacement
                    // is recursive. Paste/stringification consume raw spelling.
                    let raw_parameters = raw_macro_parameters(def, macros, &mut BTreeSet::new());
                    let args = params
                        .iter()
                        .zip(args)
                        .map(|(parameter, argument)| {
                            if substitute_only || raw_parameters.contains(parameter.as_str()) {
                                Ok(argument)
                            } else {
                                expand_mode_disabled(
                                    &argument,
                                    macros,
                                    depth + 1,
                                    location,
                                    false,
                                    disabled,
                                )
                            }
                        })
                        .collect::<Result<Vec<_>, String>>()?;
                    let replacements = params
                        .iter()
                        .cloned()
                        .zip(args)
                        .map(|(name, replacement)| {
                            (
                                name,
                                Macro {
                                    parameters: None,
                                    variadic: false,
                                    replacement,
                                },
                            )
                        })
                        .collect::<BTreeMap<_, _>>();
                    let substituted =
                        expand_mode(&def.replacement, &replacements, depth + 1, location, true)?;
                    disabled.push(name);
                    let expanded = expand_mode_disabled(
                        &substituted,
                        macros,
                        depth + 1,
                        location,
                        false,
                        disabled,
                    );
                    disabled.pop();
                    out.push_str(&expanded?);
                    i = after;
                    continue;
                }
                if substitute_only {
                    out.push_str(&def.replacement);
                } else {
                    // Rescan an object alias together with its following call
                    // arguments, so ALIAS(x) -> FUNCTION(x) actually invokes
                    // the function macro rather than leaving its name behind.
                    let mut target = def.replacement.trim();
                    let mut seen = BTreeSet::new();
                    while seen.insert(target) {
                        let Some(alias) = macros.get(target) else {
                            break;
                        };
                        if alias.parameters.is_some() {
                            break;
                        }
                        target = alias.replacement.trim();
                    }
                    if macros
                        .get(target)
                        .is_some_and(|definition| definition.parameters.is_some())
                        && tokens
                            .get(i + 1)
                            .is_some_and(|token| token.text(source) == "(")
                    {
                        let (_, after) = parse_arguments(&tokens, source, i + 1)?;
                        let call = format!(
                            "{}{}",
                            def.replacement,
                            &source[tokens[i + 1].span.start..tokens[after - 1].span.end]
                        );
                        disabled.push(name);
                        let expanded = expand_mode_disabled(
                            &call,
                            macros,
                            depth + 1,
                            location,
                            false,
                            disabled,
                        );
                        disabled.pop();
                        out.push_str(&expanded?);
                        i = after;
                        continue;
                    }
                    disabled.push(name);
                    let expanded = expand_mode_disabled(
                        &def.replacement,
                        macros,
                        depth + 1,
                        location,
                        false,
                        disabled,
                    );
                    disabled.pop();
                    out.push_str(&expanded?);
                }
                i += 1;
                continue;
            }
            if token_text == "__LINE__" {
                out.push_str(&location.line.to_string());
                i += 1;
                continue;
            }
            if token_text == "__FILE__" {
                out.push('"');
                for ch in location.file_name.chars() {
                    if matches!(ch, '\\' | '"') {
                        out.push('\\');
                    }
                    out.push(ch);
                }
                out.push('"');
                i += 1;
                continue;
            }
        }
        if token_text == "#"
            && tokens
                .get(i + 1)
                .is_some_and(|next| next.text(source) == "#")
        {
            if let Some(next) = tokens.get(i + 2) {
                if next.kind == TokenKind::Ident
                    && macros.get(next.text(source)).is_some_and(|definition| {
                        definition.parameters.is_none() && definition.replacement.is_empty()
                    })
                {
                    while out.ends_with(char::is_whitespace) {
                        out.pop();
                    }
                    if out.ends_with(',') {
                        out.pop();
                    }
                    i += 3;
                    continue;
                }
            }
            while out.ends_with(char::is_whitespace) {
                out.pop();
            }
            i += 2;
            while tokens
                .get(i)
                .is_some_and(|next| next.kind == TokenKind::Whitespace)
            {
                i += 1;
            }
            continue;
        }
        if token_text == "#" {
            if let Some(next) = tokens.get(i + 1) {
                if next.text(source) == "INF"
                    && out.as_bytes().last() == Some(&b'.')
                    && out[..out.len() - 1]
                        .as_bytes()
                        .last()
                        .is_some_and(u8::is_ascii_digit)
                {
                    out.push_str("#INF");
                    i += 2;
                    continue;
                }
                if next.kind == TokenKind::Ident {
                    if let Some(argument) = macros
                        .get(next.text(source))
                        .filter(|definition| definition.parameters.is_none())
                    {
                        out.push('"');
                        for ch in argument.replacement.chars() {
                            if matches!(ch, '\\' | '"') {
                                out.push('\\');
                            }
                            out.push(ch);
                        }
                        out.push('"');
                        i += 2;
                        continue;
                    }
                }
            }
            return Err("unsupported # token outside macro stringification".into());
        }
        out.push_str(token_text);
        i += 1;
    }
    Ok(out)
}

fn expand_interpolations<'a>(
    literal: &str,
    macros: &'a BTreeMap<String, Macro>,
    depth: usize,
    location: ExpandLocation<'_>,
    substitute_only: bool,
    disabled: &mut Vec<&'a str>,
) -> Result<String, String> {
    let mut result = String::with_capacity(literal.len());
    let mut cursor = 0;
    let mut chars = literal.char_indices().peekable();
    let mut escaped = false;
    while let Some((at, ch)) = chars.next() {
        if escaped {
            escaped = false;
            continue;
        }
        if ch == '\\' {
            escaped = true;
            continue;
        }
        if ch != '[' {
            continue;
        }
        let start = at + 1;
        let mut nesting = 1usize;
        let mut expression_escaped = false;
        let mut end = None;
        while let Some((offset, current)) = chars.next() {
            if expression_escaped {
                expression_escaped = false;
                continue;
            }
            if current == '\\' {
                expression_escaped = true;
                continue;
            }
            match current {
                '"' => {
                    let Some(length) =
                        quoted_end(&literal[offset..], false, literal[..offset].ends_with('@'))
                    else {
                        return Err("unclosed string interpolation".into());
                    };
                    while chars
                        .peek()
                        .is_some_and(|(next, _)| *next < offset + length)
                    {
                        chars.next();
                    }
                }
                '\'' => {
                    let mut escaped_quote = false;
                    let Some((close, _)) = literal[offset + 1..].char_indices().find(|(_, ch)| {
                        if escaped_quote {
                            escaped_quote = false;
                            false
                        } else if *ch == '\\' && !literal[..offset].ends_with('@') {
                            escaped_quote = true;
                            false
                        } else {
                            *ch == '\''
                        }
                    }) else {
                        return Err("unclosed string interpolation".into());
                    };
                    let close = offset + 1 + close + 1;
                    while chars.peek().is_some_and(|(next, _)| *next < close) {
                        chars.next();
                    }
                }
                '[' => nesting += 1,
                ']' => {
                    nesting -= 1;
                    if nesting == 0 {
                        end = Some(offset);
                        break;
                    }
                }
                _ => {}
            }
        }
        let Some(end) = end else {
            return Err("unclosed string interpolation".into());
        };
        result.push_str(&literal[cursor..start]);
        result.push_str(&expand_mode_disabled(
            &literal[start..end],
            macros,
            depth + 1,
            location,
            substitute_only,
            disabled,
        )?);
        cursor = end;
    }
    result.push_str(&literal[cursor..]);
    Ok(result)
}

/// Parameters feeding token-sensitive operators stay raw, including through
/// forwarding macros such as WRAP(x) -> STRINGIFY(x) or CHECK(x) -> defined(x).
fn raw_macro_parameters(
    definition: &Macro,
    macros: &BTreeMap<String, Macro>,
    visiting: &mut BTreeSet<String>,
) -> BTreeSet<String> {
    let scanned = lex_spans(&definition.replacement);
    let tokens: Vec<_> = scanned
        .tokens
        .into_iter()
        .filter(|token| {
            !matches!(
                token.kind,
                TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
            )
        })
        .collect();
    let text = |index: usize| {
        tokens
            .get(index)
            .map(|token| token.text(&definition.replacement))
    };
    let mut raw = BTreeSet::new();
    for (index, token) in tokens.iter().enumerate() {
        if token.kind != TokenKind::Ident {
            continue;
        }
        let prior = index.checked_sub(1).and_then(&text);
        let before_prior = index.checked_sub(2).and_then(&text);
        if prior == Some("#")
            || text(index + 1) == Some("#")
            || prior == Some("defined")
            || (prior == Some("(") && before_prior == Some("defined"))
        {
            raw.insert(token.text(&definition.replacement).to_owned());
        }
        let callee = token.text(&definition.replacement);
        if text(index + 1) != Some("(")
            || visiting.len() >= 64
            || !visiting.insert(callee.to_owned())
        {
            continue;
        }
        if let Some(nested) = macros
            .get(callee)
            .filter(|nested| nested.parameters.is_some())
        {
            if let Ok((arguments, _)) = parse_arguments(&tokens, &definition.replacement, index + 1)
            {
                let nested_raw = raw_macro_parameters(nested, macros, visiting);
                for (parameter, argument) in
                    nested.parameters.as_ref().unwrap().iter().zip(arguments)
                {
                    if nested_raw.contains(parameter) {
                        // Only exact forwarding propagates a raw name. Expressions
                        // remain expressions and are diagnosed by defined if invalid.
                        if definition
                            .parameters
                            .as_ref()
                            .is_some_and(|params| params.contains(&argument))
                        {
                            raw.insert(argument);
                        }
                    }
                }
            }
        }
        visiting.remove(callee);
    }
    raw
}

fn parse_arguments(
    tokens: &[SpanToken],
    source: &str,
    open: usize,
) -> Result<(Vec<String>, usize), String> {
    let mut args = Vec::new();
    let mut value = String::new();
    let mut depth = 0;
    for (i, token) in tokens.iter().enumerate().skip(open) {
        match token.text(source) {
            "(" => {
                if depth > 0 {
                    value.push('(');
                }
                depth += 1;
            }
            ")" => {
                depth -= 1;
                if depth == 0 {
                    if !value.trim().is_empty() || !args.is_empty() {
                        args.push(value.trim().to_owned());
                    }
                    return Ok((args, i + 1));
                }
                value.push(')');
            }
            "," if depth == 1 => {
                args.push(value.trim().to_owned());
                value.clear();
            }
            _ => value.push_str(token.text(source)),
        }
    }
    Err("unterminated macro invocation".into())
}

fn eval_condition(expr: &str, macros: &BTreeMap<String, Macro>) -> Result<bool, String> {
    // Evaluate defined() before expansion: its operand is a macro name, not its value.
    let tokens = lex_spans(expr)
        .tokens
        .into_iter()
        .filter(|token| {
            !matches!(
                token.kind,
                TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
            )
        })
        .collect::<Vec<_>>();
    let mut protected = String::new();
    let mut cursor = 0;
    let mut index = 0;
    while index < tokens.len() {
        if tokens[index].kind != TokenKind::Ident || tokens[index].text(expr) != "defined" {
            index += 1;
            continue;
        }
        let start = tokens[index].span.start;
        index += 1;
        let parenthesized = tokens
            .get(index)
            .is_some_and(|token| token.text(expr) == "(");
        if parenthesized {
            index += 1;
        }
        let name = tokens
            .get(index)
            .filter(|token| token.kind == TokenKind::Ident)
            .ok_or("expected identifier after defined")?;
        let yes = macro_defined(name.text(expr), macros);
        let mut end = name.span.end;
        index += 1;
        if parenthesized {
            let close = tokens
                .get(index)
                .filter(|token| token.text(expr) == ")")
                .ok_or("unclosed defined() in #if")?;
            end = close.span.end;
            index += 1;
        }
        protected.push_str(&expr[cursor..start]);
        protected.push(if yes { '1' } else { '0' });
        cursor = end;
    }
    protected.push_str(&expr[cursor..]);
    let expanded = expand(
        &protected,
        macros,
        0,
        ExpandLocation {
            line: 1,
            file_name: "",
        },
    )?;
    let expr = expanded.as_str();
    let mut parser = ConditionParser {
        tokens: lex(expr)
            .tokens
            .into_iter()
            .filter(|token| {
                !matches!(
                    token.kind,
                    TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
                )
            })
            .collect(),
        index: 0,
        macros,
        expansion_depth: 0,
    };
    let value = parser.parse(0)?;
    if parser.index != parser.tokens.len() {
        return Err(format!("unsupported #if expression: {expr}"));
    }
    Ok(value != 0)
}

struct ConditionParser<'a> {
    tokens: Vec<dm_syntax::Token>,
    index: usize,
    macros: &'a BTreeMap<String, Macro>,
    expansion_depth: usize,
}

impl ConditionParser<'_> {
    fn peek(&self) -> Option<&str> {
        self.tokens.get(self.index).map(|token| token.text.as_str())
    }

    fn take(&mut self, expected: &str) -> bool {
        if self.peek() == Some(expected) {
            self.index += 1;
            true
        } else {
            false
        }
    }

    fn parse(&mut self, min_bp: u8) -> Result<i64, String> {
        let mut lhs = if self.take("!") {
            (self.parse(21)? == 0) as i64
        } else if self.take("~") {
            !self.parse(21)?
        } else if self.take("-") {
            self.parse(21)?.wrapping_neg()
        } else if self.take("+") {
            self.parse(21)?
        } else if self.take("(") {
            let value = self.parse(0)?;
            if !self.take(")") {
                return Err("unclosed parenthesis in #if".into());
            }
            value
        } else if self.take("defined") {
            let parenthesized = self.take("(");
            let name = self
                .tokens
                .get(self.index)
                .ok_or("missing identifier after defined")?;
            if name.kind != TokenKind::Ident {
                return Err("expected identifier after defined".into());
            }
            let name = name.text.clone();
            self.index += 1;
            if parenthesized && !self.take(")") {
                return Err("unclosed defined() in #if".into());
            }
            macro_defined(&name, self.macros) as i64
        } else {
            let token = self
                .tokens
                .get(self.index)
                .ok_or("missing #if operand")?
                .clone();
            self.index += 1;
            if token.kind == TokenKind::Number {
                parse_int(&token.text)?
            } else if token.kind == TokenKind::Ident {
                self.macro_value(&token.text)?
            } else {
                return Err(format!("unsupported #if token: {}", token.text));
            }
        };
        loop {
            let Some((op, width, left_bp, right_bp)) = self.binary_operator() else {
                break;
            };
            if left_bp < min_bp {
                break;
            }
            self.index += width;
            let rhs = self.parse(right_bp)?;
            lhs = match op {
                "||" => ((lhs != 0) || (rhs != 0)) as i64,
                "&&" => ((lhs != 0) && (rhs != 0)) as i64,
                "|" => lhs | rhs,
                "^" => lhs ^ rhs,
                "&" => lhs & rhs,
                "==" => (lhs == rhs) as i64,
                "!=" => (lhs != rhs) as i64,
                "<" => (lhs < rhs) as i64,
                "<=" => (lhs <= rhs) as i64,
                ">" => (lhs > rhs) as i64,
                ">=" => (lhs >= rhs) as i64,
                "<<" => lhs.wrapping_shl(rhs as u32),
                ">>" => lhs.wrapping_shr(rhs as u32),
                "+" => lhs.wrapping_add(rhs),
                "-" => lhs.wrapping_sub(rhs),
                "*" => lhs.wrapping_mul(rhs),
                "/" if rhs != 0 => lhs.wrapping_div(rhs),
                "%" if rhs != 0 => lhs.wrapping_rem(rhs),
                "/" | "%" => return Err("division by zero in #if".into()),
                _ => unreachable!(),
            };
        }
        Ok(lhs)
    }

    fn macro_value(&self, name: &str) -> Result<i64, String> {
        let Some(definition) = self.macros.get(name) else {
            return Ok(0);
        };
        if definition.parameters.is_some() {
            return Ok(0);
        }
        if definition.replacement.trim().is_empty() {
            return Ok(0);
        }
        if self.expansion_depth >= 32 {
            return Err("#if macro expansion exceeded depth 32".into());
        }
        let mut nested = ConditionParser {
            tokens: lex(&definition.replacement)
                .tokens
                .into_iter()
                .filter(|token| {
                    !matches!(
                        token.kind,
                        TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
                    )
                })
                .collect(),
            index: 0,
            macros: self.macros,
            expansion_depth: self.expansion_depth + 1,
        };
        let value = nested.parse(0)?;
        if nested.index != nested.tokens.len() {
            return Err(format!("unsupported #if macro value: {name}"));
        }
        Ok(value)
    }

    fn binary_operator(&self) -> Option<(&'static str, usize, u8, u8)> {
        const OPS: &[(&str, u8)] = &[
            ("||", 1),
            ("&&", 3),
            ("|", 5),
            ("^", 7),
            ("&", 9),
            ("==", 11),
            ("!=", 11),
            ("<=", 13),
            (">=", 13),
            ("<", 13),
            (">", 13),
            ("<<", 15),
            (">>", 15),
            ("+", 17),
            ("-", 17),
            ("*", 19),
            ("/", 19),
            ("%", 19),
        ];
        let first = self.tokens.get(self.index)?;
        OPS.iter()
            .filter_map(|(op, bp)| {
                let mut width = 0;
                let mut spelling = String::new();
                for token in self.tokens.iter().skip(self.index) {
                    if token.span.start != first.span.start + spelling.len()
                        || spelling.len() >= op.len()
                    {
                        break;
                    }
                    spelling.push_str(&token.text);
                    width += 1;
                }
                (spelling == *op).then_some((*op, width, *bp, bp + 1))
            })
            .max_by_key(|(op, _, _, _)| op.len())
    }
}

fn parse_int(value: &str) -> Result<i64, String> {
    let value = value.replace('_', "");
    if let Some(hex) = value
        .strip_prefix("0x")
        .or_else(|| value.strip_prefix("0X"))
    {
        i64::from_str_radix(hex, 16).map_err(|_| format!("invalid #if number: {value}"))
    } else {
        value
            .parse::<i64>()
            .map_err(|_| format!("invalid #if number: {value}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Memory(BTreeMap<PathBuf, String>);
    impl SourceProvider for Memory {
        fn read(&self, path: &Path) -> Result<String, String> {
            self.0.get(path).cloned().ok_or_else(|| "missing".into())
        }
    }
    fn fixture(files: &[(&str, &str)]) -> Memory {
        Memory(
            files
                .iter()
                .map(|(p, s)| (PathBuf::from(p), (*s).into()))
                .collect(),
        )
    }

    #[test]
    fn large_macro_environment_uses_compact_leaf_cache() {
        let mut manifest = String::new();
        for index in 0..1000 {
            manifest.push_str(&format!("#define M{index} {index}\n"));
        }
        manifest.push_str("#include \"leaf.dm\"\n");
        let files = Memory(BTreeMap::from([
            (PathBuf::from("game.dme"), manifest),
            (PathBuf::from("leaf.dm"), "/datum/test\n".into()),
        ]));
        let mut cache = PreprocessCache::default();
        let output =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert!(output.diagnostics.is_empty());
        assert_eq!(output.text, "/datum/test\n");
        let entry = &cache.entries[Path::new("leaf.dm")][0];
        assert!(entry.macro_changes.is_empty());
        let replayed =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert_eq!(replayed, output);
        assert_eq!(cache.hits, 1);
    }

    #[test]
    fn large_macro_value_is_not_copied_into_leaf_cache() {
        let manifest = format!(
            "#define BIG {}\n#include \"leaf.dm\"\n",
            "x".repeat(64 * 1024 + 1)
        );
        let files = Memory(BTreeMap::from([
            (PathBuf::from("game.dme"), manifest),
            (PathBuf::from("leaf.dm"), "/datum/test\n".into()),
        ]));
        let mut cache = PreprocessCache::default();
        let output =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert!(output.diagnostics.is_empty());
        assert!(cache.entries[Path::new("leaf.dm")][0]
            .macro_changes
            .is_empty());
    }

    #[test]
    fn leaf_cache_has_a_fixed_path_budget() {
        let mut files = BTreeMap::new();
        let mut manifest = String::new();
        for index in 0..=MAX_CACHED_PATHS {
            let name = format!("leaf_{index}.dm");
            manifest.push_str(&format!("#include \"{name}\"\n"));
            files.insert(PathBuf::from(name), "/datum/test\n".into());
        }
        files.insert(PathBuf::from("game.dme"), manifest);
        let mut cache = PreprocessCache::default();
        let output = preprocess_project_cached(
            Path::new("game.dme"),
            &Memory(files),
            &BTreeMap::new(),
            &mut cache,
        );
        assert!(output.diagnostics.is_empty());
        assert_eq!(cache.entries.len(), MAX_CACHED_PATHS);
    }

    #[test]
    fn spaced_include_is_not_mistaken_for_leaf() {
        let files = fixture(&[
            ("game.dme", "#include \"parent.dm\"\n"),
            ("parent.dm", "# include \"child.dm\"\n"),
            ("child.dm", "/obj/child\n"),
        ]);
        let mut cache = PreprocessCache::default();
        let first =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        let second =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert_eq!(first, second);
        assert!(cache.entries.contains_key(Path::new("parent.dm")));
        assert!(cache.entries.contains_key(Path::new("child.dm")));
    }

    #[test]
    fn large_leaf_replays_within_unchanged_resident_budget() {
        let source = format!(
            "/obj/test\n{}",
            "  value = 7 // sizable leaf content\n".repeat(7000)
        );
        assert!(source.len() > 128 * 1024);
        let files = Memory(BTreeMap::from([
            (PathBuf::from("game.dme"), "#include \"leaf.dm\"\n".into()),
            (PathBuf::from("leaf.dm"), source),
        ]));
        let mut cache = PreprocessCache::default();
        let first =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        let second =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert_eq!(first, second);
        assert_eq!(cache.hits, 1);
        assert!(cache.resident_bytes() <= MAX_CACHE_RESIDENT_BYTES);
    }

    #[test]
    fn excessive_origin_records_are_not_retained() {
        let lines = "/obj/test\n".repeat(MAX_CACHED_ORIGINS + 1);
        let files = Memory(BTreeMap::from([
            (PathBuf::from("game.dme"), "#include \"leaf.dm\"\n".into()),
            (PathBuf::from("leaf.dm"), lines),
        ]));
        let mut cache = PreprocessCache::default();
        let output =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert_eq!(output.origins.len(), MAX_CACHED_ORIGINS + 1);
        assert!(cache.entries.is_empty());
    }

    #[test]
    fn resident_budget_evicts_cached_entries() {
        let files = fixture(&[
            ("game.dme", "#include \"a.dm\"\n#include \"b.dm\"\n"),
            ("a.dm", "/obj/a\n"),
            ("b.dm", "/obj/b\n"),
        ]);
        let mut cache = PreprocessCache::default();
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert_eq!(cache.entries.len(), 2);
        let one_entry_budget = cache.entries[Path::new("b.dm")][0].resident_bytes()
            + Path::new("b.dm").as_os_str().len();
        cache.enforce_budget(one_entry_budget);
        assert_eq!(cache.entries.len(), 1);
        assert!(cache.entries.contains_key(Path::new("b.dm")));
        assert_eq!(cache.resident_bytes, one_entry_budget);
        cache.clear();
        assert_eq!(cache.resident_bytes, 0);
    }

    #[test]
    fn resident_budget_drops_history_before_current_files() {
        let files = fixture(&[
            ("game.dme", "#include \"a.dm\"\n#include \"b.dm\"\n"),
            ("a.dm", "/obj/a\n"),
            ("b.dm", "/obj/b\n"),
        ]);
        let mut cache = PreprocessCache::default();
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        let current_budget = cache.resident_bytes;
        let historical = CachedUnit::from(DiskEntry::from(&cache.entries[Path::new("b.dm")][0]));
        cache.resident_bytes += historical.resident_bytes();
        cache
            .entries
            .get_mut(Path::new("b.dm"))
            .unwrap()
            .push(historical);
        cache.enforce_budget(current_budget);
        assert_eq!(cache.entries.len(), 2);
        assert!(cache.entries.values().all(|entries| entries.len() == 1));
        assert_eq!(cache.resident_bytes, current_budget);
    }

    #[test]
    fn parallel_chunk_publication_replays_all_files() {
        let mut files = BTreeMap::new();
        let mut manifest = String::new();
        for index in 0..40 {
            let file = format!("leaf_{index}.dm");
            manifest.push_str(&format!("#include \"{file}\"\n"));
            files.insert(PathBuf::from(file), format!("/obj/leaf_{index}\n"));
        }
        files.insert(PathBuf::from("game.dme"), manifest);
        let files = Memory(files);
        let mut cache = PreprocessCache::default();
        let first =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        let directory = std::env::temp_dir().join(format!(
            "dm-preprocess-parallel-{}-{}",
            std::process::id(),
            CACHE_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&directory).unwrap();
        let path = directory.join("cache.json");
        cache.save_incremental(&path).unwrap();
        let mut restored = PreprocessCache::load_incremental(&path);
        let replay = preprocess_project_cached(
            Path::new("game.dme"),
            &files,
            &BTreeMap::new(),
            &mut restored,
        );
        assert_eq!(first, replay);
        assert_eq!(restored.hits, 40);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn file_and_line_macros_use_invocation_location() {
        let files = fixture(&[
            ("game.dme", "#include \"src/test.dm\"\n"),
            (
                "src/test.dm",
                "#define HERE __FILE__, __LINE__\n#ifdef __FILE__\n/obj/test\n  x = HERE\n#endif\n#if defined(__LINE__)\n  y = __LINE__\n#endif\n",
            ),
        ]);
        let mut cache = PreprocessCache::default();
        let output =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
        assert!(
            output.text.contains("x = \"src/test.dm\", 4"),
            "{}",
            output.text
        );
        assert!(output.text.contains("y = 7"));
        let replay =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert_eq!(output, replay);
        assert_eq!(cache.hits, 1);
    }

    #[test]
    fn file_macro_strips_absolute_worktree_root() {
        let project = PathBuf::from("C:/worktree/project/game.dme");
        let source = PathBuf::from("C:/worktree/project/code/test.dm");
        let files = Memory(BTreeMap::from([
            (project.clone(), "#include \"code/test.dm\"\n".into()),
            (source, "/obj/test\n  file = __FILE__\n".into()),
        ]));
        let output = preprocess_project(&project, &files, &BTreeMap::new());
        assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
        assert_eq!(output.text, "/obj/test\n  file = \"code/test.dm\"\n");
    }

    #[test]
    fn line_macro_uses_physical_invocation_line_after_continuation() {
        let files = fixture(&[
            ("game.dme", "#include \"leaf.dm\"\n"),
            (
                "leaf.dm",
                "#define HERE \\\n    __LINE__\n/obj/probe\n    var/probe_line = HERE\n",
            ),
        ]);
        let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
        assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
        assert!(output.text.contains("probe_line = 4"), "{}", output.text);
    }

    #[test]
    fn leaf_disk_cache_replays_across_project_roots() {
        let first = PathBuf::from("C:/first/game.dme");
        let second = PathBuf::from("C:/second/game.dme");
        let first_leaf = PathBuf::from("C:/first/code/test.dm");
        let second_leaf = PathBuf::from("C:/second/code/test.dm");
        let files = Memory(BTreeMap::from([
            (first.clone(), "#include \"code/test.dm\"\n".into()),
            (second.clone(), "#include \"code/test.dm\"\n".into()),
            (first_leaf.clone(), "/obj/test\n  file = __FILE__\n".into()),
            (second_leaf.clone(), "/obj/test\n  file = __FILE__\n".into()),
        ]));
        let mut cache = PreprocessCache::default();
        let left = preprocess_project_cached(&first, &files, &BTreeMap::new(), &mut cache);
        let path = std::env::temp_dir().join(format!(
            "dm-preprocess-roots-test-{}-{}.json",
            std::process::id(),
            CACHE_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        cache.save(&path).unwrap();
        let mut restored = PreprocessCache::load(&path);
        let right = preprocess_project_cached(&second, &files, &BTreeMap::new(), &mut restored);
        assert_eq!(right.text, left.text);
        assert_eq!(right.text, "/obj/test\n  file = \"code/test.dm\"\n");
        assert_eq!(restored.hits, 1);
        assert_eq!(right.origins[0].path.as_path(), second_leaf.as_path());
        assert_eq!(right.units[0].path, second_leaf);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn conditional_macro_name_allows_trailing_comment() {
        let files = fixture(&[
            ("game.dme", "#include \"leaf.dm\"\n"),
            (
                "leaf.dm",
                "#define UNIT_TESTS 1\n#ifndef UNIT_TESTS // skipped\n/bad\n#endif\n#ifdef UNIT_TESTS // enabled\n/good\n#endif\n",
            ),
        ]);
        let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
        assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
        assert_eq!(output.text, "/good\n");
    }

    #[test]
    fn multiline_comments_calls_and_unnamed_variadics() {
        let files = fixture(&[
            ("game.dme", "#include \"leaf.dm\"\n"),
            ("leaf.dm", "/**\n * # docs\n */\n#define VALUES(...) list(__VA_ARGS__)\n/obj/test\n  values = VALUES(\n    1,\n    2\n  )\n"),
        ]);
        let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
        assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
        assert!(output.text.contains("list(1,2)"), "{}", output.text);
    }

    #[test]
    fn continued_token_paste_is_not_a_directive() {
        let files = fixture(&[
            ("game.dme", "#include \"leaf.dm\"\n"),
            (
                "leaf.dm",
                "#define FIELD(X) /obj/test/var/\\\n  ##X = 1\nFIELD(value)\n",
            ),
        ]);
        let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
        assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
        assert!(
            output.text.contains("/obj/test/var/value = 1"),
            "{}",
            output.text
        );
    }

    #[test]
    fn includes_inside_expressions_and_skin_assets() {
        let files = fixture(&[
            ("game.dme", "#include \"leaf.dm\"\n#include \"skin.dmf\"\n"),
            (
                "leaf.dm",
                "/proc/test()\n  return list(\n    #include \"values.dm\"\n  )\n",
            ),
            ("values.dm", "1, 2\n"),
            ("skin.dmf", "elem \"x\"\n background-color = #fff\n"),
        ]);
        let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
        assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
        assert!(output.text.contains("1, 2"));
        assert!(!output.text.contains("background-color"));
        assert_eq!(output.skin_includes, [PathBuf::from("skin.dmf")]);
    }

    #[test]
    fn continued_string_keeps_blank_physical_lines() {
        let files = fixture(&[
            ("game.dme", "#include \"leaf.dm\"\n"),
            ("leaf.dm", "/obj/test\n  desc = \"first\\\n\n  last\"\n"),
        ]);
        let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
        assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
        assert!(output.text.contains("first"));
        assert!(output.text.contains("last"));
    }

    #[test]
    fn mixed_source_encoding_preserves_valid_unicode() {
        let mut bytes = "// \u{a7} ".as_bytes().to_vec();
        bytes.extend_from_slice(&[0x97, b' ', 0x93, b'x', 0x94]);
        assert_eq!(
            decode_source_bytes(&bytes),
            "// \u{a7} \u{2014} \u{201c}x\u{201d}"
        );
        assert_eq!(decode_source_bytes(b"\xef\xbb\xbf/obj/test"), "/obj/test");
    }

    #[test]
    fn define_comments_do_not_enter_replacement() {
        let files = fixture(&[
            ("game.dme", "#include \"leaf.dm\"\n"),
            (
                "leaf.dm",
                "#define DECAY 0.8 // explained\n#define TEXT \"http://example.test\" // explained\n#define SUM 1/*gap*/+2\n/obj/test\n  a = DECAY + 1\n  b = TEXT\n  c = SUM\n",
            ),
        ]);
        let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
        assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
        assert!(output.text.contains("a = 0.8 + 1"), "{}", output.text);
        assert!(output.text.contains("b = \"http://example.test\""));
        assert!(output
            .text
            .lines()
            .any(|line| line.split_whitespace().collect::<String>() == "c=1+2"));
        assert_eq!(output.final_macros["DECAY"].replacement, "0.8");
    }

    #[test]
    fn nested_function_macros_and_object_alias_calls_rescan_correctly() {
        let files = fixture(&[
            ("game.dme", "#include \"leaf.dm\"\n"),
            (
                "leaf.dm",
                r#"#define F(x) list(x)
#define ALIAS F
#define CLAMP(x,a,b) clamp(x,a,b)
#define span_small(x) ("<font>" + x + "</font>")
#define STRINGIFY(x) #x
/proc/test()
    var/a = F(F(1))
    var/b = ALIAS(2)
    var/c = CLAMP(CLAMP(1,2,3),4,5)
    var/d = span_small("[span_small("text")]")
    var/e = STRINGIFY(F(1))
"#,
            ),
        ]);
        let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
        assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
        assert!(output.text.contains("list(list(1))"), "{}", output.text);
        assert!(output.text.contains("list(2)"));
        assert!(output.text.contains("clamp(clamp(1,2,3),4,5)"));
        assert!(!output.text.contains("span_small("));
        assert!(output.text.contains("\"F(1)\""));
    }

    #[test]
    fn function_macros_preserve_defined_operand_names() {
        let files = fixture(&[("game.dme", "#define PRESENT 0\n#define ALIAS UNDEFINED\n#define CHECK(x) defined(x)\n#define BARE(x) defined x\n#define WRAP(x) CHECK(x)\n#if CHECK(PRESENT) && CHECK(ALIAS) && !CHECK(MISSING) && BARE(PRESENT) && WRAP(PRESENT)\n/obj/selected\n#endif\n")]);
        let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
        assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
        assert!(output.text.contains("/obj/selected"), "{}", output.text);
    }

    #[test]
    fn native_predefined_constructor_macros_keep_source_context_and_arity() {
        let files = fixture(&[("game.dme", "#include \"leaf.dm\"\n"), ("leaf.dm", "/proc/test(message)\n    return EXCEPTION(message)\n/proc/quote(message)\n    return REGEX_QUOTE(message)\n/proc/replacement(message)\n    return REGEX_QUOTE_REPLACEMENT(message)\n")]);
        let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
        assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
        assert!(
            output
                .text
                .contains("new /exception(message, \"leaf.dm\", 2)"),
            "{}",
            output.text
        );
        assert!(output.text.contains("regex(message, 1)"));
        assert!(output.text.contains("regex(message, 2)"));
        let invalid = fixture(&[
            ("game.dme", "#include \"leaf.dm\"\n"),
            ("leaf.dm", "/proc/test()\n    return EXCEPTION(1, 2)\n"),
        ]);
        assert!(
            !preprocess_project(Path::new("game.dme"), &invalid, &BTreeMap::new())
                .diagnostics
                .is_empty()
        );
    }

    #[test]
    fn assertion_macro_with_nested_interpolation_and_quoted_message_expands() {
        let files = fixture(&[
            ("game.dme", "#include \"leaf.dm\"\n"),
            (
                "leaf.dm",
                r#"#define TEST_ASSERT_EQUAL(a, b, message) do { var/lhs = ##a; var/rhs = ##b; if (lhs != rhs) { return Fail("Expected [isnull(lhs) ? "null" : lhs] to equal [isnull(rhs) ? "null" : rhs].[message ? " [message]" : ""]", __FILE__, __LINE__); } } while (FALSE)
/proc/check()
    TEST_ASSERT_EQUAL(expected, output, "TGUI_CREATE_MESSAGE didn't round trip properly")
"#,
            ),
        ]);
        let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
        assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
        assert!(output
            .text
            .contains("TGUI_CREATE_MESSAGE didn't round trip properly"));
    }

    #[test]
    fn map_includes_follow_active_conditional_branches() {
        let files = fixture(&[("game.dme", "#define ENABLE 1\n#if ENABLE\n#include \"active.dmm\"\n#else\n#include \"dormant.dmm\"\n#endif\n")]);
        let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
        assert!(output.diagnostics.is_empty());
        assert_eq!(output.map_includes, [PathBuf::from("active.dmm")]);
        assert!(output.text.is_empty());
    }

    #[test]
    fn macro_dependency_closure_preserves_unrelated_files_and_tracks_undefined_names() {
        let mut files = fixture(&[
            (
                "game.dme",
                "#include \"defs.dm\"\n#include \"a.dm\"\n#include \"b.dm\"\n",
            ),
            (
                "defs.dm",
                "#define ALIAS VALUE\n#define VALUE 7\n#define OTHER 1\n",
            ),
            ("a.dm", "/proc/a()\n return ALIAS + FUTURE\n"),
            ("b.dm", "/proc/b()\n return OTHER\n"),
        ]);
        let mut cache = PreprocessCache::default();
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        files.0.insert(
            PathBuf::from("defs.dm"),
            "#define ALIAS VALUE\n#define VALUE 8\n#define OTHER 1\n".into(),
        );
        let changed =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert_eq!(
            changed,
            preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new())
        );
        assert_eq!(
            cache.hits, 1,
            "unrelated OTHER consumer must reuse its expansion"
        );
        files.0.insert(
            PathBuf::from("defs.dm"),
            "#define ALIAS VALUE\n#define VALUE 8\n#define OTHER 1\n#define FUTURE 3\n".into(),
        );
        let changed =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert_eq!(
            changed,
            preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new())
        );
        assert!(changed.text.contains("8 + 3"));
    }

    #[test]
    fn dependency_fingerprint_supports_unicode_and_falls_back_for_spaced_paste() {
        let definition = Macro {
            parameters: None,
            variadic: false,
            replacement: "7".into(),
        };
        let macros = BTreeMap::from([("\u{00c5}NSWER".into(), definition)]);
        assert!(macro_dependencies("return \u{00c5}NSWER", &macros)
            .unwrap()
            .contains(&"\u{00c5}NSWER".to_string()));
        assert!(macro_dependencies("#define CAT(a,b) a # # b", &macros).is_none());
        let (_, pasted) = parse_define("PASTE(a,b) a##b").unwrap();
        let macros = BTreeMap::from([("PASTE".into(), pasted)]);
        assert!(macro_dependencies("PASTE(A,B)", &macros).is_none());
    }

    #[test]
    fn nested_cache_replays_child_origins_macro_effects_and_rejects_child_edit() {
        let mut files = fixture(&[
            ("game.dme", "#include \"parent.dm\"\n#include \"tail.dm\"\n"),
            (
                "parent.dm",
                "#include \"child.dm\"\n/proc/parent()\n return CHILD\n",
            ),
            (
                "child.dm",
                "#define CHILD 7\n/proc/child()\n return CHILD\n",
            ),
            ("tail.dm", "/proc/tail()\n return CHILD\n"),
        ]);
        let mut cache = PreprocessCache::default();
        let first =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        let repeated =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert_eq!(first, repeated);
        assert_eq!(cache.hits, 2, "parent subtree and tail replay once each");
        files.0.insert(
            PathBuf::from("child.dm"),
            "#define CHILD 9\n/proc/child()\n return CHILD\n".into(),
        );
        let changed =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert_eq!(
            changed,
            preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new())
        );
        assert!(changed.text.contains("return 9"));
    }

    #[test]
    fn changed_leaf_reuses_unchanged_include_expansions() {
        let mut files = fixture(&[
            (
                "game.dme",
                "#include \"a.dm\"\n#include \"b.dm\"\n#include \"c.dm\"\n",
            ),
            ("a.dm", "#define VALUE 7\n/obj/a\n  x = VALUE\n"),
            ("b.dm", "/obj/b\n  x = VALUE\n"),
            ("c.dm", "/obj/c\n  x = VALUE\n"),
        ]);
        let mut cache = PreprocessCache::default();
        let first =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert_eq!(cache.misses, 3);
        files
            .0
            .insert(PathBuf::from("b.dm"), "/obj/b\n  x = VALUE + 1\n".into());
        let changed =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        let cold = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
        assert_ne!(first.text, changed.text);
        assert_eq!(changed, cold);
        assert_eq!(cache.hits, 2);
        assert_eq!(cache.misses, 4);
    }

    #[test]
    fn changed_macro_invalidates_later_include_expansions() {
        let mut files = fixture(&[
            ("game.dme", "#include \"a.dm\"\n#include \"b.dm\"\n"),
            ("a.dm", "#define VALUE 7\n"),
            ("b.dm", "/obj/b\n  x = VALUE\n"),
        ]);
        let mut cache = PreprocessCache::default();
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        files
            .0
            .insert(PathBuf::from("a.dm"), "#define VALUE 8\n".into());
        let changed =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert!(changed.text.contains("x = 8"));
        assert_eq!(cache.hits, 0);
        assert_eq!(
            changed,
            preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new())
        );
    }

    #[test]
    fn cached_macro_delta_replays_define_and_undef() {
        let files = fixture(&[
            (
                "game.dme",
                "#define OLD 1\n#include \"a.dm\"\n#include \"b.dm\"\n",
            ),
            ("a.dm", "#undef OLD\n#define NEW 7\n#define NEW 8\n"),
            ("b.dm", "/obj/b\n  x = NEW\n"),
        ]);
        let mut cache = PreprocessCache::default();
        let first =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        let second =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert_eq!(first, second);
        assert_eq!(cache.hits, 2);
        assert!(!second.final_macros.contains_key("OLD"));
        assert_eq!(second.final_macros["NEW"].replacement, "8");
        assert!(second.text.contains("x = 8"));
        assert_eq!(cache.entries[Path::new("a.dm")][0].macro_changes.len(), 2);
        let path = std::env::temp_dir().join(format!(
            "dm-preprocess-delta-test-{}-{}.json",
            std::process::id(),
            CACHE_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        cache.save(&path).unwrap();
        let mut restored = PreprocessCache::load(&path);
        let from_disk = preprocess_project_cached(
            Path::new("game.dme"),
            &files,
            &BTreeMap::new(),
            &mut restored,
        );
        assert_eq!(from_disk, first);
        assert_eq!(restored.hits, 2);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn source_digest_rejects_same_length_edits_and_obsolete_or_corrupt_cache() {
        let first_files = fixture(&[
            ("game.dme", "#include \"a.dm\"\n"),
            ("a.dm", "/obj/a\n  x = 7\n"),
        ]);
        let second_files = fixture(&[
            ("game.dme", "#include \"a.dm\"\n"),
            ("a.dm", "/obj/a\n  x = 8\n"),
        ]);
        let mut cache = PreprocessCache::default();
        let first = preprocess_project_cached(
            Path::new("game.dme"),
            &first_files,
            &BTreeMap::new(),
            &mut cache,
        );
        let path = std::env::temp_dir().join(format!(
            "dm-source-digest-{}-{}.json",
            std::process::id(),
            CACHE_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        cache.save(&path).unwrap();
        let bytes = fs::read(&path).unwrap();
        let mut restored = PreprocessCache::load(&path);
        let second = preprocess_project_cached(
            Path::new("game.dme"),
            &second_files,
            &BTreeMap::new(),
            &mut restored,
        );
        assert_eq!(restored.hits, 0);
        assert_eq!(restored.misses, 1);
        assert_ne!(first.text, second.text);
        assert!(second.text.contains("x = 8"));
        let mut file: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        file["version"] = serde_json::json!(7);
        fs::write(&path, serde_json::to_vec(&file).unwrap()).unwrap();
        assert!(PreprocessCache::load(&path).entries.is_empty());
        file["version"] = serde_json::json!(CACHE_FORMAT_VERSION);
        file["compiler_fingerprint"] = serde_json::json!("obsolete");
        fs::write(&path, serde_json::to_vec(&file).unwrap()).unwrap();
        assert!(PreprocessCache::load(&path).entries.is_empty());
        fs::write(&path, &bytes[..bytes.len() / 2]).unwrap();
        assert!(PreprocessCache::load(&path).entries.is_empty());
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn sharded_cache_is_lazy_rewrites_only_changed_chunks_and_checks_corruption() {
        let mut files = fixture(&[
            ("game.dme", "#include \"a.dm\"\n#include \"b.dm\"\n"),
            ("a.dm", "/proc/a()\n return 1\n"),
            ("b.dm", "/proc/b()\n return 2\n"),
        ]);
        let directory = std::env::temp_dir().join(format!(
            "dm-shards-{}-{}",
            std::process::id(),
            CACHE_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&directory).unwrap();
        let path = directory.join("cache.json");
        let mut cache = PreprocessCache::default();
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        cache.save_incremental(&path).unwrap();
        let first_index: CacheIndex =
            serde_json::from_slice(&fs::read(path.with_extension("index.json")).unwrap()).unwrap();
        let b_key = first_index.entries[Path::new("b.dm")][0].clone();
        let b_path = path.with_extension("parts").join(&b_key);
        let b_time = fs::metadata(&b_path).unwrap().modified().unwrap();
        let mut restored = PreprocessCache::load_incremental(&path);
        assert!(restored.entries.is_empty(), "load decodes only the index");
        files
            .0
            .insert(PathBuf::from("a.dm"), "/proc/a()\n return 3\n".into());
        let changed = preprocess_project_cached(
            Path::new("game.dme"),
            &files,
            &BTreeMap::new(),
            &mut restored,
        );
        assert_eq!(
            changed,
            preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new())
        );
        assert_eq!(restored.hits, 1);
        restored.save_incremental(&path).unwrap();
        assert_eq!(fs::metadata(&b_path).unwrap().modified().unwrap(), b_time);
        fs::write(&b_path, b"corrupt").unwrap();
        let mut restarted = PreprocessCache::load_incremental(&path);
        let again = preprocess_project_cached(
            Path::new("game.dme"),
            &files,
            &BTreeMap::new(),
            &mut restarted,
        );
        assert_eq!(again, changed);
        assert_eq!(restarted.misses, 1);
        restarted.save_incremental(&path).unwrap();
        let mut index: CacheIndex =
            serde_json::from_slice(&fs::read(path.with_extension("index.json")).unwrap()).unwrap();
        let old = path
            .with_extension("parts")
            .join(&index.entries[Path::new("b.dm")][0]);
        let mut chunk: serde_json::Value = serde_json::from_slice(&fs::read(old).unwrap()).unwrap();
        chunk["unit_digests"][0] = serde_json::to_value([0u8; 32]).unwrap();
        let bytes = serde_json::to_vec(&chunk).unwrap();
        let changed_key = format!("{:x}", Sha256::digest(&bytes));
        fs::write(path.with_extension("parts").join(&changed_key), bytes).unwrap();
        index.entries.get_mut(Path::new("b.dm")).unwrap()[0] = changed_key;
        fs::write(
            path.with_extension("index.json"),
            serde_json::to_vec(&index).unwrap(),
        )
        .unwrap();
        let mut mismatched_digest = PreprocessCache::load_incremental(&path);
        let exact = preprocess_project_cached(
            Path::new("game.dme"),
            &files,
            &BTreeMap::new(),
            &mut mismatched_digest,
        );
        assert_eq!(exact, changed);
        assert_eq!(
            mismatched_digest.misses, 1,
            "a checksum-valid chunk with incorrect semantic content identity must be rejected"
        );
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn persisted_cache_replays_exact_leaf_expansion() {
        let files = fixture(&[
            ("game.dme", "#define VALUE 7\n#include \"a.dm\"\n"),
            ("a.dm", "/obj/a\n  x = VALUE\n"),
        ]);
        let mut cache = PreprocessCache::default();
        let original =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        let dir =
            std::env::temp_dir().join(format!("dm-preprocess-cache-test-{}", std::process::id()));
        let path = dir.join("cache.json");
        cache.save(&path).unwrap();
        let mut restored = PreprocessCache::load(&path);
        let replayed = preprocess_project_cached(
            Path::new("game.dme"),
            &files,
            &BTreeMap::new(),
            &mut restored,
        );
        assert_eq!(restored.hits, 1);
        assert_eq!(original, replayed);
        std::fs::remove_file(path).unwrap();
        std::fs::remove_dir(dir).unwrap();
    }

    #[test]
    fn file_dirs_keep_active_order_through_leaf_disk_replay() {
        let files = fixture(&[
            ("game.dme", "#define FILE_DIR icons/gen\n#include \"leaf.dm\"\n#define FILE_DIR icons\n#if 0\n#define FILE_DIR ignored\n#endif\n"),
            ("leaf.dm", "#undef FILE_DIR\n#define FILE_DIR sound\n/obj/test\n"),
        ]);
        let mut cache = PreprocessCache::default();
        let original =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert_eq!(
            original.file_dirs,
            [PathBuf::from("sound"), PathBuf::from("icons")]
        );
        let path = std::env::temp_dir().join(format!(
            "dm-file-dir-cache-{}-{}.json",
            std::process::id(),
            CACHE_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        cache.save(&path).unwrap();
        let mut replay = PreprocessCache::load(&path);
        let restored =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut replay);
        assert_eq!(replay.hits, 1);
        assert_eq!(restored.file_dirs, original.file_dirs);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn undef_file_dir_restores_previous_definition() {
        let files = fixture(&[("game.dme", "#define FILE_DIR first\n#define FILE_DIR second\n#undef FILE_DIR\n#ifdef FILE_DIR\n#include \"leaf.dm\"\n#endif\n"), ("leaf.dm", "/obj/active\n")]);
        let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
        assert_eq!(output.file_dirs, [PathBuf::from("first")]);
        assert_eq!(output.final_macros["FILE_DIR"].replacement, "first");
        assert!(output.text.contains("/obj/active"));
    }

    #[test]
    fn cached_undef_file_dir_restores_previous_macro() {
        let files = fixture(&[
            (
                "game.dme",
                "#define FILE_DIR first\n#define FILE_DIR second\n#include \"leaf.dm\"\n",
            ),
            ("leaf.dm", "#undef FILE_DIR\n/obj/active\n"),
        ]);
        let mut cache = PreprocessCache::default();
        let first =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        let second =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert_eq!(first, second);
        assert_eq!(second.final_macros["FILE_DIR"].replacement, "first");
        assert_eq!(second.file_dirs, [PathBuf::from("first")]);
        assert_eq!(cache.hits, 1);
    }

    #[test]
    fn disk_cache_compacts_repeated_origin_paths() {
        let directory = "very_long_worktree_name_".repeat(8);
        let project = format!("{directory}/game.dme");
        let leaf = format!("{directory}/leaf.dm");
        let source = (0..1_000)
            .map(|index| format!("value = {index}\n"))
            .collect::<String>();
        let files = fixture(&[(&project, "#include \"leaf.dm\"\n"), (&leaf, &source)]);
        let mut cache = PreprocessCache::default();
        let original =
            preprocess_project_cached(Path::new(&project), &files, &BTreeMap::new(), &mut cache);
        assert_eq!(original.origins.len(), 1_000);
        let path = std::env::temp_dir().join(format!(
            "dm-compact-origins-{}-{}.json",
            std::process::id(),
            CACHE_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        cache.save(&path).unwrap();
        assert!(std::fs::metadata(&path).unwrap().len() < 100_000);
        let mut restored = PreprocessCache::load(&path);
        let replayed =
            preprocess_project_cached(Path::new(&project), &files, &BTreeMap::new(), &mut restored);
        assert_eq!(restored.hits, 1);
        assert_eq!(replayed, original);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn include_order_and_macro_environment() {
        let fs = fixture(&[("game.dme", "#define NAME one\n#include \"a.dm\"\n#undef NAME\n#define NAME two\n#include \"a.dm\"\n"), ("a.dm", "/obj\n  name = NAME\n")]);
        let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
        assert_eq!(output.text, "/obj\n  name = one\n/obj\n  name = two\n");
        assert_eq!(output.origins.len(), 4);
        assert_eq!(
            output
                .units
                .iter()
                .filter(|u| u.path == Path::new("a.dm"))
                .count(),
            2
        );
        assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    }

    #[test]
    fn conditional_and_function_macro() {
        let fs = fixture(&[("game.dme", "#define FLAG 1\n#define SUM(a,b) (a+b)\n#if defined(FLAG)\n#include \"a.dm\"\n#else\n#include \"missing.dm\"\n#endif\n"), ("a.dm", "var/x = SUM(2, 3)\n")]);
        let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
        assert_eq!(output.text, "var/x = (2+3)\n");
        assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    }

    #[test]
    fn recursive_macro_names_are_disabled_without_copying_the_table() {
        let mut macros = BTreeMap::new();
        for directive in ["SELF SELF", "A B", "B A", "NEST(x) (x+x)"] {
            let (name, definition) = parse_define(directive).unwrap();
            macros.insert(name, definition);
        }
        let location = ExpandLocation {
            file_name: "probe.dm",
            line: 1,
        };
        assert_eq!(expand("SELF", &macros, 0, location).unwrap(), "SELF");
        assert_eq!(expand("A", &macros, 0, location).unwrap(), "A");
        assert_eq!(expand("NEST(2)", &macros, 0, location).unwrap(), "(2+2)");
        assert_eq!(
            expand("NEST(NEST(2))", &macros, 0, location).unwrap(),
            "((2+2)+(2+2))"
        );
    }

    #[test]
    fn infinity_literal_and_raw_string_survive_macro_expansion() {
        let mut macros = BTreeMap::new();
        let (name, definition) = parse_define("INFINITY (1.#INF)").unwrap();
        macros.insert(name, definition);
        let (name, definition) = parse_define("VALUE 42").unwrap();
        macros.insert(name, definition);
        let location = ExpandLocation {
            file_name: "probe.dm",
            line: 1,
        };
        assert_eq!(
            expand("INFINITY", &macros, 0, location).unwrap(),
            "(1.#INF)"
        );
        assert_eq!(
            expand("@\"[VALUE]\\n\"", &macros, 0, location).unwrap(),
            "@\"[VALUE]\\n\""
        );
        assert!(expand("foo #BAD", &macros, 0, location).is_err());
    }

    #[test]
    fn cycle_is_diagnosed_without_recursion() {
        let fs = fixture(&[
            ("game.dme", "#include \"a.dm\"\n"),
            ("a.dm", "#include \"a.dm\"\n"),
        ]);
        let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
        assert!(output
            .diagnostics
            .iter()
            .any(|d| d.message.contains("include cycle")));
    }

    #[test]
    fn unsupported_condition_is_not_silent() {
        let fs = fixture(&[(
            "game.dme",
            "#if foo ? bar : baz\n#include \"a.dm\"\n#endif\n",
        )]);
        let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
        assert!(output
            .diagnostics
            .iter()
            .any(|d| d.message.contains("unsupported #if")));
    }

    #[test]
    fn continued_macro_and_condition_precedence() {
        let fs = fixture(&[("game.dme", "#define FLAG 0x10\n#define ADD(a,b) ((a) + \\\n    (b))\n#if defined FLAG && ((FLAG >> 2) == 4) || 0\n#include \"a.dm\"\n#endif\n"),
            ("a.dm", "var/x = ADD(2, 3)\n")]);
        let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
        assert_eq!(output.text, "var/x = ((2) +     (3))\n");
        assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
        assert_eq!(output.origins[0].source_line, 1);
    }

    #[test]
    fn continued_source_line_origin_is_first_physical_line() {
        let fs = fixture(&[
            ("game.dme", "#include \"a.dm\"\n"),
            ("a.dm", "var/x = 1 \\\n + 2\nvar/y = 3\n"),
        ]);
        let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
        assert_eq!(output.origins[0].source_line, 1);
        assert_eq!(output.origins[1].source_line, 3);
    }

    #[test]
    fn deepquarry_token_paste_and_variadic_macros() {
        let fs = fixture(&[("game.dme", "#define PROC_REF(X) (nameof(.proc/##X))\n#define ICON(I, state, rest...) new /datum/universal_icon(I, state, ##rest)\n#include \"a.dm\"\n"),
            ("a.dm", "var/a = PROC_REF(test)\nvar/b = ICON('a.dmi', \"on\")\nvar/c = ICON('a.dmi', \"on\", 3, 4)\n")]);
        let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
        assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
        assert_eq!(output.text, "var/a = (nameof(.proc/test))\nvar/b = new /datum/universal_icon('a.dmi', \"on\")\nvar/c = new /datum/universal_icon('a.dmi', \"on\",3,4)\n");
    }

    #[test]
    fn block_string_keeps_multiline_text_and_interpolation() {
        let fs = fixture(&[
            ("game.dme", "#define VALUE 9\n#include \"a.dm\"\n"),
            (
                "a.dm",
                "var/output = {\"First [VALUE]\nSecond [foo(\"inside\")]\"}\nvar/after = VALUE\n",
            ),
        ]);
        let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
        assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
        assert!(output.text.contains("First [9]\nSecond [foo(\"inside\")]"));
        assert!(output.text.ends_with("var/after = 9\n"));
        assert_eq!(output.origins.len(), 3);
        assert_eq!(output.origins[1].source_line, 2);
        assert_eq!(output.origins[2].source_line, 3);
    }

    #[test]
    fn nested_missing_include_keeps_its_authored_directive() {
        let fs = fixture(&[("game.dme", "#include \"a.dm\"\n"),
            ("a.dm", "#include \"b.dm\"\n"),
            ("b.dm", "#include \"missing.dm\"\n")]);
        let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
        assert_eq!(output.diagnostics.len(), 1);
        assert_eq!(output.diagnostics[0].path, Path::new("b.dm"));
        assert_eq!(output.diagnostics[0].line, 1);
        assert_eq!(output.diagnostics[0].kind, DiagnosticKind::Include);
        let missing_root = preprocess_project(Path::new("missing.dme"), &fs, &BTreeMap::new());
        assert_eq!(missing_root.diagnostics[0].kind, DiagnosticKind::Io);
    }

    #[test]
    fn diagnostic_kinds_distinguish_includes_macros_and_conditions() {
        let fs = fixture(&[(
            "game.dme",
            "#include \"missing.dm\"\n#define BAD(x..., y) x\n#if x ? y : z\n#endif\n",
        )]);
        let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
        assert!(output
            .diagnostics
            .iter()
            .any(|d| d.kind == DiagnosticKind::Include));
        let missing = output.diagnostics.iter().find(|d| d.kind == DiagnosticKind::Include).unwrap();
        assert_eq!(missing.path, Path::new("game.dme"));
        assert_eq!(missing.line, 1);
        assert!(missing.message.contains("missing.dm"));
        assert!(output
            .diagnostics
            .iter()
            .any(|d| d.kind == DiagnosticKind::Conditional));
        assert!(output
            .diagnostics
            .iter()
            .any(|d| d.kind == DiagnosticKind::Macro));
    }

    #[test]
    fn stringify_arguments_and_expand_inside_interpolation() {
        let fs = fixture(&[
            (
                "game.dme",
                "#define NAMEOF(X) (#X || ##X)\n#define VALUE 7\n#include \"a.dm\"\n",
            ),
            (
                "a.dm",
                "var/a = NAMEOF(foo)\nvar/b = \"Value [VALUE] and [NAMEOF(bar)]\"\n",
            ),
        ]);
        let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
        assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
        assert_eq!(
            output.text,
            "var/a = (\"foo\" ||foo)\nvar/b = \"Value [7] and [(\"bar\" ||bar)]\"\n"
        );
    }
    #[test]
    fn cached_dm_subtree_preserves_deferred_manifest_startup() {
        let files = fixture(&[
            ("game.dme", "#include \"parent.dm\"\n"),
            (
                "parent.dm",
                "#include \"startup.dme\"\n/proc/body()\n return 1\n",
            ),
            (
                "startup.dme",
                "/world/proc/_()\n var/static/_ = world.Genesis()\n",
            ),
        ]);
        let mut cache = PreprocessCache::default();
        let first =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        let repeated =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert_eq!(first, repeated);
        assert!(repeated.text.contains("world.Genesis()"));
        assert_eq!(cache.hits, 1);
    }

    #[test]
    fn included_dme_preserves_active_startup_dm_and_cache_replay() {
        let files = fixture(&[
            ("game.dme", "#define ENABLED 1\n#include \"startup.dme\"\n"),
            ("startup.dme", "#if ENABLED\n/world/proc/_()\n    var/static/_ = world.Genesis()\n#endif\n#if 0\n/proc/inactive()\n#endif\n"),
        ]);
        let mut cache = PreprocessCache::default();
        let first =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert!(first.diagnostics.is_empty());
        assert_eq!(
            first.text,
            "/world/proc/_()\n    var/static/_ = world.Genesis()\n"
        );
        let replay =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert_eq!(first, replay);
        assert!(replay
            .origins
            .iter()
            .all(|origin| origin.path.as_path() == Path::new("startup.dme")));
    }

    #[test]
    fn manifest_dm_is_deferred_but_macros_expand_at_encounter() {
        let files = fixture(&[
            ("game.dme", "#define VALUE 2\n#include \"startup.dme\"\n#include \"second.dme\"\n#include \"body.dm\"\n"),
            ("startup.dme", "/world/proc/_()\n    var/static/late = marker(VALUE)\n"),
            ("second.dme", "/proc/second()\n    var/static/second = marker(3)\n"),
            ("body.dm", "#define VALUE 4\n/proc/early()\n    var/static/early = marker(1)\n"),
        ]);
        let mut cache = PreprocessCache::default();
        let output =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert!(output.diagnostics.is_empty());
        assert_eq!(output.text, "/proc/early()\n    var/static/early = marker(1)\n/world/proc/_()\n    var/static/late = marker(2)\n/proc/second()\n    var/static/second = marker(3)\n");
        assert_eq!(
            output
                .origins
                .iter()
                .map(|origin| origin.output_line)
                .collect::<Vec<_>>(),
            (1..=6).collect::<Vec<_>>()
        );
        assert_eq!(output.origins[2].path.as_path(), Path::new("startup.dme"));
        let replay =
            preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
        assert_eq!(output, replay);
    }
}
