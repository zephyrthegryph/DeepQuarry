use super::*;

/// Bounded reusable file and include-subtree expansions. Exact source identities
/// and incoming macro dependencies gate replay. Leaf units track only relevant
/// transitive macro names; nested units conservatively checkpoint the whole
/// environment and their exact source closure. Entries retain ordered source
/// origins and macro/FILE_DIR side effects rather than copying full macro maps.
#[derive(Default)]
pub struct PreprocessCache {
    pub(super) entries: BTreeMap<PathBuf, Vec<CachedUnit>>,
    pub(super) resident_bytes: usize,
    pub(super) disk: Option<(PathBuf, BTreeMap<PathBuf, Vec<String>>)>,
    pub(super) dirty: BTreeSet<PathBuf>,
    pub hits: usize,
    pub misses: usize,
}

pub(super) struct CachedUnit {
    pub(super) source_digest: [u8; 32],
    pub(super) source_len: usize,
    pub(super) input_digest: [u8; 32],
    pub(super) macro_dependencies: Option<Vec<String>>,
    pub(super) dependencies: BTreeMap<PathBuf, [u8; 32]>,
    pub(super) map_includes: Vec<PathBuf>,
    pub(super) skin_includes: Vec<PathBuf>,
    pub(super) manifest_lines: Vec<(String, PathBuf, usize)>,
    pub(super) output_text: String,
    pub(super) origins: Vec<DiskOrigin>,
    pub(super) units: Vec<Unit>,
    pub(super) unit_digests: Vec<[u8; 32]>,
    pub(super) diagnostics: Vec<Diagnostic>,
    pub(super) macro_changes: BTreeMap<String, Option<Macro>>,
    pub(super) file_dir_changes: Vec<FileDirChange>,
}

pub(super) const CACHE_FORMAT_VERSION: u32 = 10;
pub(super) const MAX_CACHED_LEAF_BYTES: usize = 512 * 1024;
pub(super) const MAX_CACHED_ORIGINS: usize = 8192;
pub(super) const MAX_CACHED_PATHS: usize = 8192;
// Keep the station's current include closure resident across ordinary edits.
pub(super) const MAX_CACHE_RESIDENT_BYTES: usize = 160 * 1024 * 1024;
const MAX_CACHE_FILE_BYTES: u64 = 128 * 1024 * 1024;

pub(super) fn macro_hash(name: &str, definition: &Macro) -> [u8; 32] {
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

pub(super) fn xor_digest(state: &mut [u8; 32], entry: [u8; 32]) {
    for (byte, change) in state.iter_mut().zip(entry) {
        *byte ^= change;
    }
}
pub(super) static CACHE_TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(0);

// Parser/preprocessor fixes must invalidate saved expansions as well as source edits.
fn cache_compiler_fingerprint() -> String {
    static FINGERPRINT: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    FINGERPRINT
        .get_or_init(|| {
            let mut hash = Sha256::new();
            hash.update(include_str!("lib.rs"));
            hash.update(include_str!("cache_items.rs"));
            hash.update(include_str!("project_context.rs"));
            hash.update(include_str!("source_lines.rs"));
            hash.update(include_str!("macro_expansion.rs"));
            hash.update(include_str!("condition_parser.rs"));
            hash.update(include_str!("lib_tests_1.rs"));
            hash.update(include_str!("lib_tests_2.rs"));

            hash.update(include_str!("../../dm-syntax/src/lib.rs"));
            hash.update(include_str!("../../dm-syntax/src/lexer_items.rs"));
            hash.update(include_str!("../../dm-syntax/src/expression_parser.rs"));
            hash.update(include_str!("../../dm-syntax/src/declaration_parser.rs"));
            hash.update(include_str!("../../dm-syntax/src/lib_tests_1.rs"));
            hash.update(include_str!("../../dm-syntax/src/lib_tests_2.rs"));

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
pub(super) struct DiskEntry {
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
pub(super) struct DiskOrigin(
    pub(super) usize,
    pub(super) usize,
    pub(super) Option<PathBuf>,
);

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

    pub(super) fn resident_bytes(&self) -> usize {
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
            .keys()
            .map(|path| path.as_os_str().len() + 96)
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
pub(super) struct CacheIndex {
    pub(super) version: u32,
    pub(super) compiler_fingerprint: String,
    pub(super) entries: BTreeMap<PathBuf, Vec<String>>,
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

    pub(super) fn load_unit(&mut self, path: &Path) {
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
                    let bytes = serde_json::to_vec(&DiskEntry::from(entry))
                        .map_err(|error| error.to_string())?;
                    if bytes.len() > 8 * 1024 * 1024 {
                        continue;
                    }
                    let key = format!("{:x}", Sha256::digest(&bytes));
                    let chunk = directory.join(&key);
                    if !fs::read(&chunk).is_ok_and(|old| old == bytes) {
                        write_atomic(&chunk, &bytes, false)?;
                    }
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
        Ok(())
    }

    pub fn resident_bytes(&self) -> usize {
        self.resident_bytes
    }
    pub(super) fn enforce_budget(&mut self, limit: usize) {
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
