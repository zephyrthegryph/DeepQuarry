//! Shared state for a long-lived compiler service.
//!
//! Salsa databases belong to individual worktree sessions. Only immutable,
//! content-addressed artifacts are safe to share between sessions.

#[cfg(test)]
use dm_compiler::bootstrap::resolved_resource_requests;
use dm_compiler::bootstrap::{
    compile_preprocessed_project_with_resources_prepared_mode, resolved_resource_disk_path,
    resolved_resource_requests_with_literals,
};
use dm_compiler::{load_map_set_from_paths, CompilerSession};
use dm_output::generation::{
    current_generation, publish_generation_reusing_archive, publish_generation_with_archive,
    publish_generation_with_verified_bytecode, verified_archive, verify_generation_digest,
    VerifiedArchive, VerifiedBytecode,
};
use dm_output::{
    apply_pair_in_place, plan_pair, recover_pair, validate_byond_pair, PairPlan, PatchPolicy,
};
use dm_preprocess::PreprocessedProject;
use dm_resources::{ResourceRequest, ResourceSet};
use dm_syntax::AstFile;
mod input_proof;
use input_proof::InputProof;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::fs;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Instant;

pub mod frontend_pool;
mod prepared_persistence;
pub mod prepared_project;
pub mod project_discovery;

/// Detached compiler declarations for lint/documentation producers. Procedure
/// bodies remain in prepared source fragments; reference coverage is not implied.
pub struct ProjectFrontendSnapshot {
    pub prepared: Arc<prepared_project::PreparedProject>,
    pub ast: Arc<AstFile>,
    pub declarations: Result<dm_semantics::DeclarationIndex, Vec<String>>,
    pub syntax_errors: Vec<String>,
    pub syntax_complete: bool,
}

/// Shared native query model; AST fragments and semantic owner roots are
/// immutable and remain valid after the coordinator session is returned.
pub struct ProjectAnalysisView {
    pub prepared: Arc<prepared_project::PreparedProject>,
    pub view: dm_analysis::FrontendView,
}

static TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(0);
const BUILD_FINGERPRINT: &str =
    concat!(env!("CARGO_PKG_VERSION"), "+", env!("DM_BUILD_FINGERPRINT"));
const MAX_BUILD_RESULTS: usize = 256;

/// The Git common directory is shared by all worktrees of one codebase. Use
/// it for immutable artifacts, with a project-local fallback outside Git.
pub fn default_cache_root(project_or_directory: &Path) -> PathBuf {
    if let Some(root) = std::env::var_os("DM_COMPILER_CACHE_ROOT") {
        return PathBuf::from(root);
    }
    let directory = if project_or_directory.is_dir() {
        project_or_directory
    } else {
        project_or_directory
            .parent()
            .unwrap_or(project_or_directory)
    };
    // A bare manifest name has an empty parent. Git refuses it as a working
    // directory, silently sending that invocation to a separate local cache.
    let directory = if directory.as_os_str().is_empty() {
        Path::new(".")
    } else {
        directory
    };
    let absolute = if directory.is_absolute() {
        directory.to_path_buf()
    } else {
        match std::env::current_dir() {
            Ok(cwd) => cwd.join(directory),
            Err(_) => directory.to_path_buf(),
        }
    };
    let directory = absolute.canonicalize().unwrap_or(absolute);
    let common = Command::new("git")
        .args(["rev-parse", "--git-common-dir"])
        .current_dir(&directory)
        .output()
        .ok()
        .filter(|output| output.status.success())
        .and_then(|output| String::from_utf8(output.stdout).ok())
        .map(|output| output.trim().to_owned())
        .filter(|output| !output.is_empty());
    if let Some(common) = common {
        let path = PathBuf::from(common);
        let root = if path.is_absolute() {
            path
        } else {
            directory.join(path)
        };
        return root
            .canonicalize()
            .unwrap_or(root)
            .join("dm-compiled-cache");
    }
    directory.join(".dm-cache")
}

#[derive(Clone, Debug, Eq, Hash, PartialEq, Serialize, Deserialize)]
pub struct SessionKey {
    pub worktree: PathBuf,
    pub project: PathBuf,
    pub target: String,
    pub defines: Vec<(String, String)>,
    pub build_mode: String,
    pub compiler_version: String,
}

impl SessionKey {
    /// Canonicalizes only the filesystem identity. Source spelling remains in
    /// compiler inputs because resource archive names can depend on it.
    pub fn new(
        worktree: impl AsRef<Path>,
        project: impl AsRef<Path>,
        target: impl Into<String>,
        mut defines: Vec<(String, String)>,
        build_mode: impl Into<String>,
    ) -> io::Result<Self> {
        defines.sort();
        Ok(Self {
            worktree: worktree.as_ref().canonicalize()?,
            project: project.as_ref().canonicalize()?,
            target: target.into(),
            defines,
            build_mode: build_mode.into(),
            compiler_version: BUILD_FINGERPRINT.into(),
        })
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct SessionState {
    pub generation: u64,
    pub last_input_digest: Option<String>,
}

#[derive(Default)]
pub struct Sessions {
    entries: Mutex<HashMap<SessionKey, Arc<Mutex<SessionState>>>>,
}

impl Sessions {
    pub fn get_or_create(&self, key: SessionKey) -> Arc<Mutex<SessionState>> {
        self.entries
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .entry(key)
            .or_default()
            .clone()
    }

    pub fn count(&self) -> usize {
        self.entries
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .len()
    }
}

/// A disk CAS for immutable bytes. Semantic artifacts must include the
/// compiler/target/dependency fingerprint in their key before calling `put`.
pub struct ContentStore {
    root: PathBuf,
    metadata: dm_store::Store,
    verified_blobs: Mutex<BTreeMap<PathBuf, (dm_host::file_stamp::FileStamp, String)>>,
}

/// Portable key for a pure compiler stage. Every semantic dependency that can
/// affect the bytes must be included by the caller. Session-local Salsa IDs
/// and worktree paths must not appear in shared artifacts.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ArtifactKey {
    pub stage: String,
    pub format_version: u32,
    pub compiler_version: String,
    pub target: Option<String>,
    pub input_digests: Vec<String>,
    pub dependency_digests: Vec<String>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
struct ArtifactPointer {
    key: ArtifactKey,
    payload_digest: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct CachedPairManifest {
    version: u32,
    emitted_procs: usize,
    dmb_digest: String,
    rsc_digest: String,
}

const PAIR_MANIFEST_VERSION: u32 = 1;

impl ArtifactKey {
    fn validate(&self) -> io::Result<()> {
        if !valid_namespace(&self.stage)
            || self.compiler_version.is_empty()
            || self
                .input_digests
                .iter()
                .chain(&self.dependency_digests)
                .any(|digest| !valid_digest(digest))
        {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "invalid artifact key",
            ));
        }
        Ok(())
    }

    fn digest(&self) -> io::Result<String> {
        self.validate()?;
        let bytes = serde_json::to_vec(self).map_err(io::Error::other)?;
        Ok(format!("{:x}", Sha256::digest(bytes)))
    }
}

#[derive(Clone, Serialize, Deserialize)]
struct IncrementalRecord {
    version: u32,
    abi_digest: String,
    checkpoint_digest: String,
    dmb_digest: String,
    rsc_digest: String,
    emitted_procs: usize,
}
struct PreparedBuild {
    dmb: byond_dmb::dmb::Dmb,
    serialized_dmb: Option<Vec<u8>>,
    list_spans: Option<Vec<std::ops::Range<usize>>>,
    list_image: Option<dm_output::list_image::ListImage>,
    rsc_bytes: Vec<u8>,
    archive: Option<VerifiedArchive>,
    emitted_procs: usize,
    lowered_procs: usize,
    reused_procs: usize,
    artifact_reuse: dm_compiler::ArtifactReuseStats,
    checkpoint: Option<dm_compiler::incremental::EmissionCheckpoint>,
}

#[derive(Serialize, Deserialize)]
struct ArchiveCatalogRecord {
    version: u32,
    archive_digest: String,
    catalog: dm_resources::ResourceCatalog,
}

struct RetainedWorld {
    family: PathBuf,
    record: IncrementalRecord,
    checkpoint: dm_compiler::incremental::EmissionCheckpoint,
    dmb: byond_dmb::dmb::Dmb,
    indexed: dm_output::list_image::ListImage,
}

fn world_resident_bytes(dmb: &byond_dmb::dmb::Dmb, image: &[u8], checkpoint_bytes: usize) -> usize {
    // JSON checkpoint size is charged twice to cover owned strings/maps and
    // their allocations. DMB records and list/string buffers are charged directly.
    checkpoint_bytes.saturating_mul(2)
        + image.len()
        + dmb.lists.capacity() * std::mem::size_of::<Vec<u32>>()
        + dmb
            .lists
            .iter()
            .map(|list| list.capacity() * 4)
            .sum::<usize>()
        + dmb.strings.capacity() * std::mem::size_of::<byond_dmb::dmb::DmString>()
        + dmb
            .strings
            .iter()
            .map(|string| string.data.capacity())
            .sum::<usize>()
        + dmb.classes.capacity() * std::mem::size_of::<byond_dmb::dmb::Class>()
        + dmb.procs.capacity() * std::mem::size_of::<byond_dmb::dmb::Proc>()
        + dmb.variables.capacity() * std::mem::size_of::<byond_dmb::dmb::Variable>()
        + dmb.mobs.capacity() * std::mem::size_of::<byond_dmb::dmb::MobType>()
        + dmb.grid.capacity() * std::mem::size_of::<byond_dmb::dmb::GridRun>()
        + dmb.instances.capacity() * std::mem::size_of::<byond_dmb::dmb::Instance>()
        + dmb.map_objects.capacity() * std::mem::size_of::<byond_dmb::dmb::MapObject>()
        + dmb.resources.capacity() * std::mem::size_of::<byond_dmb::dmb::ResourceRef>()
        + dmb.lists.len() * std::mem::size_of::<std::ops::Range<usize>>()
}

impl ContentStore {
    pub fn new(root: impl Into<PathBuf>) -> io::Result<Self> {
        let root = root.into();
        fs::create_dir_all(&root)?;
        let metadata = dm_store::Store::open(root.join("metadata.redb"))?;
        Ok(Self {
            root,
            metadata,
            verified_blobs: Mutex::new(BTreeMap::new()),
        })
    }

    fn verify_blob(&self, path: &Path, digest: &str) -> io::Result<bool> {
        let before = (!input_proof::exact_inputs())
            .then(|| dm_host::file_stamp::capture(path))
            .flatten();
        if let Some(stamp) = &before {
            if self
                .verified_blobs
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .get(path)
                .is_some_and(|(expected, hash)| expected == stamp && hash == digest)
            {
                return Ok(true);
            }
        }
        let valid = verify_file_digest(path, digest)?;
        if valid && before.is_some() && dm_host::file_stamp::capture(path) == before {
            let mut proofs = self
                .verified_blobs
                .lock()
                .unwrap_or_else(|e| e.into_inner());
            // Strong-stamp accelerator only. Missing stamps and exact-input
            // mode always read/hash bytes. Limit metadata independently of CAS.
            while proofs.len() >= 2048 && !proofs.contains_key(path) {
                let Some(key) = proofs.keys().next().cloned() else {
                    break;
                };
                proofs.remove(&key);
            }
            proofs.insert(path.to_owned(), (before.unwrap(), digest.to_owned()));
        }
        Ok(valid)
    }

    fn proof_resident_bytes(&self) -> usize {
        self.verified_blobs
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .iter()
            .map(|(path, (_, digest))| path.as_os_str().len() * 2 + digest.capacity() + 256)
            .sum()
    }

    pub fn put(&self, namespace: &str, bytes: &[u8]) -> io::Result<String> {
        self.put_parts(namespace, &[bytes])
    }

    fn put_parts(&self, namespace: &str, parts: &[&[u8]]) -> io::Result<String> {
        self.put_parts_inner(namespace, parts, true)
    }

    /// Rebuildable input blobs are atomically installed and checksum checked on
    /// restore. Their manifest is committed last; flushing each small file is
    /// unnecessary for cache correctness and expensive on cold projects.
    pub(crate) fn put_rebuildable(&self, namespace: &str, bytes: &[u8]) -> io::Result<String> {
        self.put_parts_inner(namespace, &[bytes], false)
    }

    fn put_parts_inner(
        &self,
        namespace: &str,
        parts: &[&[u8]],
        durable: bool,
    ) -> io::Result<String> {
        if !valid_namespace(namespace) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "invalid CAS namespace",
            ));
        }
        let mut hasher = Sha256::new();
        for part in parts {
            hasher.update(part);
        }
        let digest = format!("{:x}", hasher.finalize());
        let directory = self.root.join(namespace).join(&digest[..2]);
        fs::create_dir_all(&directory)?;
        let destination = directory.join(&digest);
        if destination.exists() {
            match self.verify_blob(&destination, &digest) {
                Ok(true) => return Ok(digest),
                Ok(false) => {}
                Err(error) if error.kind() == io::ErrorKind::InvalidData => {
                    // A damaged blob can be replaced by the same digest's exact
                    // bytes. Concurrent writers of this path have identical data.
                }
                Err(error) => return Err(error),
            }
        }
        let temporary = directory.join(format!(
            "{}.{}.{}.tmp",
            digest,
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        let mut file = fs::File::create(&temporary)?;
        for part in parts {
            file.write_all(part)?;
        }
        if durable {
            file.sync_all()?;
        }
        drop(file);
        match fs::rename(&temporary, &destination) {
            Ok(()) => Ok(digest),
            Err(_error) if destination.exists() => {
                let _ = fs::remove_file(&temporary);
                if self.verify_blob(&destination, &digest)? {
                    Ok(digest)
                } else {
                    Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "CAS hash mismatch",
                    ))
                }
            }
            Err(error) => {
                let _ = fs::remove_file(&temporary);
                Err(error)
            }
        }
    }

    pub fn get(&self, namespace: &str, digest: &str) -> io::Result<Vec<u8>> {
        if !valid_namespace(namespace)
            || digest.len() != 64
            || !digest.bytes().all(|byte| byte.is_ascii_hexdigit())
        {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "invalid CAS key",
            ));
        }
        let bytes = fs::read(self.root.join(namespace).join(&digest[..2]).join(digest))?;
        if format!("{:x}", Sha256::digest(&bytes)) != digest {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "CAS hash mismatch",
            ));
        }
        Ok(bytes)
    }

    fn get_bounded(&self, namespace: &str, digest: &str, limit: usize) -> io::Result<Vec<u8>> {
        if !valid_namespace(namespace) || !valid_digest(digest) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "invalid CAS key",
            ));
        }
        let mut file = fs::File::open(self.root.join(namespace).join(&digest[..2]).join(digest))?;
        if file.metadata()?.len() > limit as u64 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "CAS blob exceeds stage budget",
            ));
        }
        let mut bytes = Vec::new();
        std::io::Read::by_ref(&mut file)
            .take(limit as u64 + 1)
            .read_to_end(&mut bytes)?;
        if bytes.len() > limit || format!("{:x}", Sha256::digest(&bytes)) != digest {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "CAS hash/size mismatch",
            ));
        }
        Ok(bytes)
    }

    /// Store a pure artifact under its complete dependency key. If the same
    /// key yields different bytes, reject it instead of serving a false hit.
    pub fn put_artifact(&self, key: &ArtifactKey, bytes: &[u8]) -> io::Result<String> {
        self.put_artifact_parts(key, &[bytes])
    }

    /// Store an artifact without joining its parts into a second allocation.
    /// The bytes, digest, and pointer format match `put_artifact` exactly.
    pub fn put_artifact_parts(&self, key: &ArtifactKey, parts: &[&[u8]]) -> io::Result<String> {
        let payload_digest = self.put_parts("artifact-payload-v1", parts)?;
        let record_key = dm_store::Key::new("artifact-index-v2", key.digest()?);
        let pointer = ArtifactPointer {
            key: key.clone(),
            payload_digest: payload_digest.clone(),
        };
        let bytes = serde_json::to_vec(&pointer).map_err(io::Error::other)?;
        for _ in 0..8 {
            let read = self
                .metadata
                .read_many(std::slice::from_ref(&record_key), None)?;
            if let Some(existing) = &read.values[0] {
                let existing: ArtifactPointer = serde_json::from_slice(existing)
                    .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?;
                if existing.key != *key || existing.payload_digest != payload_digest {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "artifact key collision or incomplete dependencies",
                    ));
                }
                return Ok(payload_digest);
            }
            if self.metadata.commit(
                &read.witnesses,
                &[dm_store::Change::Put(record_key.clone(), bytes.clone())],
                None,
            )? == dm_store::Commit::Applied
            {
                return Ok(payload_digest);
            }
        }
        Err(io::Error::new(
            io::ErrorKind::WouldBlock,
            "artifact metadata changed repeatedly; retry",
        ))
    }

    pub fn get_artifact(&self, key: &ArtifactKey) -> io::Result<Option<Vec<u8>>> {
        let record_key = dm_store::Key::new("artifact-index-v2", key.digest()?);
        let read = self.metadata.read_many(&[record_key], None)?;
        if let Some(bytes) = &read.values[0] {
            let pointer: ArtifactPointer = serde_json::from_slice(bytes)
                .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?;
            if pointer.key != *key || !valid_digest(&pointer.payload_digest) {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "artifact pointer mismatch",
                ));
            }
            return self
                .get("artifact-payload-v1", &pointer.payload_digest)
                .map(Some);
        }
        self.legacy_get_artifact(key)
    }

    fn legacy_get_artifact(&self, key: &ArtifactKey) -> io::Result<Option<Vec<u8>>> {
        let key_digest = key.digest()?;
        let path = self
            .root
            .join("artifact-index-v1")
            .join(&key_digest[..2])
            .join(&key_digest);
        let pointer_bytes = match fs::read(path) {
            Ok(bytes) => bytes,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error),
        };
        let pointer: ArtifactPointer = serde_json::from_slice(&pointer_bytes)
            .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?;
        if pointer.key != *key || !valid_digest(&pointer.payload_digest) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "artifact pointer mismatch",
            ));
        }
        self.get("artifact-payload-v1", &pointer.payload_digest)
            .map(Some)
    }

    fn get_json_artifact<T: serde::de::DeserializeOwned>(
        &self,
        key: &ArtifactKey,
    ) -> io::Result<Option<T>> {
        let decoded = self.get_artifact(key).and_then(|bytes| {
            bytes
                .map(|bytes| {
                    serde_json::from_slice(&bytes)
                        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))
                })
                .transpose()
        });
        match decoded {
            Err(error)
                if matches!(
                    error.kind(),
                    io::ErrorKind::InvalidData | io::ErrorKind::NotFound
                ) =>
            {
                self.discard_corrupt_artifact(key)?;
                Ok(None)
            }
            result => result,
        }
    }

    /// Discard a damaged index entry so a pure stage can regenerate it. Blob
    /// bytes remain content-addressed and are replaced by `put` if damaged.
    fn discard_corrupt_artifact(&self, key: &ArtifactKey) -> io::Result<()> {
        self.metadata.commit(
            &[],
            &[dm_store::Change::Delete(dm_store::Key::new(
                "artifact-index-v2",
                key.digest()?,
            ))],
            None,
        )?;
        let digest = key.digest()?;
        let path = self
            .root
            .join("artifact-index-v1")
            .join(&digest[..2])
            .join(digest);
        match fs::remove_file(path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error),
        }
    }
}

fn valid_digest(value: &str) -> bool {
    value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
}

fn verify_file_digest(path: &Path, expected: &str) -> io::Result<bool> {
    let mut file = fs::File::open(path)?;
    let mut hash = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hash.update(&buffer[..read]);
    }
    Ok(format!("{:x}", hash.finalize()) == expected)
}

fn valid_namespace(value: &str) -> bool {
    !value.is_empty()
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "command", rename_all = "snake_case")]
pub enum Request {
    Ping,
    Check {
        key: SessionKey,
        source: PathBuf,
        text: String,
    },
    /// Refresh the include closure from disk, then check the whole project.
    CheckProject {
        key: SessionKey,
    },
    /// Compile and publish a complete immutable output generation.
    BuildProject {
        key: SessionKey,
        builtins: PathBuf,
        output_root: PathBuf,
    },
    /// Patch an existing pair only when the caller owns both stopped outputs.
    /// A changed build still stores one complete pair in the shared disk CAS
    /// for future cold starts; no extra output generation is published, and
    /// only changed spans are written to the requested live pair.
    BuildProjectPatch {
        key: SessionKey,
        builtins: PathBuf,
        dmb: PathBuf,
        rsc: PathBuf,
        exclusive: bool,
    },
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct BuildResult {
    pub generation: String,
    pub dmb: PathBuf,
    pub rsc: PathBuf,
    pub cache_hit: bool,
    pub emitted_procs: usize,
    #[serde(default)]
    pub lowered_procs: usize,
    #[serde(default)]
    pub reused_procs: usize,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FailureKind {
    Source,
    Internal,
    Configuration,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Response {
    pub ok: bool,
    pub item_count: usize,
    pub diagnostics: Vec<String>,
    pub source_digest: Option<String>,
    pub shared_syntax_hit: bool,
    pub error: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub failure_kind: Option<FailureKind>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub build: Option<BuildResult>,
}

/// Single-owner coordinator. The wire service can later schedule independent
/// sessions on workers without moving Salsa inputs between databases.
pub struct Coordinator {
    sessions: HashMap<SessionKey, ActiveSession>,
    projects: HashMap<SessionKey, ActiveProject>,
    blobs: ContentStore,
    syntax_cache: HashMap<String, CachedSyntax>,
    build_cache: HashMap<BuildCacheKey, BuildResult>,
    build_inputs: HashMap<SessionKey, CachedBuildInputs>,
    asset_inventory: HashMap<SessionKey, Arc<AssetInventory>>,
    incremental: dm_compiler::incremental::IncrementalSession,
    // One bounded discovery cache per worker; switching projects releases it.
    frontend_pool: frontend_pool::FrontendPool,
    retained_world: Option<RetainedWorld>,
    serialization_validation: byond_dmb::dmb::ReferenceValidationCache,
    serialization_wire: byond_dmb::dmb::DmbWireCache,
    #[cfg(test)]
    retained_world_hits: usize,
    clock: u64,
    limits: CoordinatorLimits,
}

#[derive(Clone, Copy, Debug)]
pub struct CoordinatorLimits {
    pub max_check_source_bytes: usize,
    pub max_diagnostic_sessions: usize,
    pub max_syntax_summaries: usize,
    pub max_idle_requests: u64,
}

impl Default for CoordinatorLimits {
    fn default() -> Self {
        Self {
            max_check_source_bytes: dm_compiler::check_source_limit(),
            max_diagnostic_sessions: 8,
            max_syntax_summaries: 256,
            max_idle_requests: 128,
        }
    }
}

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
struct BuildCacheKey {
    project_digest: String,
    builtins_digest: String,
    resources_digest: String,
    maps_digest: String,
    world_name: String,
    target: String,
    defines: Vec<(String, String)>,
    build_mode: String,
    compiler_version: String,
    output_root: PathBuf,
}

#[cfg(test)]
thread_local! {
    static RESOLUTION_WALKS: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
    static RESOURCE_RESOLUTIONS: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

#[derive(Clone)]
struct BuildInputSnapshot {
    project_digest: String,
    diagnostics: Vec<String>,
    resources_digest: String,
    maps_digest: String,
    map_set: Arc<dm_compiler::maps::MapSet>,
    source_digests: BTreeMap<PathBuf, [u8; 32]>,
    missing_dependencies: Vec<PathBuf>,
    resource_requests: Vec<ResourceRequest>,
    source_resource_literals: Vec<String>,
    preprocessed: Arc<PreprocessedProject>,
    expansion: Arc<prepared_project::SegmentedExpansion>,
    proof: std::cell::RefCell<Option<InputProof>>,
    asset_proof: std::cell::RefCell<Option<InputProof>>,
    source_proof: std::cell::RefCell<Option<InputProof>>,
}

/// Compact asset node survives eviction of large source/build snapshots.
#[derive(Clone, Serialize, Deserialize)]
struct AssetInventory {
    proof: InputProof,
    requests: Vec<ResourceRequest>,
    literals: Vec<String>,
    dirs: Vec<PathBuf>,
    skins: Vec<PathBuf>,
    maps: Vec<PathBuf>,
    map_fingerprint: [u8; 32],
    resource_digest: String,
}
impl AssetInventory {
    fn resident_bytes(&self) -> usize {
        self.proof
            .resident_bytes()
            .saturating_add(
                self.requests
                    .iter()
                    .map(|x| x.archive_name.len() + x.disk_path.to_string_lossy().len() + 128)
                    .sum::<usize>(),
            )
            .saturating_add(self.literals.iter().map(|x| x.len() + 32).sum::<usize>())
            .saturating_add(
                self.dirs
                    .iter()
                    .chain(&self.skins)
                    .chain(&self.maps)
                    .map(|x| x.to_string_lossy().len() + 32)
                    .sum::<usize>(),
            )
    }
}
fn asset_inventory_key(key: &SessionKey) -> String {
    dm_compiler::incremental::digest(&serde_json::to_vec(key).unwrap())
}

#[derive(Clone)]
struct CachedBuildInputs {
    snapshot: BuildInputSnapshot,
    last_used: u64,
}

/// A compact, content-addressed receipt lets a new CLI process validate an
/// unchanged build without restoring the expanded project or compiler graph.
#[derive(Serialize, Deserialize)]
struct BuildReceipt {
    proof: InputProof,
    missing_dependencies: Vec<PathBuf>,
    resource_paths: Vec<(String, PathBuf)>,
    file_dirs: Vec<PathBuf>,
    source_digest: String,
    result: BuildResult,
}

fn receipt_key(key: &SessionKey, builtins: &str, output: &Path) -> Option<ArtifactKey> {
    let context = serde_json::to_vec(&(key, output)).ok()?;
    Some(ArtifactKey {
        stage: "build-receipt".into(),
        format_version: 1,
        compiler_version: key.compiler_version.clone(),
        target: Some(key.target.clone()),
        input_digests: vec![builtins.into(), format!("{:x}", Sha256::digest(context))],
        dependency_digests: vec![],
    })
}

impl BuildReceipt {
    fn current(&self, project: &Path) -> bool {
        if let Some(current) = self.proof.namespace_current() {
            return current;
        }
        self.proof.current()
            && !self.missing_dependencies.iter().any(|path| path.exists())
            && self.resource_paths.iter().all(|(name, disk)| {
                proven_resource_resolution_current(project, name, disk, &self.file_dirs)
            })
    }
}

/// The file proof has already established that `selected` still names the same
/// existing file. Only search candidates with higher precedence can shadow it.
fn proven_resource_resolution_current(
    project: &Path,
    name: &str,
    selected: &Path,
    file_dirs: &[PathBuf],
) -> bool {
    let root = project.parent().unwrap_or_else(|| Path::new("."));
    let direct = root.join(name);
    if direct == selected {
        return true;
    }
    if direct.is_file() {
        return false;
    }
    for directory in file_dirs.iter().rev() {
        let candidate = root.join(directory).join(name);
        if candidate == selected {
            return true;
        }
        if candidate.is_file() {
            return false;
        }
    }
    false
}

impl ContentStore {
    fn load_receipt(&self, key: &ArtifactKey) -> io::Result<Option<BuildReceipt>> {
        let read = self.metadata.read_many(
            &[dm_store::Key::new("build-receipts-v2", key.digest()?)],
            None,
        )?;
        if let Some(bytes) = &read.values[0] {
            let pointer: ArtifactPointer = serde_json::from_slice(bytes)
                .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?;
            if pointer.key != *key || !valid_digest(&pointer.payload_digest) {
                return Ok(None);
            }
            return match self.get_bounded(
                "build-receipt-v1",
                &pointer.payload_digest,
                16 * 1024 * 1024,
            ) {
                Ok(bytes) => Ok(serde_json::from_slice(&bytes).ok()),
                Err(_) => Ok(None),
            };
        }
        self.legacy_load_receipt(key)
    }

    fn legacy_load_receipt(&self, key: &ArtifactKey) -> io::Result<Option<BuildReceipt>> {
        let directory = self.root.join("build-receipts-v1").join(key.digest()?);
        let mut paths = match fs::read_dir(directory) {
            Ok(entries) => entries
                .filter_map(Result::ok)
                .map(|entry| entry.path())
                .filter(|path| {
                    path.extension()
                        .is_some_and(|extension| extension == "json")
                })
                .collect::<Vec<_>>(),
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error),
        };
        paths.sort();
        for path in paths.iter().rev().take(4) {
            let Some(bytes) = fs::metadata(path)
                .ok()
                .filter(|m| m.len() <= 4096)
                .and_then(|_| fs::read(path).ok())
            else {
                continue;
            };
            let Ok(pointer) = serde_json::from_slice::<ArtifactPointer>(&bytes) else {
                continue;
            };
            if pointer.key != *key {
                continue;
            }
            let Ok(bytes) = self.get_bounded(
                "build-receipt-v1",
                &pointer.payload_digest,
                16 * 1024 * 1024,
            ) else {
                continue;
            };
            if let Ok(receipt) = serde_json::from_slice(&bytes) {
                return Ok(Some(receipt));
            }
        }
        Ok(None)
    }

    fn store_receipt(&self, key: &ArtifactKey, receipt: &BuildReceipt) -> io::Result<()> {
        let bytes = serde_json::to_vec(receipt).map_err(io::Error::other)?;
        let payload_digest = self.put("build-receipt-v1", &bytes)?;
        let pointer = ArtifactPointer {
            key: key.clone(),
            payload_digest,
        };
        self.metadata
            .put_many(
                vec![(
                    dm_store::Key::new("build-receipts-v2", key.digest()?),
                    serde_json::to_vec(&pointer).map_err(io::Error::other)?,
                )],
                None,
            )
            .map(|_| ())
    }
}

// The expanded-source limit is 64 MiB. Leave room for its dependency/resource
// tables and strong proofs rather than evicting a valid near-limit project.
const MAX_BUILD_INPUT_BYTES: usize = 96 * 1024 * 1024;

impl BuildInputSnapshot {
    fn resident_bytes(&self) -> usize {
        // Each output line retains an Origin, but lines from one include share
        // their Arc<PathBuf>. Charge actual allocations once so this budget
        // neither drops the source map nor counts the same file per line.
        let mut origin_paths = std::collections::HashSet::new();
        let origin_bytes = self.preprocessed.origins.capacity()
            * std::mem::size_of::<dm_preprocess::Origin>()
            + self
                .preprocessed
                .origins
                .iter()
                .filter(|origin| origin_paths.insert(Arc::as_ptr(&origin.path)))
                .map(|origin| {
                    origin.path.capacity() * 2
                        + std::mem::size_of::<PathBuf>()
                        + 2 * std::mem::size_of::<usize>()
                })
                .sum::<usize>();
        self.source_resource_literals.capacity() * std::mem::size_of::<String>()
            + self
                .source_resource_literals
                .iter()
                .map(String::capacity)
                .sum::<usize>()
            + self.preprocessed.text.capacity()
            + self
                .expansion
                .segments
                .iter()
                .map(|piece| {
                    piece.text.len() + piece.lines.len() * std::mem::size_of::<usize>() + 96
                })
                .sum::<usize>()
            + origin_bytes
            + self
                .map_set
                .files
                .iter()
                .map(|(path, text)| path.as_os_str().len() * 2 + text.capacity() + 64)
                .sum::<usize>()
            + self.preprocessed.units.capacity() * std::mem::size_of::<dm_preprocess::Unit>()
            + self
                .preprocessed
                .units
                .iter()
                .map(|unit| unit.path.as_os_str().len() * 2)
                .sum::<usize>()
            + self.preprocessed.unit_digests.capacity() * 32
            + self
                .resource_requests
                .iter()
                .map(|request| {
                    std::mem::size_of::<ResourceRequest>()
                        + request.archive_name.capacity()
                        + request.disk_path.as_os_str().len() * 2
                })
                .sum::<usize>()
            + self
                .source_digests
                .keys()
                .map(|path| path.as_os_str().len() * 2 + 96)
                .sum::<usize>()
            + self
                .missing_dependencies
                .iter()
                .map(|path| path.as_os_str().len() * 2 + 32)
                .sum::<usize>()
            + self
                .preprocessed
                .map_includes
                .iter()
                .chain(&self.preprocessed.skin_includes)
                .chain(&self.preprocessed.file_dirs)
                .map(|path| path.as_os_str().len() * 2 + 32)
                .sum::<usize>()
            + self
                .diagnostics
                .iter()
                .map(|text| text.capacity() + 24)
                .sum::<usize>()
            + self.project_digest.capacity()
            + self.resources_digest.capacity()
            + self.maps_digest.capacity()
            + self
                .proof
                .borrow()
                .as_ref()
                .map_or(0, InputProof::resident_bytes)
            + self
                .asset_proof
                .borrow()
                .as_ref()
                .map_or(0, InputProof::resident_bytes)
            + self
                .source_proof
                .borrow()
                .as_ref()
                .map_or(0, InputProof::resident_bytes)
    }
    /// Recheck exact source and asset bytes without preprocessing or scanning
    /// the expanded DM text again. A new FILE_DIR shadow also invalidates it.
    fn still_current(&self, project: &Path) -> bool {
        if let Some(proof) = self.proof.borrow().as_ref() {
            return proof
                .namespace_current()
                .unwrap_or_else(|| proof.current() && self.resolutions_current(project, true));
        }
        // Capture before exact reads, then compare after them. Capturing only
        // afterwards could accidentally bless an edit made during verification.
        let previous_assets = self.asset_proof.borrow().clone();
        let validated_sources = self.source_proof.borrow().clone();
        let proof = if let Some(sources) = &validated_sources {
            let assets = previous_assets.clone().or_else(|| {
                InputProof::capture(
                    self.preprocessed.map_includes.iter().cloned().chain(
                        self.resource_requests
                            .iter()
                            .map(|request| request.disk_path.clone()),
                    ),
                )
            });
            assets.and_then(|assets| sources.clone().combined(&assets))
        } else if let Some(assets) = &previous_assets {
            InputProof::capture(self.source_digests.keys().cloned())
                .and_then(|sources| sources.combined(assets))
        } else {
            InputProof::capture(
                self.source_digests
                    .keys()
                    .cloned()
                    .chain(self.preprocessed.map_includes.iter().cloned())
                    .chain(
                        self.resource_requests
                            .iter()
                            .map(|request| request.disk_path.clone()),
                    ),
            )
        };
        // An inherited namespace proof covers the same resource lookup candidates
        // and missing includes. Validate it before doing any per-path resolution walk.
        let mut proof = proof;
        if let Some(candidate) = proof.as_mut() {
            let mut namespace_candidates = self.missing_dependencies.clone();
            let root = project.parent().unwrap_or_else(|| Path::new("."));
            for request in &self.resource_requests {
                namespace_candidates.push(root.join(&request.archive_name));
                for directory in &self.preprocessed.file_dirs {
                    namespace_candidates.push(root.join(directory).join(&request.archive_name));
                }
            }
            if candidate.reuse_namespace(&namespace_candidates) {
                *self.asset_proof.borrow_mut() = candidate.subset(
                    self.preprocessed.map_includes.iter().cloned().chain(
                        self.resource_requests
                            .iter()
                            .map(|request| request.disk_path.clone()),
                    ),
                );
                *self.proof.borrow_mut() = proof;
                *self.source_proof.borrow_mut() = None;
                return true;
            }
        }
        if (!(validated_sources.is_some() && proof.is_some())
            && !dm_work::map_ordered(
                &self.source_digests.iter().collect::<Vec<_>>(),
                dm_work::WorkLimits::configured(),
                |_| 16 * 1024,
                |(path, expected)| {
                    project_discovery::read_prepared_source(path, dm_work::WorkLimits::configured())
                        .is_ok_and(|source| source.digest == **expected)
                },
            )
            .is_ok_and(|results| results.into_iter().all(|current| current)))
            || self.missing_dependencies.iter().any(|path| path.exists())
        {
            return false;
        }
        // The final combined proof validates the original asset stamps. No
        // asset metadata scan is needed before validating source bytes.
        let assets_current = previous_assets.is_some() && proof.is_some();
        let maps = if assets_current {
            None
        } else {
            Some(
                match load_map_set_from_paths(project, &self.preprocessed.map_includes) {
                    Ok(maps) => maps,
                    Err(_) => return false,
                },
            )
        };
        if maps.is_some_and(|maps| hex_digest(&maps.fingerprint) != self.maps_digest) {
            return false;
        }
        if !self.resolutions_current(project, false) {
            return false;
        }
        let valid = assets_current
            || ResourceSet::fingerprint_requests(self.resource_requests.clone())
                .is_ok_and(|fingerprint| hex_digest(&fingerprint) == self.resources_digest);
        if valid {
            if let Some(mut proof) = proof {
                // Establishment compares every expected file stamp under an
                // exclusive barrier. A successful journal avoids repeating the
                // same full metadata scan before returning the validated proof.
                let mut namespace_candidates = self.missing_dependencies.clone();
                let root = project.parent().unwrap_or_else(|| Path::new("."));
                for request in &self.resource_requests {
                    namespace_candidates.push(root.join(&request.archive_name));
                    for directory in &self.preprocessed.file_dirs {
                        namespace_candidates.push(root.join(directory).join(&request.archive_name));
                    }
                }
                proof.enable_namespace_journal(&namespace_candidates);
                // Establishing a change cursor cannot bless a resolution change
                // between the earlier resolution scan and that cursor.
                if !self.resolutions_current(project, true) || !proof.current() {
                    return false;
                }
                let assets = proof.subset(
                    self.preprocessed.map_includes.iter().cloned().chain(
                        self.resource_requests
                            .iter()
                            .map(|request| request.disk_path.clone()),
                    ),
                );
                *self.asset_proof.borrow_mut() = assets;
                *self.proof.borrow_mut() = Some(proof);
                *self.source_proof.borrow_mut() = None;
            }
        }
        valid
    }

    fn resolutions_current(&self, project: &Path, proven: bool) -> bool {
        #[cfg(test)]
        RESOLUTION_WALKS.with(|count| count.set(count.get() + 1));
        if self.missing_dependencies.iter().any(|path| path.exists()) {
            return false;
        }
        let mut resolved_names = BTreeSet::new();
        if self.resource_requests.iter().any(|request| {
            if !resolved_names.insert((&request.archive_name, &request.disk_path)) {
                return false;
            }
            if proven {
                return !proven_resource_resolution_current(
                    project,
                    &request.archive_name,
                    &request.disk_path,
                    &self.preprocessed.file_dirs,
                );
            }
            resolved_resource_disk_path(
                project,
                &request.archive_name,
                &self.preprocessed.file_dirs,
            ) != request.disk_path
        }) {
            return false;
        }
        true
    }
}

fn hex_digest(bytes: &[u8; 32]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

struct ActiveSession {
    compiler: CompilerSession,
    last_used: u64,
}

struct ActiveProject {
    prepared_revision: String,
    last_response: Option<Response>,
    last_used: u64,
}

#[cfg(test)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct FileStamp {
    len: u64,
    modified: Option<std::time::SystemTime>,
    #[cfg(windows)]
    changed: i64,
}

#[cfg(test)]
fn file_stamp(path: &Path) -> Option<FileStamp> {
    let metadata = fs::metadata(path).ok()?;
    Some(FileStamp {
        len: metadata.len(),
        modified: metadata.modified().ok(),
        #[cfg(windows)]
        changed: windows_change_time(path)?,
    })
}

#[cfg(all(test, windows))]
fn windows_change_time(path: &Path) -> Option<i64> {
    use std::os::windows::io::AsRawHandle;

    #[repr(C)]
    struct FileBasicInfo {
        creation_time: i64,
        last_access_time: i64,
        last_write_time: i64,
        change_time: i64,
        file_attributes: u32,
    }

    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetFileInformationByHandleEx(
            file: *mut std::ffi::c_void,
            info_class: i32,
            info: *mut std::ffi::c_void,
            info_size: u32,
        ) -> i32;
    }

    let file = fs::File::open(path).ok()?;
    let mut info = std::mem::MaybeUninit::<FileBasicInfo>::uninit();
    // FileBasicInfo is information class 0. The call initializes the buffer
    // only when it reports success.
    let ok = unsafe {
        GetFileInformationByHandleEx(
            file.as_raw_handle(),
            0,
            info.as_mut_ptr().cast(),
            std::mem::size_of::<FileBasicInfo>() as u32,
        )
    };
    (ok != 0).then(|| unsafe { info.assume_init().change_time })
}

struct CachedSyntax {
    summary: SyntaxSummary,
    last_used: u64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct SyntaxSummary {
    item_count: usize,
    diagnostics: Vec<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct ProjectSummary {
    item_count: usize,
    diagnostics: Vec<String>,
}

impl Coordinator {
    fn incremental_directory(&self, artifact: &ArtifactKey) -> io::Result<PathBuf> {
        let family = serde_json::to_vec(&(
            artifact.format_version,
            &artifact.compiler_version,
            &artifact.target,
            &artifact.input_digests[1..],
            &artifact.dependency_digests,
        ))
        .map_err(io::Error::other)?;
        Ok(self
            .blobs
            .root
            .join("incremental-checkpoints-v1")
            .join(dm_compiler::incremental::digest(&family)))
    }

    fn prepare_native_build(
        &mut self,
        session_key: &SessionKey,
        artifact: &ArtifactKey,
        project: &Path,
        preprocessed: &PreprocessedProject,
        expansion: &prepared_project::SegmentedExpansion,
        builtins: &[u8],
        world_name: &str,
        resources: &str,
        maps: &str,
        archive_hint: Option<&VerifiedArchive>,
        prepared_maps: &dm_compiler::maps::MapSet,
        prepared_resources: &[ResourceRequest],
        canonical: bool,
    ) -> Result<PreparedBuild, String> {
        let mut frontend = self
            .frontend_pool
            .take_or_insert(session_key, self.blobs.root.clone());
        frontend.set_segmented_source(expansion.source());
        let compatibility;
        let preprocessed = if canonical {
            preprocessed
        } else {
            let text = match expansion.materialize() {
                Ok(text) => text,
                Err(error) => {
                    self.frontend_pool.put(session_key.clone(), frontend);
                    return Err(error);
                }
            };
            compatibility = PreprocessedProject {
                text,
                ..preprocessed.clone()
            };
            &compatibility
        };
        let result = self.prepare_native_build_with_frontend(
            artifact,
            project,
            preprocessed,
            builtins,
            world_name,
            resources,
            maps,
            archive_hint,
            prepared_maps,
            prepared_resources,
            canonical,
            &mut frontend,
        );
        self.frontend_pool.put(session_key.clone(), frontend);
        result
    }

    fn prepare_native_build_with_frontend(
        &mut self,
        artifact: &ArtifactKey,
        project: &Path,
        preprocessed: &PreprocessedProject,
        builtins: &[u8],
        world_name: &str,
        resources: &str,
        maps: &str,
        archive_hint: Option<&VerifiedArchive>,
        prepared_maps: &dm_compiler::maps::MapSet,
        prepared_resources: &[ResourceRequest],
        canonical: bool,
        frontend: &mut dm_compiler::frontend::OutlineSession,
    ) -> Result<PreparedBuild, String> {
        if canonical {
            // Canonical builds are owned by the retained frontend graph. Do
            // not inspect linked checkpoints or initialize the legacy engine.
            self.retained_world = None;
        } else {
            self.incremental
                .set_cache_root(dm_compiler::lower_cache::default_cache_root(project));
            let directory = self
                .incremental_directory(artifact)
                .map_err(|error| error.to_string())?;
            let mut candidates = fs::read_dir(&directory)
                .ok()
                .into_iter()
                .flatten()
                .filter_map(Result::ok)
                .filter(|entry| {
                    entry
                        .path()
                        .extension()
                        .is_some_and(|extension| extension == "json")
                })
                .map(|entry| entry.path())
                .collect::<Vec<_>>();
            candidates.sort();
            candidates.reverse();
            candidates.truncate(32);
            let retained = self
                .retained_world
                .take()
                .filter(|world| world.family == directory);
            if retained.is_some() || !candidates.is_empty() {
                let outline = frontend.update(preprocessed)?;
                if std::env::var_os("DM_BUILD_TRACE").is_some() {
                    eprintln!(
                        "DM_BUILD_TRACE incremental frontend: {:?}, {} retained bytes",
                        frontend.stats(),
                        frontend.resident_bytes()
                    );
                }
                enum Candidate {
                    Live(RetainedWorld),
                    Disk(PathBuf),
                }
                let candidates = retained
                    .into_iter()
                    .map(Candidate::Live)
                    .chain(candidates.into_iter().map(Candidate::Disk));
                for candidate in candidates {
                    let live_candidate = matches!(&candidate, Candidate::Live(_));
                    let (record, checkpoint, dmb, mut indexed) = match candidate {
                        Candidate::Live(world) => {
                            if world.record.abi_digest != outline.abi_digest {
                                continue;
                            }
                            let indexed = world.indexed;
                            if std::env::var_os("DM_BUILD_TRACE").is_some() {
                                eprintln!("DM_BUILD_TRACE retained linked world hit");
                            }
                            (world.record, world.checkpoint, world.dmb, indexed)
                        }
                        Candidate::Disk(path) => {
                            let Some(record) = fs::metadata(&path)
                                .ok()
                                .filter(|metadata| metadata.len() <= 4096)
                                .and_then(|_| fs::read(&path).ok())
                                .and_then(|bytes| {
                                    serde_json::from_slice::<IncrementalRecord>(&bytes).ok()
                                })
                            else {
                                continue;
                            };
                            if record.version != 1 || record.abi_digest != outline.abi_digest {
                                continue;
                            }
                            let Ok(bytes) = self.blobs.get_bounded(
                                "native-checkpoint-v1",
                                &record.checkpoint_digest,
                                64 * 1024 * 1024,
                            ) else {
                                continue;
                            };
                            let Some(checkpoint) =
                                dm_compiler::incremental::decode_checkpoint(&bytes)
                            else {
                                continue;
                            };
                            drop(bytes);
                            let Ok(bytes) = self.blobs.get_bounded(
                                "project-dmb-v1",
                                &record.dmb_digest,
                                256 * 1024 * 1024,
                            ) else {
                                continue;
                            };
                            let Ok((dmb, spans)) =
                                byond_dmb::dmb::Dmb::from_bytes_with_list_spans(&bytes)
                            else {
                                continue;
                            };
                            let indexed =
                                dm_output::list_image::ListImage::capture(bytes, &dmb, spans)
                                    .map_err(|error| error.to_string())?;
                            (record, checkpoint, dmb, indexed)
                        }
                    };
                    self.incremental
                        .set_baseline_identity(record.dmb_digest.clone());
                    let result = dm_compiler::incremental::try_emit_outline(
                        outline.clone(),
                        dmb,
                        checkpoint,
                        &mut self.incremental,
                    );
                    let Ok(Some(emission)) = result else {
                        continue;
                    };
                    let archive = archive_hint
                        .filter(|archive| archive.digest() == record.rsc_digest)
                        .cloned();
                    let rsc_bytes = if archive.is_some() {
                        Vec::new()
                    } else {
                        let Ok(bytes) = self.blobs.get_bounded(
                            "project-rsc-v1",
                            &record.rsc_digest,
                            512 * 1024 * 1024,
                        ) else {
                            continue;
                        };
                        bytes
                    };
                    if std::env::var_os("DM_BUILD_TRACE").is_some() {
                        eprintln!(
                        "DM_BUILD_TRACE incremental emission: {} changed procedures, {} preserved",
                        emission.changed_procs,
                        record.emitted_procs.saturating_sub(emission.changed_procs)
                    );
                    }
                    #[cfg(test)]
                    if live_candidate {
                        self.retained_world_hits += 1;
                    }
                    #[cfg(not(test))]
                    let _ = live_candidate;
                    let serialized_dmb = indexed
                        .serialize_changed(&emission.dmb, &emission.changed_lists)
                        .map_err(|error| error.to_string())?;
                    if std::env::var_os("DM_BUILD_TRACE").is_some() {
                        eprintln!(
                            "DM_BUILD_TRACE indexed DMB serialization: {}",
                            serialized_dmb.is_some()
                        );
                    }
                    let list_spans = if serialized_dmb.is_some() {
                        Some(
                            indexed
                                .updated_spans(&emission.dmb)
                                .map_err(|error| error.to_string())?,
                        )
                    } else {
                        None
                    };
                    let list_image =
                        if let (Some(bytes), Some(spans)) = (&serialized_dmb, &list_spans) {
                            indexed.rebase(bytes.clone(), spans.clone());
                            Some(indexed)
                        } else {
                            None
                        };
                    return Ok(PreparedBuild {
                        serialized_dmb,
                        list_spans,
                        list_image,
                        dmb: emission.dmb,
                        rsc_bytes,
                        archive,
                        emitted_procs: record.emitted_procs,
                        lowered_procs: emission.changed_procs,
                        reused_procs: record.emitted_procs.saturating_sub(emission.changed_procs),
                        artifact_reuse: dm_compiler::ArtifactReuseStats::default(),
                        checkpoint: Some(emission.checkpoint),
                    });
                }
            }
        }
        let catalog_key = ArtifactKey {
            stage: "resource-catalog-v1".into(),
            format_version: 1,
            compiler_version: artifact.compiler_version.clone(),
            target: artifact.target.clone(),
            input_digests: vec![resources.to_owned()],
            dependency_digests: Vec::new(),
        };
        let catalog = if canonical {
            archive_hint.and_then(|archive| {
                let bytes = self.blobs.get_artifact(&catalog_key).ok().flatten()?;
                let record: ArchiveCatalogRecord = serde_json::from_slice(&bytes).ok()?;
                (record.version == 1
                    && record.archive_digest == archive.digest()
                    && hex_digest(&record.catalog.fingerprint) == resources
                    && record.catalog.validate().is_ok())
                .then_some(record.catalog)
            })
        } else {
            None
        };
        let mut reused_archive = catalog.as_ref().and(archive_hint).cloned();
        let prepared_archive = if canonical && catalog.is_none() {
            Some(
                dm_resources::prepare_archive(&self.blobs.root, prepared_resources)
                    .map_err(|error| error.to_string())?,
            )
        } else {
            None
        };
        let catalog = catalog.or_else(|| {
            prepared_archive
                .as_ref()
                .map(|archive| archive.catalog().clone())
        });
        let compiled = if let Some(catalog) = &catalog {
            dm_compiler::bootstrap::compile_preprocessed_project_with_resource_catalog(
                project,
                preprocessed,
                builtins,
                world_name,
                frontend,
                prepared_maps,
                catalog,
            )?
        } else {
            compile_preprocessed_project_with_resources_prepared_mode(
                project,
                preprocessed,
                builtins,
                world_name,
                frontend,
                prepared_maps,
                prepared_resources,
                !canonical,
            )?
        };
        if hex_digest(&compiled.resource_fingerprint) != resources
            || hex_digest(&compiled.map_fingerprint) != maps
        {
            return Err("project map/resource inputs changed during build; retry".into());
        }
        if let Some(archive) = &prepared_archive {
            reused_archive = Some(
                VerifiedArchive::from_prepared_archive(archive, &compiled.dmb)
                    .map_err(|error| error.to_string())?,
            );
        }
        if prepared_archive.is_some() || reused_archive.is_none() {
            // Store compact metadata only after the canonical archive is fully
            // constructed. A subsequent build also requires its verified RSC.
            let record = ArchiveCatalogRecord {
                version: 1,
                archive_digest: reused_archive
                    .as_ref()
                    .map(|archive| archive.digest().to_owned())
                    .unwrap_or_else(|| format!("{:x}", Sha256::digest(&compiled.rsc_bytes))),
                catalog: compiled.resource_catalog.clone(),
            };
            if let Ok(bytes) = serde_json::to_vec(&record) {
                let _ = self.blobs.put_artifact(&catalog_key, &bytes);
            }
        }
        Ok(PreparedBuild {
            serialized_dmb: None,
            list_spans: None,
            list_image: None,
            emitted_procs: compiled.emitted.len(),
            lowered_procs: compiled.artifact_reuse.authored_lowered,
            reused_procs: compiled.artifact_reuse.authored_reused(),
            artifact_reuse: compiled.artifact_reuse,
            dmb: compiled.dmb,
            rsc_bytes: compiled.rsc_bytes,
            archive: reused_archive,
            checkpoint: compiled.checkpoint,
        })
    }

    fn store_incremental_checkpoint(
        &self,
        artifact: &ArtifactKey,
        checkpoint: &dm_compiler::incremental::EmissionCheckpoint,
        dmb_digest: &str,
        rsc_digest: &str,
        emitted_procs: usize,
    ) -> io::Result<usize> {
        let started = Instant::now();
        let bytes =
            dm_compiler::incremental::encode_checkpoint(checkpoint).map_err(io::Error::other)?;
        if std::env::var_os("DM_BUILD_TRACE").is_some() {
            eprintln!(
                "DM_BUILD_TRACE incremental checkpoint: {} procedures, {} bytes, encode {:.3}s",
                checkpoint.procedures.len(),
                bytes.len(),
                started.elapsed().as_secs_f64()
            );
        }
        let checkpoint_size = bytes.len();
        let checkpoint_digest = self.blobs.put("native-checkpoint-v1", &bytes)?;
        let record = IncrementalRecord {
            version: 1,
            abi_digest: checkpoint.abi_digest.clone(),
            checkpoint_digest,
            dmb_digest: dmb_digest.into(),
            rsc_digest: rsc_digest.into(),
            emitted_procs,
        };
        let bytes = serde_json::to_vec(&record).map_err(io::Error::other)?;
        let directory = self.incremental_directory(artifact)?;
        fs::create_dir_all(&directory)?;
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let name = format!(
            "{stamp:040}-{}-{}.json",
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        );
        let temporary = directory.join(format!("{name}.tmp"));
        let destination = directory.join(name);
        let mut file = fs::OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&temporary)?;
        file.write_all(&bytes)?;
        file.sync_all()?;
        drop(file);
        fs::rename(&temporary, &destination)?;
        let mut records = fs::read_dir(&directory)?
            .filter_map(Result::ok)
            .map(|entry| entry.path())
            .filter(|path| {
                path.extension()
                    .is_some_and(|extension| extension == "json")
            })
            .collect::<Vec<_>>();
        records.sort();
        let excess = records.len().saturating_sub(32);
        for old in records.into_iter().take(excess) {
            let _ = fs::remove_file(old);
        }
        Ok(checkpoint_size)
    }

    pub fn new(cache_root: impl Into<PathBuf>) -> io::Result<Self> {
        Self::with_limits(cache_root, CoordinatorLimits::default())
    }

    pub fn with_limits(
        cache_root: impl Into<PathBuf>,
        limits: CoordinatorLimits,
    ) -> io::Result<Self> {
        if limits.max_diagnostic_sessions == 0 || limits.max_syntax_summaries == 0 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "daemon cache limits must be positive",
            ));
        }
        Ok(Self {
            sessions: HashMap::new(),
            projects: HashMap::new(),
            blobs: ContentStore::new(cache_root)?,
            incremental: Default::default(),
            frontend_pool: frontend_pool::FrontendPool::default(),
            retained_world: None,
            serialization_validation: Default::default(),
            serialization_wire: Default::default(),
            #[cfg(test)]
            retained_world_hits: 0,
            syntax_cache: HashMap::new(),
            build_cache: HashMap::new(),
            build_inputs: HashMap::new(),
            asset_inventory: HashMap::new(),
            clock: 0,
            limits,
        })
    }

    pub fn handle(&mut self, request: Request) -> Response {
        self.clock = self.clock.saturating_add(1);
        self.frontend_pool.set_external_bytes(
            self.serialization_wire
                .resident_bytes()
                .saturating_add(self.serialization_validation.resident_bytes())
                .saturating_add(dm_compiler::bootstrap::shared_declaration_cache_bytes())
                .saturating_add(
                    self.asset_inventory
                        .values()
                        .map(|x| x.resident_bytes())
                        .sum::<usize>(),
                ),
        );
        self.evict_idle(self.limits.max_idle_requests);
        // Diagnostic sessions can retain Salsa syntax trees. Bound the number
        // of worktree configurations held in memory; their disk CAS survives.
        while self.session_count() >= self.limits.max_diagnostic_sessions {
            let source = self
                .sessions
                .iter()
                .min_by_key(|(_, value)| value.last_used)
                .map(|(key, value)| (key.clone(), value.last_used));
            let project = self
                .projects
                .iter()
                .min_by_key(|(_, value)| value.last_used)
                .map(|(key, value)| (key.clone(), value.last_used));
            match (source, project) {
                (Some((_, used)), Some((other, other_used))) if other_used < used => {
                    self.projects.remove(&other);
                }
                (Some((key, _)), _) => {
                    self.sessions.remove(&key);
                }
                (_, Some((key, _))) => {
                    self.projects.remove(&key);
                }
                _ => break,
            }
        }
        if self.syntax_cache.len() >= self.limits.max_syntax_summaries {
            if let Some(key) = self
                .syntax_cache
                .iter()
                .min_by_key(|(_, value)| value.last_used)
                .map(|(key, _)| key.clone())
            {
                self.syntax_cache.remove(&key);
            }
        }
        match request {
            Request::Ping => Response {
                ok: true,
                item_count: 0,
                diagnostics: vec![],
                source_digest: None,
                shared_syntax_hit: false,
                failure_kind: None,
                error: None,
                build: None,
            },
            Request::Check { key, source, text } => {
                if let Err(error) =
                    dm_compiler::check_source_size(text.len(), self.limits.max_check_source_bytes)
                {
                    return failed_project(error);
                }
                let digest = match self.blobs.put("source-v1", text.as_bytes()) {
                    Ok(digest) => digest,
                    Err(error) => {
                        return Response {
                            ok: false,
                            item_count: 0,
                            diagnostics: vec![],
                            source_digest: None,
                            shared_syntax_hit: false,
                            failure_kind: None,
                            error: Some(error.to_string()),
                            build: None,
                        }
                    }
                };
                let session = self.sessions.entry(key).or_insert_with(|| ActiveSession {
                    compiler: CompilerSession::default(),
                    last_used: self.clock,
                });
                session.last_used = self.clock;
                session.compiler.update_file(source.clone(), text);
                let artifact_key = ArtifactKey {
                    stage: "syntax-summary".into(),
                    format_version: 1,
                    compiler_version: BUILD_FINGERPRINT.into(),
                    target: None,
                    input_digests: vec![digest.clone()],
                    dependency_digests: vec![],
                };
                let summary_result: io::Result<(SyntaxSummary, bool)> = (|| {
                    if let Some(cached) = self.syntax_cache.get_mut(&digest) {
                        cached.last_used = self.clock;
                        return Ok((cached.summary.clone(), true));
                    }
                    if let Some(summary) = self.blobs.get_json_artifact(&artifact_key)? {
                        return Ok((summary, true));
                    }
                    let ast = session
                        .compiler
                        .parse(&source)
                        .expect("source was just registered");
                    let summary = summary_from_ast(ast);
                    let bytes = serde_json::to_vec(&summary).map_err(io::Error::other)?;
                    self.blobs.put_artifact(&artifact_key, &bytes)?;
                    self.syntax_cache.insert(
                        digest.clone(),
                        CachedSyntax {
                            summary: summary.clone(),
                            last_used: self.clock,
                        },
                    );
                    Ok((summary, false))
                })();
                let (summary, shared_syntax_hit) = match summary_result {
                    Ok(value) => value,
                    Err(error) => {
                        return Response {
                            ok: false,
                            item_count: 0,
                            diagnostics: vec![],
                            source_digest: Some(digest),
                            shared_syntax_hit: false,
                            failure_kind: None,
                            error: Some(error.to_string()),
                            build: None,
                        }
                    }
                };
                Response {
                    ok: summary.diagnostics.is_empty(),
                    item_count: summary.item_count,
                    diagnostics: summary.diagnostics,
                    source_digest: Some(digest),
                    shared_syntax_hit,
                    failure_kind: None,
                    error: None,
                    build: None,
                }
            }
            Request::CheckProject { key } => self.check_project(key),
            Request::BuildProject {
                key,
                builtins,
                output_root,
            } => self.build_project(key, builtins, output_root),
            Request::BuildProjectPatch {
                key,
                builtins,
                dmb,
                rsc,
                exclusive,
            } => self.patch_project(key, builtins, dmb, rsc, exclusive),
        }
    }

    fn patch_project(
        &mut self,
        key: SessionKey,
        builtins: PathBuf,
        dmb: PathBuf,
        rsc: PathBuf,
        exclusive: bool,
    ) -> Response {
        let trace = std::env::var("DM_BUILD_TRACE").is_ok_and(|value| value != "0");
        if !exclusive {
            return failed_project(
                "patching requires exclusive ownership of stopped output files".into(),
            );
        }
        if !builtins.is_absolute() || !dmb.is_absolute() || !rsc.is_absolute() {
            return failed_project("patch request paths must be absolute".into());
        }
        let same_file = matches!((dmb.canonicalize(), rsc.canonicalize()),
            (Ok(left), Ok(right)) if left == right);
        if dmb == rsc || same_file {
            return failed_project("DMB and RSC paths must differ".into());
        }
        let journal = dmb.with_extension("dmb.undo-journal");
        if journal.exists() {
            if let Err(error) = recover_pair(&dmb, &rsc, &journal) {
                return failed_project(format!("recover interrupted patch: {error}"));
            }
        }
        // Fetch from the shared CAS or compile directly into bounded memory.
        // The patch path never publishes another complete output generation.
        let mut desired = None;
        let response = self.build_project_mode(key, builtins, None, &mut desired);
        if !response.ok {
            return response;
        }
        let Some(mut build) = response.build.clone() else {
            return failed_project("build returned no output pair".into());
        };
        let Some((new_dmb, new_rsc)) = desired else {
            return failed_project("build returned no output bytes".into());
        };
        let patch_plan_started = Instant::now();
        let pair = (|| -> io::Result<_> {
            let old_dmb = fs::read(&dmb)?;
            let old_rsc = fs::read(&rsc)?;
            validate_byond_pair(&new_dmb, &new_rsc)?;
            Ok(plan_pair(
                &old_dmb,
                &old_rsc,
                &new_dmb,
                &new_rsc,
                PatchPolicy::default(),
            ))
        })();
        let plan = match pair {
            Ok(plan) => plan,
            Err(error) => return failed_project(error.to_string()),
        };
        trace_build(trace, "patch planning", patch_plan_started);
        let patch_started = Instant::now();
        match plan {
            PairPlan::Unchanged => {}
            PairPlan::Patch { .. } => {
                if let Err(error) = apply_pair_in_place(&dmb, &rsc, &journal, &plan) {
                    return failed_project(error.to_string());
                }
            }
            PairPlan::Rebuild { .. } => {
                return failed_project("output layout changed; publish a new generation".into());
            }
        }
        trace_build(trace, "patch publication", patch_started);
        build.dmb = dmb;
        build.rsc = rsc;
        Response {
            build: Some(build),
            ..response
        }
    }

    /// Detached inputs for compilation, linting, documentation and syntax tools.
    /// The result owns no live query database; all facts name its frozen revision.
    pub fn prepare_project(
        &mut self,
        key: &SessionKey,
    ) -> io::Result<Arc<prepared_project::PreparedProject>> {
        let defines = dm_compiler::target_defines(key.defines.iter().cloned().collect());
        let mut cache = self
            .frontend_pool
            .take_discovery(key, self.blobs.root.clone());
        let result = cache.prepare(&key.project, &defines);
        self.frontend_pool.put_discovery(key.clone(), cache);
        result
    }

    pub fn project_frontend_snapshot(
        &mut self,
        key: &SessionKey,
    ) -> io::Result<ProjectFrontendSnapshot> {
        self.project_frontend_snapshot_bounded(key, self.limits.max_check_source_bytes)
    }

    /// The same prepared-input/frontend pipeline with an explicit caller budget.
    /// This does not change CheckProject's configured source limit.
    pub fn project_frontend_snapshot_bounded(
        &mut self,
        key: &SessionKey,
        max_source_bytes: usize,
    ) -> io::Result<ProjectFrontendSnapshot> {
        let prepared = self.prepare_project(key)?;
        dm_compiler::check_source_size(prepared.expansion.bytes, max_source_bytes)
            .map_err(io::Error::other)?;
        Ok(self.frontend_from_prepared(key, prepared))
    }

    /// Analysis uses native persisted local AST fragments and resolved owner
    /// queries directly. No whole-project AST or output binary is required.
    pub fn project_analysis_view(
        &mut self,key:&SessionKey,max_source_bytes:usize,builtin_image:&[u8],
    ) -> io::Result<ProjectAnalysisView> {
        let prepared=self.prepare_project(key)?;
        dm_compiler::check_source_size(prepared.expansion.bytes,max_source_bytes).map_err(io::Error::other)?;
        let mut frontend=self.frontend_pool.take_or_insert(key,self.blobs.root.clone());
        let view=frontend.analysis_view_segmented(&prepared.expansion.source(),builtin_image);
        self.frontend_pool.put(key.clone(),frontend);
        let view=view.map_err(|errors|io::Error::other(errors.join("\n")))?;
        Ok(ProjectAnalysisView {prepared,view})
    }

    fn frontend_from_prepared(
        &mut self,
        key: &SessionKey,
        prepared: Arc<prepared_project::PreparedProject>,
    ) -> ProjectFrontendSnapshot {
        let mut frontend = self
            .frontend_pool
            .take_or_insert(key, self.blobs.root.clone());
        let parsed = frontend.compact_declarations_segmented(&prepared.expansion.source());
        self.frontend_pool.put(key.clone(), frontend);
        match parsed {
            Ok((ast, _)) => {
                let declarations = dm_compiler::index_ast(&ast);
                ProjectFrontendSnapshot {
                    prepared,
                    ast: Arc::new(ast),
                    declarations,
                    syntax_errors: Vec::new(),
                    syntax_complete: true,
                }
            }
            Err(error) => {
                let mut syntax_errors = dm_compiler::authored_syntax_errors_segmented(
                    &prepared.project,
                    key.project.parent().unwrap_or(Path::new(".")),
                    &prepared.expansion.source(),
                );
                if syntax_errors.is_empty() {
                    syntax_errors.push(error);
                }
                ProjectFrontendSnapshot {
                    prepared,
                    ast: Arc::new(AstFile::default()),
                    declarations: Err(Vec::new()),
                    syntax_errors,
                    syntax_complete: false,
                }
            }
        }
    }

    fn check_project(&mut self, key: SessionKey) -> Response {
        let prepared = match self.prepare_project(&key) {
            Ok(value) => value,
            Err(error) => return failed_project(error.to_string()),
        };
        let discovery = &prepared.project;
        if let Err(error) = dm_compiler::check_source_size(
            prepared.expansion.bytes,
            self.limits.max_check_source_bytes,
        ) {
            return failed_project(error);
        }
        if let Some(project) = self.projects.get_mut(&key) {
            if project.prepared_revision == prepared.revision {
                if let Some(mut response) = project.last_response.clone() {
                    project.last_used = self.clock;
                    response.shared_syntax_hit = true;
                    return response;
                }
            }
        }
        let mut diagnostics: Vec<String> = discovery
            .diagnostics
            .iter()
            .map(|d| format!("{}:{}: {}", d.path.display(), d.line, d.message))
            .collect();
        // Include order and macros are represented by the exact expanded text.
        // Source blob hashes are retained above for reuse by other pure stages.
        let digest = prepared.expanded_digest.clone();
        let artifact_key = ArtifactKey {
            stage: "project-summary".into(),
            format_version: 3,
            compiler_version: BUILD_FINGERPRINT.into(),
            target: None,
            input_digests: vec![digest.clone()],
            dependency_digests: vec![],
        };
        // Successful summaries are pure content facts and can cross worktrees.
        // Diagnostics have authored filenames/lines, so their presentation
        // cache must additionally name the exact source/origin revision.
        let presentation_key = ArtifactKey {
            stage: "project-presentation-summary".into(),
            dependency_digests: vec![prepared.revision.clone()],
            ..artifact_key.clone()
        };
        let cached_summary = self
            .blobs
            .get_json_artifact::<ProjectSummary>(&artifact_key)
            .and_then(|shared| match shared {
                Some(summary) => Ok(Some(summary)),
                None => self
                    .blobs
                    .get_json_artifact::<ProjectSummary>(&presentation_key),
            });
        let summary = match cached_summary {
            Ok(Some(summary)) => (summary, true),
            Ok(None) => {
                let frontend = self.frontend_from_prepared(&key, Arc::clone(&prepared));
                let mut summary = ProjectSummary {
                    item_count: frontend.ast.items.len(),
                    diagnostics: frontend.syntax_errors,
                };
                if let Err(errors) = frontend.declarations {
                    summary.diagnostics.extend(errors.iter().cloned());
                }
                let bytes = match serde_json::to_vec(&summary) {
                    Ok(bytes) => bytes,
                    Err(error) => return failed_project(error.to_string()),
                };
                let cache_key = if summary.diagnostics.is_empty() {
                    &artifact_key
                } else {
                    &presentation_key
                };
                if let Err(error) = self.blobs.put_artifact(cache_key, &bytes) {
                    return failed_project(error.to_string());
                }
                (summary, false)
            }
            Err(error) => return failed_project(error.to_string()),
        };
        diagnostics.extend(summary.0.diagnostics);
        let response = Response {
            ok: diagnostics.is_empty(),
            item_count: summary.0.item_count,
            diagnostics,
            source_digest: Some(digest),
            shared_syntax_hit: summary.1,
            failure_kind: None,
            error: None,
            build: None,
        };
        self.projects.insert(
            key,
            ActiveProject {
                prepared_revision: prepared.revision.clone(),
                last_response: Some(response.clone()),
                last_used: self.clock,
            },
        );
        response
    }

    fn build_project(
        &mut self,
        key: SessionKey,
        builtins: PathBuf,
        output_root: PathBuf,
    ) -> Response {
        self.build_project_mode(key, builtins, Some(output_root), &mut None)
    }

    fn build_project_mode(
        &mut self,
        key: SessionKey,
        builtins: PathBuf,
        output_root: Option<PathBuf>,
        pair_out: &mut Option<(Vec<u8>, Vec<u8>)>,
    ) -> Response {
        let response = self.build_project_mode_once(key.clone(), builtins.clone(), output_root.clone(), pair_out);
        if !response.error.as_deref().is_some_and(|error| error.starts_with("expanded-cache:")) {
            return response;
        }
        // Restart the whole transaction after repair: never mix a repaired source
        // revision into a partially lowered build. The second attempt is final.
        self.build_inputs.remove(&key);
        let mut discovery = self.frontend_pool.take_discovery(&key, self.blobs.root.clone());
        let defines = dm_compiler::target_defines(key.defines.iter().cloned().collect());
        let repaired = discovery.rebuild_expansion(&key.project, &defines);
        self.frontend_pool.put_discovery(key.clone(), discovery);
        if let Err(error) = repaired { return failed_internal(error); }
        *pair_out = None;
        self.build_project_mode_once(key, builtins, output_root, pair_out)
    }

    fn build_project_mode_once(
        &mut self,
        key: SessionKey,
        builtins: PathBuf,
        output_root: Option<PathBuf>,
        pair_out: &mut Option<(Vec<u8>, Vec<u8>)>,
    ) -> Response {
        let trace = std::env::var("DM_BUILD_TRACE").is_ok_and(|value| value != "0");
        if key.compiler_version != BUILD_FINGERPRINT {
            return failed_project(
                "compiler fingerprint mismatch; reconnect with this daemon version".into(),
            );
        }
        let defines = dm_compiler::target_defines(key.defines.iter().cloned().collect());
        let world_name = match key.project.file_stem().and_then(|stem| stem.to_str()) {
            Some(name) => name.to_owned(),
            None => return failed_project("project filename has no world name".into()),
        };
        let builtins = match fs::read(&builtins) {
            Ok(bytes) => bytes,
            Err(error) => return failed_project(error.to_string()),
        };
        let builtins_digest = format!("{:x}", Sha256::digest(&builtins));
        let output_root = match output_root
            .map(|root| fs::create_dir_all(&root).and_then(|()| root.canonicalize()))
            .transpose()
        {
            Ok(path) => path,
            Err(error) => return failed_internal(error),
        };
        // Verify the published generation before validating retained inputs. If
        // both match, the exact source/resource/shadow check is the final operation
        // needed before returning; another identical scan cannot improve freshness.
        if let (Some(entry), Some(root)) = (self.build_inputs.get(&key), &output_root) {
            let snapshot = &entry.snapshot;
            let retained_key = BuildCacheKey {
                project_digest: snapshot.project_digest.clone(),
                builtins_digest: builtins_digest.clone(),
                resources_digest: snapshot.resources_digest.clone(),
                maps_digest: snapshot.maps_digest.clone(),
                world_name: world_name.clone(),
                target: key.target.clone(),
                defines: key.defines.clone(),
                build_mode: key.build_mode.clone(),
                compiler_version: key.compiler_version.clone(),
                output_root: root.clone(),
            };
            if let Some(cached) = self.build_cache.get(&retained_key).cloned() {
                let output_matches =
                    current_generation(root)
                        .ok()
                        .flatten()
                        .is_some_and(|generation| {
                            generation.id == cached.generation
                                && generation.dmb == cached.dmb
                                && generation.rsc == cached.rsc
                                && verify_generation_digest(root, &generation).is_ok()
                        });
                if output_matches {
                    let verify_started = Instant::now();
                    let stable = snapshot.still_current(&key.project);
                    trace_build(trace, "retained input validation", verify_started);
                    if stable {
                        let mut result = cached;
                        result.cache_hit = true;
                        result.lowered_procs = 0;
                        result.reused_procs = result.emitted_procs;
                        let source_digest = snapshot.project_digest.clone();
                        self.build_inputs.get_mut(&key).unwrap().last_used = self.clock;
                        return Response {
                            ok: true,
                            item_count: result.emitted_procs,
                            diagnostics: vec![],
                            source_digest: Some(source_digest),
                            shared_syntax_hit: true,
                            failure_kind: None,
                            error: None,
                            build: Some(result),
                        };
                    }
                }
            }
        }
        let receipt_key = output_root
            .as_ref()
            .and_then(|root| receipt_key(&key, &builtins_digest, root));
        let mut disk_input_proof = None;
        // The CAS verifies receipt bytes; output validation still verifies the
        // actual published pair. A corrupt/missing receipt is simply a miss.
        if let (Some(root), Some(receipt_key)) = (&output_root, &receipt_key) {
            if let Ok(Some(receipt)) = self.blobs.load_receipt(receipt_key) {
                // A stale source receipt still contains authenticated earlier file
                // barriers. Reuse only per-file unchanged proofs, never its result.
                disk_input_proof = Some(receipt.proof.clone());
                if current_generation(root)
                    .ok()
                    .flatten()
                    .is_some_and(|generation| {
                        generation.id == receipt.result.generation
                            && generation.dmb == receipt.result.dmb
                            && generation.rsc == receipt.result.rsc
                            && verify_generation_digest(root, &generation).is_ok()
                    })
                    && receipt.current(&key.project)
                {
                    let mut result = receipt.result;
                    result.cache_hit = true;
                    result.lowered_procs = 0;
                    result.reused_procs = result.emitted_procs;
                    return Response {
                        ok: true,
                        item_count: result.emitted_procs,
                        diagnostics: vec![],
                        source_digest: Some(receipt.source_digest),
                        shared_syntax_hit: true,
                        failure_kind: None,
                        error: None,
                        build: Some(result),
                    };
                }
            }
        }
        let project_root = key.project.parent().unwrap_or(&key.worktree);
        let inventory_key = asset_inventory_key(&key);
        let retained_assets = self.asset_inventory.get(&key).cloned().or_else(|| {
            let store = dm_store::Store::open(self.blobs.root.join("asset-inventory.redb")).ok()?;
            let record = store
                .read_many(
                    &[dm_store::Key::new("asset-inventory-v1", &inventory_key)],
                    None,
                )
                .ok()?;
            let bytes = record.values.into_iter().next().flatten()?;
            if bytes.len() > 16 * 1024 * 1024 {
                return None;
            }
            serde_json::from_slice::<AssetInventory>(&bytes)
                .ok()
                .map(Arc::new)
        });
        let previous_inventory = self
            .build_inputs
            .get(&key)
            .map(|entry| {
                (
                    entry.snapshot.source_resource_literals.clone(),
                    entry.snapshot.preprocessed.file_dirs.clone(),
                    entry.snapshot.preprocessed.skin_includes.clone(),
                    entry.snapshot.preprocessed.map_includes.clone(),
                    entry.snapshot.map_set.fingerprint,
                )
            })
            .or_else(|| {
                retained_assets.as_ref().map(|assets| {
                    (
                        assets.literals.clone(),
                        assets.dirs.clone(),
                        assets.skins.clone(),
                        assets.maps.clone(),
                        assets.map_fingerprint,
                    )
                })
            });
        let previous_assets = self
            .build_inputs
            .get(&key)
            .and_then(|entry| {
                let snapshot = &entry.snapshot;
                let proof = snapshot.asset_proof.borrow().clone()?;
                Some({
                    (
                        proof,
                        snapshot.resource_requests.clone(),
                        snapshot.resources_digest.clone(),
                        snapshot.preprocessed.map_includes.clone(),
                    )
                })
            })
            .or_else(|| {
                retained_assets.as_ref().map(|assets| {
                    (
                        assets.proof.clone(),
                        assets.requests.clone(),
                        assets.resource_digest.clone(),
                        assets.maps.clone(),
                    )
                })
            });
        let previous_map_set = self
            .build_inputs
            .get(&key)
            .map(|entry| Arc::clone(&entry.snapshot.map_set));
        let previous_input_proof = self
            .build_inputs
            .get(&key)
            .and_then(|entry| entry.snapshot.proof.borrow().clone())
            .or(disk_input_proof);
        let unchanged_sources = previous_input_proof
            .as_ref()
            .map(InputProof::unchanged_paths)
            .unwrap_or_default();
        let mut discovery_cache = self
            .frontend_pool
            .take_discovery(&key, self.blobs.root.clone());
        let mut frontend = self
            .frontend_pool
            .take_or_insert(&key, self.blobs.root.clone());
        let mut source_snapshot = || -> io::Result<BuildInputSnapshot> {
            let discovery_started = Instant::now();
            let mut prepared = discovery_cache.prepare_with_previous(
                &key.project,
                &defines,
                &unchanged_sources,
                previous_input_proof.as_ref(),
            )?;
            let requests_started = Instant::now();
            let mut literal_result = frontend.resource_literals_segmented(&prepared.expansion.source());
            if literal_result.as_ref().is_err_and(|error| error.starts_with("expanded-cache:")) {
                prepared = discovery_cache.rebuild_expansion(&key.project, &defines)?;
                literal_result = frontend.resource_literals_segmented(&prepared.expansion.source());
            }
            trace_build(trace, "resource literal query", requests_started);
            let discovery = &prepared.project;
            let source_proof = prepared.proof.clone();
            trace_build(trace, "project discovery/preprocessing", discovery_started);
            let limit = std::env::var("DM_BUILD_MAX_SOURCE_BYTES")
                .ok()
                .and_then(|value| value.parse::<usize>().ok())
                .unwrap_or(64 * 1024 * 1024);
            if prepared.expansion.bytes > limit {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    format!(
                        "preprocessed project is {} bytes, above the build limit of {limit}; set DM_BUILD_MAX_SOURCE_BYTES to raise it",
                        prepared.expansion.bytes
                    ),
                ));
            }
            let diagnostics: Vec<_> = discovery
                .diagnostics
                .iter()
                .map(|d| format!("{}:{}: {}", d.path.display(), d.line, d.message))
                .collect();
            let missing_dependencies = discovery
                .dependencies
                .iter()
                .filter(|path| !prepared.sources.contains_key(*path))
                .cloned()
                .collect();
            let hash_started = Instant::now();
            let source_digests = prepared
                .sources
                .iter()
                .map(|(path, source)| (path.clone(), source.digest))
                .collect();
            trace_build(trace, "source hashing", hash_started);
            let resources_started = Instant::now();
            // Observe the asset proof once for this preparation transaction.
            // Final publication separately revalidates the combined input proof;
            // repeated observations here neither extend its validity nor help
            // detect a race, but each can walk thousands of files.
            let previous_assets_current =
                previous_assets.as_ref().is_some_and(|(proof, _, _, _)| {
                    previous_input_proof
                        .as_ref()
                        .is_some_and(|observed| proof.validated_by(observed, &unchanged_sources))
                        || proof.current()
                });
            // Map barriers precede their read/decode; resource barriers are
            // produced by the shared input cache before its exact hash reads.
            let map_proof = if previous_assets_current {
                previous_assets
                    .as_ref()
                    .and_then(|(proof, _, _, _)| {
                        proof.subset(discovery.map_includes.iter().cloned())
                    })
                    .or_else(|| InputProof::capture(discovery.map_includes.iter().cloned()))
            } else {
                InputProof::capture(discovery.map_includes.iter().cloned())
            };
            let maps = match previous_map_set.as_ref().filter(|_| {
                previous_assets.as_ref().is_some_and(|(_, _, _, paths)| {
                    *paths == discovery.map_includes && previous_assets_current
                })
            }) {
                Some(maps) => Arc::clone(maps),
                None => Arc::new(
                    load_map_set_from_paths(&key.project, &discovery.map_includes)
                        .map_err(io::Error::other)?,
                ),
            };
            trace_build(trace, "active map loading", resources_started);
            let verified_hints = previous_assets.as_ref().filter(|_| previous_assets_current);
            let literals = literal_result.map_err(|error| {
                    // Resource discovery shares the structural lexer and may
                    // reject source before a retained snapshot is assembled.
                    let authored = dm_compiler::authored_syntax_errors_segmented(
                        &discovery,
                        project_root,
                        &prepared.expansion.source(),
                    );
                    io::Error::other(if authored.is_empty() {
                        error
                    } else {
                        authored.join("\n")
                    })
                })?;
            let resolution_started = Instant::now();
            let reusable_inventory = previous_inventory.as_ref().is_some_and(
                |(old_literals, dirs, skins, map_paths, map_fingerprint)| {
                    *old_literals == literals
                        && *dirs == discovery.file_dirs
                        && *skins == discovery.skin_includes
                        && *map_paths == discovery.map_includes
                        && *map_fingerprint == maps.fingerprint
                },
            ) && previous_assets
                .as_ref()
                .is_some_and(|(proof, _, _, _)| proof.namespace_current() == Some(true));
            let resource_requests = if reusable_inventory {
                previous_assets.as_ref().unwrap().1.clone()
            } else {
                #[cfg(test)]
                RESOURCE_RESOLUTIONS.with(|count| count.set(count.get() + 1));
                resolved_resource_requests_with_literals(
                    &key.project,
                    &literals,
                    &maps,
                    &discovery.skin_includes,
                    &discovery.file_dirs,
                    verified_hints.map_or(&[], |(_, requests, _, _)| requests.as_slice()),
                )
                .map_err(io::Error::other)?
            };
            trace_build(trace, "resource path resolution", resolution_started);
            trace_build(trace, "resource request scan", requests_started);
            let asset_hash_started = Instant::now();
            let reusable_assets =
                previous_assets
                    .as_ref()
                    .filter(|(_, requests, _, map_includes)| {
                        *map_includes == discovery.map_includes
                            && requests.len() == resource_requests.len()
                            && requests.iter().zip(&resource_requests).all(|(old, new)| {
                                old.archive_name == new.archive_name
                                    && old.disk_path == new.disk_path
                            })
                            && previous_assets_current
                    });
            let (resources_digest, prepared_asset_proof) =
                if let Some((proof, _, digest, _)) = reusable_assets {
                    (digest.clone(), Some(proof.clone()))
                } else {
                    let (fingerprint, resources_proof) =
                        discovery_cache.fingerprint_resources(&resource_requests)?;
                    let proof = map_proof
                        .and_then(|maps| {
                            resources_proof.and_then(|resources| maps.combined(&resources))
                        })
                        .filter(InputProof::current);
                    (hex_digest(&fingerprint), proof)
                };
            trace_build(trace, "resource byte hashing", asset_hash_started);
            let maps_digest = hex_digest(&maps.fingerprint);
            trace_build(trace, "map/resource fingerprinting", resources_started);
            Ok(BuildInputSnapshot {
                proof: Default::default(),
                source_proof: std::cell::RefCell::new(source_proof),
                asset_proof: std::cell::RefCell::new(prepared_asset_proof.or_else(|| {
                    previous_input_proof
                        .as_ref()?
                        .subset(
                            discovery.map_includes.iter().cloned().chain(
                                resource_requests
                                    .iter()
                                    .map(|request| request.disk_path.clone()),
                            ),
                        )
                        .filter(InputProof::current)
                })),
                project_digest: prepared.project_digest.clone(),
                diagnostics: diagnostics.clone(),
                resources_digest,
                maps_digest,
                map_set: maps,
                source_digests,
                missing_dependencies,
                resource_requests,
                source_resource_literals: literals,
                preprocessed: Arc::clone(&prepared.project),
                expansion: Arc::clone(&prepared.expansion),
            })
        };
        let retained = self.build_inputs.remove(&key);
        let inputs_started = Instant::now();
        let snapshot = if let Some(retained) =
            retained.filter(|entry| entry.snapshot.still_current(&key.project))
        {
            trace_build(trace, "retained input validation", inputs_started);
            Ok(retained.snapshot)
        } else {
            source_snapshot()
        };
        drop(source_snapshot);
        self.frontend_pool.put(key.clone(), frontend);
        self.frontend_pool
            .put_discovery(key.clone(), discovery_cache);
        let snapshot = match snapshot {
            Ok(snapshot) => snapshot,
            Err(error) => return failed_project(error.to_string()),
        };
        let project_digest = &snapshot.project_digest;
        let resources_digest = &snapshot.resources_digest;
        let maps_digest = &snapshot.maps_digest;
        let diagnostics = &snapshot.diagnostics;
        if !diagnostics.is_empty() {
            return Response {
                ok: false,
                item_count: 0,
                diagnostics: diagnostics.clone(),
                source_digest: Some(project_digest.clone()),
                shared_syntax_hit: false,
                failure_kind: None,
                error: None,
                build: None,
            };
        }
        let cache_key = output_root.as_ref().map(|output_root| BuildCacheKey {
            project_digest: project_digest.clone(),
            builtins_digest: builtins_digest.clone(),
            resources_digest: resources_digest.clone(),
            maps_digest: maps_digest.clone(),
            world_name: world_name.clone(),
            target: key.target.clone(),
            defines: key.defines.clone(),
            build_mode: key.build_mode.clone(),
            compiler_version: key.compiler_version.clone(),
            output_root: output_root.clone(),
        });
        if let Some(cached) = cache_key.as_ref().and_then(|key| self.build_cache.get(key)) {
            if output_root.as_ref().is_some_and(|root| {
                current_generation(root)
                    .ok()
                    .flatten()
                    .is_some_and(|generation| {
                        generation.id == cached.generation
                            && verify_generation_digest(root, &generation).is_ok()
                    })
            }) {
                let verify_started = Instant::now();
                let stable = snapshot.still_current(&key.project);
                trace_build(trace, "input revalidation", verify_started);
                if !stable {
                    return failed_project("project sources changed during build; retry".into());
                }
                let mut result = cached.clone();
                result.cache_hit = true;
                result.lowered_procs = 0;
                result.reused_procs = result.emitted_procs;
                let source_digest = project_digest.clone();
                self.remember_build_inputs(key.clone(), snapshot);
                return Response {
                    ok: true,
                    item_count: result.emitted_procs,
                    diagnostics: vec![],
                    source_digest: Some(source_digest),
                    shared_syntax_hit: true,
                    failure_kind: None,
                    error: None,
                    build: Some(result),
                };
            }
        }
        let context = match serde_json::to_vec(&(
            &world_name,
            &key.target,
            &key.defines,
            &key.build_mode,
            &key.compiler_version,
        )) {
            Ok(bytes) => format!("{:x}", Sha256::digest(bytes)),
            Err(error) => return failed_internal(error),
        };
        let artifact = ArtifactKey {
            stage: "project-pair".into(),
            format_version: 4,
            compiler_version: key.compiler_version.clone(),
            target: Some(key.target.clone()),
            input_digests: vec![
                project_digest.clone(),
                builtins_digest,
                resources_digest.clone(),
                maps_digest.clone(),
            ],
            dependency_digests: vec![context],
        };
        let cache_started = Instant::now();
        let cached_bytes = match self.blobs.get_artifact(&artifact) {
            Ok(value) => value,
            Err(error)
                if matches!(
                    error.kind(),
                    io::ErrorKind::InvalidData | io::ErrorKind::NotFound
                ) =>
            {
                if let Err(error) = self.blobs.discard_corrupt_artifact(&artifact) {
                    return failed_internal(error);
                }
                None
            }
            Err(error) => return failed_internal(error),
        };
        let cached_archive_hint = output_root.as_ref().and_then(|root| {
            let generation = current_generation(root).ok().flatten()?;
            verified_archive(root, &generation).ok()
        });
        let mut cached_pair_archive = None;
        let mut cached_pair = match cached_bytes {
            Some(bytes) => match decode_cached_pair_with_archive(
                &self.blobs,
                &bytes,
                cached_archive_hint.as_ref(),
            ) {
                Ok((dmb, rsc, count, archive)) => {
                    cached_pair_archive = archive;
                    Some((dmb, rsc, count))
                }
                Err(error)
                    if matches!(
                        error.kind(),
                        io::ErrorKind::InvalidData | io::ErrorKind::NotFound
                    ) =>
                {
                    if let Err(error) = self.blobs.discard_corrupt_artifact(&artifact) {
                        return failed_internal(error);
                    }
                    None
                }
                Err(error) => return failed_internal(error),
            },
            None => None,
        };
        let mut bytecode_key = None;
        if cached_pair.is_none() && key.build_mode != "legacy-history" {
            let archive = match dm_resources::prepare_archive(&self.blobs.root, &snapshot.resource_requests) {
                Ok(archive) => archive,
                Err(error) => return failed_internal(error),
            };
            let mut independent = artifact.clone();
            independent.stage = "project-bytecode-catalog-v1".into();
            independent.dependency_digests.push(world_name.clone());
            independent.input_digests[2] = hex_digest(&archive.catalog().bytecode_fingerprint());
            let candidate = self.blobs.get_artifact(&independent).ok().flatten()
                .and_then(|bytes| serde_json::from_slice::<CachedPairManifest>(&bytes).ok())
                .filter(|record| record.version == PAIR_MANIFEST_VERSION);
            if let Some(record) = candidate {
                let hit = self.blobs.get("project-dmb-v1", &record.dmb_digest).ok()
                    .and_then(|bytes| {
                        let dmb = byond_dmb::dmb::Dmb::from_bytes(&bytes).ok()?;
                        let verified = VerifiedArchive::from_prepared_archive(&archive, &dmb).ok()?;
                        Some((bytes, verified))
                    });
                if let Some((bytes, verified)) = hit {
                    let manifest = CachedPairManifest {version: PAIR_MANIFEST_VERSION,
                        emitted_procs: record.emitted_procs, dmb_digest: record.dmb_digest,
                        rsc_digest: archive.digest().to_owned()};
                    if let Ok(encoded) = serde_json::to_vec(&manifest) { let _ = self.blobs.put_artifact(&artifact, &encoded); }
                    cached_pair_archive = Some(verified);
                    cached_pair = Some((bytes, Vec::new(), record.emitted_procs));
                }
            }
            // Persist catalog metadata; the addressed prepared archive cache lets
            // native preparation reuse these bytes without composing them again.
            if cached_pair.is_none() {
                let catalog_key = ArtifactKey {stage: "resource-catalog-v1".into(), format_version: 1,
                    compiler_version: artifact.compiler_version.clone(), target: artifact.target.clone(),
                    input_digests: vec![resources_digest.clone()], dependency_digests: Vec::new()};
                let record = ArchiveCatalogRecord {version: 1, archive_digest: archive.digest().to_owned(), catalog: archive.catalog().clone()};
                if let Ok(bytes) = serde_json::to_vec(&record) { let _ = self.blobs.put_artifact(&catalog_key, &bytes); }
                // Resource-only receipt requires a DMB; catalog reuse in native preparation
                // remains available through its addressed prepared archive cache.
            }
            bytecode_key = Some(independent);
        }
        trace_build(trace, "artifact CAS lookup", cache_started);
        let mut reused_archive = cached_pair_archive;
        let mut verified_bytecode = None;
        let (dmb_bytes, mut rsc_bytes, emitted_procs, cache_hit, lowered_procs, reused_procs) =
            if let Some((dmb, rsc, count)) = cached_pair {
                (dmb, rsc, count, true, 0, count)
            } else {
                let compile_started = Instant::now();
                let archive_hint = cached_archive_hint;
                let prepared = match self.prepare_native_build(
                    &key,
                    &artifact,
                    &key.project,
                    &snapshot.preprocessed,
                    &snapshot.expansion,
                    &builtins,
                    &world_name,
                    resources_digest,
                    maps_digest,
                    archive_hint.as_ref(),
                    &snapshot.map_set,
                    &snapshot.resource_requests,
                    key.build_mode != "legacy-history",
                ) {
                    Ok(prepared) => prepared,
                    Err(error) => {
                        if error.starts_with("expanded-cache:") { return failed_internal(error); }
                        let authored = dm_compiler::authored_syntax_errors_segmented(
                            &snapshot.preprocessed,
                            key.project.parent().unwrap_or(Path::new(".")),
                            &snapshot.expansion.source(),
                        );
                        return failed_project(if authored.is_empty() {
                            error
                        } else {
                            authored.join("\n")
                        });
                    }
                };
                trace_build(trace, "compiler", compile_started);
                if trace {
                    eprintln!(
                        "DM_BUILD_TRACE per-build semantic artifacts {:?}",
                        prepared.artifact_reuse
                    );
                }
                // CAS outputs describe the immutable input snapshot. Full emission
                // checks its resource/map fingerprints; incremental emission uses
                // that exact context's archive and linked world. Current disk input
                // freshness is checked once below, immediately before publication.
                // A concurrent edit may retain a valid old snapshot in CAS, but it
                // cannot publish that snapshot as the current project generation.
                let emitted_procs = prepared.emitted_procs;
                let lowered_procs = prepared.lowered_procs;
                let reused_procs = prepared.reused_procs;
                let pending_checkpoint = prepared.checkpoint;
                let dmb = prepared.dmb;
                let rsc_bytes = prepared.rsc_bytes;
                reused_archive = prepared.archive;
                let wire_started = Instant::now();
                let (dmb_bytes, list_spans) = match (prepared.serialized_dmb, prepared.list_spans) {
                    (Some(bytes), Some(spans)) => (bytes, spans),
                    _ => match dmb
                        .reference_validated(&mut self.serialization_validation)
                        .and_then(|image| {
                            VerifiedBytecode::serialize_cached(&image, &mut self.serialization_wire)
                        }) {
                        Ok((bytes, spans, receipt)) => {
                            verified_bytecode = Some(receipt);
                            (bytes, spans)
                        }
                        Err(error) => return failed_internal(error),
                    },
                };
                trace_build(trace, "bytecode validation/serialization", wire_started);
                let cache_write_started = Instant::now();
                let mut retained_record = None;
                let mut checkpoint_size = None;
                let mut write_pair = || -> io::Result<()> {
                    let dmb_digest = self.blobs.put("project-dmb-v1", &dmb_bytes)?;
                    let rsc_digest = if let Some(archive) = &reused_archive {
                        archive.digest().to_owned()
                    } else {
                        self.blobs.put("project-rsc-v1", &rsc_bytes)?
                    };
                    if let Some(checkpoint) = &pending_checkpoint {
                        let checkpoint_result = self.store_incremental_checkpoint(
                            &artifact,
                            checkpoint,
                            &dmb_digest,
                            &rsc_digest,
                            emitted_procs,
                        );
                        match checkpoint_result {
                            Ok(size) => checkpoint_size = Some(size),
                            Err(error) => {
                                if std::env::var_os("DM_BUILD_TRACE").is_some() {
                                    eprintln!(
                                    "DM_BUILD_TRACE incremental checkpoint unavailable: {error}"
                                );
                                }
                            }
                        }
                    }
                    if let Some(checkpoint) = &pending_checkpoint {
                        retained_record = Some(IncrementalRecord {
                            version: 1,
                            abi_digest: checkpoint.abi_digest.clone(),
                            checkpoint_digest: String::new(),
                            dmb_digest: dmb_digest.clone(),
                            rsc_digest: rsc_digest.clone(),
                            emitted_procs,
                        });
                    }
                    let manifest = CachedPairManifest {
                        version: PAIR_MANIFEST_VERSION,
                        emitted_procs,
                        dmb_digest,
                        rsc_digest,
                    };
                    let encoded_manifest = serde_json::to_vec(&manifest).map_err(io::Error::other)?;
                    self.blobs.put_artifact(&artifact, &encoded_manifest)?;
                    if let Some(bytecode_key) = &bytecode_key {
                        self.blobs.put_artifact(bytecode_key, &encoded_manifest)?;
                    }
                    Ok(())
                };
                if let Err(error) = write_pair() {
                    return failed_internal(error);
                }
                trace_build(trace, "artifact CAS write", cache_write_started);
                if let (Some(checkpoint), Some(record), Some(checkpoint_size)) =
                    (pending_checkpoint, retained_record, checkpoint_size)
                {
                    let indexed = match prepared.list_image {
                        Some(indexed) => indexed,
                        None => {
                            match dm_output::list_image::ListImage::from_verified_serialization(
                                dmb_bytes.clone(),
                                &dmb,
                                list_spans,
                            ) {
                                Ok(indexed) => indexed,
                                Err(error) => return failed_internal(error),
                            }
                        }
                    };
                    let resident =
                        world_resident_bytes(&dmb, &[], checkpoint_size) + indexed.resident_bytes();
                    if resident <= 320 * 1024 * 1024 {
                        self.retained_world = Some(RetainedWorld {
                            family: match self.incremental_directory(&artifact) {
                                Ok(path) => path,
                                Err(error) => return failed_internal(error),
                            },
                            record,
                            checkpoint,
                            dmb,
                            indexed,
                        });
                    }
                    if trace {
                        eprintln!(
                            "DM_BUILD_TRACE retained linked world: {resident} bytes, retained {}",
                            self.retained_world.is_some()
                        );
                    }
                }
                (
                    dmb_bytes,
                    rsc_bytes,
                    emitted_procs,
                    false,
                    lowered_procs,
                    reused_procs,
                )
            };
        let verify_started = Instant::now();
        let stable = snapshot.still_current(&key.project);
        trace_build(trace, "input revalidation", verify_started);
        if !stable {
            return failed_project("project sources changed during build; retry".into());
        }
        let (generation_id, dmb_path, rsc_path) = if let Some(root) = output_root {
            let previous_archive = current_generation(&root)
                .ok()
                .flatten()
                .map(|generation| generation.rsc);
            let publish_started = Instant::now();
            let published = if let Some(archive) = &reused_archive {
                let publication = match &verified_bytecode {
                    Some(receipt) => publish_generation_with_verified_bytecode(
                        &root, &dmb_bytes, archive, receipt,
                    ),
                    None => publish_generation_with_archive(&root, &dmb_bytes, archive),
                };
                match publication {
                    Ok(generation) => Ok(generation),
                    Err(_) => self
                        .blobs
                        .get_bounded("project-rsc-v1", archive.digest(), 512 * 1024 * 1024)
                        .and_then(|bytes| {
                            publish_generation_reusing_archive(&root, &dmb_bytes, &bytes, None)
                        }),
                }
            } else {
                publish_generation_reusing_archive(
                    &root,
                    &dmb_bytes,
                    &rsc_bytes,
                    previous_archive.as_deref(),
                )
            };
            let generation = match published {
                Ok(generation) => generation,
                Err(error) => return failed_internal(error),
            };
            trace_build(trace, "generation publication", publish_started);
            (generation.id, generation.dmb, generation.rsc)
        } else {
            if let Some(archive) = &reused_archive {
                if !archive.is_current() {
                    return failed_internal("resource archive changed before byte export");
                }
                rsc_bytes = match fs::read(archive.path()) {
                    Ok(bytes) => bytes,
                    Err(error) => return failed_internal(error),
                };
                if !archive.is_current() {
                    return failed_internal("resource archive changed during byte export");
                }
            }
            let id = pair_generation_id(&dmb_bytes, &rsc_bytes);
            *pair_out = Some((dmb_bytes, rsc_bytes));
            (id, PathBuf::new(), PathBuf::new())
        };
        let result = BuildResult {
            generation: generation_id,
            dmb: dmb_path,
            rsc: rsc_path,
            cache_hit,
            emitted_procs,
            lowered_procs,
            reused_procs,
        };
        if let Some(cache_key) = cache_key {
            if !self.build_cache.contains_key(&cache_key)
                && self.build_cache.len() >= MAX_BUILD_RESULTS
            {
                if let Some(evicted) = self.build_cache.keys().next().cloned() {
                    self.build_cache.remove(&evicted);
                }
            }
            self.build_cache.insert(cache_key, result.clone());
        }
        let source_digest = project_digest.clone();
        if let (Some(receipt_key), Some(proof)) = (receipt_key, snapshot.proof.borrow().clone()) {
            let receipt = BuildReceipt {
                proof,
                missing_dependencies: snapshot.missing_dependencies.clone(),
                resource_paths: snapshot
                    .resource_requests
                    .iter()
                    .map(|request| (request.archive_name.clone(), request.disk_path.clone()))
                    .collect(),
                file_dirs: snapshot.preprocessed.file_dirs.clone(),
                source_digest: source_digest.clone(),
                result: result.clone(),
            };
            // Optional acceleration must never turn a successful build into
            // a failure if the cache is unavailable or concurrently changed.
            let _ = self.blobs.store_receipt(&receipt_key, &receipt);
        }
        self.remember_build_inputs(key.clone(), snapshot);
        Response {
            ok: true,
            item_count: emitted_procs,
            diagnostics: vec![],
            source_digest: Some(source_digest),
            shared_syntax_hit: cache_hit,
            failure_kind: None,
            error: None,
            build: Some(result),
        }
    }

    fn remember_build_inputs(&mut self, key: SessionKey, snapshot: BuildInputSnapshot) {
        if let Some(proof) = snapshot.asset_proof.borrow().clone() {
            let assets = Arc::new(AssetInventory {
                proof,
                requests: snapshot.resource_requests.clone(),
                literals: snapshot.source_resource_literals.clone(),
                dirs: snapshot.preprocessed.file_dirs.clone(),
                skins: snapshot.preprocessed.skin_includes.clone(),
                maps: snapshot.preprocessed.map_includes.clone(),
                map_fingerprint: snapshot.map_set.fingerprint,
                resource_digest: snapshot.resources_digest.clone(),
            });
            if let Ok(bytes) = serde_json::to_vec(assets.as_ref()) {
                if bytes.len() <= 16 * 1024 * 1024 {
                    if let Ok(store) =
                        dm_store::Store::open(self.blobs.root.join("asset-inventory.redb"))
                    {
                        let _ = store.commit(
                            &[],
                            &[dm_store::Change::Put(
                                dm_store::Key::new("asset-inventory-v1", asset_inventory_key(&key)),
                                bytes,
                            )],
                            None,
                        );
                    }
                    while self.asset_inventory.len() >= self.limits.max_diagnostic_sessions
                        || self
                            .asset_inventory
                            .values()
                            .map(|x| x.resident_bytes())
                            .sum::<usize>()
                            .saturating_add(assets.resident_bytes())
                            > 32 * 1024 * 1024
                    {
                        if self.asset_inventory.is_empty() {
                            break;
                        }
                        if let Some(old) = self.asset_inventory.keys().next().cloned() {
                            self.asset_inventory.remove(&old);
                        }
                    }
                    self.asset_inventory.insert(key.clone(), assets);
                }
            }
        }
        let size = snapshot.resident_bytes();
        if std::env::var_os("DM_BUILD_TRACE").is_some() {
            eprintln!(
                "DM_BUILD_TRACE retained inputs: {} bytes, limit {} bytes",
                size, MAX_BUILD_INPUT_BYTES
            );
        }
        if size > MAX_BUILD_INPUT_BYTES {
            return;
        }
        while self.build_inputs.len() >= self.limits.max_diagnostic_sessions
            || self
                .build_inputs
                .values()
                .map(|entry| entry.snapshot.resident_bytes())
                .sum::<usize>()
                + size
                > MAX_BUILD_INPUT_BYTES
        {
            let Some(oldest) = self
                .build_inputs
                .iter()
                .min_by_key(|(_, entry)| entry.last_used)
                .map(|(key, _)| key.clone())
            else {
                break;
            };
            self.build_inputs.remove(&oldest);
        }
        self.build_inputs.insert(
            key,
            CachedBuildInputs {
                snapshot,
                last_used: self.clock,
            },
        );
    }

    pub fn session_count(&self) -> usize {
        self.sessions.len() + self.projects.len()
    }

    /// Evict sessions and memory-only syntax trees that have been idle for
    /// more than `max_idle_requests`. Immutable disk artifacts remain shared.
    pub fn evict_idle(&mut self, max_idle_requests: u64) -> (usize, usize) {
        let before_sessions = self.sessions.len() + self.projects.len();
        let before_syntax = self.syntax_cache.len();
        let now = self.clock;
        self.sessions
            .retain(|_, session| now.saturating_sub(session.last_used) <= max_idle_requests);
        self.projects
            .retain(|_, project| now.saturating_sub(project.last_used) <= max_idle_requests);
        self.build_inputs
            .retain(|_, inputs| now.saturating_sub(inputs.last_used) <= max_idle_requests);
        self.syntax_cache
            .retain(|_, syntax| now.saturating_sub(syntax.last_used) <= max_idle_requests);
        (
            before_sessions - self.session_count(),
            before_syntax - self.syntax_cache.len(),
        )
    }
}

fn failed_project(error: String) -> Response {
    Response {
        ok: false,
        item_count: 0,
        diagnostics: vec![],
        source_digest: None,
        shared_syntax_hit: false,
        failure_kind: Some(FailureKind::Source),
        error: Some(error),
        build: None,
    }
}

fn failed_internal(error: impl ToString) -> Response {
    let mut response = failed_project(error.to_string());
    response.failure_kind = Some(FailureKind::Internal);
    response
}

#[cfg(test)]
fn decode_cached_pair(store: &ContentStore, bytes: &[u8]) -> io::Result<(Vec<u8>, Vec<u8>, usize)> {
    decode_cached_pair_with_archive(store, bytes, None)
        .map(|(dmb, rsc, count, _)| (dmb, rsc, count))
}
fn decode_cached_pair_with_archive(
    store: &ContentStore,
    bytes: &[u8],
    archive: Option<&VerifiedArchive>,
) -> io::Result<(Vec<u8>, Vec<u8>, usize, Option<VerifiedArchive>)> {
    let manifest: CachedPairManifest = serde_json::from_slice(bytes).map_err(|error| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            format!("invalid pair manifest: {error}"),
        )
    })?;
    if manifest.version != PAIR_MANIFEST_VERSION
        || !valid_digest(&manifest.dmb_digest)
        || !valid_digest(&manifest.rsc_digest)
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "invalid pair manifest",
        ));
    }
    let dmb = store.get("project-dmb-v1", &manifest.dmb_digest)?;
    let reusable = archive
        .filter(|archive| archive.digest() == manifest.rsc_digest)
        .cloned();
    let rsc = if reusable.is_some() {
        Vec::new()
    } else {
        store.get("project-rsc-v1", &manifest.rsc_digest)?
    };
    Ok((dmb, rsc, manifest.emitted_procs, reusable))
}

fn pair_generation_id(dmb: &[u8], rsc: &[u8]) -> String {
    let mut hash = Sha256::new();
    hash.update(b"dm-output-generation-v1\0");
    hash.update((dmb.len() as u64).to_le_bytes());
    hash.update(dmb);
    hash.update((rsc.len() as u64).to_le_bytes());
    hash.update(rsc);
    format!("{:x}", hash.finalize())
}

fn trace_build(enabled: bool, stage: &str, started: Instant) {
    if enabled {
        eprintln!(
            "dm-compiled {stage}: {:.3}s",
            started.elapsed().as_secs_f64()
        );
    }
}

fn summary_from_ast(ast: &AstFile) -> SyntaxSummary {
    SyntaxSummary {
        item_count: ast.items.len(),
        diagnostics: ast
            .diagnostics
            .iter()
            .map(|diagnostic| format!("{diagnostic:?}"))
            .collect(),
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn concurrent_identical_artifact_publishers_leave_one_complete_blob() {
        use super::*;
        let root = std::env::temp_dir().join(format!(
            "dm-cas-race-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let key = ArtifactKey {
            stage: "race".into(),
            format_version: 1,
            compiler_version: BUILD_FINGERPRINT.into(),
            target: None,
            input_digests: vec![],
            dependency_digests: vec![],
        };
        let start = Arc::new(std::sync::Barrier::new(2));
        let handles = (0..2)
            .map(|_| {
                let root = root.clone();
                let key = key.clone();
                let start = start.clone();
                std::thread::spawn(move || {
                    let store = ContentStore::new(root).unwrap();
                    start.wait();
                    store.put_artifact_parts(&key, &[b"header", b"dmb", b"rsc"])
                })
            })
            .collect::<Vec<_>>();
        let digests = handles
            .into_iter()
            .map(|handle| handle.join().unwrap().unwrap())
            .collect::<Vec<_>>();
        assert_eq!(digests[0], digests[1]);
        assert_eq!(
            ContentStore::new(&root)
                .unwrap()
                .get_artifact(&key)
                .unwrap()
                .unwrap(),
            b"headerdmbrsc"
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn proven_resource_resolution_checks_only_higher_priority_shadows() {
        let root = std::env::temp_dir().join(format!(
            "dm-proof-shadow-{}-{}",
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(root.join("low")).unwrap();
        fs::create_dir_all(root.join("high")).unwrap();
        let project = root.join("world.dme");
        let dirs = vec![PathBuf::from("low"), PathBuf::from("high")];
        let selected = root.join("low/icon.dmi");
        fs::write(&selected, "asset").unwrap();
        assert!(proven_resource_resolution_current(
            &project, "icon.dmi", &selected, &dirs
        ));
        fs::write(root.join("high/icon.dmi"), "shadow").unwrap();
        assert!(!proven_resource_resolution_current(
            &project, "icon.dmi", &selected, &dirs
        ));
        let selected = root.join("high/icon.dmi");
        assert!(proven_resource_resolution_current(
            &project, "icon.dmi", &selected, &dirs
        ));
        fs::write(root.join("icon.dmi"), "direct").unwrap();
        assert!(!proven_resource_resolution_current(
            &project, "icon.dmi", &selected, &dirs
        ));
        assert!(proven_resource_resolution_current(
            &project,
            "icon.dmi",
            &root.join("icon.dmi"),
            &dirs
        ));
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn coordinator_errors_keep_included_authored_source_origins() {
        let root = std::env::temp_dir().join(format!(
            "dm-coordinator-origins-{}-{}",
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&root).unwrap();
        let builtins = root.join("builtins.dmb");
        fs::write(
            &builtins,
            include_bytes!("../../../fixtures/native_template.bin"),
        )
        .unwrap();
        let mut coordinator = Coordinator::new(root.join("cache")).unwrap();
        for (name, source, reason) in [
            (
                "unknown-procedure",
                "/proc/probe()\n    return definitely_absent_probe()\n",
                "definitely_absent_probe",
            ),
            (
                "unknown-type",
                "/proc/probe()\n    var/datum/definitely_absent_probe/value = new\n    return value\n",
                "definitely_absent_probe",
            ),
            (
                "lexical-error",
                "/proc/probe()\n    return \"unterminated\n",
                "unterminated",
            ),
        ] {
            let directory = root.join(name);
            fs::create_dir_all(&directory).unwrap();
            let manifest = directory.join("world.dme");
            fs::write(&manifest, "#include \"code.dm\"\n").unwrap();
            fs::write(directory.join("code.dm"), source).unwrap();
            let response = coordinator.handle(Request::BuildProject {
                key: SessionKey::new(&directory, &manifest, "516.1687", vec![], "canonical")
                    .unwrap(),
                builtins: builtins.clone(),
                output_root: directory.join("output"),
            });
            assert!(!response.ok, "{name}: {response:?}");
            assert!(
                response
                    .diagnostics
                    .iter()
                    .chain(response.error.iter())
                    .any(|message| message.contains("code.dm:2:") && message.contains(reason)),
                "{name}: expected authored code.dm:2 error: {response:?}"
            );
        }
        drop(coordinator);
        assert!(root
            .canonicalize()
            .unwrap()
            .starts_with(std::env::temp_dir().canonicalize().unwrap()));
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn cold_build_receipt_bypasses_discovery_and_rejects_edits_and_corruption() {
        let root = std::env::temp_dir().join(format!(
            "dm-cold-receipt-{}-{}",
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&root).unwrap();
        let manifest = root.join("world.dme");
        let source = root.join("code.dm");
        let builtins = root.join("builtins.dmb");
        fs::write(&manifest, "#include \"code.dm\"\n").unwrap();
        fs::write(&source, "/proc/value() return 7\n").unwrap();
        fs::write(
            &builtins,
            include_bytes!("../../../fixtures/native_template.bin"),
        )
        .unwrap();
        let key = SessionKey::new(&root, &manifest, "516.1687", vec![], "build").unwrap();
        let request = || Request::BuildProject {
            key: key.clone(),
            builtins: builtins.clone(),
            output_root: root.join("output"),
        };
        let cache = root.join("cache");
        let mut daemon = Coordinator::new(&cache).unwrap();
        let first = daemon.handle(request());
        assert!(first.ok, "{first:?}");
        // A retained generation must precede the cold receipt path. Give the
        // otherwise valid receipt distinguishable statistics; the live worker
        // must use its bounded in-memory result, without decoding that receipt.
        let hot_receipt_key = receipt_key(
            &key,
            &format!("{:x}", Sha256::digest(fs::read(&builtins).unwrap())),
            &root.join("output").canonicalize().unwrap(),
        )
        .unwrap();
        let mut receipt = daemon
            .blobs
            .load_receipt(&hot_receipt_key)
            .unwrap()
            .unwrap();
        let emitted = receipt.result.emitted_procs;
        receipt.result.emitted_procs += 99;
        daemon
            .blobs
            .store_receipt(&hot_receipt_key, &receipt)
            .unwrap();
        let hot = daemon.handle(request());
        assert!(hot.ok, "{hot:?}");
        let hot = hot.build.unwrap();
        assert!(hot.cache_hit);
        assert_eq!(hot.emitted_procs, emitted);
        assert_eq!(hot.lowered_procs, 0);
        assert_eq!(hot.reused_procs, emitted);
        receipt.result.emitted_procs = emitted;
        daemon
            .blobs
            .store_receipt(&hot_receipt_key, &receipt)
            .unwrap();
        drop(daemon);
        let preprocess = dm_compiler::preprocess_cache_path(&manifest).with_extension("index.json");
        fs::remove_file(&preprocess).unwrap();
        let mut restarted = Coordinator::new(&cache).unwrap();
        let reused = restarted.handle(request());
        assert!(reused.ok && reused.build.unwrap().cache_hit);
        assert!(
            !preprocess.exists(),
            "cold receipt must bypass preprocessing"
        );
        assert!(
            restarted.build_inputs.is_empty(),
            "receipt requires no expanded project resident memory"
        );
        let time = fs::metadata(&source).unwrap().modified().unwrap();
        fs::write(&source, "/proc/value() return 8\n").unwrap();
        fs::File::options()
            .write(true)
            .open(&source)
            .unwrap()
            .set_times(fs::FileTimes::new().set_modified(time))
            .unwrap();
        let changed = restarted.handle(request());
        assert!(changed.ok && !changed.build.unwrap().cache_hit);
        drop(restarted);
        fs::remove_file(&preprocess).unwrap();
        let mut restarted = Coordinator::new(&cache).unwrap();
        let reused = restarted.handle(request());
        assert!(reused.ok && reused.build.unwrap().cache_hit);
        assert!(
            !preprocess.exists(),
            "latest edited receipt must be persisted"
        );
        let key = receipt_key(
            &key,
            &format!("{:x}", Sha256::digest(fs::read(&builtins).unwrap())),
            &root.join("output").canonicalize().unwrap(),
        )
        .unwrap();
        {
            let read = restarted
                .blobs
                .metadata
                .read_many(
                    &[dm_store::Key::new(
                        "build-receipts-v2",
                        key.digest().unwrap(),
                    )],
                    None,
                )
                .unwrap();
            let pointer: ArtifactPointer =
                serde_json::from_slice(read.values[0].as_ref().unwrap()).unwrap();
            fs::write(
                cache
                    .join("build-receipt-v1")
                    .join(&pointer.payload_digest[..2])
                    .join(pointer.payload_digest),
                b"damaged",
            )
            .unwrap();
        }
        let recovered = restarted.handle(request());
        assert!(recovered.ok, "{recovered:?}");
        assert!(
            preprocess.exists(),
            "corrupt receipt must fall back to discovery"
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn build_snapshot_rejects_same_length_source_edit_and_new_resource_shadow() {
        use super::*;
        let root = std::env::temp_dir().join(format!(
            "dm-input-snapshot-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(root.join("assets")).unwrap();
        let project = root.join("world.dme");
        let source = root.join("code.dm");
        fs::write(&project, "#include \"code.dm\"\n").unwrap();
        fs::write(&source, "/proc/a() return 7\n").unwrap();
        fs::write(root.join("assets/icon.dmi"), b"asset").unwrap();
        let requests = vec![ResourceRequest {
            archive_name: "icon.dmi".into(),
            disk_path: root.join("assets/icon.dmi"),
        }];
        let maps = load_map_set_from_paths(&project, &[]).unwrap();
        let mut snapshot = BuildInputSnapshot {
            proof: Default::default(),
            source_proof: Default::default(),
            asset_proof: Default::default(),
            project_digest: String::new(),
            diagnostics: vec![],
            resources_digest: hex_digest(
                &ResourceSet::fingerprint_requests(requests.clone()).unwrap(),
            ),
            map_set: Arc::new(dm_compiler::maps::MapSet {
                files: vec![],
                fingerprint: [0; 32],
            }),
            maps_digest: hex_digest(&maps.fingerprint),
            source_digests: [(
                source.clone(),
                Sha256::digest(fs::read(&source).unwrap()).into(),
            )]
            .into(),
            missing_dependencies: vec![],
            resource_requests: requests,
            source_resource_literals: vec![],
            expansion: Arc::new(prepared_project::SegmentedExpansion::default()),
            preprocessed: Arc::new(PreprocessedProject {
                file_dirs: vec![PathBuf::from("assets")],
                ..Default::default()
            }),
        };
        assert!(snapshot.still_current(&project));
        fs::write(&source, "/proc/a() return 8\n").unwrap();
        assert!(!snapshot.still_current(&project));
        let previous = snapshot.proof.borrow().clone().unwrap();
        let mut refreshed = InputProof::capture([source.clone()]).unwrap();
        refreshed.inherit_unchanged(&previous);
        *snapshot.source_proof.borrow_mut() = Some(refreshed);
        *snapshot.proof.borrow_mut() = None;
        snapshot.source_digests.insert(
            source.clone(),
            Sha256::digest(fs::read(&source).unwrap()).into(),
        );
        let walks = RESOLUTION_WALKS.with(|count| count.get());
        assert!(snapshot.still_current(&project));
        if snapshot
            .proof
            .borrow()
            .as_ref()
            .unwrap()
            .namespace_current()
            == Some(true)
        {
            assert_eq!(
                RESOLUTION_WALKS.with(|count| count.get()),
                walks,
                "refreshed body proof must skip resource resolution walks"
            );
        }
        fs::write(root.join("icon.dmi"), b"shadow").unwrap();
        assert!(!snapshot.still_current(&project));
        fs::remove_file(root.join("icon.dmi")).unwrap();
        fs::rename(
            root.join("assets/icon.dmi"),
            root.join("assets/renamed.dmi"),
        )
        .unwrap();
        assert!(!snapshot.still_current(&project));
        fs::write(&source, "/proc/a() return 7\n").unwrap();
        fs::write(root.join("icon.dmi"), b"shadow").unwrap();
        assert!(!snapshot.still_current(&project));
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn repeated_resource_literals_resolve_once_without_losing_archive_aliases() {
        let root = std::env::temp_dir().join(format!(
            "dm-resource-resolution-{}-{}",
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(root.join("assets")).unwrap();
        let project = root.join("world.dme");
        fs::write(&project, "").unwrap();
        fs::write(root.join("assets/icon.dmi"), b"payload").unwrap();
        fs::write(root.join("skin.dmf"), "icon = 'icon.dmi'\n").unwrap();
        let maps = dm_compiler::maps::MapSet {
            files: vec![(
                root.join("map.dmm"),
                "'icon.dmi' 'assets/icon.dmi' 'icon.dmi'".into(),
            )],
            fingerprint: [0; 32],
        };
        let requests = resolved_resource_requests(
            &project,
            "/proc/f()\n    return list('icon.dmi','icon.dmi','assets/icon.dmi')\n",
            &maps,
            &[root.join("skin.dmf")],
            &[PathBuf::from("assets")],
        )
        .unwrap();
        assert_eq!(
            requests
                .iter()
                .map(|request| request.archive_name.as_str())
                .collect::<Vec<_>>(),
            ["icon.dmi", "assets/icon.dmi", "skin.dmf"]
        );
        let mut duplicated = requests.clone();
        duplicated.insert(1, requests[0].clone());
        duplicated.push(requests[1].clone());
        assert_eq!(
            ResourceSet::fingerprint_requests(requests).unwrap(),
            ResourceSet::fingerprint_requests(duplicated).unwrap()
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn git_worktrees_share_cold_artifacts_but_keep_source_revisions_separate() {
        use super::*;
        let root = std::env::temp_dir().join(format!(
            "dm-worktree-cache-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let first = root.join("first");
        let second = root.join("second");
        fs::create_dir_all(&first).unwrap();
        let git = |dir: &Path, args: &[&str]| {
            let output = Command::new("git")
                .args(args)
                .current_dir(dir)
                .output()
                .unwrap();
            assert!(
                output.status.success(),
                "git {:?}: {}",
                args,
                String::from_utf8_lossy(&output.stderr)
            );
        };
        git(&first, &["init", "-q"]);
        let source_text = "/proc/first()\n    return 7\n/proc/second()\n    return 8\n";
        fs::write(first.join("world.dme"), "#include \"code.dm\"\n").unwrap();
        fs::write(first.join("code.dm"), source_text).unwrap();
        git(&first, &["add", "world.dme", "code.dm"]);
        git(
            &first,
            &[
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.invalid",
                "commit",
                "-qm",
                "fixture",
            ],
        );
        assert!(second.starts_with(&root));
        git(
            &first,
            &[
                "worktree",
                "add",
                "-q",
                "-b",
                "fixture-edit",
                second.to_str().unwrap(),
            ],
        );
        let first_manifest = first.join("world.dme");
        let second_manifest = second.join("world.dme");
        let cache = default_cache_root(&first_manifest);
        assert_eq!(cache, default_cache_root(&second_manifest));
        assert_eq!(
            dm_compiler::preprocess_cache_path(&first_manifest),
            dm_compiler::preprocess_cache_path(&second_manifest)
        );
        assert_eq!(
            dm_compiler::lower_cache::default_cache_root(&first_manifest),
            dm_compiler::lower_cache::default_cache_root(&second_manifest)
        );
        let builtins = root.join("builtins.dmb");
        fs::write(
            &builtins,
            include_bytes!("../../../fixtures/native_template.bin"),
        )
        .unwrap();
        let build = |manifest: &Path, output_root: PathBuf| Request::BuildProject {
            key: SessionKey::new(
                manifest.parent().unwrap(),
                manifest,
                "516.1687",
                vec![],
                "build",
            )
            .unwrap(),
            builtins: builtins.clone(),
            output_root,
        };
        let first_request = || build(&first_manifest, first.join("output"));
        let second_request = || build(&second_manifest, second.join("output"));
        let first_build = Coordinator::new(&cache).unwrap().handle(first_request());
        assert!(first_build.ok, "{first_build:?}");
        let first_build = first_build.build.unwrap();
        assert!(!first_build.cache_hit);
        let first_bytes = fs::read(&first_build.dmb).unwrap();

        // A fresh coordinator in the other worktree must fetch the same pair
        // from the Git-common CAS without recompiling either procedure.
        let second_build = Coordinator::new(default_cache_root(&second_manifest))
            .unwrap()
            .handle(second_request());
        assert!(second_build.ok, "{second_build:?}");
        let second_build = second_build.build.unwrap();
        assert!(second_build.cache_hit);
        assert_eq!(fs::read(&second_build.dmb).unwrap(), first_bytes);

        fs::write(
            second.join("code.dm"),
            source_text.replace("return 8", "return 9"),
        )
        .unwrap();
        let mut edited_daemon = Coordinator::new(&cache).unwrap();
        let edited = edited_daemon.handle(second_request());
        assert!(edited.ok, "{edited:?}");
        let edited = edited.build.unwrap();
        assert!(!edited.cache_hit);
        assert!(edited.lowered_procs >= 1, "{edited:?}");
        assert!(edited.reused_procs >= 1, "{edited:?}");
        assert_ne!(fs::read(&edited.dmb).unwrap(), first_bytes);

        git(&second, &["add", "code.dm"]);
        git(
            &second,
            &[
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.invalid",
                "commit",
                "-qm",
                "edited fixture",
            ],
        );
        git(&second, &["checkout", "-q", "--detach", "HEAD~1"]);
        let head_changed = edited_daemon.handle(second_request());
        assert!(head_changed.ok, "{head_changed:?}");
        let head_changed = head_changed.build.unwrap();
        assert!(head_changed.cache_hit);
        assert_ne!(head_changed.generation, edited.generation);
        assert_eq!(fs::read(&head_changed.dmb).unwrap(), first_bytes);

        let unchanged = Coordinator::new(&cache).unwrap().handle(first_request());
        assert!(unchanged.ok, "{unchanged:?}");
        assert!(unchanged.build.unwrap().cache_hit);
        assert_eq!(fs::read(&first_build.dmb).unwrap(), first_bytes);

        git(
            &first,
            &["worktree", "remove", "--force", second.to_str().unwrap()],
        );
        assert!(root
            .canonicalize()
            .unwrap()
            .starts_with(std::env::temp_dir().canonicalize().unwrap()));
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn retained_body_edit_avoids_disk_decode_and_updates_growth_spans() {
        let root = std::env::temp_dir().join(format!(
            "dm-live-world-{}-{}",
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&root).unwrap();
        let manifest = root.join("world.dme");
        let source = root.join("code.dm");
        let schema = root.join("schema.dmb");
        let cache = root.join("cache");
        fs::write(&manifest, "#include \"code.dm\"\n").unwrap();
        fs::write(
            &source,
            "/proc/a()\n    return 1\n/proc/b()\n    return 7\n",
        )
        .unwrap();
        fs::write(
            &schema,
            include_bytes!("../../../fixtures/native_template.bin"),
        )
        .unwrap();
        let request = || Request::BuildProject {
            key: SessionKey::new(&root, &manifest, "516.1687", vec![], "legacy-history").unwrap(),
            builtins: schema.clone(),
            output_root: root.join("output"),
        };
        let mut daemon = Coordinator::new(&cache).unwrap();
        let first = daemon.handle(request());
        assert!(first.ok, "{first:?}");
        let old_digest = daemon
            .retained_world
            .as_ref()
            .unwrap()
            .record
            .dmb_digest
            .clone();
        // A disk decode cannot succeed, but the retained immutable world can.
        fs::remove_file(
            cache
                .join("project-dmb-v1")
                .join(&old_digest[..2])
                .join(&old_digest),
        )
        .unwrap();
        for body in ["    sleep(1)\n    return 9", "    return 3"] {
            fs::write(
                &source,
                format!("/proc/a()\n{body}\n/proc/b()\n    return 7\n"),
            )
            .unwrap();
            let response = daemon.handle(request());
            assert!(response.ok, "{response:?}");
            let result = response.build.unwrap();
            assert_eq!((result.lowered_procs, result.reused_procs), (1, 1));
            let world = daemon.retained_world.as_ref().unwrap();
            assert_eq!(world.indexed.bytes(), world.dmb.to_bytes().unwrap());
            let (_, spans) =
                byond_dmb::dmb::Dmb::from_bytes_with_list_spans(world.indexed.bytes()).unwrap();
            assert_eq!(world.indexed.spans(), spans);
        }
        assert_eq!(daemon.retained_world_hits, 2);
        assert!(
            world_resident_bytes(
                &daemon.retained_world.as_ref().unwrap().dmb,
                daemon.retained_world.as_ref().unwrap().indexed.bytes(),
                0
            ) < 320 * 1024 * 1024
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[cfg(windows)]
    #[test]
    fn body_generation_reuses_archive_without_resource_cas_blob() {
        let root = std::env::temp_dir().join(format!(
            "dm-live-archive-{}-{}",
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&root).unwrap();
        let manifest = root.join("world.dme");
        let source = root.join("code.dm");
        let schema = root.join("schema.dmb");
        let cache = root.join("cache");
        let output = root.join("output");
        fs::write(&manifest, "#include \"code.dm\"\n").unwrap();
        fs::write(
            &source,
            "/proc/a()\n    return 1\n/proc/b()\n    return 7\n",
        )
        .unwrap();
        fs::write(
            &schema,
            include_bytes!("../../../fixtures/native_template.bin"),
        )
        .unwrap();
        let request = || Request::BuildProject {
            key: SessionKey::new(&root, &manifest, "516.1687", vec![], "legacy-history").unwrap(),
            builtins: schema.clone(),
            output_root: output.clone(),
        };
        let mut daemon = Coordinator::new(&cache).unwrap();
        let first = daemon.handle(request());
        assert!(first.ok, "{first:?}");
        let original = current_generation(&output).unwrap().unwrap();
        let old_archive = fs::read(&original.rsc).unwrap();
        let digest = daemon
            .retained_world
            .as_ref()
            .unwrap()
            .record
            .rsc_digest
            .clone();
        let blob = cache
            .join("project-rsc-v1")
            .join(&digest[..2])
            .join(&digest);
        fs::remove_file(&blob).unwrap();
        fs::write(
            &source,
            "/proc/a()\n    sleep(1)\n    return 9\n/proc/b()\n    return 7\n",
        )
        .unwrap();
        let response = daemon.handle(request());
        assert!(response.ok, "{response:?}");
        let result = response.build.unwrap();
        assert_eq!((result.lowered_procs, result.reused_procs), (1, 1));
        assert!(
            !blob.exists(),
            "body generation must not reconstruct the RSC CAS blob"
        );
        let generation = current_generation(&output).unwrap().unwrap();
        assert_ne!(original.id, generation.id);
        assert_eq!(fs::read(&generation.rsc).unwrap(), old_archive);
        assert!(verified_archive(&output, &generation).is_ok());
        let world = daemon.retained_world.as_ref().unwrap();
        assert_eq!(
            fs::read(&generation.dmb).unwrap(),
            world.dmb.to_bytes().unwrap()
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn cold_body_edit_uses_linked_checkpoint_and_preserves_proc_ids() {
        use super::*;
        let root = std::env::temp_dir().join(format!(
            "dm-body-checkpoint-{}-{}",
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&root).unwrap();
        let manifest = root.join("world.dme");
        let source = root.join("code.dm");
        let schema = root.join("schema.dmb");
        let cache = root.join("cache");
        fs::write(&manifest, "#include \"code.dm\"\n").unwrap();
        fs::write(
            &source,
            "/proc/a()\n    return 1\n/proc/b(value=7)\n    return value\n",
        )
        .unwrap();
        fs::write(
            &schema,
            include_bytes!("../../../fixtures/native_template.bin"),
        )
        .unwrap();
        let request = || Request::BuildProject {
            key: SessionKey::new(&root, &manifest, "516.1687", vec![], "legacy-history").unwrap(),
            builtins: schema.clone(),
            output_root: root.join("output"),
        };
        let first = Coordinator::new(&cache).unwrap().handle(request());
        assert!(first.ok, "{first:?}");
        let first = first.build.unwrap();
        let before = byond_dmb::dmb::Dmb::from_bytes(&fs::read(&first.dmb).unwrap()).unwrap();
        let a = before
            .procs
            .iter()
            .position(|proc_| before.string(proc_.strings[0]) == Some(b"/proc/a"))
            .unwrap();
        let b = before
            .procs
            .iter()
            .position(|proc_| before.string(proc_.strings[0]) == Some(b"/proc/b"))
            .unwrap();
        fs::write(&source,"/proc/a()\n    var/local = \"fresh\"\n    return local\n/proc/b(value=7)\n    return value\n").unwrap();
        let edited = Coordinator::new(&cache).unwrap().handle(request());
        assert!(edited.ok, "{edited:?}");
        let edited = edited.build.unwrap();
        assert_eq!(edited.lowered_procs, 1);
        assert_eq!(edited.reused_procs, 1);
        let after = byond_dmb::dmb::Dmb::from_bytes(&fs::read(&edited.dmb).unwrap()).unwrap();
        assert_eq!(after.procs[b], before.procs[b]);
        assert_eq!(after.procs[a].strings, before.procs[a].strings);
        assert_eq!(
            after.procs[a].code_locals_args[0], before.procs[a].code_locals_args[0],
            "unshared code retains its stable list ID across growth"
        );
        assert_eq!(
            after.procs[a].code_locals_args[2],
            before.procs[a].code_locals_args[2]
        );
        let indexes = fs::read_dir(cache.join("incremental-checkpoints-v1"))
            .unwrap()
            .flat_map(|entry| fs::read_dir(entry.unwrap().path()).unwrap())
            .collect::<Vec<_>>();
        assert_eq!(indexes.len(), 2);
        // Damaged persisted checkpoints cannot prevent a correct full fallback.
        let records = indexes
            .into_iter()
            .map(|entry| {
                serde_json::from_slice::<IncrementalRecord>(
                    &fs::read(entry.unwrap().path()).unwrap(),
                )
                .unwrap()
            })
            .collect::<Vec<_>>();
        for record in records {
            fs::write(
                cache
                    .join("native-checkpoint-v1")
                    .join(&record.checkpoint_digest[..2])
                    .join(record.checkpoint_digest),
                b"corrupt",
            )
            .unwrap();
        }
        fs::write(
            &source,
            "/proc/a()\n    return 3\n/proc/b(value=7)\n    return value\n",
        )
        .unwrap();
        let repaired = Coordinator::new(&cache).unwrap().handle(request());
        assert!(repaired.ok, "{repaired:?}");
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn streamed_artifact_parts_match_joined_bytes_and_digest() {
        use super::*;
        let root = std::env::temp_dir().join(format!(
            "dm-cas-parts-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let store = ContentStore::new(&root).unwrap();
        let key = ArtifactKey {
            stage: "test-pair".into(),
            format_version: 1,
            compiler_version: BUILD_FINGERPRINT.into(),
            target: None,
            input_digests: vec![],
            dependency_digests: vec![],
        };
        let parts = [
            b"header".as_slice(),
            b"dmb-body".as_slice(),
            b"rsc-body".as_slice(),
        ];
        let joined = parts.concat();
        let streamed = store.put_artifact_parts(&key, &parts).unwrap();
        let ordinary = store.put_artifact(&key, &joined).unwrap();
        assert_eq!(streamed, ordinary);
        assert_eq!(streamed, format!("{:x}", Sha256::digest(&joined)));
        assert_eq!(store.get_artifact(&key).unwrap().unwrap(), joined);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn cached_pair_manifest_reuses_rsc_and_detects_corruption() {
        use super::*;
        let root = std::env::temp_dir().join(format!(
            "dm-split-pair-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let store = ContentStore::new(&root).unwrap();
        let rsc_digest = store.put("project-rsc-v1", b"unchanged assets").unwrap();
        let first_dmb = store.put("project-dmb-v1", b"first bytecode").unwrap();
        let second_dmb = store.put("project-dmb-v1", b"second bytecode").unwrap();
        assert_ne!(first_dmb, second_dmb);
        assert_eq!(
            rsc_digest,
            store.put("project-rsc-v1", b"unchanged assets").unwrap()
        );
        let resource_directory = root.join("project-rsc-v1").join(&rsc_digest[..2]);
        assert_eq!(fs::read_dir(&resource_directory).unwrap().count(), 1);
        let manifest = CachedPairManifest {
            version: PAIR_MANIFEST_VERSION,
            emitted_procs: 17,
            dmb_digest: second_dmb,
            rsc_digest: rsc_digest.clone(),
        };
        let payload = serde_json::to_vec(&manifest).unwrap();
        let (dmb, rsc, count) = decode_cached_pair(&store, &payload).unwrap();
        assert_eq!(
            (dmb.as_slice(), rsc.as_slice(), count),
            (
                b"second bytecode".as_slice(),
                b"unchanged assets".as_slice(),
                17
            )
        );
        fs::write(resource_directory.join(&rsc_digest), b"corrupted").unwrap();
        assert_eq!(
            decode_cached_pair(&store, &payload).unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn bare_manifest_name_uses_the_same_shared_cache_as_absolute_manifest() {
        let cwd = std::env::current_dir().unwrap();
        let name = std::path::Path::new("cache-root-probe.dme");
        assert_eq!(
            super::default_cache_root(name),
            super::default_cache_root(&cwd.join(name))
        );
        assert!(super::default_cache_root(name).is_absolute());
    }

    #[test]
    fn daemon_patch_requires_exclusive_pair_and_rejects_layout_changes() {
        use super::*;
        let root = std::env::temp_dir().join(format!(
            "dm-daemon-patch-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&root).unwrap();
        let manifest = root.join("world.dme");
        let source = root.join("code.dm");
        let builtins = root.join("builtins.dmb");
        let dmb = root.join("world.dmb");
        let rsc = root.join("world.rsc");
        fs::write(&manifest, "#include \"code.dm\"\n").unwrap();
        fs::write(&source, "/proc/value()\n    return 7\n").unwrap();
        fs::write(
            &builtins,
            include_bytes!("../../../fixtures/native_template.bin"),
        )
        .unwrap();
        let key = SessionKey::new(&root, &manifest, "516.1687", vec![], "build").unwrap();
        let mut daemon = Coordinator::new(root.join("cache")).unwrap();
        let initial = daemon.handle(Request::BuildProject {
            key: key.clone(),
            builtins: builtins.clone(),
            output_root: root.join("first-generation"),
        });
        assert!(initial.ok, "{initial:?}");
        let initial = initial.build.unwrap();
        fs::copy(&initial.dmb, &dmb).unwrap();
        fs::copy(&initial.rsc, &rsc).unwrap();
        let original_dmb = fs::read(&dmb).unwrap();
        let original_rsc = fs::read(&rsc).unwrap();
        fs::write(&source, "/proc/value()\n    return 8\n").unwrap();
        let request = |exclusive| Request::BuildProjectPatch {
            key: key.clone(),
            builtins: builtins.clone(),
            dmb: dmb.clone(),
            rsc: rsc.clone(),
            exclusive,
        };
        assert!(!daemon.handle(request(false)).ok);
        assert_eq!(fs::read(&dmb).unwrap(), original_dmb);
        let patched = daemon.handle(request(true));
        assert!(patched.ok, "{patched:?}");
        assert!(!root.join(".dm-patch-generations").exists());
        assert_ne!(fs::read(&dmb).unwrap(), original_dmb);
        assert_eq!(fs::read(&rsc).unwrap(), original_rsc);
        assert!(!dmb.with_extension("dmb.undo-journal").exists());
        drop(daemon);
        let mut restarted = Coordinator::new(root.join("cache")).unwrap();
        assert!(restarted.handle(request(true)).ok);
        // Simulate a crash after DMB writes but before RSC writes. The next
        // request must consume the undo journal before reading either input.
        fs::write(&source, "/proc/value()\n    return 9\n").unwrap();
        let next = restarted.handle(Request::BuildProject {
            key: key.clone(),
            builtins: builtins.clone(),
            output_root: root.join("next-generation"),
        });
        assert!(next.ok, "{next:?}");
        let next = next.build.unwrap();
        let next_dmb = fs::read(&next.dmb).unwrap();
        let old_dmb = fs::read(&dmb).unwrap();
        let old_rsc = fs::read(&rsc).unwrap();
        let next_rsc = fs::read(&next.rsc).unwrap();
        let PairPlan::Patch {
            dmb: dmb_patch,
            rsc: rsc_patch,
            ..
        } = plan_pair(
            &old_dmb,
            &old_rsc,
            &next_dmb,
            &next_rsc,
            PatchPolicy::default(),
        )
        else {
            panic!("same-layout change should be patchable")
        };
        fs::write(&dmb, &next_dmb).unwrap();
        let journal = dmb.with_extension("dmb.undo-journal");
        fs::write(
            &journal,
            serde_json::to_vec(&serde_json::json!({
                "version": 1, "dmb": dmb_patch, "rsc": rsc_patch
            }))
            .unwrap(),
        )
        .unwrap();
        drop(restarted);
        let mut restarted = Coordinator::new(root.join("cache")).unwrap();
        let recovered = restarted.handle(request(true));
        assert!(recovered.ok, "{recovered:?}");
        assert!(!journal.exists());
        assert_eq!(fs::read(&dmb).unwrap(), next_dmb);
        let patched_dmb = fs::read(&dmb).unwrap();
        fs::write(
            &source,
            "/proc/value()\n    return 9\n/proc/added()\n    return 1\n",
        )
        .unwrap();
        let changed_layout = restarted.handle(request(true));
        assert!(!changed_layout.ok, "{changed_layout:?}");
        assert!(changed_layout.error.unwrap().contains("layout changed"));
        assert_eq!(fs::read(&dmb).unwrap(), patched_dmb);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn poisoned_session_index_remains_readable() {
        let sessions = std::sync::Arc::new(super::Sessions::default());
        let crashed = std::sync::Arc::clone(&sessions);
        let _ = std::thread::spawn(move || {
            let _guard = crashed.entries.lock().unwrap();
            panic!("simulate a crashed request while holding the index");
        })
        .join();
        assert_eq!(sessions.count(), 0);
    }
    use super::*;

    #[test]
    fn cas_round_trip_and_namespace_guard() {
        let root = std::env::temp_dir().join(format!("dm-cas-{}", std::process::id()));
        let store = ContentStore::new(&root).unwrap();
        let digest = store.put("syntax-v1", b"one").unwrap();
        assert_eq!(store.get("syntax-v1", &digest).unwrap(), b"one");
        assert!(store.put("../escape", b"one").is_err());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn sessions_keep_worktrees_separate() {
        let root = std::env::temp_dir();
        let project = root.join("test.dme");
        // Direct construction avoids requiring a real checkout in this test.
        let a = SessionKey {
            worktree: root.join("a"),
            project: project.clone(),
            target: "516.1687".into(),
            defines: vec![],
            build_mode: "debug".into(),
            compiler_version: "test".into(),
        };
        let b = SessionKey {
            worktree: root.join("b"),
            ..a.clone()
        };
        let sessions = Sessions::default();
        let first = sessions.get_or_create(a.clone());
        first.lock().unwrap().generation = 1;
        assert_eq!(sessions.get_or_create(a).lock().unwrap().generation, 1);
        assert_eq!(sessions.get_or_create(b).lock().unwrap().generation, 0);
        assert_eq!(sessions.count(), 2);
    }

    #[test]
    fn coordinator_isolates_worktree_inputs() {
        let root = std::env::temp_dir().join(format!("dm-coordinator-{}", std::process::id()));
        let mut coordinator = Coordinator::new(&root).unwrap();
        let a = SessionKey {
            worktree: PathBuf::from("a"),
            project: PathBuf::from("project.dme"),
            target: "516.1687".into(),
            defines: vec![],
            build_mode: "debug".into(),
            compiler_version: "test".into(),
        };
        let b = SessionKey {
            worktree: PathBuf::from("b"),
            ..a.clone()
        };
        let first = coordinator.handle(Request::Check {
            key: a,
            source: PathBuf::from("code.dm"),
            text: "/obj/one\n".into(),
        });
        let second = coordinator.handle(Request::Check {
            key: b,
            source: PathBuf::from("code.dm"),
            text: "/obj/two\n".into(),
        });
        assert!(first.ok && second.ok);
        assert_ne!(first.source_digest, second.source_digest);
        assert_eq!(coordinator.session_count(), 2);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn identical_source_reuses_syntax_across_worktrees() {
        let root = std::env::temp_dir().join(format!("dm-shared-syntax-{}", std::process::id()));
        let mut coordinator = Coordinator::new(&root).unwrap();
        let first_key = SessionKey {
            worktree: PathBuf::from("first"),
            project: PathBuf::from("project.dme"),
            target: "516.1687".into(),
            defines: vec![],
            build_mode: "check".into(),
            compiler_version: "test".into(),
        };
        let second_key = SessionKey {
            worktree: PathBuf::from("second"),
            ..first_key.clone()
        };
        let request = |key| Request::Check {
            key,
            source: PathBuf::from("same.dm"),
            text: "/obj/same\n".into(),
        };
        assert!(!coordinator.handle(request(first_key)).shared_syntax_hit);
        assert!(coordinator.handle(request(second_key)).shared_syntax_hit);
        assert_eq!(coordinator.session_count(), 2);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn keyed_artifact_requires_same_dependency_fingerprint() {
        let root = std::env::temp_dir().join(format!("dm-keyed-artifact-{}", std::process::id()));
        let store = ContentStore::new(&root).unwrap();
        let input = store.put("source-v1", b"/obj").unwrap();
        let first_dependency = store.put("source-v1", b"/datum/value = 1").unwrap();
        let second_dependency = store.put("source-v1", b"/datum/value = 2").unwrap();
        let first = ArtifactKey {
            stage: "symbolic-code".into(),
            format_version: 1,
            compiler_version: "test".into(),
            target: Some("516.1687".into()),
            input_digests: vec![input],
            dependency_digests: vec![first_dependency],
        };
        store.put_artifact(&first, b"code for value 1").unwrap();
        assert_eq!(
            store.get_artifact(&first).unwrap(),
            Some(b"code for value 1".to_vec())
        );
        assert!(store.put_artifact(&first, b"different code").is_err());
        let second = ArtifactKey {
            dependency_digests: vec![second_dependency],
            ..first
        };
        assert_eq!(store.get_artifact(&second).unwrap(), None);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn syntax_summary_survives_daemon_restart_and_session_eviction() {
        let root = std::env::temp_dir().join(format!("dm-daemon-restart-{}", std::process::id()));
        let key = SessionKey {
            worktree: PathBuf::from("worktree-a"),
            project: PathBuf::from("project.dme"),
            target: "516.1687".into(),
            defines: vec![],
            build_mode: "check".into(),
            compiler_version: "test".into(),
        };
        let request = || Request::Check {
            key: key.clone(),
            source: PathBuf::from("code.dm"),
            text: "/obj/one\n".into(),
        };
        {
            let mut first = Coordinator::new(&root).unwrap();
            assert!(!first.handle(request()).shared_syntax_hit);
            first.handle(Request::Ping);
            assert_eq!(first.evict_idle(0), (1, 1));
            assert_eq!(first.session_count(), 0);
        }
        let mut restarted = Coordinator::new(&root).unwrap();
        let response = restarted.handle(request());
        assert!(response.ok);
        assert!(response.shared_syntax_hit);
        assert_eq!(response.item_count, 1);
        drop(restarted);
        let artifact_key = ArtifactKey {
            stage: "syntax-summary".into(),
            format_version: 1,
            compiler_version: BUILD_FINGERPRINT.into(),
            target: None,
            input_digests: vec![format!("{:x}", Sha256::digest(b"/obj/one\n"))],
            dependency_digests: vec![],
        };
        let digest = artifact_key.digest().unwrap();
        let metadata = dm_store::Store::open(root.join("metadata.redb")).unwrap();
        let read = metadata
            .read_many(&[dm_store::Key::new("artifact-index-v2", &digest)], None)
            .unwrap();
        let pointer: ArtifactPointer =
            serde_json::from_slice(read.values[0].as_ref().unwrap()).unwrap();
        let payload = root
            .join("artifact-payload-v1")
            .join(&pointer.payload_digest[..2])
            .join(&pointer.payload_digest);
        fs::write(&payload, b"damaged summary").unwrap();
        let mut repaired = Coordinator::new(&root).unwrap();
        let response = repaired.handle(request());
        assert!(response.ok, "{response:?}");
        assert!(!response.shared_syntax_hit);
        assert_eq!(response.item_count, 1);
        drop(repaired);
        let mut next = Coordinator::new(&root).unwrap();
        assert!(next.handle(request()).shared_syntax_hit);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn project_checks_isolate_worktrees_and_refresh_include_graph() {
        let root = std::env::temp_dir().join(format!(
            "dm-project-check-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let cache = root.join("cache");
        let first = root.join("first");
        let second = root.join("second");
        fs::create_dir_all(&first).unwrap();
        fs::create_dir_all(&second).unwrap();
        for worktree in [&first, &second] {
            fs::write(worktree.join("world.dme"), "#include \"types.dm\"\n").unwrap();
            fs::write(worktree.join("types.dm"), "/obj/one\n").unwrap();
        }
        let key = |worktree: &Path| {
            SessionKey::new(
                worktree,
                worktree.join("world.dme"),
                "516.1687",
                vec![],
                "check",
            )
            .unwrap()
        };
        let first_key = key(&first);
        let second_key = key(&second);
        let mut coordinator = Coordinator::new(&cache).unwrap();
        let a = coordinator.handle(Request::CheckProject {
            key: first_key.clone(),
        });
        let b = coordinator.handle(Request::CheckProject {
            key: second_key.clone(),
        });
        assert!(a.ok && b.ok, "{a:?} {b:?}");
        assert_eq!(a.source_digest, b.source_digest);
        assert!(!a.shared_syntax_hit);
        assert!(b.shared_syntax_hit);
        assert_eq!(coordinator.session_count(), 2);
        let repeated = coordinator.handle(Request::CheckProject {
            key: first_key.clone(),
        });
        assert!(repeated.ok && repeated.shared_syntax_hit);
        assert_eq!(repeated.source_digest, a.source_digest);

        fs::write(first.join("types.dm"), "/obj/two\n").unwrap();
        let edited = coordinator.handle(Request::CheckProject {
            key: first_key.clone(),
        });
        let unchanged = coordinator.handle(Request::CheckProject {
            key: second_key.clone(),
        });
        assert!(edited.ok && unchanged.ok);
        assert_ne!(edited.source_digest, unchanged.source_digest);
        assert_eq!(unchanged.source_digest, b.source_digest);

        fs::write(
            first.join("world.dme"),
            "#include \"types.dm\"\n#include \"extra.dm\"\n",
        )
        .unwrap();
        let missing = coordinator.handle(Request::CheckProject {
            key: first_key.clone(),
        });
        assert!(!missing.ok);
        assert!(missing.diagnostics.iter().any(|d| d.contains("extra.dm")));
        fs::write(first.join("extra.dm"), "/datum/extra\n").unwrap();
        let added = coordinator.handle(Request::CheckProject { key: first_key });
        assert!(added.ok, "{added:?}");
        assert_eq!(added.item_count, 2);
        let still_unchanged = coordinator.handle(Request::CheckProject { key: second_key });
        assert_eq!(still_unchanged.source_digest, b.source_digest);
        assert_eq!(coordinator.session_count(), 2);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn project_diagnostics_rebind_identical_expansion_to_current_authored_file() {
        let root = std::env::temp_dir().join(format!(
            "dm-project-diagnostic-origins-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&root).unwrap();
        let invalid = "/proc/broken()\n    return \"unterminated\n";
        let make = |name: &str| {
            let directory = root.join(name);
            fs::create_dir_all(&directory).unwrap();
            fs::write(
                directory.join("world.dme"),
                format!("#include \"{name}.dm\"\n"),
            )
            .unwrap();
            fs::write(directory.join(format!("{name}.dm")), invalid).unwrap();
            SessionKey::new(
                &directory,
                directory.join("world.dme"),
                "516.1687",
                vec![],
                "check",
            )
            .unwrap()
        };
        let first = make("first");
        let second = make("second");
        let cache = root.join("cache");
        let mut coordinator = Coordinator::new(&cache).unwrap();
        let a = coordinator.handle(Request::CheckProject { key: first });
        let b = coordinator.handle(Request::CheckProject {
            key: second.clone(),
        });
        assert!(!a.ok && !b.ok, "{a:?} {b:?}");
        assert_eq!(a.source_digest, b.source_digest);
        assert!(a
            .diagnostics
            .iter()
            .any(|error| error.contains("first.dm:")));
        assert!(b
            .diagnostics
            .iter()
            .any(|error| error.contains("second.dm:")));
        assert!(!b
            .diagnostics
            .iter()
            .any(|error| error.contains("first.dm:")));
        drop(coordinator);
        let mut restarted = Coordinator::new(&cache).unwrap();
        let restored = restarted.handle(Request::CheckProject { key: second });
        assert!(restored.shared_syntax_hit);
        assert_eq!(restored.diagnostics, b.diagnostics);
        drop(restarted);
        fs::remove_dir_all(root).unwrap();
    }

    #[cfg(windows)]
    #[test]
    fn project_check_detects_same_size_edit_with_restored_mtime() {
        let root = std::env::temp_dir().join(format!(
            "dm-project-restored-mtime-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&root).unwrap();
        let project = root.join("world.dme");
        let source = root.join("types.dm");
        fs::write(&project, "#include \"types.dm\"\n").unwrap();
        fs::write(&source, "/obj/one\n").unwrap();
        let key = SessionKey::new(&root, &project, "516.1687", vec![], "check").unwrap();
        let mut coordinator = Coordinator::new(root.join("cache")).unwrap();
        let first = coordinator.handle(Request::CheckProject { key: key.clone() });
        assert!(first.ok, "{first:?}");
        let before = file_stamp(&source).unwrap();
        let original_mtime = fs::metadata(&source).unwrap().modified().unwrap();

        std::thread::sleep(std::time::Duration::from_millis(20));
        fs::write(&source, "/obj/two\n").unwrap();
        fs::File::options()
            .write(true)
            .open(&source)
            .unwrap()
            .set_times(fs::FileTimes::new().set_modified(original_mtime))
            .unwrap();
        let after = file_stamp(&source).unwrap();
        assert_eq!(before.len, after.len);
        assert_eq!(before.modified, after.modified);
        assert_ne!(before.changed, after.changed);

        let edited = coordinator.handle(Request::CheckProject { key });
        assert!(edited.ok, "{edited:?}");
        assert_ne!(first.source_digest, edited.source_digest);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn repeated_project_check_skips_unchanged_include_tree() {
        use std::time::Instant;
        let root = std::env::temp_dir().join(format!(
            "dm-check-speed-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&root).unwrap();
        let mut manifest = String::new();
        for index in 0..128 {
            let name = format!("part_{index}.dm");
            manifest.push_str(&format!("#include \"{name}\"\n"));
            fs::write(root.join(&name), format!("/datum/part_{index}\n")).unwrap();
        }
        let project = root.join("world.dme");
        fs::write(&project, manifest).unwrap();
        let key = SessionKey::new(&root, &project, "516.1687", vec![], "check").unwrap();
        let mut coordinator = Coordinator::new(root.join("cache")).unwrap();
        let begin = Instant::now();
        let first = coordinator.handle(Request::CheckProject { key: key.clone() });
        let cold = begin.elapsed();
        let begin = Instant::now();
        let second = coordinator.handle(Request::CheckProject { key });
        let warm = begin.elapsed();
        assert!(first.ok && second.ok, "{first:?} {second:?}");
        assert!(second.shared_syntax_hit);
        assert_eq!(first.source_digest, second.source_digest);
        eprintln!("128-include project: cold {cold:?}, unchanged {warm:?}");
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn map_only_edit_invalidates_cached_build() {
        let root = std::env::temp_dir().join(format!(
            "dm-map-cache-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&root).unwrap();
        let manifest = root.join("world.dme");
        let map = root.join("map.dmm");
        let builtins = root.join("builtins.dmb");
        fs::write(
            &manifest,
            "#include \"code.dm\"\n#include \"map.dmm\"\n#if 0\n#include \"inactive.dmm\"\n#endif\n",
        )
        .unwrap();
        fs::write(root.join("code.dm"), "/proc/value()\n    return 7\n").unwrap();
        fs::write(&map, "\"a\" = (/turf,/area)\n(1,1,1) = {\"a\"}\n").unwrap();
        fs::write(
            &builtins,
            include_bytes!("../../../fixtures/native_template.bin"),
        )
        .unwrap();
        let key = SessionKey::new(&root, &manifest, "516.1687", vec![], "build").unwrap();
        let mut daemon = Coordinator::new(root.join("cache")).unwrap();
        let request = || Request::BuildProject {
            key: key.clone(),
            builtins: builtins.clone(),
            output_root: root.join("output"),
        };
        let first = daemon.handle(request());
        assert!(first.ok, "{first:?}");
        let first_build = first.build.unwrap();
        assert!(daemon.handle(request()).build.unwrap().cache_hit);
        fs::write(root.join("inactive.dmm"), "invalid inactive map").unwrap();
        assert!(daemon.handle(request()).build.unwrap().cache_hit);
        fs::write(&map, "\"a\" = (/turf,/area)\n(1,1,1) = {\"aa\"}\n").unwrap();
        let changed = daemon.handle(request());
        assert!(changed.ok, "{changed:?}");
        let changed_build = changed.build.unwrap();
        assert!(!changed_build.cache_hit);
        assert_ne!(first_build.generation, changed_build.generation);
        drop(daemon);
        let mut restarted = Coordinator::new(root.join("cache")).unwrap();
        let reused = restarted.handle(Request::BuildProject {
            key,
            builtins,
            output_root: root.join("restarted-output"),
        });
        assert!(reused.ok, "{reused:?}");
        let reused_build = reused.build.unwrap();
        assert!(reused_build.cache_hit);
        assert_eq!(changed_build.generation, reused_build.generation);
        let other_worktree = root.join("other-worktree");
        fs::create_dir_all(&other_worktree).unwrap();
        for name in ["world.dme", "code.dm", "map.dmm"] {
            fs::copy(root.join(name), other_worktree.join(name)).unwrap();
        }
        let other_key = SessionKey::new(
            &other_worktree,
            other_worktree.join("world.dme"),
            "516.1687",
            vec![],
            "build",
        )
        .unwrap();
        let shared = restarted.handle(Request::BuildProject {
            key: other_key,
            builtins: root.join("builtins.dmb"),
            output_root: other_worktree.join("output"),
        });
        assert!(shared.ok, "{shared:?}");
        let shared_build = shared.build.unwrap();
        assert!(shared_build.cache_hit);
        assert_eq!(changed_build.generation, shared_build.generation);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn build_defines_select_include_map_and_survive_daemon_restart() {
        let root = std::env::temp_dir().join(format!(
            "dm-defined-build-{}-{}",
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&root).unwrap();
        let manifest = root.join("world.dme");
        fs::write(&manifest, "#ifdef CITESTING\n#include \"test.dm\"\n#include \"test.dmm\"\n#else\n#include \"game.dm\"\n#include \"game.dmm\"\n#endif\n").unwrap();
        fs::write(root.join("test.dm"), "/proc/value()\n    return VALUE\n").unwrap();
        fs::write(root.join("game.dm"), "/proc/value()\n    return 99\n").unwrap();
        fs::write(
            root.join("test.dmm"),
            "\"a\" = (/turf,/area)\n(1,1,1) = {\"a\"}\n",
        )
        .unwrap();
        fs::write(
            root.join("game.dmm"),
            "\"a\" = (/turf,/area)\n(1,1,1) = {\"aa\"}\n",
        )
        .unwrap();
        let builtins = root.join("builtins.dmb");
        fs::write(
            &builtins,
            include_bytes!("../../../fixtures/native_template.bin"),
        )
        .unwrap();
        let cache = root.join("cache");
        let request = |value: Option<&str>, output: &str| Request::BuildProject {
            key: SessionKey::new(
                &root,
                &manifest,
                "516.1687",
                value
                    .map(|value| {
                        vec![
                            ("CITESTING".into(), "1".into()),
                            ("VALUE".into(), value.into()),
                        ]
                    })
                    .unwrap_or_default(),
                "build",
            )
            .unwrap(),
            builtins: builtins.clone(),
            output_root: root.join(output),
        };
        let mut daemon = Coordinator::new(&cache).unwrap();
        let test = daemon.handle(request(Some("7"), "test-output"));
        assert!(test.ok, "{test:?}");
        let test = test.build.unwrap();
        assert!(!test.cache_hit);
        assert!(
            daemon
                .handle(request(Some("7"), "test-output"))
                .build
                .unwrap()
                .cache_hit
        );
        let game = daemon.handle(request(None, "game-output"));
        assert!(game.ok, "{game:?}");
        assert_ne!(test.generation, game.build.unwrap().generation);
        let changed = daemon.handle(request(Some("8"), "changed-output"));
        assert!(changed.ok, "{changed:?}");
        assert_ne!(test.generation, changed.build.unwrap().generation);
        // An inactive source need not exist. It must stay outside discovery,
        // map/resource fingerprints, and the configured build cache key.
        fs::remove_file(root.join("game.dm")).unwrap();
        fs::remove_file(root.join("game.dmm")).unwrap();
        drop(daemon);
        let mut restarted = Coordinator::new(&cache).unwrap();
        let reused = restarted.handle(request(Some("7"), "restart-output"));
        assert!(reused.ok, "{reused:?}");
        let reused = reused.build.unwrap();
        assert!(reused.cache_hit);
        assert_eq!(test.generation, reused.generation);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn edited_procedure_reuses_other_procedure_from_disk() {
        let root = std::env::temp_dir().join(format!(
            "dm-stage-reuse-{}-{}",
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&root).unwrap();
        let manifest = root.join("world.dme");
        let source = root.join("code.dm");
        let builtins = root.join("builtins.dmb");
        fs::write(&manifest, "#include \"code.dm\"\n").unwrap();
        fs::write(
            &source,
            "/proc/a()\n    return 7\n/proc/b()\n    return 8\n",
        )
        .unwrap();
        fs::write(
            &builtins,
            include_bytes!("../../../fixtures/native_template.bin"),
        )
        .unwrap();
        let cache = root.join("cache");
        let key = SessionKey::new(&root, &manifest, "516.1687", vec![], "build").unwrap();
        let request = || Request::BuildProject {
            key: key.clone(),
            builtins: builtins.clone(),
            output_root: root.join("output"),
        };
        let mut first = Coordinator::new(&cache).unwrap();
        let before = first.handle(request());
        assert!(before.ok, "{before:?}");
        let before = before.build.unwrap();
        assert_eq!(before.lowered_procs, 2);
        assert_eq!(before.reused_procs, 0);
        drop(first);
        fs::write(
            &source,
            "/proc/a()\n    return 9\n/proc/b()\n    return 8\n",
        )
        .unwrap();
        let mut restarted = Coordinator::new(&cache).unwrap();
        let after = restarted.handle(request());
        assert!(after.ok, "{after:?}");
        let after = after.build.unwrap();
        assert!(!after.cache_hit);
        assert_eq!(after.lowered_procs, 1);
        assert_eq!(after.reused_procs, 1);
        assert_ne!(after.generation, before.generation);
        let unchanged = restarted.handle(request()).build.unwrap();
        assert_eq!(unchanged.lowered_procs, 0);
        assert_eq!(unchanged.reused_procs, 2);
        drop(restarted);
        fs::write(
            &source,
            "/var/global/unrelated_worktree_value = 42\n/proc/a()\n    return 9\n/proc/b()\n    return 8\n",
        ).unwrap();
        let mut other_worktree_edit = Coordinator::new(&cache).unwrap();
        let added = other_worktree_edit.handle(request());
        assert!(added.ok, "{added:?}");
        let added = added.build.unwrap();
        assert!(!added.cache_hit);
        assert_eq!(added.lowered_procs, 0);
        assert_eq!(added.reused_procs, 2);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn daemon_limits_bound_sessions_and_reject_large_checks_before_parsing() {
        let root = std::env::temp_dir().join(format!(
            "dm-daemon-limits-{}-{}",
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&root).unwrap();
        let project = root.join("world.dme");
        fs::write(&project, "/obj/example\n").unwrap();
        let mut coordinator = Coordinator::with_limits(
            root.join("cache"),
            CoordinatorLimits {
                max_check_source_bytes: 64,
                max_diagnostic_sessions: 2,
                max_syntax_summaries: 2,
                max_idle_requests: 100,
            },
        )
        .unwrap();
        for index in 0..5 {
            let key = SessionKey::new(
                &root,
                &project,
                "516.1687",
                vec![],
                format!("check-{index}"),
            )
            .unwrap();
            let response = coordinator.handle(Request::Check {
                key,
                source: project.clone(),
                text: format!("/obj/example{index}\n"),
            });
            assert!(response.ok, "{response:?}");
            assert!(coordinator.session_count() <= 2);
            assert!(coordinator.syntax_cache.len() <= 2);
        }
        let key = SessionKey::new(&root, &project, "516.1687", vec![], "too-large").unwrap();
        let response = coordinator.handle(Request::Check {
            key,
            source: project,
            text: "x".repeat(65),
        });
        assert!(!response.ok);
        assert!(response.error.unwrap().contains("check limit of 64"));
        assert!(coordinator
            .sessions
            .keys()
            .all(|key| key.build_mode != "too-large"));
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn skin_and_skin_icon_edits_invalidate_persisted_outputs() {
        let root = std::env::temp_dir().join(format!(
            "dm-skin-cache-{}-{}",
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&root).unwrap();
        let manifest = root.join("world.dme");
        let skin = root.join("skin.dmf");
        let icon = root.join("tiny.png");
        let builtins = root.join("builtins.dmb");
        fs::write(&manifest, "#include \"skin.dmf\"\n").unwrap();
        fs::write(
            &skin,
            include_bytes!("../../../fixtures/translation/selected_skin/skin.dmf"),
        )
        .unwrap();
        fs::write(
            &icon,
            include_bytes!("../../../fixtures/translation/selected_skin/tiny.png"),
        )
        .unwrap();
        fs::write(
            &builtins,
            include_bytes!("../../../fixtures/native_template.bin"),
        )
        .unwrap();
        let key = SessionKey::new(&root, &manifest, "516.1687", vec![], "skin").unwrap();
        let request = || Request::BuildProject {
            key: key.clone(),
            builtins: builtins.clone(),
            output_root: root.join("output"),
        };
        let cache = root.join("cache");
        let mut coordinator = Coordinator::new(&cache).unwrap();
        let first = coordinator.handle(request());
        assert!(first.ok, "{first:?}");
        let first = first.build.unwrap();
        let mut changed_icon = fs::read(&icon).unwrap();
        changed_icon.push(0);
        fs::write(&icon, changed_icon).unwrap();
        drop(coordinator);
        let mut coordinator = Coordinator::new(&cache).unwrap();
        let icon_changed = coordinator.handle(request());
        assert!(icon_changed.ok, "{icon_changed:?}");
        let icon_changed = icon_changed.build.unwrap();
        assert!(!icon_changed.cache_hit);
        assert_ne!(first.generation, icon_changed.generation);
        let changed_skin = fs::read_to_string(&skin)
            .unwrap()
            .replace("320x240", "400x240");
        fs::write(&skin, changed_skin).unwrap();
        let skin_changed = coordinator.handle(request());
        assert!(skin_changed.ok, "{skin_changed:?}");
        let skin_changed = skin_changed.build.unwrap();
        assert!(!skin_changed.cache_hit);
        assert_ne!(icon_changed.generation, skin_changed.generation);
        assert!(coordinator.handle(request()).build.unwrap().cache_hit);
        drop(coordinator);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn retained_build_inputs_skip_discovery_and_detect_source_asset_and_map_edits() {
        let root = std::env::temp_dir().join(format!(
            "dm-retained-inputs-{}-{}",
            std::process::id(),
            TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(root.join("assets")).unwrap();
        let manifest = root.join("world.dme");
        let source = root.join("code.dm");
        let asset = root.join("assets/asset.txt");
        let map = root.join("map.dmm");
        let builtins = root.join("builtins.bin");
        fs::write(
            &manifest,
            "#define FILE_DIR assets\n#include \"code.dm\"\n#include \"map.dmm\"\n",
        )
        .unwrap();
        fs::write(
            &source,
            "/var/asset = 'asset.txt'\n/proc/value() return 7\n",
        )
        .unwrap();
        fs::write(&asset, b"first").unwrap();
        fs::write(&map, "\"a\" = (/turf,/area)\n(1,1,1) = {\"a\"}\n").unwrap();
        fs::write(
            &builtins,
            include_bytes!("../../../fixtures/native_template.bin"),
        )
        .unwrap();
        let key = SessionKey::new(&root, &manifest, "516.1687", vec![], "build").unwrap();
        let request = || Request::BuildProject {
            key: key.clone(),
            builtins: builtins.clone(),
            output_root: root.join("output"),
        };
        let mut daemon = Coordinator::new(root.join("cache")).unwrap();
        let first = daemon.handle(request());
        assert!(first.ok, "{first:?}");
        assert!(daemon.build_inputs[&key]
            .snapshot
            .preprocessed
            .text
            .contains("return 7"));
        let preprocess_cache =
            dm_compiler::preprocess_cache_path(&manifest).with_extension("index.json");
        fs::remove_file(&preprocess_cache).unwrap();
        let repeated = daemon.handle(request());
        assert!(repeated.ok);
        let repeated_build = repeated.build.unwrap();
        assert!(repeated_build.cache_hit);
        assert_eq!(repeated_build.lowered_procs, 0);
        assert_eq!(repeated_build.reused_procs, repeated_build.emitted_procs);
        assert!(
            !preprocess_cache.exists(),
            "retained inputs must bypass discovery"
        );
        let published_bytes = fs::read(&repeated_build.dmb).unwrap();
        fs::write(&repeated_build.dmb, b"damaged output").unwrap();
        let repaired = daemon.handle(request());
        assert!(repaired.ok, "{repaired:?}");
        assert_eq!(
            fs::read(repaired.build.unwrap().dmb).unwrap(),
            published_bytes
        );
        let namespace_reusable = daemon.build_inputs[&key]
            .snapshot
            .asset_proof
            .borrow()
            .as_ref()
            .is_some_and(|proof| proof.namespace_current() == Some(true));
        let resolutions = RESOURCE_RESOLUTIONS.with(|count| count.get());
        let source_time = fs::metadata(&source).unwrap().modified().unwrap();
        fs::write(
            &source,
            "/var/asset = 'asset.txt'\n/proc/value() return 8\n",
        )
        .unwrap();
        fs::File::options()
            .write(true)
            .open(&source)
            .unwrap()
            .set_times(fs::FileTimes::new().set_modified(source_time))
            .unwrap();
        let source_changed = daemon.handle(request());
        assert!(source_changed.ok && !source_changed.build.unwrap().cache_hit);
        if namespace_reusable {
            assert_eq!(
                RESOURCE_RESOLUTIONS.with(|count| count.get()),
                resolutions,
                "body-only edit must reuse verified resource inventory"
            );
        }
        fs::write(root.join("assets/new.txt"), b"new").unwrap();
        fs::write(&source, "/var/asset = 'new.txt'\n/proc/value() return 8\n").unwrap();
        let inventory_changed = daemon.handle(request());
        assert!(inventory_changed.ok, "{inventory_changed:?}");
        assert!(daemon.build_inputs[&key]
            .snapshot
            .resource_requests
            .iter()
            .any(|request| request.archive_name == "new.txt"));
        // Restore the original resource before testing its data and shadow changes.
        fs::write(
            &source,
            "/var/asset = 'asset.txt'\n/proc/value() return 8\n",
        )
        .unwrap();
        assert!(daemon.handle(request()).ok);
        let asset_time = fs::metadata(&asset).unwrap().modified().unwrap();
        fs::write(&asset, b"other").unwrap();
        fs::File::options()
            .write(true)
            .open(&asset)
            .unwrap()
            .set_times(fs::FileTimes::new().set_modified(asset_time))
            .unwrap();
        let asset_changed = daemon.handle(request());
        assert!(asset_changed.ok && !asset_changed.build.unwrap().cache_hit);
        fs::write(root.join("asset.txt"), b"shadow").unwrap();
        let shadowed = daemon.handle(request());
        assert!(shadowed.ok && !shadowed.build.unwrap().cache_hit);
        fs::write(&map, "\"a\" = (/turf,/area)\n(1,1,1) = {\"aa\"}\n").unwrap();
        let map_changed = daemon.handle(request());
        assert!(map_changed.ok && !map_changed.build.unwrap().cache_hit);
        assert!(
            daemon
                .build_inputs
                .values()
                .map(|entry| entry.snapshot.resident_bytes())
                .sum::<usize>()
                <= MAX_BUILD_INPUT_BYTES
        );
        daemon.clock += 1;
        daemon.evict_idle(0);
        assert!(daemon.build_inputs.is_empty());
        drop(daemon);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn daemon_build_reuses_disk_artifact_and_republishes_per_output_root() {
        let root = std::env::temp_dir().join(format!(
            "dm-build-daemon-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&root).unwrap();
        let manifest = root.join("world.dme");
        let source = root.join("code.dm");
        let builtins = root.join("builtins.dmb");
        fs::write(&manifest, "#include \"code.dm\"\n").unwrap();
        fs::write(&source, "/proc/value()\n    return 7\n").unwrap();
        fs::write(
            &builtins,
            include_bytes!("../../../fixtures/native_template.bin"),
        )
        .unwrap();
        let key = SessionKey::new(&root, &manifest, "516.1687", vec![], "build").unwrap();
        let cache = root.join("cache");
        let request = |output_root: PathBuf| Request::BuildProject {
            key: key.clone(),
            builtins: builtins.clone(),
            output_root,
        };
        let first_root = root.join("first-output");
        let second_root = root.join("second-output");
        let mut daemon = Coordinator::new(&cache).unwrap();
        let first = daemon.handle(request(first_root.clone()));
        assert!(first.ok, "{first:?}");
        let first_build = first.build.unwrap();
        assert!(!first_build.cache_hit);
        assert!(first_build.dmb.is_file());
        let repeated = daemon.handle(request(first_root));
        assert!(repeated.build.unwrap().cache_hit);
        drop(daemon);

        let mut restarted = Coordinator::new(&cache).unwrap();
        let second = restarted.handle(request(second_root));
        assert!(second.ok, "{second:?}");
        let second_build = second.build.unwrap();
        assert!(second_build.cache_hit);
        assert_eq!(first_build.generation, second_build.generation);
        assert_ne!(first_build.dmb, second_build.dmb);

        // A torn or altered disk payload must cause a recompile, not leave
        // every subsequent build of this source permanently failing.
        let records = restarted
            .blobs
            .metadata
            .snapshot_namespace("artifact-index-v2", 64_000, 16 * 1024 * 1024, None)
            .unwrap();
        let (index, pointer) = records
            .records
            .into_iter()
            .find_map(|(key, bytes)| {
                let pointer: ArtifactPointer = serde_json::from_slice(&bytes).unwrap();
                (pointer.key.stage == "project-pair").then_some((key, pointer))
            })
            .unwrap();
        let payload_path = cache
            .join("artifact-payload-v1")
            .join(&pointer.payload_digest[..2])
            .join(&pointer.payload_digest);
        fs::write(&payload_path, b"damaged").unwrap();
        let repaired = restarted.handle(request(root.join("repaired-output")));
        assert!(repaired.ok, "{repaired:?}");
        let repaired_build = repaired.build.unwrap();
        assert!(!repaired_build.cache_hit);
        assert_eq!(repaired_build.generation, first_build.generation);
        assert_eq!(
            format!("{:x}", Sha256::digest(fs::read(&payload_path).unwrap())),
            pointer.payload_digest
        );

        fs::remove_file(&payload_path).unwrap();
        let missing_payload = restarted.handle(request(root.join("missing-payload-output")));
        assert!(missing_payload.ok, "{missing_payload:?}");
        assert!(!missing_payload.build.unwrap().cache_hit);
        assert!(payload_path.is_file());

        restarted
            .blobs
            .metadata
            .put_many(vec![(index.clone(), b"{".to_vec())], None)
            .unwrap();
        let malformed_pointer = restarted.handle(request(root.join("malformed-pointer-output")));
        assert!(malformed_pointer.ok, "{malformed_pointer:?}");
        assert!(!malformed_pointer.build.unwrap().cache_hit);
        let read = restarted.blobs.metadata.read_many(&[index], None).unwrap();
        assert!(
            serde_json::from_slice::<ArtifactPointer>(read.values[0].as_ref().unwrap()).is_ok()
        );

        let other_worktree = root.join("other-worktree");
        fs::create_dir_all(&other_worktree).unwrap();
        fs::write(other_worktree.join("world.dme"), "#include \"code.dm\"\n").unwrap();
        fs::write(
            other_worktree.join("code.dm"),
            "/proc/value()\n    return 7\n",
        )
        .unwrap();
        let other_key = SessionKey::new(
            &other_worktree,
            other_worktree.join("world.dme"),
            "516.1687",
            vec![],
            "build",
        )
        .unwrap();
        let cross_worktree = restarted.handle(Request::BuildProject {
            key: other_key,
            builtins: builtins.clone(),
            output_root: other_worktree.join("output"),
        });
        assert!(cross_worktree.ok, "{cross_worktree:?}");
        let cross_worktree = cross_worktree.build.unwrap();
        assert!(cross_worktree.cache_hit);
        assert_eq!(first_build.generation, cross_worktree.generation);

        fs::write(&source, "/proc/value()\n    return 8\n").unwrap();
        let edited = restarted.handle(request(root.join("third-output")));
        assert!(edited.ok, "{edited:?}");
        let edited_build = edited.build.unwrap();
        assert!(!edited_build.cache_hit);
        assert_ne!(first_build.generation, edited_build.generation);
        let count_blobs = |namespace: &str| {
            fs::read_dir(cache.join(namespace))
                .unwrap()
                .map(|shard| fs::read_dir(shard.unwrap().path()).unwrap().count())
                .sum::<usize>()
        };
        assert_eq!(count_blobs("project-rsc-v1"), 1);
        assert_eq!(count_blobs("project-dmb-v1"), 2);
        fs::write(
            &builtins,
            include_bytes!("../../../fixtures/native_compiler/simple.native.bin"),
        )
        .unwrap();
        let new_builtins = restarted.handle(request(root.join("fourth-output")));
        assert!(new_builtins.ok, "{new_builtins:?}");
        let new_builtins = new_builtins.build.unwrap();
        assert!(!new_builtins.cache_hit);
        assert_ne!(edited_build.generation, new_builtins.generation);
        fs::write(&source, "/proc/value()\n    return 'asset.txt'\n").unwrap();
        fs::write(root.join("asset.txt"), b"alpha").unwrap();
        let with_asset = restarted.handle(request(root.join("asset-output")));
        assert!(with_asset.ok, "{with_asset:?}");
        let with_asset = with_asset.build.unwrap();
        assert!(!fs::read(&with_asset.rsc).unwrap().is_empty());
        let repeated_asset = restarted.handle(request(root.join("asset-output")));
        assert!(repeated_asset.build.unwrap().cache_hit);
        fs::write(root.join("asset.txt"), b"beta").unwrap();
        let changed_asset = restarted.handle(request(root.join("changed-asset-output")));
        assert!(changed_asset.ok, "{changed_asset:?}");
        let changed_asset = changed_asset.build.unwrap();
        assert!(!changed_asset.cache_hit);
        assert_ne!(with_asset.generation, changed_asset.generation);
        fs::remove_dir_all(root).unwrap();
    }
}
