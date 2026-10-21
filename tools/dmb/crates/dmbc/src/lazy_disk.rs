//! Request-local disk access. Resident acceptance does not open or scan the cache.
#[path = "lazy_disk_batch.rs"]
mod batch;
use std::{
    path::PathBuf,
    sync::{Arc, Mutex, OnceLock},
};

pub struct LazyDisk {
    root: Option<PathBuf>,
    batch: Mutex<batch::State>,
    writer: OnceLock<Result<Arc<dm_cache::Cache>, String>>,
    snapshot: OnceLock<Option<Arc<dm_cache::CacheSnapshot>>>,
}
/// A segment that served a record is touched (at most hourly) when the request that used it ends, so the cache directory's
/// modification times mean "last used" and the daemon's size budget (`daemon::cache_gc`) evicts what nothing has used lately.
const TOUCH_INTERVAL: std::time::Duration = std::time::Duration::from_secs(3600);
impl Drop for LazyDisk {
    fn drop(&mut self) {
        if let Some(Some(snapshot)) = self.snapshot.get() {
            snapshot.touch_used_segments(std::time::SystemTime::now(), TOUCH_INTERVAL);
        }
    }
}
impl LazyDisk {
    #[cfg(test)]
    pub(crate) fn is_opened(&self) -> bool {
        self.writer.get().is_some()
    }
    pub fn new(root: PathBuf) -> Self {
        Self {
            root: Some(root),
            batch: Mutex::new(batch::State::Dormant),
            writer: OnceLock::new(),
            snapshot: OnceLock::new(),
        }
    }
    pub fn from_snapshot(snapshot: Arc<dm_cache::CacheSnapshot>) -> Self {
        Self {
            root: None,
            batch: Mutex::new(batch::State::Dormant),
            writer: OnceLock::new(),
            snapshot: OnceLock::from(Some(snapshot)),
        }
    }
    pub fn writer(&self) -> Result<&Arc<dm_cache::Cache>, &str> {
        self.writer
            .get_or_init(|| {
                let root = self
                    .root
                    .as_ref()
                    .ok_or("captured snapshot has no independent writer")?;
                dm_cache::Cache::open(root.clone(), dm_cache::Limits::default())
                    .map(Arc::new)
                    .map_err(|error| error.to_string())
            })
            .as_ref()
            .map_err(String::as_str)
    }
    pub fn snapshot(&self) -> Option<&Arc<dm_cache::CacheSnapshot>> {
        self.snapshot
            .get_or_init(|| {
                let result = self
                    .writer()
                    .map_err(str::to_owned)
                    .and_then(|cache| cache.snapshot().map_err(|error| error.to_string()));
                match result {
                    Ok(snapshot) => Some(Arc::new(snapshot)),
                    Err(error) => {
                        crate::daemon_eprintln!(
                            "native cache unavailable: {error}; compiling fresh"
                        );
                        None
                    }
                }
            })
            .as_ref()
    }
    /// Observing used keys must never trigger a scan on a resident-only request.
    pub fn loaded_snapshot(&self) -> Option<&Arc<dm_cache::CacheSnapshot>> {
        self.snapshot.get().and_then(Option::as_ref)
    }
    pub fn publish(&self, records: &[dm_cache::Record]) -> Result<u128, dm_cache::CacheError> {
        if self.root.is_none() {
            return self
                .loaded_snapshot()
                .expect("captured snapshot")
                .publish(records);
        }
        self.writer()
            .map_err(|error| dm_cache::CacheError::Invalid(error.into()))?
            .publish(records)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Temporary(PathBuf);
    impl Temporary {
        fn new() -> Self {
            let unique = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            Self(
                crate::test_scratch::root()
                    .join(format!("lazy-disk-{}-{unique}", std::process::id())),
            )
        }
    }
    impl Drop for Temporary {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }
    #[test]
    fn unopened_handle_and_writer_only_append_do_not_scan() {
        let directory = Temporary::new();
        let disk = LazyDisk::new(directory.0.clone());
        assert!(!disk.is_opened());
        assert!(!directory.0.exists());
        assert!(disk.loaded_snapshot().is_none());
        let record = dm_cache::Record {
            key: dm_cache::RecordKey {
                stage: 1,
                version: 1,
                content: 7,
            },
            symbols: Vec::new(),
            payload: Arc::from(&b"computed"[..]),
        };
        disk.publish(&[record.clone()]).unwrap();
        assert!(disk.is_opened());
        assert!(disk.loaded_snapshot().is_none());
        let first = disk.snapshot().unwrap();
        let second = disk.snapshot().unwrap();
        assert!(Arc::ptr_eq(first, second));
        assert_eq!(
            first.get(record.key, |_, _| Ok(())).unwrap().payload,
            record.payload.as_ref()
        );
    }
    #[test]
    fn failed_open_is_attempted_once_and_next_request_can_retry() {
        let directory = Temporary::new();
        std::fs::create_dir_all(&directory.0).unwrap();
        let root = directory.0.join("cache");
        std::fs::write(&root, b"not a directory").unwrap();
        let disk = LazyDisk::new(root.clone());
        assert!(disk.snapshot().is_none());
        std::fs::remove_file(&root).unwrap();
        assert!(disk.snapshot().is_none());
        assert!(!root.exists());
        assert!(LazyDisk::new(root).snapshot().is_some());
    }
}
