#[path = "store_candidates.rs"]
mod candidates;
use crate::segment::{encode, CacheError, Limits, Record, RecordKey, RecordView, Segment};
use fs2::FileExt;
use std::{
    collections::{BTreeMap, BTreeSet},
    fs::{self, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex,
    },
};
static NEXT: AtomicU64 = AtomicU64::new(0);
#[derive(Clone, Debug)]
pub struct RejectedSegment {
    pub path: PathBuf,
    pub reason: String,
}
pub struct Cache {
    pub(crate) root: PathBuf,
    pub(crate) limits: Limits,
}
pub struct CacheSnapshot {
    writer: Cache,
    pub(crate) segments: Vec<(PathBuf, Arc<Segment>)>,
    rejected: Mutex<Vec<RejectedSegment>>,
    index: BTreeMap<RecordKey, Vec<usize>>,
    superseded: Arc<BTreeSet<u128>>,
    rejection_generation: AtomicU64,
    revised_superseded: Mutex<(u64, Arc<BTreeSet<u128>>)>,
    used_keys: Mutex<BTreeSet<RecordKey>>,
}
#[derive(Debug)]
pub struct CompactResult {
    pub segment: Option<u128>,
    pub segments: Vec<u128>,
    pub records: usize,
    pub deleted: usize,
    pub deferred_deletes: Vec<PathBuf>,
}
impl Cache {
    pub fn open(root: impl Into<PathBuf>, limits: Limits) -> Result<Self, CacheError> {
        let root = root.into();
        fs::create_dir_all(&root)?;
        Ok(Self { root, limits })
    }
    pub fn user_default(limits: Limits) -> Result<Self, CacheError> {
        Self::open(Self::default_root()?, limits)
    }
    /// Select the caller's cache namespace without opening or creating it.
    pub fn default_root() -> Result<PathBuf, CacheError> {
        if let Some(root) = std::env::var_os("DMB_CACHE_DIR") {
            if root.is_empty() {
                return Err(CacheError::Invalid("DMB_CACHE_DIR is empty".into()));
            }
            return Ok(PathBuf::from(root));
        }
        let root = if cfg!(windows) {
            PathBuf::from("E:/dq-cache/dmbd/cache")
        } else if let Some(root) = std::env::var_os("XDG_CACHE_HOME") {
            PathBuf::from(root).join("dmbd")
        } else {
            PathBuf::from(
                std::env::var_os("HOME")
                    .ok_or_else(|| CacheError::Invalid("HOME unavailable".into()))?,
            )
            .join(".cache/dmbd")
        };
        Ok(root)
    }
    /// Check quota-aware available space before appending a segment. This never
    /// skips a record; shortages are explicit publication errors.
    pub fn check_population_space(&self, required: u64) -> Result<(), CacheError> {
        check_available_space(&self.root, required)
    }
    pub fn root(&self) -> &Path {
        &self.root
    }
    pub fn snapshot(&self) -> Result<CacheSnapshot, CacheError> {
        let mut paths = Vec::new();
        for item in fs::read_dir(&self.root)? {
            let item = item?;
            if item.file_type()?.is_file()
                && item.path().extension().is_some_and(|ext| ext == "seg")
            {
                paths.push(item.path());
            }
        }
        paths.sort();
        let mut segments = Vec::new();
        let mut rejected = Vec::new();
        let mut ids = BTreeSet::new();
        for path in paths {
            match Segment::open(&path, self.limits) {
                Ok(segment) => {
                    if path.file_stem().and_then(|s| s.to_str())
                        != Some(format!("{:032x}", segment.id()).as_str())
                        || !ids.insert(segment.id())
                    {
                        rejected.push(RejectedSegment {
                            path,
                            reason: "segment identity/name mismatch".into(),
                        });
                    } else {
                        segments.push((path, Arc::new(segment)));
                    }
                }
                Err(error) => rejected.push(RejectedSegment {
                    path,
                    reason: error.to_string(),
                }),
            }
        }
        let mut index: BTreeMap<RecordKey, Vec<usize>> = BTreeMap::new();
        for (ordinal, (_, segment)) in segments.iter().enumerate() {
            for key in segment.keys() {
                index.entry(key).or_default().push(ordinal);
            }
        }
        let superseded: BTreeSet<u128> = segments
            .iter()
            .flat_map(|(_, segment)| segment.supersedes().iter().copied())
            .collect();
        Ok(CacheSnapshot {
            writer: Cache {
                root: self.root.clone(),
                limits: self.limits,
            },
            segments,
            rejected: Mutex::new(rejected),
            index,
            superseded: Arc::new(superseded),
            rejection_generation: AtomicU64::new(0),
            revised_superseded: Mutex::new((0, Arc::new(BTreeSet::new()))),
            used_keys: Mutex::new(BTreeSet::new()),
        })
    }
    pub fn publish(&self, records: &[Record]) -> Result<u128, CacheError> {
        self.publish_superseding(records, &[])
    }
    fn publish_superseding(
        &self,
        records: &[Record],
        supersedes: &[u128],
    ) -> Result<u128, CacheError> {
        let (id, bytes) = encode(records, supersedes, self.limits)?;
        let destination = self.root.join(format!("{id:032x}.seg"));
        if destination.exists() {
            if fs::read(&destination)? == bytes {
                return Ok(id);
            }
            return Err(CacheError::Invalid(
                "segment content identity collision".into(),
            ));
        }
        self.check_population_space(bytes.len() as u64)?;
        let nonce = NEXT.fetch_add(1, Ordering::Relaxed);
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(|e| CacheError::Invalid(e.to_string()))?
            .as_nanos();
        let temporary = self.root.join(format!(
            ".{id:032x}-{}-{stamp}-{nonce}.tmp",
            std::process::id()
        ));
        let result = (|| {
            let mut file = OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&temporary)?;
            file.write_all(&bytes)?;
            file.flush()?;
            drop(file);
            // On Windows rename never replaces an existing destination. A competing
            // identical publisher may win; compare exact bytes before accepting it.
            match fs::rename(&temporary, &destination) {
                Ok(()) => Ok(id),
                Err(error) => {
                    if destination.exists() && fs::read(&destination)? == bytes {
                        Ok(id)
                    } else {
                        Err(CacheError::Io(error))
                    }
                }
            }
        })();
        let _ = fs::remove_file(&temporary);
        result
    }
    /// `live` is supplied by session reachability (last fourteen days). This
    /// neutral storage layer does not invent session or payload dependency rules.
    /// All retained payloads are bytechecked before a base may supersede inputs.
    pub fn compact(
        &self,
        live: &BTreeSet<RecordKey>,
        validate: impl Fn(RecordKey, &[u8], &[(u64, &[u8])]) -> Result<(), String>,
    ) -> Result<CompactResult, CacheError> {
        let _lock = self.compact_lock(false)?;
        self.compact_locked(live, &validate)
    }
    pub(crate) fn compact_lock(&self, wait: bool) -> Result<std::fs::File, CacheError> {
        let lock = OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(self.root.join("compact.lock"))?;
        let result = if wait {
            lock.lock_exclusive()
        } else {
            lock.try_lock_exclusive()
        };
        match result {
            Ok(()) => Ok(lock),
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => Err(CacheError::Busy),
            Err(error) => Err(error.into()),
        }
    }
    pub(crate) fn compact_locked(
        &self,
        live: &BTreeSet<RecordKey>,
        validate: &impl Fn(RecordKey, &[u8], &[(u64, &[u8])]) -> Result<(), String>,
    ) -> Result<CompactResult, CacheError> {
        let snapshot = self.snapshot()?;
        // Complete admission before publishing any base. All healthy candidates
        // must be inspected: a later typed rejection excludes its whole segment.
        // Format 1 permits only one record per key in each base segment, so a
        // neutral compactor cannot discard distinct semantic-context variants.
        loop {
            let before = snapshot.segment_count();
            let multiple_candidates = std::cell::Cell::new(None);
            for key in live {
                let Some(first) =
                    snapshot.get(*key, |payload, symbols| validate(*key, payload, symbols))
                else {
                    continue;
                };
                let _ = snapshot.get_candidate(*key, |payload, symbols| {
                    validate(*key, payload, symbols)?;
                    if (payload != first.payload || symbols != first.symbols.as_slice())
                        && multiple_candidates.get().is_none()
                    {
                        multiple_candidates.set(Some(*key));
                    }
                    Ok(false)
                });
            }
            if snapshot.segment_count() == before {
                if let Some(key) = multiple_candidates.get() {
                    return Err(CacheError::Invalid(format!(
                        "compaction deferred: distinct healthy candidates for {key:?} require lossless multi-candidate storage"
                    )));
                }
                break;
            }
        }
        // Persist whole-segment typed rejection in the new base's supersedes
        // roster too. Otherwise an undeleted rejected segment becomes healthy
        // in a later snapshot and can resurrect records excluded above.
        let supersedes = snapshot
            .segments
            .iter()
            .map(|(_, segment)| segment.id())
            .collect::<Vec<_>>();
        if supersedes.is_empty() {
            return Ok(CompactResult {
                segment: None,
                segments: Vec::new(),
                records: 0,
                deleted: 0,
                deferred_deletes: Vec::new(),
            });
        }
        let overhead = 72u64
            .checked_add(
                (supersedes.len() as u64)
                    .checked_mul(16)
                    .ok_or_else(|| CacheError::Invalid("compaction framing overflow".into()))?,
            )
            .ok_or_else(|| CacheError::Invalid("compaction framing overflow".into()))?;
        let mut chunks = Vec::new();
        let mut pending = Vec::new();
        let mut charge = overhead;
        let mut count = 0;
        for key in live {
            let Some(view) =
                snapshot.get(*key, |payload, symbols| validate(*key, payload, symbols))
            else {
                continue;
            };
            let record = Record {
                key: *key,
                symbols: view
                    .symbols
                    .iter()
                    .map(|(id, text)| crate::SymbolText {
                        id: *id,
                        text: Arc::from(*text),
                    })
                    .collect(),
                payload: Arc::from(view.payload),
            };
            let bytes = crate::sink::record_charge(&record)?;
            if !pending.is_empty()
                && (charge.saturating_add(bytes) > self.limits.segment_bytes
                    || pending.len() >= self.limits.records as usize)
            {
                chunks.push(self.publish_superseding(&pending, &supersedes)?);
                pending.clear();
                charge = overhead;
            }
            if charge.saturating_add(bytes) > self.limits.segment_bytes {
                chunks.push(self.publish_superseding(&[record], &supersedes)?);
                count += 1;
                continue;
            }
            charge += bytes;
            pending.push(record);
            count += 1;
        }
        if !pending.is_empty() || chunks.is_empty() {
            chunks.push(self.publish_superseding(&pending, &supersedes)?);
        }
        let old = snapshot
            .segments
            .iter()
            .map(|(path, segment)| (path.clone(), segment.id()))
            .collect::<Vec<_>>();
        drop(snapshot);
        let mut deleted = 0;
        let mut deferred_deletes = Vec::new();
        for (path, id) in old {
            if supersedes.contains(&id) && !chunks.contains(&id) {
                match fs::remove_file(&path) {
                    Ok(()) => deleted += 1,
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => (),
                    Err(_) => deferred_deletes.push(path),
                }
            }
        }
        Ok(CompactResult {
            segment: chunks.first().copied(),
            segments: chunks,
            records: count,
            deleted,
            deferred_deletes,
        })
    }
}
impl CacheSnapshot {
    /// Append through the captured writer without mutating this mapped snapshot.
    /// Used only to flush bounded population queues when no callback was supplied.
    pub fn publish(&self, records: &[Record]) -> Result<u128, CacheError> {
        self.writer.publish(records)
    }

    /// Successful returned views only, including records whose consumer later
    /// rejects semantic replay. Missing/corrupt lookups never become roots.
    /// Storage is bounded by this snapshot's immutable indexed key inventory.
    pub fn record_used_keys(&self) -> BTreeSet<RecordKey> {
        self.used_keys
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
    }
    /// Conservative roots for configured-session leases. Superseded or rejected
    /// segments contribute no roots; keys are immutable symbolic record identities.
    pub fn record_keys(&self) -> BTreeSet<RecordKey> {
        let superseded = self
            .segments
            .iter()
            .filter(|(_, segment)| !segment.is_rejected())
            .flat_map(|(_, segment)| segment.supersedes().iter().copied())
            .collect::<BTreeSet<_>>();
        self.segments
            .iter()
            .filter(|(_, segment)| !segment.is_rejected() && !superseded.contains(&segment.id()))
            .flat_map(|(_, segment)| segment.keys())
            .collect()
    }
    pub fn segment_count(&self) -> usize {
        self.segments
            .iter()
            .filter(|(_, s)| !s.is_rejected())
            .count()
    }
    pub fn mapped_bytes(&self) -> u64 {
        self.segments
            .iter()
            .map(|(_, segment)| segment.mapped_bytes() as u64)
            .sum()
    }
    pub fn rejected(&self) -> Vec<RejectedSegment> {
        self.rejected
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .clone()
    }
    /// A corrupt/unsupported record is a cache miss. Whole-segment rejection is
    /// visible in `rejected`; no pointer from that segment is admitted again.
    pub fn get<'a>(
        &'a self,
        key: RecordKey,
        validate: impl Fn(&[u8], &[(u64, &[u8])]) -> Result<(), String>,
    ) -> Option<RecordView<'a>> {
        self.get_candidate(key, |payload, symbols| {
            validate(payload, symbols).map(|()| true)
        })
    }
}

#[cfg(windows)]
fn check_available_space(root: &Path, required: u64) -> Result<(), CacheError> {
    use std::os::windows::ffi::OsStrExt;
    #[link(name = "kernel32")]
    extern "system" {
        fn GetDiskFreeSpaceExW(
            directory: *const u16,
            available: *mut u64,
            total: *mut u64,
            free: *mut u64,
        ) -> i32;
    }
    let mut path: Vec<u16> = root.as_os_str().encode_wide().collect();
    if path.contains(&0) {
        return Err(CacheError::Invalid("cache path contains NUL".into()));
    }
    path.push(0);
    let mut available = 0u64;
    // Microsoft GetDiskFreeSpaceExW documents quota-aware u64 available bytes.
    // The terminated path and output remain live for this synchronous call.
    if unsafe {
        GetDiskFreeSpaceExW(
            path.as_ptr(),
            &mut available,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
        )
    } == 0
    {
        return Err(std::io::Error::last_os_error().into());
    }
    if available < required {
        return Err(CacheError::Invalid(format!(
            "cache population requires {required} bytes; only {available} available at {}",
            root.display()
        )));
    }
    Ok(())
}
#[cfg(not(windows))]
fn check_available_space(_root: &Path, _required: u64) -> Result<(), CacheError> {
    // Portable std exposes no quota-aware free-space API. Writes still propagate
    // StorageFull as errors; the Windows-supported population path checks above.
    Ok(())
}
