//! Bounded publication of newly captured records, shared by runner consumers.
pub(super) fn publish_cache_records(
    cache: &crate::runner_disk::LazyDisk,
    records: Vec<dm_cache::Record>,
) -> Result<std::collections::BTreeSet<dm_cache::RecordKey>, String> {
    if records.is_empty() {
        return Ok(std::collections::BTreeSet::new());
    }
    let mut sink = cache.writer()?.publish_sink(8 * 1024 * 1024);
    for record in records {
        sink.push(record)
            .map_err(|error| format!("cache population failed: {error}"))?;
    }
    match sink.finish() {
        Ok(report) => Ok(report.keys),
        Err(error) => Err(format!("cache population failed: {error}")),
    }
}
