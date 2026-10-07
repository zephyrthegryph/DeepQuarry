//! Configured one-worktree sessions. Immutable records are disposable hints;
//! input validation is mandatory before their output/memo IDs may be reused.
use crate::input_snapshot::{InputSnapshot, SnapshotProvider, Validation};
use dm_preprocess::regions::canonical_path;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};

const SCHEMA: u32 = 1;
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
    pub inputs: InputSnapshot,
    /// Content identity of the immutable published DMB/RSC pair. Acquisition
    /// still authenticates that pair through PairStore (fully in exact mode).
    pub pair: u128,
    /// Exact hashes of conventional output bytes after verified copy/link.
    /// None means repair/materialize even when the immutable pair is reusable.
    pub outputs: Option<InputSnapshot>,
}

#[derive(Serialize, Deserialize)]
struct Envelope {
    schema: u32,
    configuration: Configuration,
    record: Record,
}

pub struct Session {
    configuration: Configuration,
    directory: PathBuf,
    // Reuses the existing worktree manifest build lock, conservatively shared
    // by different configurations in that manifest directory. Held to drop.
    _build_lock: File,
}

pub struct ValidatedRecord {
    record: Record,
    pub validation: Validation,
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
}

impl Session {
    /// Acquire before capture; keep this guard across lowering and publication.
    /// CLI must transfer its existing lock rather than reacquire it.
    pub fn acquire(configuration: Configuration) -> io::Result<Self> {
        let lock = crate::compile_driver::acquire_build_lock(&configuration.manifest)?;
        Self::from_locked(configuration, lock)
    }

    /// Caller transfers the already-held compile_driver build lock. Ownership
    /// is explicit so the lock cannot be dropped between capture and publish.
    pub fn from_locked(configuration: Configuration, build_lock: File) -> io::Result<Self> {
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
            _build_lock: build_lock,
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
            let Some(name) = name.to_str().and_then(|name| name.strip_suffix(".json")) else {
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
        let bytes = serde_json::to_vec(&envelope).map_err(invalid)?;
        if bytes.len() as u64 > MAX_RECORD_BYTES {
            return Err(invalid("session record exceeds budget"));
        }
        let id = xxhash_rust::xxh3::xxh3_128(&bytes);
        let destination = self.directory.join(format!("{id:032x}.json"));
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

    /// A missing, malformed, mismatched or stale record is a cold-build miss.
    /// Provider IO errors remain errors; permission failures are not absence.
    pub fn validate(
        &self,
        id: u128,
        provider: &impl SnapshotProvider,
        exact: bool,
        now_ns: u128,
    ) -> io::Result<Option<ValidatedRecord>> {
        let path = self.directory.join(format!("{id:032x}.json"));
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
        let envelope: Envelope = match serde_json::from_slice(&bytes) {
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
        let (validation, inputs) = envelope.record.inputs.validate(provider, exact, now_ns)?;
        if !validation.unchanged() {
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
        Ok(Some(ValidatedRecord {
            record: Record {
                inputs,
                pair: envelope.record.pair,
                outputs: envelope.record.outputs,
            },
            validation,
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
}

fn invalid(error: impl std::fmt::Display) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, error.to_string())
}

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
                inputs,
                pair: 7,
                outputs: None,
            })
            .unwrap();
        let valid = session
            .validate(id, &host, true, 20_000_000_000)
            .unwrap()
            .unwrap();
        assert_eq!(valid.record().pair, 7);
        assert!(!valid.outputs_match(&host, true, 20_000_000_000).unwrap());
        let changed = Host {
            bytes: b"edited".to_vec(),
        };
        assert!(session
            .validate(id, &changed, true, 20_000_000_000)
            .unwrap()
            .is_none());
        fs::write(session.directory.join(format!("{id:032x}.json")), b"broken").unwrap();
        assert!(session
            .validate(id, &host, true, 20_000_000_000)
            .unwrap()
            .is_none());
        drop(session);
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
