//! Conservative configured-session reachability. Leases contain only record
//! identities; every retained record still passes the ordinary bytecheck path.
use crate::{Cache, CacheError, CompactResult, RecordKey};
use std::{
    collections::BTreeSet,
    fs::{self, OpenOptions},
    io::{Read, Write},
    path::Path,
    sync::atomic::{AtomicU64, Ordering},
    time::{Duration, SystemTime, UNIX_EPOCH},
};
static NEXT: AtomicU64 = AtomicU64::new(0);
const MAGIC: &[u8; 8] = b"DMBCLES1";
#[derive(Debug)]
pub struct LeaseCompaction {
    pub compact: CompactResult,
    pub active_leases: usize,
    pub expired_leases: usize,
    pub roots: usize,
}
fn invalid(message: &str) -> CacheError {
    CacheError::Invalid(message.into())
}
fn nanos(time: SystemTime) -> Result<u128, CacheError> {
    Ok(time
        .duration_since(UNIX_EPOCH)
        .map_err(|_| invalid("lease time precedes epoch"))?
        .as_nanos())
}
impl Cache {
    /// Publish after successful build, including snapshot roots and new records.
    /// The compactor's lock protects replacement and root collection; segment
    /// writers remain independent and never take this lock.
    pub fn record_lease(
        &self,
        session: u128,
        seen: SystemTime,
        keys: &BTreeSet<RecordKey>,
    ) -> Result<(), CacheError> {
        if keys.len() > self.limits.records as usize {
            return Err(invalid("lease record count outside limits"));
        }
        let _lock = self.compact_lock(true)?;
        let directory = self.root.join("leases");
        fs::create_dir_all(&directory)?;
        let mut bytes = MAGIC.to_vec();
        bytes.extend_from_slice(&session.to_le_bytes());
        bytes.extend_from_slice(&nanos(seen)?.to_le_bytes());
        bytes.extend_from_slice(&(keys.len() as u64).to_le_bytes());
        for key in keys {
            bytes.extend_from_slice(&key.stage.to_le_bytes());
            bytes.extend_from_slice(&key.version.to_le_bytes());
            bytes.extend_from_slice(&key.content.to_le_bytes());
        }
        bytes.extend_from_slice(&xxhash_rust::xxh3::xxh3_128(&bytes).to_le_bytes());
        let temporary = directory.join(format!(
            ".{}-{}.tmp",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let result = (|| {
            let mut file = OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&temporary)?;
            file.write_all(&bytes)?;
            drop(file);
            replace(&temporary, &directory.join(format!("{session:032x}.lease")))
        })();
        let _ = fs::remove_file(&temporary);
        result
    }
    /// The caller supplies DESIGN's fourteen-day retention and its usual stage
    /// validators. Recent unleased segments protect the publish-to-lease window.
    pub fn compact_leased(
        &self,
        now: SystemTime,
        retention: Duration,
        validate: impl Fn(RecordKey, &[u8], &[(u64, &[u8])]) -> Result<(), String>,
    ) -> Result<LeaseCompaction, CacheError> {
        let _lock = self.compact_lock(false)?;
        let now_ns = nanos(now)?;
        let mut roots = BTreeSet::new();
        let mut active = 0;
        let mut expired = Vec::new();
        let directory = self.root.join("leases");
        if directory.exists() {
            for entry in fs::read_dir(&directory)? {
                let entry = entry?;
                if !entry.file_type()?.is_file()
                    || entry
                        .path()
                        .extension()
                        .is_none_or(|extension| extension != "lease")
                {
                    continue;
                }
                let (session, seen, keys) = read(&entry.path(), self.limits.records)?;
                if entry.path().file_stem().and_then(|name| name.to_str())
                    != Some(format!("{session:032x}").as_str())
                {
                    return Err(invalid("lease name/identity differs"));
                }
                if now_ns.saturating_sub(seen) <= retention.as_nanos() {
                    active += 1;
                    roots.extend(keys);
                } else {
                    expired.push(entry.path());
                }
            }
        }
        let snapshot = self.snapshot()?;
        for (path, segment) in &snapshot.segments {
            let modified = fs::metadata(path)?.modified()?;
            if segment.supersedes().is_empty()
                && now.duration_since(modified).unwrap_or_default() <= retention
            {
                roots.extend(segment.keys());
            }
        }
        drop(snapshot);
        let count = roots.len();
        let result = self.compact_locked(&roots, &validate)?;
        // Disposable expired hints are removed only after successful compaction.
        for path in &expired {
            let _ = fs::remove_file(path);
        }
        Ok(LeaseCompaction {
            compact: result,
            active_leases: active,
            expired_leases: expired.len(),
            roots: count,
        })
    }
}
fn read(path: &Path, limit: u32) -> Result<(u128, u128, BTreeSet<RecordKey>), CacheError> {
    let mut file = fs::File::open(path)?;
    let max = 64u64 + (limit as u64) * 24;
    if file.metadata()?.len() > max {
        return Err(invalid("lease size outside limits"));
    }
    let mut bytes = Vec::new();
    Read::by_ref(&mut file)
        .take(max + 1)
        .read_to_end(&mut bytes)?;
    if bytes.len() < 64 || &bytes[..8] != MAGIC {
        return Err(invalid("lease framing differs"));
    }
    let end = bytes.len() - 16;
    if xxhash_rust::xxh3::xxh3_128(&bytes[..end])
        != u128::from_le_bytes(bytes[end..].try_into().unwrap())
    {
        return Err(invalid("lease checksum differs"));
    }
    let session = u128::from_le_bytes(bytes[8..24].try_into().unwrap());
    let seen = u128::from_le_bytes(bytes[24..40].try_into().unwrap());
    let count = u64::from_le_bytes(bytes[40..48].try_into().unwrap());
    if count > limit as u64 || 48u64 + count * 24 != end as u64 {
        return Err(invalid("lease record framing differs"));
    }
    let mut keys = BTreeSet::new();
    for row in bytes[48..end].chunks_exact(24) {
        if !keys.insert(RecordKey {
            stage: u32::from_le_bytes(row[..4].try_into().unwrap()),
            version: u32::from_le_bytes(row[4..8].try_into().unwrap()),
            content: u128::from_le_bytes(row[8..].try_into().unwrap()),
        }) {
            return Err(invalid("duplicate lease root"));
        }
    }
    Ok((session, seen, keys))
}
#[cfg(not(windows))]
fn replace(source: &Path, destination: &Path) -> Result<(), CacheError> {
    Ok(fs::rename(source, destination)?)
}
#[cfg(windows)]
fn replace(source: &Path, destination: &Path) -> Result<(), CacheError> {
    use std::os::windows::ffi::OsStrExt;
    #[link(name = "kernel32")]
    extern "system" {
        fn MoveFileExW(source: *const u16, destination: *const u16, flags: u32) -> i32;
    }
    let wide = |path: &Path| -> Result<Vec<u16>, CacheError> {
        let mut text = path.as_os_str().encode_wide().collect::<Vec<_>>();
        if text.contains(&0) {
            return Err(invalid("lease path contains NUL"));
        }
        text.push(0);
        Ok(text)
    };
    let source = wide(source)?;
    let destination = wide(destination)?;
    // Terminated buffers live through replacement; the old lease stays complete
    // when the OS rejects replacement. Hints need no sync_all durability.
    if unsafe { MoveFileExW(source.as_ptr(), destination.as_ptr(), 1) } == 0 {
        return Err(std::io::Error::last_os_error().into());
    }
    Ok(())
}
