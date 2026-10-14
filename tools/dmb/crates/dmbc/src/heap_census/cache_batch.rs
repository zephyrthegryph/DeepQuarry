//! Explicit active-spool census. Temporary file bytes are disk storage, not heap.
use super::*;
impl HeapCensus {
    pub fn cache_batch(&mut self, disk: &crate::runner_disk::LazyDisk) {
        disk.visit_batch_storage(|view| match view {
            dm_cache::BatchStorageView::Index { records, symbols } => {
                self.observe_items("cache_batch.record_index", records);
                self.observe_items("cache_batch.symbol_index", symbols);
                if records != 0 || symbols != 0 {
                    self.unknown("cache_batch.index", "record/symbol BTree entries are logical counts; private node/control backing is not exposed");
                }
            }
            dm_cache::BatchStorageView::Buffer { pointer, len_bytes, capacity_bytes } => {
                self.buffer("cache_batch.descriptors", pointer, len_bytes, capacity_bytes);
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn explicit_spool_census_counts_descriptors_without_opening_a_snapshot() {
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root = PathBuf::from("E:/dq-cache/dmb-protocol-checks")
            .join(format!("spool-census-{}-{stamp}", std::process::id()));
        let disk = crate::runner_disk::LazyDisk::new(root.clone());
        let attempt = disk.batch_attempt();
        let record = dm_cache::Record {
            key: dm_cache::RecordKey {
                stage: 2,
                version: 1,
                content: 1,
            },
            symbols: vec![],
            payload: Arc::from(b"bytes live in file".as_slice()),
        };
        disk.append_records(vec![record]).unwrap();
        let mut census = HeapCensus::new("cache_batch");
        census.cache_batch(&disk);
        let first = census.finish();
        assert!(first
            .owners
            .iter()
            .any(|owner| owner.owner == "cache_batch.descriptors"
                && owner.unique_known_capacity_bytes > 0));
        assert!(first
            .owners
            .iter()
            .any(|owner| owner.owner == "cache_batch.index" && !owner.unknown.is_empty()));
        assert!(disk.loaded_snapshot().is_none());
        drop(attempt);
        let mut census = HeapCensus::new("cache_batch_aborted");
        census.cache_batch(&disk);
        assert_eq!(census.finish().unique_known_capacity_bytes, 0);
        drop(disk);
        let _ = std::fs::remove_dir_all(root);
    }
}
