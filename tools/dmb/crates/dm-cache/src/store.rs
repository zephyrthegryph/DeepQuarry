use crate::segment::{encode, CacheError, Limits, Record, RecordKey, RecordView, Segment};
use fs2::FileExt;
use std::{
    collections::{BTreeMap, BTreeSet},
    fs::{self, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
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
    root: PathBuf,
    limits: Limits,
}
pub struct CacheSnapshot {
    segments: Vec<(PathBuf, Arc<Segment>)>,
    rejected: Mutex<Vec<RejectedSegment>>,
    index: BTreeMap<RecordKey, Vec<usize>>,
    superseded: BTreeSet<u128>,
    record_rejected: AtomicBool,
}
#[derive(Debug)]
pub struct CompactResult {
    pub segment: Option<u128>,
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
        let superseded = segments
            .iter()
            .flat_map(|(_, segment)| segment.supersedes().iter().copied())
            .collect();
        Ok(CacheSnapshot {
            segments,
            rejected: Mutex::new(rejected),
            index,
            superseded,
            record_rejected: AtomicBool::new(false),
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
        let lock = OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(self.root.join("compact.lock"))?;
        match lock.try_lock_exclusive() {
            Ok(()) => (),
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                return Err(CacheError::Busy)
            }
            Err(error) => return Err(error.into()),
        }
        let snapshot = self.snapshot()?;
        let mut retained = BTreeMap::new();
        loop {
            let admitted_segments = snapshot.segment_count();
            retained.clear();
            for key in live {
                if let Some(view) =
                    snapshot.get(*key, |payload, symbols| validate(*key, payload, symbols))
                {
                    retained.insert(
                        *key,
                        Record {
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
                        },
                    );
                }
            }
            if snapshot.segment_count() == admitted_segments {
                break;
            }
            // A late failure rejects its entire segment, including earlier keys.
            // Restart against the remaining immutable segments; each restart
            // removes at least one segment, so this cannot loop indefinitely.
        }
        let supersedes = snapshot
            .segments
            .iter()
            .filter(|(_, s)| !s.is_rejected())
            .map(|(_, s)| s.id())
            .collect::<Vec<_>>();
        if supersedes.is_empty() {
            return Ok(CompactResult {
                segment: None,
                records: 0,
                deleted: 0,
                deferred_deletes: Vec::new(),
            });
        }
        let id =
            self.publish_superseding(&retained.values().cloned().collect::<Vec<_>>(), &supersedes)?;
        // Release this process's maps before deleting; other readers retain their
        // immutable maps. Windows sharing failures are reported for the next pass.
        let old = snapshot
            .segments
            .iter()
            .map(|(path, s)| (path.clone(), s.id()))
            .collect::<Vec<_>>();
        drop(snapshot);
        let mut deleted = 0;
        let mut deferred_deletes = Vec::new();
        for (path, old_id) in old {
            if supersedes.contains(&old_id) && old_id != id {
                match fs::remove_file(&path) {
                    Ok(()) => deleted += 1,
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => (),
                    Err(_) => deferred_deletes.push(path),
                }
            }
        }
        Ok(CompactResult {
            segment: Some(id),
            records: retained.len(),
            deleted,
            deferred_deletes,
        })
    }
}
impl CacheSnapshot {
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
            let revised = self.record_rejected.load(Ordering::Acquire).then(|| {
                self.segments
                    .iter()
                    .filter(|(_, segment)| !segment.is_rejected())
                    .flat_map(|(_, segment)| segment.supersedes().iter().copied())
                    .collect::<BTreeSet<_>>()
            });
            let superseded = revised.as_ref().unwrap_or(&self.superseded);
            let mut retry = false;
            for &ordinal in self.index.get(&key)? {
                let (path, segment) = &self.segments[ordinal];
                if segment.is_rejected() || superseded.contains(&segment.id()) {
                    continue;
                }
                match segment.get(key, &validate) {
                    Ok(Some(view)) => return Some(view),
                    Ok(None) => (),
                    Err(error) => {
                        self.record_rejected.store(true, Ordering::Release);
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
