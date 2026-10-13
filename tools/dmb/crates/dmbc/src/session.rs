//! Configured one-worktree sessions. Immutable records are disposable hints;
//! input validation is mandatory before their output/memo IDs may be reused.
use crate::input_snapshot::{InputSnapshot, SnapshotProvider, Validation};
use dm_preprocess::regions::canonical_path;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::Arc;

// Schema 4 also carries successful diagnostic bytes for unchanged replay. Older
// immutable records remain on disk and are rejected as disposable cache hints.
const SCHEMA: u32 = 4;
const MAX_RECORD_BYTES: u64 = 32 * 1024 * 1024;

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct Configuration {
    pub worktree: PathBuf,
    pub manifest: PathBuf,
    pub defines: BTreeMap<String, String>,
    pub compiler: u128,
    pub engine: u128,
    /// Includes interpretation schema, intrinsic/macro/pure-call policy pins.
    pub policy: u128,
}

impl Configuration {
    pub fn new(
        worktree: &Path,
        manifest: &Path,
        defines: BTreeMap<String, String>,
        compiler: u128,
        engine: u128,
        policy: u128,
    ) -> io::Result<Self> {
        let worktree = canonical_path(worktree);
        let manifest = canonical_path(manifest);
        if !worktree.is_absolute() || !manifest.is_absolute() || !manifest.starts_with(&worktree) {
            return Err(invalid(
                "session manifest must be absolute and inside its worktree",
            ));
        }
        Ok(Self {
            worktree,
            manifest,
            defines,
            compiler,
            engine,
            policy,
        })
    }
    pub fn identity(&self) -> io::Result<u128> {
        let bytes = serde_json::to_vec(&(SCHEMA, self)).map_err(invalid)?;
        Ok(xxhash_rust::xxh3::xxh3_128(&bytes))
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct Record {
    /// Successful diagnostics bound to this exact compiler/configuration/input record.
    pub warnings: Vec<String>,
    pub inputs: InputSnapshot,
    /// Content identity of the immutable published DMB/RSC pair. Acquisition
    /// still authenticates that pair through PairStore (fully in exact mode).
    pub pair: u128,
    /// Exact hashes of conventional output bytes after verified copy/link.
    /// None means repair/materialize even when the immutable pair is reusable.
    pub outputs: Option<InputSnapshot>,
    #[serde(default)]
    pub resource_manifest: Option<crate::resource_manifest::ResourceManifest>,
}

#[derive(Serialize, Deserialize)]
struct Envelope {
    schema: u32,
    configuration: Configuration,
    record: Record,
}

/// Immutable configured record namespace, independent of a build lease.
/// Keeping this owner alive never blocks another request for the worktree.
/// Its records remain hints: every reuse still requires current input proofs.
pub struct SessionRecords {
    configuration: Configuration,
    directory: PathBuf,
}

/// Request-held manifest lease. It lives through capture and output installation,
/// while the shared configured record namespace may survive this request.
pub struct Session {
    records: Arc<SessionRecords>,
    _lease: BuildLease,
}
struct BuildLease {
    _build_lock: File,
}
impl std::ops::Deref for Session {
    type Target = SessionRecords;
    fn deref(&self) -> &Self::Target {
        &self.records
    }
}

/// Request measurements only; absent from immutable session serialization.
#[derive(Clone, Copy, Debug, Default)]
pub struct ValidationTimings {
    pub record_decode: std::time::Duration,
    pub bulk_capture: std::time::Duration,
    pub input_validate: std::time::Duration,
    pub proofs: crate::filesystem_proofs::ProofCounts,
}
pub struct ValidatedRecord {
    record: Record,
    pub validation: Validation,
    pub timings: ValidationTimings,
}
impl ValidatedRecord {
    pub fn record(&self) -> &Record {
        &self.record
    }
    /// Authenticate the pair with PairStore::verify separately before calling
    /// this. A false result requires conventional-path repair, not recompilation.
    pub fn outputs_match(
        &self,
        provider: &impl SnapshotProvider,
        exact: bool,
        now_ns: u128,
    ) -> io::Result<bool> {
        match &self.record.outputs {
            Some(outputs) => Ok(outputs.validate(provider, exact, now_ns)?.0.unchanged()),
            None => Ok(false),
        }
    }
    pub fn refresh_outputs(
        &mut self,
        provider: &impl SnapshotProvider,
        exact: bool,
        now_ns: u128,
    ) -> io::Result<(bool, usize)> {
        let Some(outputs) = &self.record.outputs else {
            return Ok((false, 0));
        };
        let (validation, refreshed) = outputs.validate(provider, exact, now_ns)?;
        if validation.unchanged() {
            self.record.outputs = Some(refreshed);
        }
        Ok((validation.unchanged(), validation.rehashed))
    }
    pub fn into_record(self) -> Record {
        self.record
    }
    /// A reusable pair does not prove this request's conventional destination.
    pub fn refresh_outputs_at(
        &mut self,
        output_project: &Path,
        provider: &impl SnapshotProvider,
        exact: bool,
        now_ns: u128,
    ) -> io::Result<(bool, usize)> {
        let Some(outputs) = &self.record.outputs else {
            return Ok((false, 0));
        };
        let expected = ["dmb", "rsc", "dmb-pair.json"]
            .map(|extension| canonical_path(&output_project.with_extension(extension)));
        if outputs.files().count() != 3
            || outputs.proof_paths().count() != 3
            || !outputs.folders().is_empty()
            || !expected
                .iter()
                .all(|path| outputs.files().any(|file| &file.path == path))
        {
            return Ok((false, 0));
        }
        self.refresh_outputs(provider, exact, now_ns)
    }
}

impl Session {
    /// Acquire before capture; keep this guard across lowering and publication.
    /// CLI must transfer its existing lock rather than reacquire it.
    pub fn acquire(configuration: Configuration) -> io::Result<Self> {
        let lock = crate::compile_driver::acquire_build_lock(&configuration.manifest)?;
        Self::from_locked(configuration, lock)
    }

    /// Preserve the already-held manifest lock across configuration admission.
    pub fn from_locked(configuration: Configuration, build_lock: File) -> io::Result<Self> {
        Ok(Self {
            records: Arc::new(SessionRecords::open(configuration)?),
            _lease: BuildLease {
                _build_lock: build_lock,
            },
        })
    }

    /// Publish only after the output pair has committed. No mutable head is
    /// needed: callers retain returned IDs in their session/build state.
    pub fn store(&self, record: Record) -> io::Result<u128> {
        record.inputs.check_structure()?;
        if !record.inputs.contains_file(&self.configuration.manifest) {
            return Err(invalid("session snapshot omits its required manifest"));
        }
        if let Some(outputs) = &record.outputs {
            outputs.check_structure()?;
        }
        let envelope = Envelope {
            schema: SCHEMA,
            configuration: self.configuration.clone(),
            record,
        };
        let bytes = dm_wire::encode(SCHEMA, &envelope).map_err(invalid)?;
        if bytes.len() as u64 > MAX_RECORD_BYTES {
            return Err(invalid("session record exceeds budget"));
        }
        let id = xxhash_rust::xxh3::xxh3_128(&bytes);
        let destination = self.directory.join(format!("{id:032x}.bin"));
        if destination.exists() {
            if self.read_bytes(&destination)? != bytes {
                return Err(invalid("session content ID collision"));
            }
            return Ok(id);
        }
        let temporary = self
            .directory
            .join(format!("{id:032x}.{}.temporary", std::process::id()));
        let result = (|| {
            let mut file = OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&temporary)?;
            file.write_all(&bytes)?;
            drop(file);
            fs::rename(&temporary, &destination)
        })();
        if result.is_err() {
            let _ = fs::remove_file(&temporary);
        }
        result?;
        Ok(id)
    }

    pub fn records(&self) -> Arc<SessionRecords> {
        Arc::clone(&self.records)
    }

    /// Release only the request lease, retaining the same immutable namespace.
    pub fn into_records(self) -> Arc<SessionRecords> {
        self.records
    }
}
impl SessionRecords {
    pub fn open(configuration: Configuration) -> io::Result<Self> {
        let checked = Configuration::new(
            &configuration.worktree,
            &configuration.manifest,
            configuration.defines.clone(),
            configuration.compiler,
            configuration.engine,
            configuration.policy,
        )?;
        if checked != configuration {
            return Err(invalid("session configuration is not canonical"));
        }
        let directory = configuration
            .manifest
            .parent()
            .ok_or_else(|| invalid("manifest parent missing"))?
            .join(".dmbc")
            .join("input-sessions")
            .join(format!("{:032x}", configuration.identity()?));
        fs::create_dir_all(&directory)?;
        Ok(Self {
            configuration,
            directory,
        })
    }

    /// Start a new request over this namespace using the ordinary manifest lock.
    /// No resident compiler or daemon is activated by retaining this owner.
    pub fn begin_request(self: &Arc<Self>) -> io::Result<Session> {
        let build_lock = crate::compile_driver::acquire_build_lock(&self.configuration.manifest)?;
        Ok(Session {
            records: Arc::clone(self),
            _lease: BuildLease {
                _build_lock: build_lock,
            },
        })
    }

    pub fn identity(&self) -> io::Result<u128> {
        self.configuration.identity()
    }

    /// Recover a bounded set of prior immutable records. Modification time is
    /// only a discovery ranking hint, never an input/content validation proof.
    /// Corrupt newest records do not mask older candidates.
    pub fn latest(&self, limit: usize) -> io::Result<Vec<u128>> {
        let limit = limit.min(32);
        let mut candidates = std::collections::BTreeSet::new();
        for entry in fs::read_dir(&self.directory)? {
            let entry = entry?;
            if !entry.file_type()?.is_file() {
                continue;
            }
            let name = entry.file_name();
            let Some(name) = name.to_str().and_then(|name| name.strip_suffix(".bin")) else {
                continue;
            };
            if name.len() != 32 {
                continue;
            }
            let Ok(id) = u128::from_str_radix(name, 16) else {
                continue;
            };
            let modified = entry.metadata()?.modified()?;
            candidates.insert((modified, id));
            if candidates.len() > limit {
                candidates.pop_first();
            }
        }
        Ok(candidates.into_iter().rev().map(|(_, id)| id).collect())
    }

    /// Authenticate record/configuration only and issue private structural
    /// receipts for its decoded snapshots. Subsequent validation reuses only
    /// these structural checks; it still checks all current file/folder facts.
    /// This does NOT authorize output or memo reuse by itself.
    pub fn prior(&self, id: u128) -> io::Result<Option<Record>> {
        let path = self.directory.join(format!("{id:032x}.bin"));
        let bytes = match self.read_bytes(&path) {
            Ok(bytes) => bytes,
            Err(error)
                if matches!(
                    error.kind(),
                    io::ErrorKind::NotFound | io::ErrorKind::InvalidData
                ) =>
            {
                return Ok(None)
            }
            Err(error) => return Err(error),
        };
        if xxhash_rust::xxh3::xxh3_128(&bytes) != id {
            return Ok(None);
        }
        let envelope: Envelope = match dm_wire::decode(SCHEMA, &bytes, MAX_RECORD_BYTES as usize) {
            Ok(value) => value,
            Err(_) => return Ok(None),
        };
        if envelope.schema != SCHEMA
            || envelope.configuration != self.configuration
            || envelope.record.inputs.check_structure().is_err()
            || !envelope
                .record
                .inputs
                .contains_file(&self.configuration.manifest)
        {
            return Ok(None);
        }
        if envelope
            .record
            .outputs
            .as_ref()
            .is_some_and(|outputs| outputs.check_structure().is_err())
        {
            return Ok(None);
        }
        Ok(Some(envelope.record))
    }

    /// A stale whole-input record is a cold-build miss. Permission failures
    /// remain errors; they are never interpreted as absence.
    pub fn validate(
        &self,
        id: u128,
        provider: &impl SnapshotProvider,
        exact: bool,
        now_ns: u128,
    ) -> io::Result<Option<ValidatedRecord>> {
        let started = std::time::Instant::now();
        let Some(mut record) = self.prior(id)? else {
            return Ok(None);
        };
        let mut timings = ValidationTimings {
            record_decode: started.elapsed(),
            ..ValidationTimings::default()
        };
        let started = std::time::Instant::now();
        let validated = record.inputs.validate_for_reuse(provider, exact, now_ns)?;
        timings.input_validate = started.elapsed();
        let Some((validation, inputs)) = validated else {
            return Ok(None);
        };
        record.inputs = inputs;
        Ok(Some(ValidatedRecord {
            record,
            validation,
            timings,
        }))
    }

    fn read_bytes(&self, path: &Path) -> io::Result<Vec<u8>> {
        let mut file = File::open(path)?;
        if file.metadata()?.len() > MAX_RECORD_BYTES {
            return Err(invalid("session record exceeds budget"));
        }
        let mut bytes = Vec::new();
        Read::by_ref(&mut file)
            .take(MAX_RECORD_BYTES + 1)
            .read_to_end(&mut bytes)?;
        if bytes.len() as u64 > MAX_RECORD_BYTES {
            return Err(invalid("session record exceeds budget"));
        }
        Ok(bytes)
    }
    pub fn validate_filesystem(
        &self,
        id: u128,
        exact: bool,
        now_ns: u128,
    ) -> io::Result<Option<ValidatedRecord>> {
        self.validate_filesystem_observed(id, exact, now_ns, |_| {})
    }
    /// Inspect an authenticated receipt without reading/deserializing it twice.
    /// Observation does not authorize reuse; the whole input proof still follows.
    pub fn validate_filesystem_observed(
        &self,
        id: u128,
        exact: bool,
        now_ns: u128,
        observer: impl FnOnce(&Record),
    ) -> io::Result<Option<ValidatedRecord>> {
        self.validate_filesystem_observed_with_generated_outputs(
            id,
            exact,
            now_ns,
            &std::collections::BTreeSet::new(),
            observer,
        )
    }
    pub fn validate_filesystem_observed_with_generated_outputs(
        &self,
        id: u128,
        exact: bool,
        now_ns: u128,
        generated_outputs: &std::collections::BTreeSet<std::path::PathBuf>,
        observer: impl FnOnce(&Record),
    ) -> io::Result<Option<ValidatedRecord>> {
        self.validate_filesystem_shared(id, exact, now_ns, generated_outputs, observer, &mut None)
    }
    /// As above, sharing one directory-proof capture across the records of a
    /// request: the first record's capture answers later records (paths outside
    /// it fall back to ordinary per-file handling), so the session's recent
    /// records cost one directory sweep instead of one each.
    pub fn validate_filesystem_shared(
        &self,
        id: u128,
        exact: bool,
        now_ns: u128,
        generated_outputs: &std::collections::BTreeSet<std::path::PathBuf>,
        observer: impl FnOnce(&Record),
        shared: &mut Option<std::sync::Arc<crate::filesystem_proofs::BulkFileSystemProofs>>,
    ) -> io::Result<Option<ValidatedRecord>> {
        let started = std::time::Instant::now();
        let Some(mut record) = self.prior(id)? else {
            return Ok(None);
        };
        let mut timings = ValidationTimings {
            record_decode: started.elapsed(),
            ..ValidationTimings::default()
        };
        observer(&record);
        let started = std::time::Instant::now();
        let proofs = match shared {
            Some(proofs) => std::sync::Arc::clone(proofs),
            None => {
                let proofs = std::sync::Arc::new(
                    crate::filesystem_proofs::BulkFileSystemProofs::capture_snapshot(
                        &record.inputs,
                    )?,
                );
                *shared = Some(std::sync::Arc::clone(&proofs));
                proofs
            }
        };
        let proofs = proofs.as_ref();
        timings.bulk_capture = started.elapsed();
        let started = std::time::Instant::now();
        let generated = crate::input_snapshot::GeneratedOutputInputs::new(
            proofs,
            generated_outputs.iter().cloned(),
        );
        let validated = record
            .inputs
            .validate_for_reuse(&generated, exact, now_ns)?;
        timings.input_validate = started.elapsed();
        timings.proofs = proofs.counts();
        let Some((validation, inputs)) = validated else {
            return Ok(None);
        };
        record.inputs = inputs;
        Ok(Some(ValidatedRecord {
            record,
            validation,
            timings,
        }))
    }
}

fn invalid(error: impl std::fmt::Display) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, error.to_string())
}

#[cfg(test)]
#[path = "session_output_tests.rs"]
mod output_tests;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::input_snapshot::{FolderListing, Stamp};
    struct Host {
        bytes: Vec<u8>,
    }
    impl SnapshotProvider for Host {
        fn stamp(&self, _: &Path) -> io::Result<Stamp> {
            Ok(Stamp {
                size: self.bytes.len() as u64,
                modified_ns: 1,
                file_id: Some(1),
            })
        }
        fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
            Ok((self.stamp(path)?, self.bytes.clone()))
        }
        fn list(&self, _: &Path) -> io::Result<FolderListing> {
            Ok(FolderListing::Missing)
        }
    }
    struct Temporary(PathBuf);
    impl Drop for Temporary {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }
    #[test]
    fn immutable_session_reuse_validates_inputs_and_rejects_corruption() {
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let temp = Temporary(
            std::env::temp_dir().join(format!("dmbc-session-{}-{unique}", std::process::id())),
        );
        fs::create_dir_all(&temp.0).unwrap();
        let manifest = temp.0.join("project.dme");
        let configuration =
            Configuration::new(&temp.0, &manifest, BTreeMap::new(), 1, 2, 3).unwrap();
        let session = Session::acquire(configuration).unwrap();
        let host = Host {
            bytes: b"source".to_vec(),
        };
        let mut inputs = InputSnapshot::new(10_000_000_000);
        inputs
            .record_file(&manifest, host.stamp(&manifest).unwrap(), &host.bytes)
            .unwrap();
        let id = session
            .store(Record {
                warnings: vec!["project.dm:2:warning (list_double_init): value: list doubly initialized\n".into()],
                inputs,
                pair: 7,
                outputs: None,
                resource_manifest: None,
            })
            .unwrap();
        let valid = session
            .validate(id, &host, true, 20_000_000_000)
            .unwrap()
            .unwrap();
        assert_eq!(valid.record.warnings, ["project.dm:2:warning (list_double_init): value: list doubly initialized\n"]);
        assert_eq!(valid.record().pair, 7);
        assert!(!valid.outputs_match(&host, true, 20_000_000_000).unwrap());
        let changed = Host {
            bytes: b"edited".to_vec(),
        };
        assert!(session
            .validate(id, &changed, true, 20_000_000_000)
            .unwrap()
            .is_none());
        fs::write(session.directory.join(format!("{id:032x}.bin")), b"broken").unwrap();
        assert!(session
            .validate(id, &host, true, 20_000_000_000)
            .unwrap()
            .is_none());
        drop(session);
    }
    #[test]
    fn retained_namespace_releases_request_lock_and_reuses_exact_records() {
        use fs2::FileExt;
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let temp = Temporary(std::env::temp_dir().join(format!(
            "dmbc-retained-session-{}-{unique}",
            std::process::id()
        )));
        fs::create_dir_all(&temp.0).unwrap();
        let manifest = temp.0.join("project.dme");
        let configuration =
            Configuration::new(&temp.0, &manifest, BTreeMap::new(), 1, 2, 3).unwrap();
        let request = Session::acquire(configuration.clone()).unwrap();
        let retained = request.records();
        let host = Host {
            bytes: b"source".to_vec(),
        };
        let mut inputs = InputSnapshot::new(10_000_000_000);
        inputs
            .record_file(&manifest, host.stamp(&manifest).unwrap(), &host.bytes)
            .unwrap();
        let id = request
            .store(Record {
                warnings: Vec::new(),
                inputs,
                pair: 7,
                outputs: None,
                resource_manifest: None,
            })
            .unwrap();
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .open(temp.0.join(".dmbc/build.lock"))
            .unwrap();
        assert!(
            lock.try_lock_exclusive().is_err(),
            "request must retain its manifest lease"
        );
        let namespace = request.into_records();
        assert!(Arc::ptr_eq(&retained, &namespace));
        lock.try_lock_exclusive().unwrap();
        FileExt::unlock(&lock).unwrap();
        assert_eq!(
            namespace.identity().unwrap(),
            configuration.identity().unwrap()
        );
        let next = namespace.begin_request().unwrap();
        assert!(Arc::ptr_eq(&next.records(), &namespace));
        assert!(lock.try_lock_exclusive().is_err());
        assert_eq!(
            next.validate(id, &host, true, 20_000_000_000)
                .unwrap()
                .unwrap()
                .record()
                .pair,
            7
        );
        drop(next);
        lock.try_lock_exclusive().unwrap();
        FileExt::unlock(&lock).unwrap();
    }
    #[test]
    fn configured_record_owner_never_acquires_a_build_lease() {
        use fs2::FileExt;
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let temp = Temporary(
            std::env::temp_dir().join(format!("dmbc-record-owner-{}-{unique}", std::process::id())),
        );
        fs::create_dir_all(&temp.0).unwrap();
        let manifest = temp.0.join("project.dme");
        let owner = Arc::new(
            SessionRecords::open(
                Configuration::new(&temp.0, &manifest, BTreeMap::new(), 1, 2, 3).unwrap(),
            )
            .unwrap(),
        );
        assert!(!temp.0.join(".dmbc/build.lock").exists());
        let request = owner.begin_request().unwrap();
        drop(request);
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .open(temp.0.join(".dmbc/build.lock"))
            .unwrap();
        lock.try_lock_exclusive().unwrap();
        FileExt::unlock(&lock).unwrap();
        assert!(owner.latest(4).unwrap().is_empty());
    }
    #[test]
    fn configured_session_identity_includes_defines_and_compiler_engine() {
        let root = std::env::current_dir().unwrap();
        let first =
            Configuration::new(&root, &root.join("project.dme"), BTreeMap::new(), 1, 2, 3).unwrap();
        let mut changed = first.clone();
        changed.defines.insert("TEST".into(), "0".into());
        assert_ne!(first.identity().unwrap(), changed.identity().unwrap());
        changed = first.clone();
        changed.engine = 4;
        assert_ne!(first.identity().unwrap(), changed.identity().unwrap());
        changed = first.clone();
        changed.compiler = 4;
        assert_ne!(first.identity().unwrap(), changed.identity().unwrap());
        assert!(Configuration::new(
            &root,
            &root.parent().unwrap().join("else.dme"),
            BTreeMap::new(),
            1,
            2,
            3
        )
        .is_err());
    }
}
