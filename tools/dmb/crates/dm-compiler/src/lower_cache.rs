//! Portable cache of symbolic procedure code, before any DMB table IDs exist.
//! Keys cover the body, bindings, and compiler implementation. Cache failures
//! fall back to normal lowering; they cannot prevent a correct compilation.

use dm_codegen_byond::{
    compile_simple_proc_with_bindings, LowerBindings, LowerError, SharedLowerBindings, SimpleProc,
};
use dm_syntax::Item;
use sha2::{Digest, Sha256};
use std::borrow::Cow;
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

const VERSION: &str = env!("DM_LOWERING_FINGERPRINT");
const MAX_ENTRY_BYTES: usize = 4 * 1024 * 1024;
const MAX_MEMORY_BYTES: usize = 16 * 1024 * 1024;
static TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(0);
const RECORD_MAGIC: &[u8; 8] = b"DMPRC02\0";
const COMPRESSED_RECORD_MAGIC: &[u8; 8] = b"DMPRC03\0";
const RECORD_HEADER_BYTES: usize = 8 + 64 + 64 + 8;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct CacheStats {
    pub hits: usize,
    pub misses: usize,
    pub corrupt_entries: usize,
    pub timing: CacheTiming,
    pub query_timing: QueryTiming,
    pub decoded_bytes: usize,
    pub encoded_bytes: usize,
}

// Totals measure elapsed time inside operations, not a wall-time partition:
// query/flush timings are nested and workers may overlap or be descheduled.
macro_rules! duration_fields {
    ($name:ident { $($field:ident),* $(,)? }) => {
        #[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
        pub struct $name { $(pub $field: Duration,)* }
        impl $name {
            fn add(&mut self, other: Self) { $(self.$field += other.$field;)* }
            fn since(self, before: Self) -> Self {
                Self { $($field: self.$field.saturating_sub(before.$field),)* }
            }
        }
    }
}
duration_fields!(CacheTiming {
    compile,
    identity,
    record_decode,
    memo_decode,
    witness,
    query,
    loose_read,
    memo_encode,
    record_encode,
    retain,
    flush,
});
duration_fields!(QueryTiming {
    total,
    memory_accounting,
    preparation,
    fact_replay,
    candidate_clone,
    candidate_witness,
    fresh_codegen,
    input_body_clone,
    result_clone,
});
impl CacheStats {
    pub(crate) fn merge(&mut self, other: Self) {
        self.hits += other.hits;
        self.misses += other.misses;
        self.corrupt_entries += other.corrupt_entries;
        self.timing.add(other.timing);
        self.query_timing.add(other.query_timing);
        self.decoded_bytes += other.decoded_bytes;
        self.encoded_bytes += other.encoded_bytes;
    }
    pub(crate) fn since(self, before: Self) -> Self {
        Self {
            hits: self.hits.saturating_sub(before.hits),
            misses: self.misses.saturating_sub(before.misses),
            corrupt_entries: self.corrupt_entries.saturating_sub(before.corrupt_entries),
            timing: self.timing.since(before.timing),
            query_timing: self.query_timing.since(before.query_timing),
            decoded_bytes: self.decoded_bytes.saturating_sub(before.decoded_bytes),
            encoded_bytes: self.encoded_bytes.saturating_sub(before.encoded_bytes),
        }
    }
    pub(crate) fn trace(self, label: &str) {
        eprintln!("DM_BUILD_TRACE {label}: {} hits {} misses {} corrupt; decoded {} encoded {} bytes; elapsed cache {:?}; nested query {:?}",
            self.hits, self.misses, self.corrupt_entries, self.decoded_bytes, self.encoded_bytes, self.timing, self.query_timing);
    }
}
#[derive(Clone, Copy)]
pub(crate) struct StageTimer(Option<Instant>);
impl StageTimer {
    pub(crate) fn start(enabled: bool) -> Self {
        Self(enabled.then(Instant::now))
    }
    pub(crate) fn elapsed(self) -> Duration {
        self.0.map_or(Duration::ZERO, |start| start.elapsed())
    }
    pub(crate) fn record(self, total: &mut Duration) {
        *total += self.elapsed();
    }
}
impl QueryTiming {
    #[cfg(test)]
    pub(crate) fn accumulate(&mut self, other: Self) {
        self.add(other);
    }
}

// Keep the serialized procedure bytes directly in the record. Wrapping a
// byte vector in JSON expands it into thousands of decimal integers.
fn encode_record(key: &str, payload: &[u8]) -> Vec<u8> {
    let compressed = lz4_flex::block::compress(payload);
    let (magic, stored) = if compressed.len().saturating_add(64) < payload.len() {
        (COMPRESSED_RECORD_MAGIC, compressed.as_slice())
    } else {
        (RECORD_MAGIC, payload)
    };
    let mut bytes = Vec::with_capacity(RECORD_HEADER_BYTES + stored.len());
    bytes.extend_from_slice(magic);
    bytes.extend_from_slice(key.as_bytes());
    bytes.extend_from_slice(digest(payload).as_bytes());
    bytes.extend_from_slice(&(payload.len() as u64).to_le_bytes());
    bytes.extend_from_slice(stored);
    bytes
}

fn decode_record<'a>(key: &str, bytes: &'a [u8]) -> Option<Cow<'a, [u8]>> {
    if bytes.len() < RECORD_HEADER_BYTES
        || (&bytes[..8] != RECORD_MAGIC && &bytes[..8] != COMPRESSED_RECORD_MAGIC)
        || &bytes[8..72] != key.as_bytes()
        || bytes.len() - RECORD_HEADER_BYTES > MAX_ENTRY_BYTES
    {
        return None;
    }
    let length = u64::from_le_bytes(bytes[136..144].try_into().ok()?);
    if length > MAX_ENTRY_BYTES as u64 {
        return None;
    }
    let stored = &bytes[RECORD_HEADER_BYTES..];
    let payload = if &bytes[..8] == COMPRESSED_RECORD_MAGIC {
        // The declared expansion size is checked before allocation; never trust
        // a size prefix inside a corrupt compressed stream.
        let mut decoded = vec![0; length as usize];
        if lz4_flex::block::decompress_into(stored, &mut decoded).ok()? != decoded.len() {
            return None;
        }
        Cow::Owned(decoded)
    } else {
        if stored.len() as u64 != length {
            return None;
        }
        Cow::Borrowed(stored)
    };
    (&bytes[72..136] == digest(payload.as_ref()).as_bytes()).then_some(payload)
}

#[derive(Default)]
struct SymbolicSnapshot {
    records: BTreeMap<String, Vec<u8>>,
    missing: std::collections::BTreeSet<String>,
    bytes: usize,
}

pub struct ProcLoweringCache {
    root: Option<PathBuf>,
    memory: BTreeMap<String, Vec<u8>>,
    memory_bytes: usize,
    stats: CacheStats,
    store: Option<dm_store::Store>,
    snapshot: std::sync::Arc<std::sync::OnceLock<std::sync::Mutex<SymbolicSnapshot>>>,
    pending: BTreeMap<String, Vec<u8>>,
    pending_bytes: usize,
    profiling: bool,
    legacy_loose: bool,
    disk_ready: bool,
}

/// Put portable artifacts in Git's common directory so all worktrees share
/// them. Standalone projects keep the cache beside their DME.
pub fn project_cache_root(project: &Path) -> PathBuf {
    if let Some(root) = std::env::var_os("DM_COMPILER_CACHE_ROOT") {
        return PathBuf::from(root);
    }
    let absolute = fs::canonicalize(project).unwrap_or_else(|_| {
        if project.is_absolute() {
            project.to_path_buf()
        } else {
            std::env::current_dir()
                .unwrap_or_else(|_| PathBuf::from("."))
                .join(project)
        }
    });
    let directory = absolute.parent().unwrap_or_else(|| Path::new("."));
    let common = Command::new("git")
        .args(["rev-parse", "--git-common-dir"])
        .current_dir(directory)
        .output()
        .ok()
        .filter(|r| r.status.success())
        .and_then(|r| String::from_utf8(r.stdout).ok())
        .map(|r| r.trim().to_owned())
        .filter(|r| !r.is_empty());
    let root = match common {
        Some(common) => {
            let path = PathBuf::from(common);
            let path = if path.is_absolute() {
                path
            } else {
                directory.join(path)
            };
            fs::canonicalize(&path)
                .unwrap_or(path)
                .join("dm-compiled-cache")
        }
        None => directory.join(".dm-cache"),
    };
    root
}

pub fn default_cache_root(project: &Path) -> PathBuf {
    project_cache_root(project).join("proc-lowering-v1")
}

impl ProcLoweringCache {
    pub fn disabled() -> Self {
        Self {
            root: None,
            memory: BTreeMap::new(),
            memory_bytes: 0,
            stats: CacheStats::default(),
            store: None,
            snapshot: Default::default(),
            pending: BTreeMap::new(),
            pending_bytes: 0,
            profiling: std::env::var_os("DM_BUILD_TRACE").is_some(),
            legacy_loose: false,
            disk_ready: false,
        }
    }

    pub fn open(root: PathBuf) -> Self {
        let root = fs::create_dir_all(&root).ok().map(|()| root);
        let mut cache = Self::disabled();
        cache.legacy_loose = root.as_ref().is_some_and(|root| fs::read_dir(root).ok().is_some_and(|entries| entries.flatten().any(|entry| {
            let name=entry.file_name();let name=name.to_string_lossy();
            name.len()==2 && name.bytes().all(|byte|byte.is_ascii_hexdigit()) && entry.file_type().is_ok_and(|kind|kind.is_dir())
        })));
        cache.root = root;
        if let Some(root) = &cache.root {
            if let Ok(store) = dm_store::Store::open(root.join("symbolic.redb")) {
                cache.disk_ready=store.read_many(&[dm_store::Key::new("symbolic-requested-ready",VERSION)],None).ok().is_some_and(|read|read.values.first().is_some_and(Option::is_some));
                cache.store = Some(store);
            }
        }
        cache
    }
    fn namespace() -> String {
        format!("symbolic-lowering-{VERSION}")
    }
    /// Worker-local portable overlays share one lazily loaded immutable stage
    /// snapshot. Prepared graph hits do not touch the symbolic namespace.
    pub fn fork(&self) -> Self {
        let mut cache = Self::disabled();
        cache.root = self.root.clone();
        cache.store = self.store.clone();
        cache.snapshot = std::sync::Arc::clone(&self.snapshot);
        cache.profiling = self.profiling;
        cache.legacy_loose = self.legacy_loose;
        cache.disk_ready = self.disk_ready;
        cache
    }
    /// Compatibility signal: reads now use requested-key snapshots only.
    pub fn snapshot_complete(&self) -> bool {
        self.snapshot.get_or_init(||std::sync::Mutex::new(SymbolicSnapshot::default()));
        self.store.is_some()
    }
    pub(crate) fn prefetch_keys(&self, keys:&[String]) {
        let Some(store)=&self.store else {return;};
        if !self.disk_ready {return;}
        let mut requested=self.snapshot.get_or_init(||std::sync::Mutex::new(SymbolicSnapshot::default()))
            .lock().unwrap_or_else(|error|error.into_inner());
        let keys:Vec<_>=keys.iter().filter(|key|!requested.records.contains_key(*key)&&!requested.missing.contains(*key))
            .map(|key|dm_store::Key::new(Self::namespace(),key)).collect();
        for keys in keys.chunks(4096) {
            let Ok(read)=store.read_grouped_bounded(keys,128,MAX_ENTRY_BYTES+RECORD_HEADER_BYTES,16*1024*1024,64*1024*1024,None) else {continue;};
            for (key,bytes) in keys.iter().zip(read.values) {
                if let Some(bytes)=bytes {
                    while requested.bytes.saturating_add(bytes.len())>64*1024*1024 {
                        let Some(old)=requested.records.keys().next().cloned() else {break;};
                        if let Some(bytes)=requested.records.remove(&old) {requested.bytes=requested.bytes.saturating_sub(bytes.len());}
                    }
                    if bytes.len()<=64*1024*1024 {requested.bytes+=bytes.len();requested.records.insert(key.name.clone(),bytes);}
                } else if requested.missing.len()<128_000 {requested.missing.insert(key.name.clone());}
            }
        }
    }
    /// Persist one bounded accumulated batch. No database is opened by `compile`.
    pub fn flush(&mut self) -> std::io::Result<()> {
        let timer = StageTimer::start(self.profiling);
        let result = self.flush_inner();
        timer.record(&mut self.stats.timing.flush);
        result
    }
    fn flush_inner(&mut self) -> std::io::Result<()> {
        if self.pending.is_empty() {
            return Ok(());
        }
        let Some(store) = &self.store else {
            return Ok(());
        };
        let mut changes = self
            .pending
            .iter()
            .map(|(key, bytes)| {
                dm_store::Change::Put(dm_store::Key::new(Self::namespace(), key), bytes.clone())
            })
            .collect::<Vec<_>>();
        changes.push(dm_store::Change::Put(dm_store::Key::new("symbolic-requested-ready",VERSION),vec![1]));
        match store.commit(&[], &changes, None)? {
            dm_store::Commit::Applied => {
                self.pending.clear();
                self.pending_bytes = 0;
                Ok(())
            }
            dm_store::Commit::Conflict => Err(std::io::Error::other(
                "unexpected unwitnessed cache conflict",
            )),
        }
    }
    fn buffer(&mut self, key: String, record: Vec<u8>) {
        if record.len() > MAX_MEMORY_BYTES {
            return;
        }
        let old = self.pending.get(&key).map_or(0, Vec::len);
        if self.pending_bytes - old + record.len() > MAX_MEMORY_BYTES
            || self.pending.len() >= 64_000
        {
            if self.flush().is_err() {
                return;
            }
        }
        let bytes = record.len();
        if let Some(old) = self.pending.insert(key, record) {
            self.pending_bytes -= old.len();
        }
        self.pending_bytes += bytes;
    }

    pub fn stats(&self) -> CacheStats {
        self.stats
    }

    pub(crate) fn merge_stats(&mut self, stats: CacheStats) {
        self.stats.merge(stats);
    }

    pub(crate) fn profiling_enabled(&self) -> bool {
        self.profiling
    }
    pub(crate) fn hits_count(&self) -> usize {
        self.stats.hits
    }

    pub(crate) fn cache_root(&self) -> Option<&Path> {
        self.root.as_deref()
    }

    pub fn compile(
        &mut self,
        body: &[Item],
        bindings: &LowerBindings,
    ) -> Result<SimpleProc, Vec<LowerError>> {
        self.compile_memo(body, bindings).map(|memo| memo.procedure)
    }

    /// Keeps the actual positive and negative semantic reads for installation
    /// into a long-lived project graph. Portable candidates are still validated
    /// against the supplied immutable invocation frame before being returned.
    pub fn compile_memo(
        &mut self,
        body: &[Item],
        bindings: &LowerBindings,
    ) -> Result<crate::ProcedureMemo, Vec<LowerError>> {
        let timer = StageTimer::start(self.profiling);
        let result = self.compile_inner(body, bindings);
        timer.record(&mut self.stats.timing.compile);
        result
    }
    fn compile_inner(
        &mut self,
        body: &[Item],
        bindings: &LowerBindings,
    ) -> Result<crate::ProcedureMemo, Vec<LowerError>> {
        if self.root.is_none() {
            self.stats.misses += 1;
            return self.query(body, bindings);
        }
        let timer = StageTimer::start(self.profiling);
        let key = identity_key(body, bindings);
        timer.record(&mut self.stats.timing.identity);
        if let Some(payload) = self.memory.get(&key) {
            let timer = StageTimer::start(self.profiling);
            let memo = serde_json::from_slice::<crate::semantic_queries::SemanticMemo>(payload);
            self.stats.decoded_bytes += payload.len();
            timer.record(&mut self.stats.timing.memo_decode);
            if let Ok(memo) = memo {
                if self.valid_memo(&memo, bindings) {
                    self.stats.hits += 1;
                    return Ok(memo);
                }
            }
        }
        self.prefetch_keys(std::slice::from_ref(&key));
        let record=self.snapshot.get().and_then(|snapshot|snapshot.lock().ok())
            .and_then(|snapshot|snapshot.records.get(&key).cloned());
        if let Some(record) = record.as_ref() {
            let timer = StageTimer::start(self.profiling);
            let payload = decode_record(&key, record);
            timer.record(&mut self.stats.timing.record_decode);
            let timer = StageTimer::start(self.profiling);
            let cached = payload.and_then(|payload| {
                self.stats.decoded_bytes += payload.len();
                serde_json::from_slice::<crate::semantic_queries::SemanticMemo>(payload.as_ref())
                    .ok()
            });
            timer.record(&mut self.stats.timing.memo_decode);
            if let Some(memo) = cached {
                if self.valid_memo(&memo, bindings) {
                    self.stats.hits += 1;
                    return Ok(memo);
                }
            } else {
                self.stats.corrupt_entries += 1;
            }
        }
        let path = self.root.as_ref().unwrap().join(&key[..2]).join(&key);
        let timer = StageTimer::start(self.profiling);
        let file = if self.legacy_loose {fs::File::open(&path)} else {Err(std::io::Error::from(std::io::ErrorKind::NotFound))};
        if let Ok(file) = file {
            // Bound the read even for corrupt records. A separate metadata
            // request doubles filesystem operations across large projects.
            let mut bytes = Vec::new();
            let read = file
                .take((MAX_ENTRY_BYTES + RECORD_HEADER_BYTES + 1) as u64)
                .read_to_end(&mut bytes)
                .ok()
                .filter(|_| bytes.len() <= MAX_ENTRY_BYTES + RECORD_HEADER_BYTES);
            timer.record(&mut self.stats.timing.loose_read);
            let timer = StageTimer::start(self.profiling);
            let payload = read.and_then(|_| decode_record(&key, &bytes));
            timer.record(&mut self.stats.timing.record_decode);
            let timer = StageTimer::start(self.profiling);
            let cached = payload.and_then(|payload| {
                self.stats.decoded_bytes += payload.len();
                serde_json::from_slice::<crate::semantic_queries::SemanticMemo>(payload.as_ref())
                    .ok()
                    .map(|memo| (memo, payload.to_vec()))
            });
            timer.record(&mut self.stats.timing.memo_decode);
            if let Some((memo, payload)) = cached {
                if self.valid_memo(&memo, bindings) {
                    if self.store.is_some() {
                        let timer = StageTimer::start(self.profiling);
                        let bytes = encode_record(&key, &payload);
                        timer.record(&mut self.stats.timing.record_encode);
                        self.buffer(key.clone(), bytes);
                    }
                    self.remember(key, payload);
                    self.stats.hits += 1;
                    return Ok(memo);
                }
            } else {
                self.stats.corrupt_entries += 1;
            }
        } else {
            timer.record(&mut self.stats.timing.loose_read);
        }
        self.stats.misses += 1;
        let memo = self.query(body, bindings)?;
        let timer = StageTimer::start(self.profiling);
        let payload = serde_json::to_vec(&memo);
        timer.record(&mut self.stats.timing.memo_encode);
        if let Ok(payload) = payload {
            self.stats.encoded_bytes += payload.len();
            if payload.len() <= MAX_ENTRY_BYTES {
                let timer = StageTimer::start(self.profiling);
                let bytes = encode_record(&key, &payload);
                timer.record(&mut self.stats.timing.record_encode);
                if self.store.is_some() {
                    self.buffer(key.clone(), bytes);
                } else {
                    let _ = atomic_write(&path, &bytes);
                }
                self.remember(key, payload);
            }
        }
        Ok(memo)
    }

    fn valid_memo(
        &mut self,
        memo: &crate::semantic_queries::SemanticMemo,
        bindings: &LowerBindings,
    ) -> bool {
        let timer = StageTimer::start(self.profiling);
        let valid = memo.valid_for(bindings);
        timer.record(&mut self.stats.timing.witness);
        valid
    }
    /// Fresh portable production has no live dependency graph. The project
    /// graph owns tracked inputs; this adapter returns only actual read facts.
    fn query(
        &mut self,
        body: &[Item],
        bindings: &LowerBindings,
    ) -> Result<crate::semantic_queries::SemanticMemo, Vec<LowerError>> {
        let timer = StageTimer::start(self.profiling);
        let codegen = StageTimer::start(self.profiling);
        let (result, dependencies) = dm_codegen_byond::capture_binding_reads(|| {
            compile_simple_proc_with_bindings(body, bindings)
        });
        codegen.record(&mut self.stats.query_timing.fresh_codegen);
        let result = result.map(|procedure| crate::ProcedureMemo {
            procedure,
            dependencies,
        });
        let elapsed = timer.elapsed();
        self.stats.query_timing.total += elapsed;
        self.stats.timing.query += elapsed;
        result
    }

    fn remember(&mut self, key: String, payload: Vec<u8>) {
        let timer = StageTimer::start(self.profiling);
        if payload.len() > MAX_MEMORY_BYTES {
            return;
        }
        while self.memory_bytes + payload.len() > MAX_MEMORY_BYTES {
            let Some((_, bytes)) = self.memory.pop_first() else {
                break;
            };
            self.memory_bytes -= bytes.len();
        }
        self.memory_bytes += payload.len();
        if let Some(old) = self.memory.insert(key, payload) {
            self.memory_bytes -= old.len();
        }
        timer.record(&mut self.stats.timing.retain);
    }
}

impl Drop for ProcLoweringCache {
    fn drop(&mut self) {
        if let Err(error) = self.flush() {
            if std::env::var_os("DM_BUILD_TRACE").is_some() {
                eprintln!("symbolic store cache flush failed: {error}");
            }
        }
    }
}

fn digest(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

/// Source and invocation frame identify a candidate, while actual recorded
/// semantic reads determine whether that candidate is valid in this skeleton.
fn identity_key(body: &[Item], bindings: &LowerBindings) -> String {
    let mut hash = Sha256::new();
    hash.update(b"dm-observed-symbolic-proc-v3\0");
    hash.update(VERSION.as_bytes());
    hash_items(&mut hash, body);
    let spans = dm_codegen_byond::debug::relative_body_span_shape(body);
    hash.update((spans.len() as u64).to_le_bytes());
    for span in spans {
        for offset in span {
            hash.update(offset.to_le_bytes());
        }
    }
    let value = serde_json::json!({
        "current_proc_path": bindings.current_proc_path,
        "current_type_path": bindings.current_type_path,
        "parameters": bindings.parameters,
        "parameter_type_flags": bindings.parameter_type_flags,
        "parameter_value_sources": bindings.parameter_value_sources,
        "parameter_defaults": bindings.parameter_defaults,
        "parameter_types": bindings.parameter_types,
    });
    hash_json(&mut hash, &value);
    format!("{:x}", hash.finalize())
}

/// Canonical shared-context identity computed once when building a project.
pub fn shared_binding_fingerprint<T: serde::Serialize>(bindings: &T) -> String {
    let mut hash = Sha256::new();
    let value = serde_json::to_value(bindings).expect("shared bindings are serializable");
    hash_json(&mut hash, &value);
    format!("{:x}", hash.finalize())
}

/// Prepare member dependencies once rather than serializing the project index
/// for every procedure. Adding an unrelated member preserves existing keys.
pub fn prepare_member_type_fingerprints(bindings: &mut SharedLowerBindings) {
    let ancestry = shared_binding_fingerprint(&bindings.parent_types);
    let mut members: BTreeMap<
        &str,
        (
            BTreeMap<&str, &str>,
            BTreeMap<&str, &str>,
            BTreeMap<&str, &str>,
            BTreeSet<&str>,
            BTreeMap<&str, &str>,
            BTreeSet<&str>,
        ),
    > = BTreeMap::new();
    for (class, fields) in &bindings.member_types {
        for (name, declared_type) in fields {
            members
                .entry(name)
                .or_default()
                .0
                .insert(class, declared_type);
        }
    }
    for (class, procedures) in &bindings.member_procs {
        for (name, path) in procedures {
            members.entry(name).or_default().1.insert(class, path);
        }
    }
    for (class, procedures) in &bindings.known_member_procs {
        for name in procedures {
            members.entry(name).or_default().3.insert(class);
        }
    }
    for (class, globals) in &bindings.member_globals {
        for (name, symbol) in globals {
            members.entry(name).or_default().4.insert(class, symbol);
        }
    }
    for (class, fields) in &bindings.known_member_fields {
        for name in fields {
            members.entry(name).or_default().5.insert(class);
        }
    }
    for (alias, base) in &bindings.modified_instances {
        let name = alias.rsplit('/').next().unwrap_or(alias);
        members.entry(name).or_default().2.insert(alias, base);
    }
    bindings.member_type_fingerprints = members
        .into_iter()
        .map(|(name, declarations)| {
            let mut hash = Sha256::new();
            hash.update(ancestry.as_bytes());
            hash.update(shared_binding_fingerprint(&declarations).as_bytes());
            (name.to_owned(), format!("{:x}", hash.finalize()))
        })
        .collect();
}

#[cfg(test)]
fn cache_key(body: &[Item], bindings: &LowerBindings) -> String {
    let mut hash = Sha256::new();
    hash.update(b"dm-symbolic-proc-v1\0");
    hash.update(VERSION.as_bytes());
    hash_items(&mut hash, body);
    // A declaration added in another worktree must not invalidate every proc.
    // Include positive and negative lookups for every identifier-like spelling
    // in the body/defaults, including interpolation text. Literal text adds
    // conservative dependencies but cannot hide a real name lookup.
    let mut names = BTreeSet::new();
    collect_names(body, &mut names);
    for default in bindings.parameter_defaults.iter().flatten() {
        collect_text_names(default, &mut names);
    }
    let shared = bindings.shared.as_deref();
    for name in names {
        hash_optional_bytes(&mut hash, Some(name.as_bytes()));
        // Public callers can construct bindings directly without the project
        // indexing pass. Preserve correctness for those smaller contexts too.
        let fallback_member_digest = shared
            .filter(|s| {
                s.member_type_fingerprints.is_empty()
                    && (!s.member_types.is_empty()
                        || !s.member_procs.is_empty()
                        || !s.modified_instances.is_empty()
                        || !s.known_member_procs.is_empty()
                        || !s.member_globals.is_empty()
                        || !s.known_member_fields.is_empty())
            })
            .and_then(|s| {
                let declarations: BTreeMap<&str, &str> = s
                    .member_types
                    .iter()
                    .filter_map(|(class, members)| {
                        members
                            .get(name)
                            .map(|declared_type| (class.as_str(), declared_type.as_str()))
                    })
                    .collect();
                let procedures: BTreeMap<&str, &str> = s
                    .member_procs
                    .iter()
                    .filter_map(|(class, members)| {
                        members
                            .get(name)
                            .map(|path| (class.as_str(), path.as_str()))
                    })
                    .collect();
                let instances: BTreeMap<&str, &str> = s
                    .modified_instances
                    .iter()
                    .filter(|(alias, _)| alias.rsplit('/').next() == Some(name))
                    .map(|(alias, base)| (alias.as_str(), base.as_str()))
                    .collect();
                let known: BTreeSet<&str> = s
                    .known_member_procs
                    .iter()
                    .filter(|(_, names)| names.contains(name))
                    .map(|(class, _)| class.as_str())
                    .collect();
                let globals: BTreeMap<&str, &str> = s
                    .member_globals
                    .iter()
                    .filter_map(|(class, members)| {
                        members
                            .get(name)
                            .map(|symbol| (class.as_str(), symbol.as_str()))
                    })
                    .collect();
                let fields: BTreeSet<&str> = s
                    .known_member_fields
                    .iter()
                    .filter(|(_, names)| names.contains(name))
                    .map(|(class, _)| class.as_str())
                    .collect();
                if declarations.is_empty()
                    && procedures.is_empty()
                    && instances.is_empty()
                    && known.is_empty()
                    && globals.is_empty()
                    && fields.is_empty()
                {
                    return None;
                }
                let mut hash = Sha256::new();
                hash.update(shared_binding_fingerprint(&s.parent_types).as_bytes());
                hash.update(
                    shared_binding_fingerprint(&(
                        declarations,
                        procedures,
                        instances,
                        known,
                        globals,
                        fields,
                    ))
                    .as_bytes(),
                );
                Some(format!("{:x}", hash.finalize()))
            });
        hash_optional_bytes(
            &mut hash,
            shared
                .and_then(|s| s.member_type_fingerprints.get(name))
                .or(fallback_member_digest.as_ref())
                .map(|s| s.as_bytes()),
        );
        hash.update([
            u8::from(
                bindings.binding_fact(&dm_codegen_byond::BindingFact::Field(name.to_owned()))
                    == dm_codegen_byond::FactValue::Boolean(true),
            ),
            u8::from(
                bindings.globals.contains(name) || shared.is_some_and(|s| s.globals.contains(name)),
            ),
            u8::from(
                bindings.global_procs.contains(name)
                    || shared.is_some_and(|s| s.global_procs.contains(name)),
            ),
        ]);
        let field_type =
            bindings.binding_fact(&dm_codegen_byond::BindingFact::FieldType(name.to_owned()));
        hash_optional_bytes(
            &mut hash,
            match &field_type {
                dm_codegen_byond::FactValue::Text(value) => Some(value.as_bytes()),
                _ => None,
            },
        );
        hash_optional_bytes(
            &mut hash,
            bindings
                .global_types
                .get(name)
                .or_else(|| shared?.global_types.get(name))
                .map(|s| s.as_bytes()),
        );
        let number = shared.and_then(|s| s.numeric_constants.get(name));
        hash.update([u8::from(number.is_some())]);
        if let Some(number) = number {
            hash.update(number.to_le_bytes());
        }
        hash_optional_bytes(
            &mut hash,
            shared
                .and_then(|s| s.string_constants.get(name))
                .map(|s| s.as_bytes()),
        );
    }
    // JSON object maps from HashMap are normalized before hashing. No source
    // offsets, filesystem paths, or session-local IDs enter this key.
    // Dependency overlays were hashed selectively above. Do not serialize
    // thousands of unrelated names just to discard those fields afterwards.
    // Exhaustive destructuring makes additions to LowerBindings require an
    // explicit cache-key decision here.
    let LowerBindings {
        current_proc_path,
        current_type_path,
        parameters,
        parameter_type_flags,
        parameter_value_sources,
        parameter_defaults,
        parameter_types,
        fields: _,
        globals: _,
        field_types: _,
        owner: _,
        hidden_owner_fields: _,
        global_types: _,
        global_procs: _,
        shared: _,
        prepared_member_globals: _,
    } = bindings;
    let value = serde_json::json!({
        "current_proc_path": current_proc_path,
        "current_type_path": current_type_path,
        "parameters": parameters,
        "parameter_type_flags": parameter_type_flags,
        "parameter_value_sources": parameter_value_sources,
        "parameter_defaults": parameter_defaults,
        "parameter_types": parameter_types,
    });
    hash_json(&mut hash, &value);
    format!("{:x}", hash.finalize())
}

#[cfg(test)]
fn hash_optional_bytes(hash: &mut Sha256, bytes: Option<&[u8]>) {
    hash.update([u8::from(bytes.is_some())]);
    if let Some(bytes) = bytes {
        hash.update((bytes.len() as u64).to_le_bytes());
        hash.update(bytes);
    }
}

#[cfg(test)]
fn collect_text_names<'a>(text: &'a str, names: &mut BTreeSet<&'a str>) {
    let mut start = None;
    for (offset, c) in text.char_indices() {
        if c == '_' || c.is_alphabetic() || (start.is_some() && c.is_alphanumeric()) {
            start.get_or_insert(offset);
        } else if let Some(start) = start.take() {
            names.insert(&text[start..offset]);
        }
    }
    if let Some(start) = start {
        names.insert(&text[start..]);
    }
}

#[cfg(test)]
fn collect_names<'a>(body: &'a [Item], names: &mut BTreeSet<&'a str>) {
    for item in body {
        collect_text_names(&item.header, names);
        collect_names(&item.children, names);
    }
}

fn hash_items(hash: &mut Sha256, items: &[Item]) {
    hash.update((items.len() as u64).to_le_bytes());
    for item in items {
        hash.update([item.kind as u8]);
        hash.update((item.header.len() as u64).to_le_bytes());
        hash.update(item.header.as_bytes());
        hash_items(hash, &item.children);
    }
}

fn hash_json(hash: &mut Sha256, value: &serde_json::Value) {
    match value {
        serde_json::Value::Object(map) => {
            hash.update(b"object\0");
            hash.update((map.len() as u64).to_le_bytes());
            for (key, value) in map.iter().collect::<BTreeMap<_, _>>() {
                hash.update((key.len() as u64).to_le_bytes());
                hash.update(key.as_bytes());
                hash_json(hash, value);
            }
        }
        serde_json::Value::Array(values) => {
            hash.update(b"array\0");
            hash.update((values.len() as u64).to_le_bytes());
            for value in values {
                hash_json(hash, value);
            }
        }
        _ => {
            let bytes = serde_json::to_vec(value).unwrap();
            hash.update((bytes.len() as u64).to_le_bytes());
            hash.update(bytes);
        }
    }
}

fn atomic_write(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let parent = path.parent().unwrap();
    fs::create_dir_all(parent)?;
    let temporary = parent.join(format!(
        ".proc-{}-{}.tmp",
        std::process::id(),
        TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
    ));
    let result = (|| {
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)?;
        file.write_all(bytes)?;
        // These are disposable derived records, verified before every reuse.
        // Closing before rename publishes a complete file to other processes;
        // a power-loss truncation falls back to lowering. Avoid one disk barrier
        // per procedure when a large project populates tens of thousands.
        drop(file);
        fs::rename(&temporary, path)
    })();
    if result.is_err() {
        let _ = fs::remove_file(temporary);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_syntax::{parse, Span};

    #[test]
    fn profiling_preserves_output_and_disabled_clocks_remain_zero() {
        let body = parse("/proc/value()\n    var/list/items = list(1, 2)\n    return items[1]\n")
            .items
            .remove(0)
            .children;
        let bindings = LowerBindings::default();
        let mut plain = ProcLoweringCache::disabled();
        plain.profiling = false;
        let expected = plain.compile(&body, &bindings).unwrap();
        assert_eq!(plain.stats().timing, CacheTiming::default());
        assert_eq!(plain.stats().query_timing, QueryTiming::default());
        let mut traced = ProcLoweringCache::disabled();
        traced.profiling = true;
        assert_eq!(traced.compile(&body, &bindings).unwrap(), expected);
        assert!(traced.stats().timing.compile > Duration::ZERO);
        assert!(traced.stats().query_timing.fresh_codegen > Duration::ZERO);
    }

    #[test]
    fn portable_memo_hits_return_validated_reads_without_secondary_query_clones() {
        let root = std::env::temp_dir().join(format!(
            "dm-portable-only-{}-{}",
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        let body = parse("/proc/test()\n    return value\n")
            .items
            .remove(0)
            .children;
        let mut bindings = LowerBindings {
            globals: ["value".into()].into(),
            ..Default::default()
        };
        let mut cache = ProcLoweringCache::open(root.clone());
        cache.profiling = true;
        let first = cache.compile_memo(&body, &bindings).unwrap();
        assert!(first.valid_for(&bindings));
        let codegen = cache.stats().query_timing.fresh_codegen;
        bindings.globals.insert("unrelated".into());
        assert_eq!(cache.compile_memo(&body, &bindings).unwrap(), first);
        assert_eq!(cache.stats().hits, 1);
        assert_eq!(cache.stats().query_timing.fresh_codegen, codegen);
        bindings.globals.remove("value");
        bindings.fields.insert("value".into());
        assert!(!first.valid_for(&bindings));
        let changed = cache.compile_memo(&body, &bindings).unwrap();
        assert!(changed.valid_for(&bindings));
        assert_ne!(changed.procedure, first.procedure);
        assert_eq!(cache.stats().misses, 2);
        let timing = cache.stats().query_timing;
        assert!(timing.fresh_codegen > codegen);
        assert_eq!(timing.input_body_clone, Duration::ZERO);
        assert_eq!(timing.result_clone, Duration::ZERO);
        assert_eq!(timing.candidate_clone, Duration::ZERO);
        assert_eq!(timing.fact_replay, Duration::ZERO);
        drop(cache);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn borrowed_names_match_owned_identifier_classification_and_order() {
        fn owned_names(text: &str) -> BTreeSet<String> {
            let mut names = BTreeSet::new();
            let mut name = String::new();
            for c in text.chars() {
                if c == '_' || c.is_alphabetic() || (!name.is_empty() && c.is_alphanumeric()) {
                    name.push(c);
                } else if !name.is_empty() {
                    names.insert(std::mem::take(&mut name));
                }
            }
            if !name.is_empty() {
                names.insert(name);
            }
            names
        }
        let mut text = String::from(
            "/obj/item/proc/example(foo_2, αβ = 3, é = \"[foo_2]\") foo_2 foo_2 123abc abc123 _ ²name name² e\u{301} 'icons/path.dmi'\n",
        );
        let mut state = 17u32;
        for _ in 0..8192 {
            state = state.wrapping_mul(1664525).wrapping_add(1013904223);
            if let Some(c) = char::from_u32(state % 0x110000) {
                text.push(c);
            }
        }
        let expected = owned_names(&text);
        let mut actual = BTreeSet::new();
        collect_text_names(&text, &mut actual);
        assert_eq!(
            actual.iter().copied().collect::<Vec<_>>(),
            expected.iter().map(String::as_str).collect::<Vec<_>>()
        );
        for name in actual {
            let start = name.as_ptr() as usize;
            assert!(start >= text.as_ptr() as usize);
            assert!(start + name.len() <= text.as_ptr() as usize + text.len());
        }
    }

    #[test]
    fn framed_records_reject_wrong_keys_torn_payloads_and_corruption() {
        let key = digest(b"procedure identity");
        let payload = b"{\"value\":7}";
        let bytes = encode_record(&key, payload);
        assert_eq!(bytes.len(), RECORD_HEADER_BYTES + payload.len());
        assert_eq!(
            decode_record(&key, &bytes).as_deref(),
            Some(payload.as_slice())
        );
        assert!(decode_record(&digest(b"another procedure"), &bytes).is_none());
        assert!(decode_record(&key, &bytes[..bytes.len() - 1]).is_none());
        let mut corrupt = bytes.clone();
        *corrupt.last_mut().unwrap() ^= 1;
        assert!(decode_record(&key, &corrupt).is_none());
        let mut excessive = bytes;
        excessive[136..144].copy_from_slice(&u64::MAX.to_le_bytes());
        assert!(decode_record(&key, &excessive).is_none());
    }

    #[test]
    fn compressed_memos_validate_identity_checksum_and_expansion_bound() {
        let key = digest(b"large symbolic procedure");
        let payload = b"{\"instruction\":\"PushNull\",\"arguments\":[],\"origin\":0}".repeat(2048);
        let bytes = encode_record(&key, &payload);
        assert_eq!(&bytes[..8], COMPRESSED_RECORD_MAGIC);
        assert!(bytes.len() * 8 < payload.len());
        assert_eq!(
            decode_record(&key, &bytes).as_deref(),
            Some(payload.as_slice())
        );
        assert!(decode_record(&digest(b"other"), &bytes).is_none());
        let mut checksum = bytes.clone();
        checksum[72] ^= 1;
        assert!(decode_record(&key, &checksum).is_none());
        let mut oversized = bytes.clone();
        oversized[136..144].copy_from_slice(&((MAX_ENTRY_BYTES as u64) + 1).to_le_bytes());
        assert!(decode_record(&key, &oversized).is_none());
        let mut undersized = bytes.clone();
        undersized[136..144].copy_from_slice(&1u64.to_le_bytes());
        assert!(decode_record(&key, &undersized).is_none());
        assert!(decode_record(&key, &bytes[..bytes.len() - 1]).is_none());
    }

    #[test]
    fn typed_method_dispatch_dependencies_invalidate_cached_calls() {
        use std::sync::Arc;
        let body = parse("/proc/test()\n    return receiver.method()\n")
            .items
            .remove(0)
            .children;
        let mut shared = SharedLowerBindings::default();
        shared.member_procs.insert(
            "/datum/receiver".into(),
            [("method".into(), "/datum/base/proc/method".into())].into(),
        );
        let bindings = |context| LowerBindings {
            shared: Some(Arc::new(context)),
            ..Default::default()
        };
        let unprepared = bindings(shared.clone());
        prepare_member_type_fingerprints(&mut shared);
        let original = bindings(shared.clone());
        assert_eq!(cache_key(&body, &unprepared), cache_key(&body, &original));
        shared
            .member_procs
            .get_mut("/datum/receiver")
            .unwrap()
            .insert("unrelated".into(), "/datum/receiver/proc/unrelated".into());
        prepare_member_type_fingerprints(&mut shared);
        assert_eq!(
            cache_key(&body, &original),
            cache_key(&body, &bindings(shared.clone()))
        );
        shared
            .member_procs
            .get_mut("/datum/receiver")
            .unwrap()
            .insert("method".into(), "/datum/receiver/proc/method".into());
        prepare_member_type_fingerprints(&mut shared);
        assert_ne!(
            cache_key(&body, &original),
            cache_key(&body, &bindings(shared))
        );
    }

    #[test]
    fn contextual_proc_and_type_constants_do_not_cross_cache_contexts() {
        let body = parse("/proc/test()\n    return list(__PROC__, __TYPE__)\n")
            .items
            .remove(0)
            .children;
        let first = LowerBindings {
            current_proc_path: Some("/datum/a/proc/test".into()),
            current_type_path: Some("/datum/a".into()),
            ..Default::default()
        };
        let mut second = first.clone();
        second.current_proc_path = Some("/datum/a/proc/other".into());
        assert_ne!(cache_key(&body, &first), cache_key(&body, &second));
        second = first.clone();
        second.current_type_path = Some("/datum/b".into());
        assert_ne!(cache_key(&body, &first), cache_key(&body, &second));
    }

    #[test]
    fn declared_method_removal_invalidates_cached_bare_calls() {
        use std::sync::Arc;
        let body = parse("/proc/test()\n    return method()\n")
            .items
            .remove(0)
            .children;
        let mut shared = SharedLowerBindings::default();
        shared
            .known_member_procs
            .insert("/datum/receiver".into(), (["method".into()]).into_iter().collect());
        let bindings = |context| LowerBindings {
            current_type_path: Some("/datum/receiver".into()),
            shared: Some(Arc::new(context)),
            ..Default::default()
        };
        let unprepared = cache_key(&body, &bindings(shared.clone()));
        prepare_member_type_fingerprints(&mut shared);
        let original = cache_key(&body, &bindings(shared.clone()));
        assert_eq!(original, unprepared);
        shared
            .known_member_procs
            .get_mut("/datum/receiver")
            .unwrap()
            .insert("unrelated".into());
        prepare_member_type_fingerprints(&mut shared);
        assert_eq!(original, cache_key(&body, &bindings(shared.clone())));
        shared
            .known_member_procs
            .get_mut("/datum/receiver")
            .unwrap()
            .remove("method");
        prepare_member_type_fingerprints(&mut shared);
        assert_ne!(original, cache_key(&body, &bindings(shared)));
    }

    #[test]
    fn member_type_changes_invalidate_only_referenced_member_names() {
        use std::sync::Arc;
        let body = parse("/proc/test()\n    receiver.child = new()\n")
            .items
            .remove(0)
            .children;
        let mut shared = SharedLowerBindings::default();
        shared.member_types.insert(
            "/datum/receiver".into(),
            [("child".into(), "/datum/a".into())].into(),
        );
        shared
            .parent_types
            .insert("/datum/receiver".into(), "/datum".into());
        let bindings = |context| LowerBindings {
            shared: Some(Arc::new(context)),
            ..Default::default()
        };
        let unprepared = bindings(shared.clone());
        prepare_member_type_fingerprints(&mut shared);
        let original = bindings(shared.clone());
        assert_eq!(cache_key(&body, &unprepared), cache_key(&body, &original));
        shared
            .member_types
            .get_mut("/datum/receiver")
            .unwrap()
            .insert("unrelated".into(), "/datum/b".into());
        prepare_member_type_fingerprints(&mut shared);
        assert_eq!(
            cache_key(&body, &original),
            cache_key(&body, &bindings(shared.clone()))
        );
        shared
            .member_types
            .get_mut("/datum/receiver")
            .unwrap()
            .insert("child".into(), "/datum/b".into());
        prepare_member_type_fingerprints(&mut shared);
        assert_ne!(
            cache_key(&body, &original),
            cache_key(&body, &bindings(shared.clone()))
        );
        let changed_member = bindings(shared.clone());
        shared
            .parent_types
            .insert("/datum/receiver".into(), "/datum/other".into());
        prepare_member_type_fingerprints(&mut shared);
        assert_ne!(
            cache_key(&body, &changed_member),
            cache_key(&body, &bindings(shared))
        );
    }

    #[test]
    fn member_global_storage_changes_invalidate_only_referenced_members() {
        let body = parse("/proc/test()\n    return receiver.shared\n")
            .items
            .remove(0)
            .children;
        let bind = |shared| LowerBindings {
            shared: Some(std::sync::Arc::new(shared)),
            ..Default::default()
        };
        let mut shared = SharedLowerBindings::default();
        shared.member_globals.insert(
            "/datum/receiver".into(),
            [("shared".into(), "__dm_class_static_7".into())].into(),
        );
        let unprepared = cache_key(&body, &bind(shared.clone()));
        prepare_member_type_fingerprints(&mut shared);
        let original = cache_key(&body, &bind(shared.clone()));
        assert_eq!(unprepared, original);
        shared
            .known_member_fields
            .insert("/datum/other".into(), ["unrelated".into()].into());
        prepare_member_type_fingerprints(&mut shared);
        assert_eq!(original, cache_key(&body, &bind(shared.clone())));
        shared
            .known_member_fields
            .get_mut("/datum/other")
            .unwrap()
            .insert("shared".into());
        let unprepared_collision = {
            let mut context = shared.clone();
            context.member_type_fingerprints.clear();
            cache_key(&body, &bind(context))
        };
        prepare_member_type_fingerprints(&mut shared);
        let collision = cache_key(&body, &bind(shared.clone()));
        assert_ne!(original, collision);
        assert_eq!(unprepared_collision, collision);
        shared.known_member_fields.clear();
        prepare_member_type_fingerprints(&mut shared);
        assert_eq!(original, cache_key(&body, &bind(shared.clone())));
        shared
            .member_globals
            .get_mut("/datum/receiver")
            .unwrap()
            .insert("unrelated".into(), "__dm_class_static_8".into());
        prepare_member_type_fingerprints(&mut shared);
        assert_eq!(original, cache_key(&body, &bind(shared.clone())));
        shared
            .member_globals
            .get_mut("/datum/receiver")
            .unwrap()
            .insert("shared".into(), "__dm_class_static_9".into());
        let unprepared = {
            let mut context = shared.clone();
            context.member_type_fingerprints.clear();
            cache_key(&body, &bind(context))
        };
        prepare_member_type_fingerprints(&mut shared);
        let changed = cache_key(&body, &bind(shared.clone()));
        assert_ne!(original, changed);
        assert_eq!(unprepared, changed);
        shared.member_globals.clear();
        prepare_member_type_fingerprints(&mut shared);
        assert_ne!(changed, cache_key(&body, &bind(shared)));
    }

    #[test]
    fn unrelated_declarations_reuse_code_but_referenced_names_invalidate() {
        use dm_codegen_byond::SharedLowerBindings;
        use std::sync::Arc;
        let body = parse("/proc/test()\n    return x\n")
            .items
            .remove(0)
            .children;
        let mut context = SharedLowerBindings {
            globals: ["x".into()].into(),
            ..Default::default()
        };
        let first = LowerBindings {
            shared: Some(Arc::new(context.clone())),
            ..Default::default()
        };
        context.globals.insert("unrelated_worktree_global".into());
        context
            .global_procs
            .insert("unrelated_worktree_proc".into());
        context
            .field_types
            .insert("unrelated_field".into(), "/datum/new_type".into());
        let second = LowerBindings {
            shared: Some(Arc::new(context.clone())),
            ..Default::default()
        };
        assert_eq!(cache_key(&body, &first), cache_key(&body, &second));
        context.fields.insert("x".into());
        let third = LowerBindings {
            shared: Some(Arc::new(context)),
            ..Default::default()
        };
        assert_ne!(cache_key(&body, &second), cache_key(&body, &third));
        assert_ne!(
            compile_simple_proc_with_bindings(&body, &second)
                .unwrap()
                .code,
            compile_simple_proc_with_bindings(&body, &third)
                .unwrap()
                .code
        );

        let mut constants = SharedLowerBindings::default();
        constants
            .numeric_constants
            .insert("NORTH".into(), 1f32.to_bits());
        let old = LowerBindings {
            shared: Some(Arc::new(constants.clone())),
            ..Default::default()
        };
        constants
            .numeric_constants
            .insert("NORTH".into(), 2f32.to_bits());
        let new = LowerBindings {
            shared: Some(Arc::new(constants)),
            ..Default::default()
        };
        let interpolation = parse("/proc/test()\n    return \"direction [NORTH]\"\n")
            .items
            .remove(0)
            .children;
        assert_ne!(
            cache_key(&interpolation, &old),
            cache_key(&interpolation, &new)
        );
        let default_old = LowerBindings {
            parameters: vec!["x".into()],
            parameter_defaults: vec![Some("NORTH".into())],
            ..old
        };
        let default_new = LowerBindings {
            parameters: vec!["x".into()],
            parameter_defaults: vec![Some("NORTH".into())],
            ..new
        };
        assert_ne!(
            cache_key(&body, &default_old),
            cache_key(&body, &default_new)
        );
    }

    #[test]
    fn modified_instance_dependencies_are_selective_and_prepared_consistently() {
        use std::sync::Arc;
        let body = parse("/proc/test()\n    return new /datum/base/__dm_modified_used\n")
            .items
            .remove(0)
            .children;
        let bindings = |shared| LowerBindings {
            shared: Some(Arc::new(shared)),
            ..Default::default()
        };
        let plain = cache_key(&body, &bindings(SharedLowerBindings::default()));
        let mut shared = SharedLowerBindings::default();
        shared.modified_instances.insert(
            "/datum/base/__dm_modified_used".into(),
            "/datum/base".into(),
        );
        let used = cache_key(&body, &bindings(shared.clone()));
        assert_ne!(plain, used);
        prepare_member_type_fingerprints(&mut shared);
        assert_eq!(used, cache_key(&body, &bindings(shared.clone())));
        shared.modified_instances.insert(
            "/datum/other/__dm_modified_unused".into(),
            "/datum/other".into(),
        );
        prepare_member_type_fingerprints(&mut shared);
        assert_eq!(used, cache_key(&body, &bindings(shared.clone())));
        shared.modified_instances.insert(
            "/datum/base/__dm_modified_used".into(),
            "/datum/changed".into(),
        );
        prepare_member_type_fingerprints(&mut shared);
        assert_ne!(used, cache_key(&body, &bindings(shared)));
    }

    #[test]
    fn persisted_symbolic_code_is_portable_and_invalidates_bindings() {
        let root = std::env::temp_dir().join(format!(
            "dm-proc-cache-{}-{}",
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        let body = parse("/proc/test()\n    return x\n")
            .items
            .remove(0)
            .children;
        let args = LowerBindings {
            parameters: vec!["x".into()],
            ..Default::default()
        };
        let mut first = ProcLoweringCache::open(root.clone());
        let original = first.compile(&body, &args).unwrap();
        assert_eq!(first.stats().misses, 1);
        drop(first);
        let mut shifted = body.clone();
        fn shift(items: &mut [Item]) {
            for item in items {
                item.span = Span::new(item.span.start + 100, item.span.end + 100);
                item.header_span =
                    Span::new(item.header_span.start + 100, item.header_span.end + 100);
                shift(&mut item.children);
            }
        }
        shift(&mut shifted);
        let mut cold = ProcLoweringCache::open(root.clone());
        assert_eq!(cold.compile(&shifted, &args).unwrap(), original);
        assert_eq!(cold.stats().hits, 1);
        let globals = LowerBindings {
            globals: ["x".into()].into(),
            ..Default::default()
        };
        assert_ne!(cold.compile(&body, &globals).unwrap().code, original.code);
        assert_eq!(cold.stats().misses, 1);
        drop(cold);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn shared_context_identity_invalidates_cached_symbol_resolution() {
        use dm_codegen_byond::SharedLowerBindings;
        use std::sync::Arc;
        let body = parse("/proc/test()\n    return x\n")
            .items
            .remove(0)
            .children;
        let mut global = SharedLowerBindings {
            globals: ["x".into()].into(),
            ..Default::default()
        };
        global.fingerprint = shared_binding_fingerprint(&global);
        let globals = LowerBindings {
            shared: Some(Arc::new(global)),
            ..Default::default()
        };
        let mut field = SharedLowerBindings {
            fields: ["x".into()].into(),
            ..Default::default()
        };
        field.fingerprint = shared_binding_fingerprint(&field);
        let fields = LowerBindings {
            shared: Some(Arc::new(field)),
            ..Default::default()
        };
        // The portable overlay is identical; the borrowed context changes semantics.
        assert_eq!(
            serde_json::to_value(&globals).unwrap(),
            serde_json::to_value(&fields).unwrap()
        );
        assert_ne!(cache_key(&body, &globals), cache_key(&body, &fields));
        assert_ne!(
            compile_simple_proc_with_bindings(&body, &globals)
                .unwrap()
                .code,
            compile_simple_proc_with_bindings(&body, &fields)
                .unwrap()
                .code
        );
        let mut first = SharedLowerBindings::default();
        first.global_types.insert("x".into(), "/datum/x".into());
        first.global_types.insert("y".into(), "/datum/y".into());
        let mut second = SharedLowerBindings::default();
        second.global_types.insert("y".into(), "/datum/y".into());
        second.global_types.insert("x".into(), "/datum/x".into());
        assert_eq!(
            shared_binding_fingerprint(&first),
            shared_binding_fingerprint(&second)
        );
    }

    #[test]
    fn internal_source_spacing_invalidates_relative_statement_anchors() {
        let body = parse("/proc/test()\n    var/x = 1\n    return x\n")
            .items
            .remove(0)
            .children;
        let spaced = parse("/proc/test()\n    var/x = 1\n\n    return x\n")
            .items
            .remove(0)
            .children;
        assert_ne!(
            identity_key(&body, &LowerBindings::default()),
            identity_key(&spaced, &LowerBindings::default())
        );
    }
    #[test]
    fn worker_forks_share_stage_snapshot_and_flush_buffers_once() {
        let root = std::env::temp_dir().join(format!(
            "dm-stage-cache-{}-{}",
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        let body = parse("/proc/test()\n    return 3\n")
            .items
            .remove(0)
            .children;
        let bindings = LowerBindings::default();
        let mut seed = ProcLoweringCache::open(root.clone());
        seed.compile(&body, &bindings).unwrap();
        assert!(!seed.pending.is_empty());
        seed.flush().unwrap();
        assert!(seed.pending.is_empty());
        drop(seed);
        let parent = ProcLoweringCache::open(root.clone());
        assert!(parent.snapshot.get().is_none());
        let mut worker = parent.fork();
        assert!(std::sync::Arc::ptr_eq(&parent.snapshot, &worker.snapshot));
        assert!(worker.snapshot.get().is_none());
        assert!(worker.snapshot_complete());
        assert!(parent.snapshot.get().is_some());
        worker.compile(&body, &bindings).unwrap();
        assert_eq!(worker.stats().hits, 1);
        assert!(worker.pending.is_empty());
        drop(worker);
        drop(parent);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn corrupt_entry_is_recompiled_and_repaired() {
        let root = std::env::temp_dir().join(format!(
            "dm-proc-repair-{}-{}",
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        let body = parse("/proc/test()\n    return 7\n")
            .items
            .remove(0)
            .children;
        let bindings = LowerBindings::default();
        let key = identity_key(&body, &bindings);
        let mut first = ProcLoweringCache::open(root.clone());
        let expected = first.compile(&body, &bindings).unwrap();
        first.flush().unwrap();
        drop(first);
        dm_store::Store::open(root.join("symbolic.redb"))
            .unwrap()
            .put_many(
                vec![(
                    dm_store::Key::new(ProcLoweringCache::namespace(), key),
                    b"torn".to_vec(),
                )],
                None,
            )
            .unwrap();
        let mut cold = ProcLoweringCache::open(root.clone());
        assert_eq!(cold.compile(&body, &bindings).unwrap(), expected);
        assert_eq!(cold.stats().corrupt_entries, 1);
        drop(cold);
        let mut repaired = ProcLoweringCache::open(root.clone());
        assert_eq!(repaired.compile(&body, &bindings).unwrap(), expected);
        assert_eq!(repaired.stats().hits, 1);
        drop(repaired);
        fs::remove_dir_all(root).unwrap();
    }
}
