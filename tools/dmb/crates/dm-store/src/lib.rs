//! Transactional metadata and immutable blobs shared by independent compiler processes.
//! Bounded reusable ownership windows share redb connections between batches.
//! An idle/age reaper releases OS locks for independent compiler processes.
use fs2::FileExt;
mod shared_artifacts;
mod packed_records;
pub use packed_records::PackedRecords;
mod sessions;
use redb::{Database, ReadableTable, TableDefinition};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
pub use shared_artifacts::SharedArtifacts;
use std::{
    collections::BTreeMap,
    fs::{self, File, OpenOptions},
    io,
    path::{Path, PathBuf},
    sync::atomic::{AtomicBool, Ordering},
    time::{Duration, Instant},
};

const RECORDS: TableDefinition<&str, &[u8]> = TableDefinition::new("records");
const SCHEMA_KEY: &str = "@schema";
const SCHEMA: &[u8] = b"dm-store-v2-sha256";
const MAX_RECORD: usize = 256 * 1024 * 1024;

fn error(e: impl std::fmt::Display) -> io::Error {
    io::Error::other(e.to_string())
}
fn invalid_data(e: impl std::fmt::Display) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, e.to_string())
}
fn digest(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

fn encode_record(bytes: &[u8]) -> Vec<u8> {
    let mut encoded = Vec::with_capacity(32 + bytes.len());
    encoded.extend_from_slice(&Sha256::digest(bytes));
    encoded.extend_from_slice(bytes);
    encoded
}
fn decode_record(bytes: &[u8]) -> io::Result<Vec<u8>> {
    if bytes.len() < 32 || Sha256::digest(&bytes[32..]).as_slice() != &bytes[..32] {
        return Err(invalid_data("store record checksum mismatch"));
    }
    Ok(bytes[32..].to_vec())
}

#[derive(Clone, Debug, Serialize, Deserialize, Eq, PartialEq, Ord, PartialOrd)]
pub struct Key {
    pub namespace: String,
    pub name: String,
}
impl Key {
    pub fn new(namespace: impl Into<String>, name: impl Into<String>) -> Self {
        Self {
            namespace: namespace.into(),
            name: name.into(),
        }
    }
    fn encode(&self) -> io::Result<String> {
        if self.namespace.is_empty() || self.namespace.starts_with('@') {
            return Err(error("invalid store namespace"));
        }
        serde_json::to_string(self).map_err(error)
    }
}
#[derive(Clone, Debug, Serialize, Deserialize, Eq, PartialEq)]
pub struct ReadWitness {
    pub key: Key,
    pub value_digest: Option<String>,
}
#[derive(Clone, Debug)]
pub struct ReadBatch {
    pub values: Vec<Option<Vec<u8>>>,
    pub witnesses: Vec<ReadWitness>,
}
#[derive(Clone, Debug)]
pub struct NamespaceSnapshot {
    pub records: Vec<(Key, Vec<u8>)>,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub enum Change {
    Put(Key, Vec<u8>),
    Delete(Key),
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Commit {
    Applied,
    Conflict,
}
#[derive(Clone, Debug)]
pub struct Store {
    path: PathBuf,
    timeout: Duration,
    cache_bytes: usize,
    session: std::sync::Arc<sessions::Session>,
}
struct Lock(File);
impl Drop for Lock {
    fn drop(&mut self) {
        let _ = FileExt::unlock(&self.0);
    }
}

impl Store {
    /// `path` names the database, not a directory. Memory cache defaults to 16 MiB.
    pub fn open(path: impl AsRef<Path>) -> io::Result<Self> {
        let path = sessions::canonical_path(path.as_ref())?;
        let store = Self {
            session: sessions::session(&path),
            path,
            timeout: Duration::from_secs(30),
            cache_bytes: 16 * 1024 * 1024,
        };
        store.access(None, |_| Ok(()))?;
        Ok(store)
    }
    pub fn with_limits(mut self, timeout: Duration, cache_bytes: usize) -> Self {
        self.timeout = timeout;
        self.cache_bytes = cache_bytes.clamp(1024 * 1024, 64 * 1024 * 1024);
        self
    }
    fn lock(&self, cancel: Option<&AtomicBool>) -> io::Result<Lock> {
        if let Some(parent) = self
            .path
            .parent()
            .filter(|path| !path.as_os_str().is_empty())
        {
            fs::create_dir_all(parent)?;
        }
        let lock = OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(self.path.with_extension("lock"))?;
        let start = Instant::now();
        loop {
            if cancel.is_some_and(|flag| flag.load(Ordering::Relaxed)) {
                return Err(io::Error::new(
                    io::ErrorKind::Interrupted,
                    "store acquisition cancelled",
                ));
            }
            match lock.try_lock_exclusive() {
                Ok(()) => return Ok(Lock(lock)),
                Err(e) if e.kind() == io::ErrorKind::WouldBlock || e.raw_os_error() == Some(33) => {
                }
                Err(e) => return Err(e),
            }
            if start.elapsed() >= self.timeout {
                return Err(io::Error::new(
                    io::ErrorKind::TimedOut,
                    "store acquisition timed out",
                ));
            }
            std::thread::sleep(Duration::from_millis(5));
        }
    }
    fn access<T>(
        &self,
        cancel: Option<&AtomicBool>,
        f: impl FnOnce(&Database) -> io::Result<T>,
    ) -> io::Result<T> {
        self.session.access(self, cancel, f)
    }
    fn open_database(&self) -> io::Result<Database> {
        let started=Instant::now();
        let mut builder = Database::builder();
        builder.set_cache_size(self.cache_bytes);
        let path=self.path.clone();
        let repair_timeout=self.timeout;
        builder.set_repair_callback(move |repair| {
            if std::env::var_os("DM_BUILD_TRACE").is_some() {
                eprintln!("DM_BUILD_TRACE store recovery: {} progress={:.3} elapsed={:.3}s",path.display(),repair.progress(),started.elapsed().as_secs_f64());
            }
            if started.elapsed()>=repair_timeout {repair.abort();}
        });
        let db = builder.create(&self.path).map_err(|failure| {
            if std::env::var_os("DM_BUILD_TRACE").is_some() {
                eprintln!("DM_BUILD_TRACE store connection open failed: {} {:.3}s: {failure}",self.path.display(),started.elapsed().as_secs_f64());
            }
            error(failure)
        })?;
        let schema = {
            let tx = db.begin_read().map_err(error)?;
            match tx.open_table(RECORDS) {
                Ok(table) => table.get(SCHEMA_KEY).map_err(error)?.map(|v| v.value().to_vec()),
                Err(redb::TableError::TableDoesNotExist(_)) => None,
                Err(e) => return Err(error(e)),
            }
        };
        match schema {
            Some(value) if value != SCHEMA => return Err(invalid_data("unsupported dm-store schema")),
            Some(_) => {},
            None => {
                let tx=db.begin_write().map_err(error)?;
                { let mut table=tx.open_table(RECORDS).map_err(error)?; table.insert(SCHEMA_KEY,SCHEMA).map_err(error)?; }
                tx.commit().map_err(error)?;
            }
        }
        if std::env::var_os("DM_BUILD_TRACE").is_some() {
            eprintln!("DM_BUILD_TRACE store connection open: {} {:.3}s",self.path.display(),started.elapsed().as_secs_f64());
        }
        Ok(db)
    }
    /// One database open/read transaction for all requested keys, including misses.
    pub fn read_many(&self, keys: &[Key], cancel: Option<&AtomicBool>) -> io::Result<ReadBatch> {
        self.read_many_bounded(keys, MAX_RECORD, 128 * 1024 * 1024, cancel)
    }

    /// Check stored lengths before copying payloads. Stages with small records
    /// can enforce their own allocation budget even if a cache row is oversized.
    /// Exceeding either bound fails the batch; omitted data never proves absence.
    pub fn read_many_bounded(
        &self,
        keys: &[Key],
        max_record_bytes: usize,
        max_batch_bytes: usize,
        cancel: Option<&AtomicBool>,
    ) -> io::Result<ReadBatch> {
        self.read_grouped_bounded(keys, keys.len().max(1), max_record_bytes,
            max_batch_bytes, max_batch_bytes, cancel)
    }

    /// Hydrate several allocation groups under one short database ownership
    /// window. All bytes are copied before releasing the lock; decoding and
    /// compiler work happen after this returns. Never holds a database between
    /// stages or across independent compiler processes.
    pub fn read_grouped_bounded(
        &self, keys: &[Key], group_records: usize, max_record_bytes: usize,
        max_group_bytes: usize, max_session_bytes: usize,
        cancel: Option<&AtomicBool>,
    ) -> io::Result<ReadBatch> {
        self.read_grouped_bounded_mode(keys,group_records,max_record_bytes,max_group_bytes,max_session_bytes,cancel,false)
    }

    /// Return only the leading requested keys that fit a bounded hydration
    /// window. Unreturned keys have no witness and must never count as misses.
    /// This permits nearby-key prefetch under one database ownership window.
    pub fn read_prefix_bounded(
        &self, keys: &[Key], max_record_bytes: usize, max_batch_bytes: usize,
        cancel: Option<&AtomicBool>,
    ) -> io::Result<ReadBatch> {
        self.read_grouped_bounded_mode(keys,keys.len().max(1),max_record_bytes,max_batch_bytes,max_batch_bytes,cancel,true)
    }

    fn read_grouped_bounded_mode(
        &self, keys: &[Key], group_records: usize, max_record_bytes: usize,
        max_group_bytes: usize, max_session_bytes: usize,
        cancel: Option<&AtomicBool>, prefix: bool,
    ) -> io::Result<ReadBatch> {
        if group_records == 0 { return Err(error("read group must contain records")); }
        if keys.len() > 64_000 {
            return Err(error("batch exceeds 64000 records"));
        }
        let encoded = keys
            .iter()
            .map(Key::encode)
            .collect::<io::Result<Vec<_>>>()?;
        let raw = self.access(cancel, |db| {
            let tx = db.begin_read().map_err(error)?;
            let table = tx.open_table(RECORDS).map_err(error)?;
            let mut values = Vec::with_capacity(keys.len());
            let mut bytes = 0usize;
            let mut group_bytes = 0usize;
            for (ordinal, key) in encoded.iter().enumerate() {
                if ordinal % group_records == 0 { group_bytes = 0; }
                let stored = table.get(key.as_str()).map_err(error)?;
                let size = stored.as_ref().map_or(0, |value| value.value().len());
                if size.saturating_sub(32) > max_record_bytes.min(MAX_RECORD) {
                    if prefix { break; }
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidInput,
                        "read record exceeds stage byte limit",
                    ));
                }
                bytes = bytes
                    .checked_add(size)
                    .ok_or_else(|| error("read batch size overflow"))?;
                group_bytes = group_bytes.checked_add(size).ok_or_else(||error("read group size overflow"))?;
                if group_bytes > max_group_bytes || bytes > max_session_bytes.min(128 * 1024 * 1024) {
                    if prefix { break; }
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidInput,
                        "read batch exceeds stage byte limit",
                    ));
                }
                values.push(stored.map(|value| value.value().to_vec()));
            }
            Ok(values)
        })?;
        // Verify checksums and construct witnesses after releasing DB ownership.
        let mut values = Vec::with_capacity(keys.len());
        let mut witnesses = Vec::with_capacity(keys.len());
        for (key, raw) in keys.iter().zip(raw) {
            let value = raw.as_deref().map(decode_record).transpose()?;
            // decode_record already verified the stored SHA. Reuse it for the
            // transaction witness instead of hashing each payload a second time.
            let value_digest = raw.as_ref().map(|bytes| {
                const HEX: &[u8; 16] = b"0123456789abcdef";
                let mut digest = String::with_capacity(64);
                for byte in &bytes[..32] {
                    digest.push(HEX[(byte >> 4) as usize] as char);
                    digest.push(HEX[(byte & 15) as usize] as char);
                }
                digest
            });
            witnesses.push(ReadWitness {
                key: key.clone(),
                value_digest,
            });
            values.push(value);
        }
        Ok(ReadBatch { values, witnesses })
    }

    /// All witness comparisons and writes occur in one transaction. A conflict writes nothing.
    pub fn commit(
        &self,
        witnesses: &[ReadWitness],
        changes: &[Change],
        cancel: Option<&AtomicBool>,
    ) -> io::Result<Commit> {
        if changes.len() > 64_000 || witnesses.len() > 64_000 {
            return Err(error("batch exceeds 64000 records"));
        }
        let bytes = changes.iter().try_fold(0usize, |total, change| {
            let (key, payload) = match change {
                Change::Put(k, v) => (k, v.len()),
                Change::Delete(k) => (k, 0),
            };
            total
                .checked_add(key.namespace.len())
                .and_then(|n| n.checked_add(key.name.len()))
                .and_then(|n| n.checked_add(payload))
                .ok_or_else(|| error("batch size overflow"))
        })?;
        if bytes > 128 * 1024 * 1024 {
            return Err(error("batch exceeds 128 MiB"));
        }
        // Key encoding and content hashing happen before acquiring the DB lock.
        let mut encoded = BTreeMap::new();
        for change in changes {
            let (key, value) = match change {
                Change::Put(k, v) => {
                    if v.len() > MAX_RECORD {
                        return Err(error("record exceeds 256 MiB limit"));
                    }
                    if k.namespace == "blob-v1" && digest(v) != k.name {
                        return Err(error("blob key does not match content"));
                    }
                    (k, Some(encode_record(v)))
                }
                Change::Delete(k) => (k, None),
            };
            encoded.insert(key.encode()?, value);
        }
        let trace = std::env::var_os("DM_BUILD_TRACE").is_some();
        let encoded_bytes = if trace {encoded.iter().map(|(key,value)|key.len()+value.as_ref().map_or(0,Vec::len)).sum::<usize>()} else {0};
        let transaction_started = Instant::now();
        let result = self.access(cancel, |db| {
            let tx = db.begin_write().map_err(error)?;
            {
                let mut table = tx.open_table(RECORDS).map_err(error)?;
                for witness in witnesses {
                    let actual = table
                        .get(witness.key.encode()?.as_str())
                        .map_err(error)?
                        .map(|v| decode_record(v.value()).map(|value| digest(&value)))
                        .transpose()?;
                    if actual != witness.value_digest {
                        return Ok(Commit::Conflict);
                    }
                }
                for (key, value) in encoded {
                    match value {
                        Some(value) => {
                            table
                                .insert(key.as_str(), value.as_slice())
                                .map_err(error)?;
                        }
                        None => {
                            table.remove(key.as_str()).map_err(error)?;
                        }
                    }
                }
            }
            tx.commit().map_err(error)?;
            Ok(Commit::Applied)
        });
        if trace {
            eprintln!("DM_BUILD_TRACE store transaction: {} changes={} witnesses={} encoded_bytes={} elapsed={:.3}s outcome={:?}",
                self.path.display(),changes.len(),witnesses.len(),encoded_bytes,transaction_started.elapsed().as_secs_f64(),result.as_ref().map_err(|failure|failure.kind()));
        }
        result
    }
    /// Bounded stage snapshot. Omitted entries never prove semantic absence;
    /// callers can recompute or use read_many when `complete=false`.
    pub fn snapshot_namespace(
        &self,
        namespace: &str,
        max_records: usize,
        max_bytes: usize,
        cancel: Option<&AtomicBool>,
    ) -> io::Result<NamespaceSnapshot> {
        Key::new(namespace, "").encode()?;
        // Read snapshots need to cover projects larger than one write batch.
        // The byte budget is unchanged, and transactions still cap writes at 64k.
        let max_records = max_records.min(128_000);
        let max_bytes = max_bytes.min(128 * 1024 * 1024);
        let prefix = format!(
            "{{\"namespace\":{},\"name\":",
            serde_json::to_string(namespace).map_err(error)?
        );
        let upper = format!("{prefix}~");
        let mut snapshot = self.access(cancel, |db| {
            let tx = db.begin_read().map_err(error)?;
            let table = tx.open_table(RECORDS).map_err(error)?;
            let mut records = Vec::new();
            let mut bytes = 0usize;
            for row in table
                .range(prefix.as_str()..upper.as_str())
                .map_err(error)?
            {
                if cancel.is_some_and(|flag| flag.load(Ordering::Relaxed)) {
                    return Err(io::Error::new(
                        io::ErrorKind::Interrupted,
                        "store snapshot cancelled",
                    ));
                }
                let (key, value) = row.map_err(error)?;
                let key: Key = serde_json::from_str(key.value()).map_err(error)?;
                if key.namespace != namespace {
                    return Err(invalid_data("namespace index mismatch"));
                }
                let cost = value.value().len() + key.namespace.len() + key.name.len();
                if records.len() == max_records || cost > max_bytes.saturating_sub(bytes) {
                    return Ok(NamespaceSnapshot {
                        records,
                        complete: false,
                    });
                }
                bytes += cost;
                records.push((key, value.value().to_vec()));
            }
            Ok(NamespaceSnapshot {
                records,
                complete: true,
            })
        })?;
        for (_, value) in &mut snapshot.records {
            *value = decode_record(value)?;
        }
        Ok(snapshot)
    }
    pub fn put_many(
        &self,
        records: Vec<(Key, Vec<u8>)>,
        cancel: Option<&AtomicBool>,
    ) -> io::Result<Commit> {
        let changes = records
            .into_iter()
            .map(|(key, value)| Change::Put(key, value))
            .collect::<Vec<_>>();
        self.commit(&[], &changes, cancel)
    }
    pub fn blob_key(bytes: &[u8]) -> Key {
        Key::new("blob-v1", digest(bytes))
    }
    pub fn read_blobs(&self, keys: &[Key], cancel: Option<&AtomicBool>) -> io::Result<ReadBatch> {
        let batch = self.read_many(keys, cancel)?;
        for (key, value) in keys.iter().zip(&batch.values) {
            if key.namespace != "blob-v1"
                || value
                    .as_ref()
                    .is_some_and(|value| digest(value) != key.name)
            {
                return Err(error("invalid content-addressed blob"));
            }
        }
        Ok(batch)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stage_read_budgets_reject_oversize_without_inventing_absence() {
        let path = temporary();
        let store = Store::open(&path).unwrap();
        let keys = [Key::new("stage", "first"), Key::new("stage", "second")];
        store
            .put_many(
                keys.iter().map(|key| (key.clone(), vec![7; 64])).collect(),
                None,
            )
            .unwrap();
        let expected = store.read_many(&keys, None).unwrap();
        let bounded = store.read_many_bounded(&keys, 64, 192, None).unwrap();
        assert_eq!(bounded.values, expected.values);
        assert_eq!(bounded.witnesses, expected.witnesses);
        assert_eq!(
            store.read_many_bounded(&keys, 63, 192, None).unwrap_err().kind(),
            io::ErrorKind::InvalidInput,
        );
        assert_eq!(
            store.read_many_bounded(&keys, 64, 191, None).unwrap_err().kind(),
            io::ErrorKind::InvalidInput,
        );
        let missing = store
            .read_many_bounded(&[Key::new("stage", "missing")], 1, 1, None)
            .unwrap();
        assert_eq!(missing.values, vec![None]);
        assert_eq!(missing.witnesses[0].value_digest, None);
        drop(store);
        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }
    fn temporary() -> PathBuf {
        std::env::temp_dir()
            .join(format!(
                "dm-store-{}-{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_nanos()
            ))
            .join("store.redb")
    }
    #[test]
    fn witnesses_detect_update_delete_and_new_negative_dependency_atomically() {
        let path = temporary();
        let store = Store::open(&path).unwrap();
        let a = Key::new("facts", "a");
        let b = Key::new("facts", "b");
        let baseline = store.read_many(&[a.clone(), b.clone()], None).unwrap();
        store
            .commit(&[], &[Change::Put(a.clone(), b"new".to_vec())], None)
            .unwrap();
        assert_eq!(
            store
                .commit(
                    &baseline.witnesses,
                    &[Change::Put(b.clone(), b"wrong".to_vec())],
                    None
                )
                .unwrap(),
            Commit::Conflict
        );
        assert!(store.read_many(&[b.clone()], None).unwrap().values[0].is_none());
        let fresh = store.read_many(&[a.clone(), b.clone()], None).unwrap();
        assert_eq!(
            store
                .commit(
                    &fresh.witnesses,
                    &[
                        Change::Delete(a.clone()),
                        Change::Put(b.clone(), b"ok".to_vec())
                    ],
                    None
                )
                .unwrap(),
            Commit::Applied
        );
        let reopened = Store::open(&path).unwrap();
        assert_eq!(
            reopened.read_many(&[a, b], None).unwrap().values,
            vec![None, Some(b"ok".to_vec())]
        );
        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }
    #[test]
    fn cancelled_and_timed_out_acquisition_do_not_modify_database() {
        let path = temporary();
        let store = Store::open(&path)
            .unwrap()
            .with_limits(Duration::from_millis(10), 1024 * 1024);
        let cancelled = AtomicBool::new(true);
        assert_eq!(
            store.read_many(&[], Some(&cancelled)).unwrap_err().kind(),
            io::ErrorKind::Interrupted
        );
        let lock = store.lock(None).unwrap();
        assert_eq!(
            store.read_many(&[], None).unwrap_err().kind(),
            io::ErrorKind::TimedOut
        );
        drop(lock);
        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }
    #[test]
    fn schema_and_blob_identity_reject_incompatible_persistence() {
        let path = temporary();
        let store = Store::open(&path).unwrap();
        let blob = Store::blob_key(b"content");
        assert!(store
            .commit(&[], &[Change::Put(blob.clone(), b"wrong".to_vec())], None)
            .is_err());
        store
            .commit(&[], &[Change::Put(blob.clone(), b"content".to_vec())], None)
            .unwrap();
        assert_eq!(
            store.read_blobs(&[blob], None).unwrap().values[0].as_deref(),
            Some(b"content".as_slice())
        );
        {
            let _lock = store.lock(None).unwrap();
            let db = Database::create(&path).unwrap();
            let tx = db.begin_write().unwrap();
            {
                let mut table = tx.open_table(RECORDS).unwrap();
                table
                    .insert(SCHEMA_KEY, b"future-schema".as_slice())
                    .unwrap();
            }
            tx.commit().unwrap();
        }
        assert!(Store::open(&path).is_err());
        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }

    #[test]
    fn stage_snapshot_spans_multiple_write_batches_within_byte_budget() {
        let path = temporary();
        let store = Store::open(&path).unwrap();
        for range in [0..32_001, 32_001..64_001] {
            store
                .put_many(
                    range
                        .map(|i| (Key::new("procedures", format!("{i:05}")), vec![7]))
                        .collect(),
                    None,
                )
                .unwrap();
        }
        let snapshot = store
            .snapshot_namespace("procedures", 128_000, 8 * 1024 * 1024, None)
            .unwrap();
        assert!(snapshot.complete);
        assert_eq!(snapshot.records.len(), 64_001);
        let bounded = store
            .snapshot_namespace("procedures", 128_000, 1024, None)
            .unwrap();
        assert!(!bounded.complete);
        assert!(bounded.records.len() < snapshot.records.len());
        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }

    #[test]
    fn namespace_snapshot_bounds_and_checksum_validation() {
        let path = temporary();
        let store = Store::open(&path).unwrap();
        let a = Key::new("lowering", "a");
        let b = Key::new("lowering", "b");
        store
            .put_many(
                vec![
                    (a.clone(), b"first".to_vec()),
                    (b.clone(), b"second".to_vec()),
                    (Key::new("other", "x"), b"other".to_vec()),
                ],
                None,
            )
            .unwrap();
        let full = store
            .snapshot_namespace("lowering", 64, 1024, None)
            .unwrap();
        assert!(full.complete);
        assert_eq!(full.records.len(), 2);
        let capped = store.snapshot_namespace("lowering", 1, 1024, None).unwrap();
        assert!(!capped.complete);
        assert_eq!(capped.records.len(), 1);
        assert!(
            !store
                .snapshot_namespace("lowering", 64, 1, None)
                .unwrap()
                .complete
        );
        assert!(
            store
                .snapshot_namespace("absent", 64, 1024, None)
                .unwrap()
                .complete
        );
        {
            let _lock = store.lock(None).unwrap();
            let db = Database::create(&path).unwrap();
            let tx = db.begin_write().unwrap();
            {
                let mut table = tx.open_table(RECORDS).unwrap();
                table
                    .insert(a.encode().unwrap().as_str(), b"corrupt payload".as_slice())
                    .unwrap();
            }
            tx.commit().unwrap();
        }
        assert!(store.read_many(&[a], None).is_err());
        assert!(store
            .snapshot_namespace("lowering", 64, 1024, None)
            .is_err());
        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }

    #[test]
    fn process_worker() {
        let Some(path) = std::env::var_os("DM_STORE_TEST_PATH") else {
            return;
        };
        let client = std::env::var("DM_STORE_TEST_CLIENT").unwrap();
        let store = Store::open(path).unwrap();
        let keys = (0..64)
            .map(|row| Key::new("clients", format!("{client}:{row}")))
            .collect::<Vec<_>>();
        for i in 0u32..8 {
            let batch = store.read_many(&keys, None).unwrap();
            let changes = keys
                .iter()
                .map(|key| Change::Put(key.clone(), i.to_le_bytes().to_vec()))
                .collect::<Vec<_>>();
            assert_eq!(
                store.commit(&batch.witnesses, &changes, None).unwrap(),
                Commit::Applied
            );
        }
    }

    #[test]
    fn six_independent_processes_share_transactional_store() {
        let path = temporary();
        let store = Store::open(&path).unwrap();
        let started = Instant::now();
        let mut children = (0..6)
            .map(|i| {
                std::process::Command::new(std::env::current_exe().unwrap())
                    .args(["--exact", "tests::process_worker", "--nocapture"])
                    .env("DM_STORE_TEST_PATH", &path)
                    .env("DM_STORE_TEST_CLIENT", i.to_string())
                    .stdout(std::process::Stdio::null())
                    .spawn()
                    .unwrap()
            })
            .collect::<Vec<_>>();
        for child in &mut children {
            assert!(child.wait().unwrap().success());
        }
        let keys = (0..6)
            .flat_map(|client| {
                (0..64).map(move |row| Key::new("clients", format!("{client}:{row}")))
            })
            .collect::<Vec<_>>();
        eprintln!(
            "six clients, 48 read+commit batches, 3072 writes: {:?}",
            started.elapsed()
        );
        assert!(store
            .read_many(&keys, None)
            .unwrap()
            .values
            .iter()
            .all(|v| v.as_deref() == Some(7u32.to_le_bytes().as_slice())));
        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }
}
