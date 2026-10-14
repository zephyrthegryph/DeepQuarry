//! Stage queue draining into the sole request-owned cache spool.
pub(super) fn publish_cache_records(
    cache: &crate::runner_disk::LazyDisk,
    records: Vec<dm_cache::Record>,
) {
    if let Err(error) = cache.append_records(records) {
        crate::daemon_eprintln!("native cache staging skipped: {error}");
    }
}
