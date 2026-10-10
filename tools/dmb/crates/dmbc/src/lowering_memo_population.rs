//! Shared request-owned pending staging used by rich and frozen completion records.
use super::*;
#[derive(Clone)]
pub(crate) struct DiskWriter {
    disk: Option<Arc<crate::runner_disk::LazyDisk>>,
    pending: Arc<Mutex<Pending>>,
    counts: Arc<MemoCounts>,
    limits: MemoLimits,
    publisher: Option<Arc<CachePublisher>>,
    staging_errors: Arc<Mutex<Vec<String>>>,
}
impl DiskWriter {
    pub(super) fn from_memo(memo: &ProcedureMemo) -> Self {
        Self {
            disk: memo.disk.clone(),
            pending: Arc::clone(&memo.pending),
            counts: Arc::clone(&memo.counts),
            limits: memo.limits,
            publisher: memo.publisher.clone(),
            staging_errors: Arc::clone(&memo.staging_errors),
        }
    }
    pub(crate) fn queue_compact(
        &self,
        key: &[u8],
        reads: &dm_session::Receipt<dm_ir::ResolveQuery, dm_ir::ResolvedMeaning, dm_ir::ReadDomain>,
        versions: &[(ReadDomain, u128)],
        value: &crate::symbolic::PreparedContribution,
        debug: &[usize],
    ) {
        let start = std::time::Instant::now();
        let payload =
            crate::lowering_memo_compact::encode(key, reads.iter(), versions, value, debug);
        self.counts.encode_ns.fetch_add(
            start.elapsed().as_nanos().min(u64::MAX as u128) as u64,
            Ordering::Relaxed,
        );
        if let Some(payload) = payload {
            self.queue_payload(key, payload);
            self.counts
                .compact_disk_encoded
                .fetch_add(1, Ordering::Relaxed);
        } else {
            self.counts
                .compact_fallback_encoding
                .fetch_add(1, Ordering::Relaxed);
        }
    }
    pub(super) fn wire_error(&self, message: &str) {
        self.counts.unsupported_disk.fetch_add(1, Ordering::Relaxed);
        self.counts.staging_failed.fetch_add(1, Ordering::Relaxed);
        let mut errors = self
            .staging_errors
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        if errors.len() < 8 {
            errors.push(message.to_owned());
        }
    }
    pub(super) fn publish(&self, records: Vec<dm_cache::Record>) {
        let _profile = dm_profile::stage("lowering.population_flush");
        let count = records.len();
        let start = std::time::Instant::now();
        let outcome = match &self.publisher {
            Some(publisher) => publisher(records),
            None => self
                .disk
                .as_ref()
                .ok_or_else(|| "cache staging has no captured writer".to_owned())
                .and_then(|disk| {
                    disk.append_records(records)
                        .map(|_| ())
                        .map_err(|error| error.to_string())
                }),
        };
        match outcome {
            Ok(()) => {
                self.counts
                    .staged_records
                    .fetch_add(count as u64, Ordering::Relaxed);
            }
            Err(message) => {
                self.counts
                    .staging_failed
                    .fetch_add(count as u64, Ordering::Relaxed);
                let mut errors = self
                    .staging_errors
                    .lock()
                    .unwrap_or_else(|error| error.into_inner());
                if errors.len() < 8 {
                    errors.push(message.chars().take(512).collect());
                }
            }
        }
        self.counts.staging_ns.fetch_add(
            start.elapsed().as_nanos().min(u64::MAX as u128) as u64,
            Ordering::Relaxed,
        );
    }
    pub(super) fn queue_payload(&self, key: &[u8], payload: Vec<u8>) {
        let record_key = ProcedureMemo::record_key(key);
        let bytes = match dm_cache::encode_variants(&[payload]) {
            Ok(bytes) => bytes,
            Err(error) => {
                self.wire_error(&format!("cache variant encoding failed: {error}"));
                return;
            }
        };
        let ready = {
            let _profile = dm_profile::item("lowering.population_queue");
            self.pending
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .push(
                    dm_cache::Record {
                        key: record_key,
                        symbols: Vec::new(),
                        payload: bytes.into(),
                    },
                    self.limits.pending_bytes.clamp(1, 8 * 1024 * 1024) as u64,
                )
        };
        match ready {
            Ok(batches) => {
                for records in batches {
                    self.publish(records);
                }
            }
            Err(error) => self.wire_error(&format!("cache record staging failed: {error}")),
        }
    }
}
