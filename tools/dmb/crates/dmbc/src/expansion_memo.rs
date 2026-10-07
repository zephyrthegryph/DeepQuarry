//! Client storage adapter. The preprocessor owns semantic read validation.
use dm_preprocess::regions::{
    DirectiveRecord, ExpansionMemo, ExpansionRecord, FragmentRecord, DIRECTIVE_VERSION,
    EXPANSION_VERSION, FRAGMENT_VERSION,
};
use std::collections::BTreeMap;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc, Mutex,
};

pub struct DiskExpansionMemo {
    policy: u128,
    disk: Arc<dm_cache::CacheSnapshot>,
    pending: Mutex<(usize, BTreeMap<dm_cache::RecordKey, dm_cache::Record>)>,
    insert_guard: Mutex<()>,
    publisher: Option<Arc<crate::lowering_memo::CachePublisher>>,
    publication_errors: Mutex<Vec<String>>,
    recent: Mutex<(usize, BTreeMap<dm_cache::RecordKey, dm_cache::Record>)>,
    pub published_records: AtomicU64,
    pub publication_failed: AtomicU64,
    pub publication_ns: AtomicU64,
    pub candidates: AtomicU64,
    pub stored: AtomicU64,
    pub dropped: AtomicU64,
}

impl DiskExpansionMemo {
    pub fn new(policy: u128, disk: impl Into<Arc<dm_cache::CacheSnapshot>>) -> Self {
        Self {
            policy,
            disk: disk.into(),
            insert_guard: Mutex::new(()),
            publisher: None,
            publication_errors: Mutex::new(Vec::new()),
            recent: Mutex::new((0, BTreeMap::new())),
            published_records: AtomicU64::new(0),
            publication_failed: AtomicU64::new(0),
            publication_ns: AtomicU64::new(0),
            pending: Mutex::new((0, BTreeMap::new())),
            candidates: AtomicU64::new(0),
            stored: AtomicU64::new(0),
            dropped: AtomicU64::new(0),
        }
    }
    /// Stream bounded batches. The callback runs outside all memo locks.
    pub fn with_publisher(mut self, publisher: Arc<crate::lowering_memo::CachePublisher>) -> Self {
        self.publisher = Some(publisher);
        self
    }
    fn record_error(&self, message: String) {
        self.publication_failed.fetch_add(1, Ordering::Relaxed);
        let mut errors = self
            .publication_errors
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        if errors.len() < 8 {
            errors.push(message.chars().take(512).collect());
        }
    }
    pub fn publication_errors(&self) -> Vec<String> {
        self.publication_errors
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
    }
    pub fn pending_bytes(&self) -> usize {
        self.pending.lock().unwrap_or_else(|e| e.into_inner()).0
    }
    fn recent_payload(&self, key: dm_cache::RecordKey) -> Option<Arc<[u8]>> {
        self.recent
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .1
            .get(&key)
            .map(|r| Arc::clone(&r.payload))
    }
    fn flush_if_needed(&self) {
        let records = {
            let mut pending = self.pending.lock().unwrap_or_else(|e| e.into_inner());
            if pending.0 < 8 * 1024 * 1024 {
                return;
            }
            pending.0 = 0;
            std::mem::take(&mut pending.1)
                .into_values()
                .collect::<Vec<_>>()
        };
        // This bounded lookback avoids rescanning every mapped segment after each
        // flush. Eviction can reduce retained variants, never semantic authority:
        // a parser-enriched insert contains its complete issued expansion receipt.
        {
            let mut recent = self.recent.lock().unwrap_or_else(|e| e.into_inner());
            for record in &records {
                let old = recent.1.remove(&record.key).map_or(0, |r| r.payload.len());
                recent.0 = recent.0.saturating_sub(old);
                if record.payload.len() <= 8 * 1024 * 1024 {
                    while recent.0 + record.payload.len() > 8 * 1024 * 1024 {
                        let Some((_, removed)) = recent.1.pop_first() else {
                            break;
                        };
                        recent.0 -= removed.payload.len();
                    }
                    recent.0 += record.payload.len();
                    recent.1.insert(record.key, record.clone());
                }
            }
        }
        let count = records.len() as u64;
        let started = std::time::Instant::now();
        let outcome = match &self.publisher {
            Some(publisher) => publisher(records),
            None => self
                .disk
                .publish(&records)
                .map(|_| ())
                .map_err(|error| error.to_string()),
        };
        match outcome {
            Ok(()) => {
                self.published_records.fetch_add(count, Ordering::Relaxed);
            }
            Err(error) => {
                self.publication_failed.fetch_add(count, Ordering::Relaxed);
                let mut errors = self
                    .publication_errors
                    .lock()
                    .unwrap_or_else(|e| e.into_inner());
                if errors.len() < 8 {
                    errors.push(error.chars().take(512).collect());
                }
            }
        }
        self.publication_ns.fetch_add(
            started.elapsed().as_nanos().min(u64::MAX as u128) as u64,
            Ordering::Relaxed,
        );
    }
    fn validated_variants<T>(
        &self,
        key: dm_cache::RecordKey,
        decode: impl Fn(&[u8]) -> Result<T, String>,
        retain_bytes: bool,
    ) -> Vec<(Vec<u8>, Arc<T>)> {
        let pending = self
            .pending
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .1
            .get(&key)
            .map(|record| Arc::clone(&record.payload));
        let load = |bytes: &[u8]| -> Result<Vec<(Vec<u8>, Arc<T>)>, String> {
            dm_cache::decode_variants(bytes)?
                .into_iter()
                .map(|bytes| {
                    decode(bytes).map(|record| {
                        (
                            if retain_bytes {
                                bytes.to_vec()
                            } else {
                                Vec::new()
                            },
                            Arc::new(record),
                        )
                    })
                })
                .collect()
        };
        if let Some(bytes) = pending.or_else(|| self.recent_payload(key)) {
            return load(&bytes).unwrap_or_default();
        }
        let result = std::cell::RefCell::new(Vec::new());
        let accepted = self
            .disk
            .get(key, |bytes, _| {
                // Validate the entire envelope before accepting any candidate. Keep
                // its decoded receipts rather than deserialize the accepted row twice.
                *result.borrow_mut() = load(bytes)?;
                Ok(())
            })
            .is_some();
        if accepted {
            result.into_inner()
        } else {
            Vec::new()
        }
    }
    fn key(&self, key: u128) -> dm_cache::RecordKey {
        let mut bytes = self.policy.to_le_bytes().to_vec();
        bytes.extend_from_slice(&key.to_le_bytes());
        dm_cache::RecordKey {
            stage: 1,
            version: EXPANSION_VERSION,
            content: xxhash_rust::xxh3::xxh3_128(&bytes),
        }
    }
    fn directive_key(&self, key: u128) -> dm_cache::RecordKey {
        let mut bytes = self.policy.to_le_bytes().to_vec();
        bytes.extend_from_slice(&key.to_le_bytes());
        dm_cache::RecordKey {
            stage: 4,
            version: DIRECTIVE_VERSION,
            content: xxhash_rust::xxh3::xxh3_128(&bytes),
        }
    }
    fn fragment_key(&self, key: u128) -> dm_cache::RecordKey {
        let mut bytes = self.policy.to_le_bytes().to_vec();
        bytes.extend_from_slice(&key.to_le_bytes());
        dm_cache::RecordKey {
            stage: 8,
            version: FRAGMENT_VERSION,
            content: xxhash_rust::xxh3::xxh3_128(&bytes),
        }
    }
    pub fn take_pending(&self) -> Vec<dm_cache::Record> {
        let mut pending = self.pending.lock().unwrap_or_else(|e| e.into_inner());
        pending.0 = 0;
        std::mem::take(&mut pending.1).into_values().collect()
    }
}

impl ExpansionMemo for DiskExpansionMemo {
    fn directive_candidates(&self, key: u128) -> Vec<Arc<DirectiveRecord>> {
        self.validated_variants(self.directive_key(key), DirectiveRecord::from_bytes, false)
            .into_iter()
            .filter(|(_, record)| record.key() == key)
            .map(|(_, record)| record)
            .collect()
    }
    fn insert_directive(&self, record: Arc<DirectiveRecord>) {
        let bytes = match record.to_bytes() {
            Ok(bytes) => bytes,
            Err(error) => {
                self.record_error(format!("cache record encoding failed: {error}"));
                return;
            }
        };
        let key = self.directive_key(record.key());
        let insert_guard = self.insert_guard.lock().unwrap_or_else(|e| e.into_inner());
        let previous_variants = self.validated_variants(key, DirectiveRecord::from_bytes, true);
        let mut variants = previous_variants
            .into_iter()
            .filter(|(_, previous)| previous.key() == record.key() && !previous.same_plan(&record))
            .map(|(bytes, _)| bytes)
            .collect::<Vec<_>>();
        let mut pending = self.pending.lock().unwrap_or_else(|e| e.into_inner());
        variants.push(bytes);
        if variants.len() > 4 {
            variants.remove(0);
        }
        let bytes = match dm_cache::encode_variants(&variants) {
            Ok(bytes) => bytes,
            Err(error) => {
                self.record_error(format!("cache variant encoding failed: {error}"));
                return;
            }
        };
        let previous = pending.1.get(&key).map_or(0, |value| value.payload.len());
        let total = pending
            .0
            .saturating_sub(previous)
            .saturating_add(bytes.len());
        pending.0 = total;
        pending.1.insert(
            key,
            dm_cache::Record {
                key,
                symbols: Vec::new(),
                payload: bytes.into(),
            },
        );
        self.stored.fetch_add(1, Ordering::Relaxed);
        drop(pending);
        drop(insert_guard);
        self.flush_if_needed();
    }
    fn fragment_candidates(&self, key: u128) -> Vec<Arc<FragmentRecord>> {
        self.validated_variants(self.fragment_key(key), FragmentRecord::from_bytes, false)
            .into_iter()
            .filter(|(_, record)| record.key() == key)
            .map(|(_, record)| record)
            .collect()
    }
    fn insert_fragment(&self, record: Arc<FragmentRecord>) {
        let bytes = match record.to_bytes() {
            Ok(bytes) => bytes,
            Err(error) => {
                self.record_error(format!("cache record encoding failed: {error}"));
                return;
            }
        };
        let key = self.fragment_key(record.key());
        let insert_guard = self.insert_guard.lock().unwrap_or_else(|e| e.into_inner());
        let previous_variants = self.validated_variants(key, FragmentRecord::from_bytes, true);
        let mut variants = previous_variants
            .into_iter()
            .filter(|(_, previous)| {
                previous.key() == record.key() && previous.as_ref() != record.as_ref()
            })
            .map(|(bytes, _)| bytes)
            .collect::<Vec<_>>();
        let mut pending = self.pending.lock().unwrap_or_else(|e| e.into_inner());
        variants.push(bytes);
        if variants.len() > 4 {
            variants.remove(0);
        }
        let bytes = match dm_cache::encode_variants(&variants) {
            Ok(bytes) => bytes,
            Err(error) => {
                self.record_error(format!("cache variant encoding failed: {error}"));
                return;
            }
        };
        let previous = pending.1.get(&key).map_or(0, |value| value.payload.len());
        let total = pending
            .0
            .saturating_sub(previous)
            .saturating_add(bytes.len());
        pending.0 = total;
        pending.1.insert(
            key,
            dm_cache::Record {
                key,
                symbols: Vec::new(),
                payload: bytes.into(),
            },
        );
        self.stored.fetch_add(1, Ordering::Relaxed);
        drop(pending);
        drop(insert_guard);
        self.flush_if_needed();
    }
    fn candidates(&self, key: u128) -> Vec<Arc<ExpansionRecord>> {
        let records: Vec<_> = self
            .validated_variants(self.key(key), ExpansionRecord::from_bytes, false)
            .into_iter()
            .filter(|(_, record)| record.key() == key)
            .map(|(_, record)| record)
            .collect();
        self.candidates
            .fetch_add(records.len() as u64, Ordering::Relaxed);
        records
    }
    fn insert(&self, record: Arc<ExpansionRecord>) {
        let bytes = match record.to_bytes() {
            Ok(bytes) => bytes,
            Err(error) => {
                self.record_error(format!("cache record encoding failed: {error}"));
                return;
            }
        };
        let key = self.key(record.key());
        let insert_guard = self.insert_guard.lock().unwrap_or_else(|e| e.into_inner());
        let previous_variants = self.validated_variants(key, ExpansionRecord::from_bytes, true);
        let mut variants = previous_variants
            .into_iter()
            .filter(|(_, previous)| {
                previous.key() == record.key() && !previous.same_expansion(&record)
            })
            .map(|(bytes, _)| bytes)
            .collect::<Vec<_>>();
        let mut pending = self.pending.lock().unwrap_or_else(|e| e.into_inner());
        variants.push(bytes);
        if variants.len() > 4 {
            variants.remove(0);
        }
        let bytes = match dm_cache::encode_variants(&variants) {
            Ok(bytes) => bytes,
            Err(error) => {
                self.record_error(format!("cache variant encoding failed: {error}"));
                return;
            }
        };
        let previous = pending.1.get(&key).map_or(0, |value| value.payload.len());
        let total = pending
            .0
            .saturating_sub(previous)
            .saturating_add(bytes.len());
        pending.0 = total;
        pending.1.insert(
            key,
            dm_cache::Record {
                key,
                symbols: Vec::new(),
                payload: bytes.into(),
            },
        );
        self.stored.fetch_add(1, Ordering::Relaxed);
        drop(pending);
        drop(insert_guard);
        self.flush_if_needed();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn memo(name: &str) -> DiskExpansionMemo {
        let path =
            std::env::temp_dir().join(format!("expansion-stream-{}-{name}", std::process::id()));
        let cache = dm_cache::Cache::open(path, dm_cache::Limits::default()).unwrap();
        DiskExpansionMemo::new(1, cache.snapshot().unwrap())
    }
    fn fill(memo: &DiskExpansionMemo) {
        let key = memo.key(9);
        let bytes: Arc<[u8]> = vec![7; 8 * 1024 * 1024].into();
        let mut pending = memo.pending.lock().unwrap();
        pending.0 = bytes.len();
        pending.1.insert(
            key,
            dm_cache::Record {
                key,
                symbols: Vec::new(),
                payload: bytes,
            },
        );
    }
    #[test]
    fn expansion_stream_flushes_outside_lock_and_retains_bounded_lookback() {
        let seen = Arc::new(AtomicU64::new(0));
        let captured = Arc::clone(&seen);
        let memo = memo("success").with_publisher(Arc::new(move |records| {
            captured.fetch_add(records.len() as u64, Ordering::Relaxed);
            Ok(())
        }));
        fill(&memo);
        memo.flush_if_needed();
        assert_eq!(memo.pending_bytes(), 0);
        assert_eq!(memo.published_records.load(Ordering::Relaxed), 1);
        assert_eq!(seen.load(Ordering::Relaxed), 1);
        assert!(memo.recent_payload(memo.key(9)).is_some());
        assert!(memo.publication_errors().is_empty());
    }
    #[test]
    fn expansion_stream_publication_failure_is_reported() {
        let memo = memo("failure").with_publisher(Arc::new(|_| Err("injected failure".into())));
        fill(&memo);
        memo.flush_if_needed();
        assert_eq!(memo.publication_failed.load(Ordering::Relaxed), 1);
        assert_eq!(memo.publication_errors(), vec!["injected failure"]);
        assert_eq!(memo.published_records.load(Ordering::Relaxed), 0);
    }
}
