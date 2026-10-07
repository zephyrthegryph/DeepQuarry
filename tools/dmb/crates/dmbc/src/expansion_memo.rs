//! Client storage adapter. The preprocessor owns semantic read validation.
use dm_preprocess::regions::{ExpansionMemo, ExpansionRecord, EXPANSION_VERSION};
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, atomic::{AtomicU64, Ordering}};

pub struct DiskExpansionMemo {
    policy: u128,
    disk: dm_cache::CacheSnapshot,
    pending: Mutex<(usize, BTreeMap<dm_cache::RecordKey, dm_cache::Record>)>,
    pub candidates: AtomicU64,
    pub stored: AtomicU64,
    pub dropped: AtomicU64,
}

impl DiskExpansionMemo {
    pub fn new(policy: u128, disk: dm_cache::CacheSnapshot) -> Self {
        Self { policy, disk, pending: Mutex::new((0, BTreeMap::new())),
            candidates: AtomicU64::new(0), stored: AtomicU64::new(0), dropped: AtomicU64::new(0) }
    }
    fn key(&self, key: u128) -> dm_cache::RecordKey {
        let mut bytes = self.policy.to_le_bytes().to_vec(); bytes.extend_from_slice(&key.to_le_bytes());
        dm_cache::RecordKey { stage: 1, version: EXPANSION_VERSION,
            content: xxhash_rust::xxh3::xxh3_128(&bytes) }
    }
    pub fn take_pending(&self) -> Vec<dm_cache::Record> {
        let mut pending = self.pending.lock().unwrap_or_else(|e| e.into_inner());
        pending.0 = 0;
        std::mem::take(&mut pending.1).into_values().collect()
    }
}

impl ExpansionMemo for DiskExpansionMemo {
    fn candidates(&self, key: u128) -> Vec<Arc<ExpansionRecord>> {
        let record_key = self.key(key);
        let pending = self.pending.lock().unwrap_or_else(|e| e.into_inner()).1.get(&record_key)
            .map(|record| record.payload.clone());
        let decode = |bytes: &[u8]| -> Vec<Arc<ExpansionRecord>> {
            dm_cache::decode_variants(bytes).unwrap_or_default().into_iter()
                .filter_map(|bytes| ExpansionRecord::from_bytes(bytes).ok())
                .filter(|record| record.key() == key).map(Arc::new).collect()
        };
        let records = match pending {
            Some(bytes) => decode(&bytes),
            None => self.disk.get(record_key, |bytes, _| {
                for bytes in dm_cache::decode_variants(bytes)? {
                    ExpansionRecord::from_bytes(bytes).map_err(|error| error.to_string())?;
                }
                Ok(())
            }).map_or_else(Vec::new, |record| decode(record.payload)),
        };
        self.candidates.fetch_add(records.len() as u64, Ordering::Relaxed);
        records
    }
    fn insert(&self, record: Arc<ExpansionRecord>) {
        let Ok(bytes) = record.to_bytes() else { self.dropped.fetch_add(1, Ordering::Relaxed); return; };
        let key = self.key(record.key());
        let disk_variants = self.candidates(record.key()).into_iter()
            .filter_map(|record| record.to_bytes().ok()).collect::<Vec<_>>();
        let mut pending = self.pending.lock().unwrap_or_else(|e| e.into_inner());
        let mut variants = pending.1.get(&key)
            .and_then(|record| dm_cache::decode_variants(&record.payload).ok())
            .map(|values| values.into_iter().map(Vec::from).collect::<Vec<_>>()).unwrap_or(disk_variants);
        if !variants.contains(&bytes) { variants.push(bytes); }
        if variants.len() > 4 { variants.remove(0); }
        let Ok(bytes) = dm_cache::encode_variants(&variants) else { self.dropped.fetch_add(1, Ordering::Relaxed); return; };
        let previous = pending.1.get(&key).map_or(0, |value| value.payload.len());
        let total = pending.0.saturating_sub(previous).saturating_add(bytes.len());
        if bytes.len() > 16 * 1024 * 1024 || total > 64 * 1024 * 1024 {
            self.dropped.fetch_add(1, Ordering::Relaxed); return;
        }
        pending.0 = total;
        pending.1.insert(key, dm_cache::Record { key, symbols: Vec::new(), payload: bytes.into() });
        self.stored.fetch_add(1, Ordering::Relaxed);
    }
}
