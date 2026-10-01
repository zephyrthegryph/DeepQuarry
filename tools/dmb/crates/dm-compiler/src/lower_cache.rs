//! Portable cache of symbolic procedure code, before any DMB table IDs exist.
//! Keys cover the body, bindings, and compiler implementation. Cache failures
//! fall back to normal lowering; they cannot prevent a correct compilation.

use dm_codegen_byond::{
    compile_simple_proc_with_bindings, LowerBindings, LowerError, SharedLowerBindings, SimpleProc,
};
use dm_syntax::Item;
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};

const VERSION: &str = env!("DM_LOWERING_FINGERPRINT");
const MAX_ENTRY_BYTES: usize = 4 * 1024 * 1024;
const MAX_MEMORY_BYTES: usize = 16 * 1024 * 1024;
static TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(0);
const RECORD_MAGIC: &[u8; 8] = b"DMPRC02\0";
const RECORD_HEADER_BYTES: usize = 8 + 64 + 64 + 8;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct CacheStats {
    pub hits: usize,
    pub misses: usize,
    pub corrupt_entries: usize,
}

// Keep the serialized procedure bytes directly in the record. Wrapping a
// byte vector in JSON expands it into thousands of decimal integers.
fn encode_record(key: &str, payload: &[u8]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(RECORD_HEADER_BYTES + payload.len());
    bytes.extend_from_slice(RECORD_MAGIC);
    bytes.extend_from_slice(key.as_bytes());
    bytes.extend_from_slice(digest(payload).as_bytes());
    bytes.extend_from_slice(&(payload.len() as u64).to_le_bytes());
    bytes.extend_from_slice(payload);
    bytes
}

fn decode_record<'a>(key: &str, bytes: &'a [u8]) -> Option<&'a [u8]> {
    if bytes.len() < RECORD_HEADER_BYTES
        || &bytes[..8] != RECORD_MAGIC
        || &bytes[8..72] != key.as_bytes()
    {
        return None;
    }
    let length = u64::from_le_bytes(bytes[136..144].try_into().ok()?);
    if length > MAX_ENTRY_BYTES as u64 || length != (bytes.len() - RECORD_HEADER_BYTES) as u64 {
        return None;
    }
    let payload = &bytes[RECORD_HEADER_BYTES..];
    (&bytes[72..136] == digest(payload).as_bytes()).then_some(payload)
}

pub struct ProcLoweringCache {
    root: Option<PathBuf>,
    memory: BTreeMap<String, Vec<u8>>,
    memory_bytes: usize,
    stats: CacheStats,
}

/// Put portable artifacts in Git's common directory so all worktrees share
/// them. Standalone projects keep the cache beside their DME.
pub fn project_cache_root(project: &Path) -> PathBuf {
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
        }
    }

    pub fn open(root: PathBuf) -> Self {
        let root = fs::create_dir_all(&root).ok().map(|()| root);
        Self {
            root,
            ..Self::disabled()
        }
    }

    pub fn stats(&self) -> CacheStats {
        self.stats
    }

    pub(crate) fn cache_root(&self) -> Option<&Path> {
        self.root.as_deref()
    }

    pub fn compile(
        &mut self,
        body: &[Item],
        bindings: &LowerBindings,
    ) -> Result<SimpleProc, Vec<LowerError>> {
        if self.root.is_none() {
            return compile_simple_proc_with_bindings(body, bindings);
        }
        let key = cache_key(body, bindings);
        if let Some(payload) = self.memory.get(&key) {
            if let Ok(proc) = serde_json::from_slice(payload) {
                self.stats.hits += 1;
                return Ok(proc);
            }
        }
        let path = self.root.as_ref().unwrap().join(&key[..2]).join(&key);
        if let Ok(file) = fs::File::open(&path) {
            // Bound the read even for corrupt records. A separate metadata
            // request doubles filesystem operations across large projects.
            let mut bytes = Vec::new();
            let cached = file
                .take((MAX_ENTRY_BYTES + RECORD_HEADER_BYTES + 1) as u64)
                .read_to_end(&mut bytes)
                .ok()
                .filter(|_| bytes.len() <= MAX_ENTRY_BYTES + RECORD_HEADER_BYTES)
                .and_then(|_| {
                    let payload = decode_record(&key, &bytes)?;
                    serde_json::from_slice::<SimpleProc>(payload)
                        .ok()
                        .map(|proc| (proc, payload.to_vec()))
                });
            if let Some((proc, payload)) = cached {
                self.remember(key, payload);
                self.stats.hits += 1;
                return Ok(proc);
            }
            self.stats.corrupt_entries += 1;
        }
        self.stats.misses += 1;
        let proc = compile_simple_proc_with_bindings(body, bindings)?;
        if let Ok(payload) = serde_json::to_vec(&proc) {
            if payload.len() <= MAX_ENTRY_BYTES {
                let bytes = encode_record(&key, &payload);
                let _ = atomic_write(&path, &bytes);
                self.remember(key, payload);
            }
        }
        Ok(proc)
    }

    fn remember(&mut self, key: String, payload: Vec<u8>) {
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
    }
}

fn digest(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
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
                            .get(&name)
                            .map(|declared_type| (class.as_str(), declared_type.as_str()))
                    })
                    .collect();
                let procedures: BTreeMap<&str, &str> = s
                    .member_procs
                    .iter()
                    .filter_map(|(class, members)| {
                        members
                            .get(&name)
                            .map(|path| (class.as_str(), path.as_str()))
                    })
                    .collect();
                let instances: BTreeMap<&str, &str> = s
                    .modified_instances
                    .iter()
                    .filter(|(alias, _)| alias.rsplit('/').next() == Some(name.as_str()))
                    .map(|(alias, base)| (alias.as_str(), base.as_str()))
                    .collect();
                let known: BTreeSet<&str> = s
                    .known_member_procs
                    .iter()
                    .filter(|(_, names)| names.contains(&name))
                    .map(|(class, _)| class.as_str())
                    .collect();
                let globals: BTreeMap<&str, &str> = s
                    .member_globals
                    .iter()
                    .filter_map(|(class, members)| {
                        members
                            .get(&name)
                            .map(|symbol| (class.as_str(), symbol.as_str()))
                    })
                    .collect();
                let fields: BTreeSet<&str> = s
                    .known_member_fields
                    .iter()
                    .filter(|(_, names)| names.contains(&name))
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
                .and_then(|s| s.member_type_fingerprints.get(&name))
                .or(fallback_member_digest.as_ref())
                .map(|s| s.as_bytes()),
        );
        hash.update([
            u8::from(
                bindings.fields.contains(&name) || shared.is_some_and(|s| s.fields.contains(&name)),
            ),
            u8::from(
                bindings.globals.contains(&name)
                    || shared.is_some_and(|s| s.globals.contains(&name)),
            ),
            u8::from(
                bindings.global_procs.contains(&name)
                    || shared.is_some_and(|s| s.global_procs.contains(&name)),
            ),
        ]);
        hash_optional_bytes(
            &mut hash,
            bindings
                .field_types
                .get(&name)
                .or_else(|| shared?.field_types.get(&name))
                .map(|s| s.as_bytes()),
        );
        hash_optional_bytes(
            &mut hash,
            bindings
                .global_types
                .get(&name)
                .or_else(|| shared?.global_types.get(&name))
                .map(|s| s.as_bytes()),
        );
        let number = shared.and_then(|s| s.numeric_constants.get(&name));
        hash.update([u8::from(number.is_some())]);
        if let Some(number) = number {
            hash.update(number.to_le_bytes());
        }
        hash_optional_bytes(
            &mut hash,
            shared
                .and_then(|s| s.string_constants.get(&name))
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
        global_types: _,
        global_procs: _,
        shared: _,
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

fn hash_optional_bytes(hash: &mut Sha256, bytes: Option<&[u8]>) {
    hash.update([u8::from(bytes.is_some())]);
    if let Some(bytes) = bytes {
        hash.update((bytes.len() as u64).to_le_bytes());
        hash.update(bytes);
    }
}

fn collect_text_names(text: &str, names: &mut BTreeSet<String>) {
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
}

fn collect_names(body: &[Item], names: &mut BTreeSet<String>) {
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
    fn framed_records_reject_wrong_keys_torn_payloads_and_corruption() {
        let key = digest(b"procedure identity");
        let payload = b"{\"value\":7}";
        let bytes = encode_record(&key, payload);
        assert_eq!(bytes.len(), RECORD_HEADER_BYTES + payload.len());
        assert_eq!(decode_record(&key, &bytes), Some(payload.as_slice()));
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
            .insert("/datum/receiver".into(), BTreeSet::from(["method".into()]));
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
        shifted[0].span = Span::new(100, 200);
        shifted[0].header_span = Span::new(100, 120);
        let mut cold = ProcLoweringCache::open(root.clone());
        assert_eq!(cold.compile(&shifted, &args).unwrap(), original);
        assert_eq!(cold.stats().hits, 1);
        let globals = LowerBindings {
            globals: ["x".into()].into(),
            ..Default::default()
        };
        assert_ne!(cold.compile(&body, &globals).unwrap().code, original.code);
        assert_eq!(cold.stats().misses, 1);
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
        let key = cache_key(&body, &bindings);
        let mut first = ProcLoweringCache::open(root.clone());
        let expected = first.compile(&body, &bindings).unwrap();
        let path = root.join(&key[..2]).join(&key);
        fs::write(&path, b"torn").unwrap();
        let mut cold = ProcLoweringCache::open(root.clone());
        assert_eq!(cold.compile(&body, &bindings).unwrap(), expected);
        assert_eq!(cold.stats().corrupt_entries, 1);
        drop(cold);
        let mut repaired = ProcLoweringCache::open(root.clone());
        assert_eq!(repaired.compile(&body, &bindings).unwrap(), expected);
        assert_eq!(repaired.stats().hits, 1);
        fs::remove_dir_all(root).unwrap();
    }
}
