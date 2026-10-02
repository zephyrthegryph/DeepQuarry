//! Payload-free resource identities use the shared bounded work engine and store.
//! Strong file proofs accelerate reads; failed/unsupported proofs hash exactly.
use super::{invalid, validate_archive_name, ResourceRequest};
use dm_host::file_stamp::{capture, FileStamp};
use dm_store::{Key, Store};
use dm_work::{map_ordered, WorkError, WorkLimits};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::fs;
use std::io::{self, Read};
use std::path::{Path, PathBuf};

const NAMESPACE: &str = "resource-source-sha-v2";
const MAX_RECORDS: usize = 64_000;
const MAX_CACHE_BYTES: usize = 32 * 1024 * 1024;

#[derive(Clone, Debug, Serialize, Deserialize)]
struct Identity {
    path: PathBuf,
    len: u64,
    digest: [u8; 32],
    stamp: Option<FileStamp>,
}

#[derive(Clone, Copy, Debug, Default)]
pub struct ResourceFingerprintStats {
    pub files_hashed: usize,
    pub bytes_hashed: u64,
    pub proof_hits: usize,
    pub disk_records: usize,
}

#[derive(Default)]
pub struct ResourceFingerprintCache {
    store: Option<Store>,
    records: BTreeMap<PathBuf, Identity>,
    latest_stamps: BTreeMap<PathBuf, FileStamp>,
    resident_bytes: usize,
    stats: ResourceFingerprintStats,
}

fn key(path: &Path) -> Key {
    Key::new(
        NAMESPACE,
        format!("{:x}", Sha256::digest(path.to_string_lossy().as_bytes())),
    )
}

pub(super) fn work_error(error: WorkError) -> io::Error {
    match error {
        WorkError::Panic { job, message } => panic!("resource worker {job}: {message}"),
        other => io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("resource work limits: {other:?}"),
        ),
    }
}

pub(super) fn fingerprint<'a>(
    values: impl IntoIterator<Item = (&'a str, u64, [u8; 32])>,
) -> [u8; 32] {
    let mut hash = Sha256::new();
    hash.update(b"dm-resources-v2\0");
    for (name, len, digest) in values {
        hash.update((name.len() as u64).to_le_bytes());
        hash.update(name.as_bytes());
        hash.update(len.to_le_bytes());
        hash.update(digest);
    }
    hash.finalize().into()
}

fn read_identity(path: &Path, expected: Option<FileStamp>) -> io::Result<Identity> {
    let mut file = fs::File::open(path)
        .map_err(|error| io::Error::new(error.kind(), format!("{}: {error}", path.display())))?;
    let len = file.metadata()?.len();
    let mut hash = Sha256::new();
    let mut read = 0u64;
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let count = file.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        read = read
            .checked_add(count as u64)
            .ok_or_else(|| invalid("resource size overflow"))?;
        hash.update(&buffer[..count]);
    }
    drop(file);
    let after = capture(path);
    if read != len
        || expected
            .as_ref()
            .is_some_and(|stamp| after.as_ref() != Some(stamp))
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("{}: resource changed while hashing", path.display()),
        ));
    }
    Ok(Identity {
        path: path.to_owned(),
        len,
        digest: hash.finalize().into(),
        stamp: expected.filter(|stamp| after.as_ref() == Some(stamp)),
    })
}

impl ResourceFingerprintCache {
    pub fn open(root: &Path) -> Self {
        Self {
            store: Store::open(root.join("resource-inputs.redb")).ok(),
            ..Self::default()
        }
    }
    pub fn stats(&self) -> ResourceFingerprintStats {
        self.stats
    }
    pub fn resident_bytes(&self) -> usize {
        self.resident_bytes
            + self
                .latest_stamps
                .keys()
                .map(|path| path.as_os_str().len() * 2 + 192)
                .sum::<usize>()
    }

    /// Proofs describe the exact payloads used by the most recent identity
    /// request. Caller-visible paths remain authored aliases; namespace lookup
    /// proofs are still the project preparer's responsibility.
    pub fn verified_stamps(
        &self,
        requests: &[ResourceRequest],
    ) -> Option<BTreeMap<PathBuf, FileStamp>> {
        if std::env::var("DM_BUILD_EXACT_INPUTS").is_ok_and(|value| value != "0") {
            return None;
        }
        requests
            .iter()
            .map(|request| {
                self.latest_stamps
                    .get(&request.disk_path)
                    .map(|stamp| (request.disk_path.clone(), stamp.clone()))
            })
            .collect()
    }

    /// Only same-object change-clock proofs may reuse a payload identity. Name
    /// collision checks and final framing always run in original request order.
    pub fn fingerprint_requests(
        &mut self,
        requests: impl IntoIterator<Item = ResourceRequest>,
    ) -> io::Result<[u8; 32]> {
        self.fingerprint_requests_with_limits(requests, WorkLimits::configured())
    }

    pub fn fingerprint_requests_with_limits(
        &mut self,
        requests: impl IntoIterator<Item = ResourceRequest>,
        limits: WorkLimits,
    ) -> io::Result<[u8; 32]> {
        self.stats = ResourceFingerprintStats::default();
        self.latest_stamps.clear();
        let mut requests: Vec<_> = requests.into_iter().collect();
        let authored_paths: Vec<_> = requests
            .iter()
            .map(|request| request.disk_path.clone())
            .collect();
        for request in &mut requests {
            validate_archive_name(&request.archive_name)?;
            // Junction-backed worktrees share the same actual asset proof.
            request.disk_path = request.disk_path.canonicalize().map_err(|error| {
                io::Error::new(
                    error.kind(),
                    format!("{}: {error}", request.disk_path.display()),
                )
            })?;
        }
        let mut seen = BTreeSet::new();
        let paths: Vec<_> = requests
            .iter()
            .filter_map(|request| {
                seen.insert(request.disk_path.clone())
                    .then(|| request.disk_path.clone())
            })
            .collect();
        if let Some(store) = &self.store {
            let missing: Vec<_> = paths
                .iter()
                .filter(|path| !self.records.contains_key(*path))
                .collect();
            for chunk in missing.chunks(256) {
                let keys: Vec<_> = chunk.iter().map(|path| key(path)).collect();
                if let Ok(batch) = store.read_many(&keys, None) {
                    for (path, bytes) in chunk.iter().zip(batch.values) {
                        if let Some(record) = bytes
                            .and_then(|bytes| serde_json::from_slice::<Identity>(&bytes).ok())
                            .filter(|record| record.path == **path)
                        {
                            if self.records.len() < MAX_RECORDS
                                && self.resident_bytes + path.as_os_str().len() * 2 + 256
                                    <= MAX_CACHE_BYTES
                            {
                                self.resident_bytes += path.as_os_str().len() * 2 + 256;
                                self.records.insert((**path).clone(), record);
                                self.stats.disk_records += 1;
                            }
                        }
                    }
                }
            }
        }
        let exact = std::env::var("DM_BUILD_EXACT_INPUTS").is_ok_and(|value| value != "0");
        let records = &self.records;
        let values = map_ordered(
            &paths,
            limits,
            |_| 96 * 1024,
            |path| {
                let current = (!exact).then(|| capture(path)).flatten();
                if let Some(record) = records
                    .get(path)
                    .filter(|record| current.is_some() && record.stamp == current)
                {
                    return Ok((record.clone(), true));
                }
                read_identity(path, current).map(|record| (record, false))
            },
        )
        .map_err(work_error)?;
        let mut identities = BTreeMap::new();
        let mut writes = Vec::new();
        for result in values {
            let (record, hit) = result?;
            if hit {
                self.stats.proof_hits += 1;
            } else {
                self.stats.files_hashed += 1;
                self.stats.bytes_hashed += record.len;
                if record.stamp.is_some() {
                    if let Ok(bytes) = serde_json::to_vec(&record) {
                        writes.push((key(&record.path), bytes));
                    }
                }
            }
            if !self.records.contains_key(&record.path)
                && self.records.len() < MAX_RECORDS
                && self.resident_bytes + record.path.as_os_str().len() * 2 + 256 <= MAX_CACHE_BYTES
            {
                self.resident_bytes += record.path.as_os_str().len() * 2 + 256;
                self.records.insert(record.path.clone(), record.clone());
            } else if let Some(previous) = self.records.get_mut(&record.path) {
                *previous = record.clone();
            }
            identities.insert(record.path.clone(), record);
        }
        // Every hash is complete before persistence publishes its stamp/digest.
        if let Some(store) = &self.store {
            let _ = store.put_many(writes, None);
        }
        let mut names = HashMap::new();
        let mut ordered = Vec::new();
        for (request, authored) in requests.iter().zip(authored_paths) {
            let input = &identities[&request.disk_path];
            if let Some(stamp) = &input.stamp {
                self.latest_stamps.insert(authored, stamp.clone());
            }
            if let Some(previous) =
                names.insert(request.archive_name.as_str(), (input.len, input.digest))
            {
                if previous != (input.len, input.digest) {
                    return Err(invalid("resource archive name resolves to different data"));
                }
            } else {
                ordered.push((request.archive_name.as_str(), input.len, input.digest));
            }
        }
        Ok(fingerprint(ordered))
    }
}
