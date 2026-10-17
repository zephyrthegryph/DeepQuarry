//! Size budget for the shared cache directory, by recency of use.
//!
//! Every compiler build writes new immutable segments (a cold build of the production tree publishes about 700 MB of
//! lowering records keyed by the compiler's identity), and nothing removed them until they were 14 days old: the shared
//! cache reached 107 GB in three days, and every request opens the index of every segment (about 2.4 GB of heap at
//! that size, plus the open time). A segment's modification time is therefore kept meaningful: a segment that served a
//! record is touched (at most once per interval, `touch_used_segments`), and `evict_to_budget` deletes the least recently
//! used segments until the directory fits a byte budget. Segments are disposable memos: an evicted record is recomputed
//! and republished by the next compile that needs it; nothing here changes what any compile produces.
use super::*;
use std::time::{Duration, SystemTime};

#[derive(Debug, Default)]
pub struct BudgetReport {
    pub total_before: u64,
    pub total_after: u64,
    pub leaves: usize,
    pub deleted: usize,
    pub deleted_bytes: u64,
    pub deferred: usize,
    pub protected: usize,
}

impl CacheSnapshot {
    /// Set the modification time of every segment that served a record to `now`, unless it was already touched within
    /// `interval`. Best effort: a segment that cannot be opened for writing (deleted, held) is skipped. Returns the number touched.
    pub fn touch_used_segments(&self, now: SystemTime, interval: Duration) -> usize {
        let used: Vec<usize> = self
            .used_segments
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .iter()
            .copied()
            .collect();
        let mut touched = 0;
        for ordinal in used {
            let Some((path, _)) = self.segments.get(ordinal) else { continue };
            let Ok(metadata) = fs::symlink_metadata(path) else { continue };
            if !metadata.is_file() {
                continue;
            }
            let recent = metadata
                .modified()
                .ok()
                .and_then(|modified| now.duration_since(modified).ok())
                .is_some_and(|age| age < interval);
            if recent {
                continue;
            }
            let opened = fs::OpenOptions::new().write(true).open(path);
            if opened.and_then(|file| file.set_modified(now)).is_ok() {
                touched += 1;
            }
        }
        touched
    }
}

impl Cache {
    /// Delete the least recently modified segment and group leaves until the directory holds at most `budget_bytes`.
    /// Leaves modified within `min_age` of `now` are never deleted (a build in progress is publishing them), and a leaf
    /// that cannot be deleted (a Windows sharing violation: some process maps it) is skipped and counted. Takes the
    /// maintenance lock without waiting; a compaction in progress yields `CacheError::Busy`.
    pub fn evict_to_budget(
        &self,
        now: SystemTime,
        budget_bytes: u64,
        min_age: Duration,
    ) -> Result<BudgetReport, CacheError> {
        let _lock = self.compact_lock(false)?;
        let mut leaves: Vec<(SystemTime, u64, PathBuf)> = Vec::new();
        for entry in fs::read_dir(&self.root)? {
            let entry = entry?;
            let path = entry.path();
            if !path.extension().is_some_and(|ext| ext == "seg" || ext == "grp") {
                continue;
            }
            let Ok(metadata) = fs::symlink_metadata(&path) else { continue };
            if !metadata.is_file() || lifecycle::reparse(&metadata) {
                continue;
            }
            let Ok(modified) = metadata.modified() else { continue };
            leaves.push((modified, metadata.len(), path));
        }
        let mut report = BudgetReport {
            total_before: leaves.iter().map(|(_, bytes, _)| *bytes).sum(),
            leaves: leaves.len(),
            ..BudgetReport::default()
        };
        report.total_after = report.total_before;
        if report.total_before <= budget_bytes {
            return Ok(report);
        }
        leaves.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.2.cmp(&b.2)));
        for (modified, bytes, path) in leaves {
            if report.total_after <= budget_bytes {
                break;
            }
            // A modification time in the future counts as fresh.
            if now.duration_since(modified).is_ok_and(|age| age < min_age) || modified > now {
                report.protected += 1;
                continue;
            }
            match fs::remove_file(&path) {
                Ok(()) => {
                    report.deleted += 1;
                    report.deleted_bytes += bytes;
                    report.total_after -= bytes;
                }
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => report.total_after -= bytes,
                Err(_) => report.deferred += 1,
            }
        }
        Ok(report)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Limits, Record, RecordKey};
    use std::sync::Arc;

    fn record(content: u128, size: usize) -> Record {
        Record { key: RecordKey { stage: 2, version: 1, content }, payload: Arc::from(vec![7u8; size]), symbols: vec![] }
    }
    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("dm-cache-budget-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        dir
    }
    fn set_age(path: &Path, now: SystemTime, age: Duration) {
        fs::OpenOptions::new().write(true).open(path).unwrap().set_modified(now - age).unwrap();
    }

    #[test]
    fn eviction_deletes_least_recently_modified_first_and_spares_fresh_leaves() {
        let dir = scratch("evict");
        let cache = Cache::open(&dir, Limits::default()).unwrap();
        let ids: Vec<u128> = (0..4).map(|n| cache.publish(&[record(n + 1, 10_000)]).unwrap()).collect();
        let path = |id: u128| dir.join(format!("{id:032x}.seg"));
        let now = SystemTime::now();
        // Oldest ids[2], then ids[0], then ids[3]; ids[1] is fresh.
        set_age(&path(ids[2]), now, Duration::from_secs(30 * 3600));
        set_age(&path(ids[0]), now, Duration::from_secs(20 * 3600));
        set_age(&path(ids[3]), now, Duration::from_secs(10 * 3600));
        set_age(&path(ids[1]), now, Duration::from_secs(60));
        let one = fs::metadata(path(ids[0])).unwrap().len();
        // Budget for two segments: the two oldest go.
        let report = cache.evict_to_budget(now, one * 2 + one / 2, Duration::from_secs(3600)).unwrap();
        assert_eq!((report.deleted, report.deferred), (2, 0), "{report:?}");
        assert!(!path(ids[2]).exists() && !path(ids[0]).exists());
        assert!(path(ids[3]).exists() && path(ids[1]).exists());
        // A budget of zero still never touches a leaf younger than min_age.
        let report = cache.evict_to_budget(now, 0, Duration::from_secs(3600)).unwrap();
        assert_eq!(report.deleted, 1);
        assert!(path(ids[1]).exists());
        assert_eq!(report.protected, 1);
        // Under budget: nothing happens.
        assert_eq!(cache.evict_to_budget(now, u64::MAX, Duration::ZERO).unwrap().deleted, 0);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_segment_that_served_a_record_is_touched_and_survives_the_next_eviction() {
        let dir = scratch("touch");
        let cache = Cache::open(&dir, Limits::default()).unwrap();
        let hot = cache.publish(&[record(1, 10_000)]).unwrap();
        let cold = cache.publish(&[record(2, 10_000)]).unwrap();
        let path = |id: u128| dir.join(format!("{id:032x}.seg"));
        let now = SystemTime::now();
        for id in [hot, cold] {
            set_age(&path(id), now, Duration::from_secs(40 * 3600));
        }
        let snapshot = cache.snapshot().unwrap();
        let key = RecordKey { stage: 2, version: 1, content: 1 };
        assert!(snapshot.get_candidate(key, |_, _| Ok(true)).is_some());
        assert_eq!(snapshot.touch_used_segments(now, Duration::from_secs(3600)), 1);
        // Touching again within the interval does nothing.
        assert_eq!(snapshot.touch_used_segments(now, Duration::from_secs(3600)), 0);
        drop(snapshot);
        let one = fs::metadata(path(hot)).unwrap().len();
        let report = cache.evict_to_budget(now, one + one / 2, Duration::from_secs(3600)).unwrap();
        assert_eq!(report.deleted, 1);
        assert!(path(hot).exists(), "the used segment must survive");
        assert!(!path(cold).exists());
        let _ = fs::remove_dir_all(&dir);
    }
}
