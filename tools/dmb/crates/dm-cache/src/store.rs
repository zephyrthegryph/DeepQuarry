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
        if let Some(root) = std::env::var_os("DMB_CACHE_DIR") {
            if root.is_empty() { return Err(CacheError::Invalid("DMB_CACHE_DIR is empty".into())); }
            return Self::open(PathBuf::from(root), limits);
        }
        let root = if cfg!(windows) {
            std::env::var_os("LOCALAPPDATA")
                .map(PathBuf::from)
                .ok_or_else(|| CacheError::Invalid("LOCALAPPDATA unavailable".into()))?
                .join("dmbd/cache")
        } else if let Some(root) = std::env::var_os("XDG_CACHE_HOME") {
            PathBuf::from(root).join("dmbd")
        } else {
            PathBuf::from(
                std::env::var_os("HOME")
                    .ok_or_else(|| CacheError::Invalid("HOME unavailable".into()))?,
            )
            .join(".cache/dmbd")
        };
        Self::open(root, limits)
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
        // Complete admission before publishing any base: a late rejection must
        // exclude every record of that segment, including earlier valid records.
        loop {
            let before = snapshot.segment_count();
            for key in live {
                let _ = snapshot.get(*key, |payload, symbols| validate(*key, payload, symbols));
            }
            if snapshot.segment_count() == before {
                break;
            }
        }
        let supersedes = snapshot
            .segments
            .iter()
            .filter(|(_, segment)| !segment.is_rejected())
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
                return Err(CacheError::Invalid(
                    "compaction record cannot fit segment".into(),
                ));
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
        loop {
            let generation = self.rejection_generation.load(Ordering::Acquire);
            let superseded = if generation == 0 {
                self.superseded.clone()
            } else {
                let mut revised = self
                    .revised_superseded
                    .lock()
                    .unwrap_or_else(|e| e.into_inner());
                if revised.0 != generation {
                    revised.1 = Arc::new(
                        self.segments
                            .iter()
                            .filter(|(_, segment)| !segment.is_rejected())
                            .flat_map(|(_, segment)| segment.supersedes().iter().copied())
                            .collect(),
                    );
                    revised.0 = generation;
                }
                revised.1.clone()
            };
            let mut retry = false;
            for &ordinal in self.index.get(&key)? {
                let (path, segment) = &self.segments[ordinal];
                if segment.is_rejected() || superseded.contains(&segment.id()) {
                    continue;
                }
                match segment.get(key, &validate) {
                    Ok(Some(view)) => {
                        // At most index.len() keys: every successful lookup is
                        // already present in this immutable snapshot's index.
                        self.used_keys
                            .lock()
                            .unwrap_or_else(|e| e.into_inner())
                            .insert(key);
                        return Some(view);
                    }
                    Ok(None) => (),
                    Err(error) => {
                        self.rejection_generation.fetch_add(1, Ordering::AcqRel);
                        self.rejected
                            .lock()
                            .unwrap_or_else(|p| p.into_inner())
                            .push(RejectedSegment {
                                path: path.clone(),
                                reason: error.to_string(),
                            });
                        retry = true;
                        break;
                    }
                }
            }
            if !retry {
                return None;
            }
        }
    }
}
