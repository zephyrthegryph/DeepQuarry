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
    disk: Arc<crate::runner_disk::LazyDisk>,
    pending: Mutex<dm_cache::PendingRecords>,
    read_only_disk: bool,
    publisher: Option<Arc<crate::lowering_memo::CachePublisher>>,
    publication_errors: Mutex<Vec<String>>,
    recent: Mutex<(usize, BTreeMap<dm_cache::RecordKey, Vec<dm_cache::Record>>)>,
    pub published_records: AtomicU64,
    pub publication_failed: AtomicU64,
    pub publication_ns: AtomicU64,
    pub candidates: AtomicU64,
    pub stored: AtomicU64,
    pub dropped: AtomicU64,
}

impl DiskExpansionMemo {
    pub fn new(policy: u128, disk: impl Into<Arc<dm_cache::CacheSnapshot>>) -> Self {
        Self::with_lazy_disk(
            policy,
            Arc::new(crate::runner_disk::LazyDisk::from_snapshot(disk.into())),
        )
    }
    pub fn with_lazy_disk(policy: u128, disk: Arc<crate::runner_disk::LazyDisk>) -> Self {
        Self {
            policy,
            disk,
            read_only_disk: false,
            publisher: None,
            publication_errors: Mutex::new(Vec::new()),
            recent: Mutex::new((0, BTreeMap::new())),
            published_records: AtomicU64::new(0),
            publication_failed: AtomicU64::new(0),
            publication_ns: AtomicU64::new(0),
            pending: Mutex::new(dm_cache::PendingRecords::default()),
            candidates: AtomicU64::new(0),
            stored: AtomicU64::new(0),
            dropped: AtomicU64::new(0),
        }
    }
    /// Stream bounded batches. The callback runs outside all memo locks.
    /// Hydrate existing records without encoding/populating this disk store.
    pub fn with_read_only_disk(mut self) -> Self {
        self.read_only_disk = true;
        self
    }
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
        self.pending
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .bytes()
            .min(usize::MAX as u64) as usize
    }
    fn recent_payloads(&self, key: dm_cache::RecordKey) -> Vec<Arc<[u8]>> {
        self.recent
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .1
            .get(&key)
            .into_iter()
            .flatten()
            .map(|r| Arc::clone(&r.payload))
            .collect()
    }
    fn publish_records(&self, records: Vec<dm_cache::Record>) {
        if records.is_empty() {
            return;
        }
        // Retain all contexts within the byte-bounded request lookback, so
        // the immutable initial snapshot need not be rescanned after a flush.
        {
            let mut recent = self.recent.lock().unwrap_or_else(|e| e.into_inner());
            for record in &records {
                let size = record.payload.len();
                if size > 8 * 1024 * 1024
                    || recent
                        .1
                        .get(&record.key)
                        .is_some_and(|rows| rows.iter().any(|row| row == record))
                {
                    continue;
                }
                while recent.0 + size > 8 * 1024 * 1024 {
                    let Some((_, removed)) = recent.1.pop_first() else {
                        break;
                    };
                    recent.0 -= removed.iter().map(|row| row.payload.len()).sum::<usize>();
                }
                recent.0 += size;
                recent.1.entry(record.key).or_default().push(record.clone());
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
    fn queue_record(&self, key: dm_cache::RecordKey, bytes: Vec<u8>) {
        let payload = match dm_cache::encode_variants(&[bytes]) {
            Ok(payload) => payload,
            Err(error) => {
                self.record_error(format!("cache variant encoding failed: {error}"));
                return;
            }
        };
        let batches = self.pending.lock().unwrap_or_else(|e| e.into_inner()).push(
            dm_cache::Record {
                key,
                symbols: Vec::new(),
                payload: payload.into(),
            },
            8 * 1024 * 1024,
        );
        match batches {
            Ok(batches) => {
                self.stored.fetch_add(1, Ordering::Relaxed);
                for batch in batches {
                    self.publish_records(batch);
                }
            }
            Err(error) => self.record_error(format!("cache staging failed: {error}")),
        }
    }
    fn validated_variants<T>(
        &self,
        key: dm_cache::RecordKey,
        decode: impl Fn(&[u8]) -> Result<T, String>,
    ) -> Vec<Arc<T>> {
        let pending = self
            .pending
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get(&key)
            .map(|record| Arc::clone(&record.payload));
        let mut local = self.recent_payloads(key);
        if let Some(bytes) = pending {
            if !local.iter().any(|old| old.as_ref() == bytes.as_ref()) {
                local.push(bytes);
            }
        }
        let load = |bytes: &[u8]| -> Result<Vec<Arc<T>>, String> {
            // Validate the complete envelope before exposing a candidate.
            dm_cache::decode_variants(bytes)?
                .into_iter()
                .map(|bytes| decode(bytes).map(Arc::new))
                .collect()
        };
        let mut records = Vec::new();
        for bytes in &local {
            records.extend(load(bytes).unwrap_or_default());
        }
        if let Some(disk) = self.disk.snapshot() {
            let decoded = std::cell::RefCell::new(BTreeMap::new());
            let views = disk.validated_candidates(key, |bytes, _| {
                let values = load(bytes)?;
                decoded
                    .borrow_mut()
                    .insert((bytes.as_ptr() as usize, bytes.len()), values);
                Ok(())
            });
            for view in views {
                if !local.iter().any(|old| old.as_ref() == view.payload) {
                    if let Some(values) = decoded
                        .borrow_mut()
                        .remove(&(view.payload.as_ptr() as usize, view.payload.len()))
                    {
                        records.extend(values);
                    }
                }
            }
            if !records.is_empty() {
                // ExpansionMemo exposes candidate pools; semantic admission is
                // performed by the preprocessor. Lease this pool conservatively.
                let _ = disk.get(key, |_, _| Ok(()));
            }
        }
        records
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
        self.pending
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take()
    }
    #[cfg(test)]
    fn flush_pending(&self) {
        self.publish_records(self.take_pending());
    }
}

impl ExpansionMemo for DiskExpansionMemo {
    fn directive_candidates(&self, key: u128) -> Vec<Arc<DirectiveRecord>> {
        self.validated_variants(self.directive_key(key), DirectiveRecord::from_bytes)
            .into_iter()
            .filter(|record| record.key() == key)
            .collect()
    }
    fn insert_directive(&self, record: Arc<DirectiveRecord>) {
        if self.read_only_disk {
            return;
        }
        let bytes = match record.to_bytes() {
            Ok(bytes) => bytes,
            Err(error) => {
                self.record_error(format!("cache record encoding failed: {error}"));
                return;
            }
        };
        self.queue_record(self.directive_key(record.key()), bytes);
    }
    fn fragment_candidates(&self, key: u128) -> Vec<Arc<FragmentRecord>> {
        self.validated_variants(self.fragment_key(key), FragmentRecord::from_bytes)
            .into_iter()
            .filter(|record| record.key() == key)
            .collect()
    }
    fn insert_fragment(&self, record: Arc<FragmentRecord>) {
        if self.read_only_disk {
            return;
        }
        let bytes = match record.to_bytes() {
            Ok(bytes) => bytes,
            Err(error) => {
                self.record_error(format!("cache record encoding failed: {error}"));
                return;
            }
        };
        self.queue_record(self.fragment_key(record.key()), bytes);
    }
    fn candidates(&self, key: u128) -> Vec<Arc<ExpansionRecord>> {
        let mut records: Vec<_> = self
            .validated_variants(self.key(key), ExpansionRecord::from_bytes)
            .into_iter()
            .filter(|record| record.key() == key)
            .collect();
        // Prefer enriched sidecars without replacing their expansion authority.
        // The parser still validates schema, span and payload on every admission.
        records.sort_by_key(|record| std::cmp::Reverse(record.fragment_count()));
        self.candidates
            .fetch_add(records.len() as u64, Ordering::Relaxed);
        records
    }
    fn insert(&self, record: Arc<ExpansionRecord>) {
        if self.read_only_disk {
            return;
        }
        let bytes = match record.to_bytes() {
            Ok(bytes) => bytes,
            Err(error) => {
                self.record_error(format!("cache record encoding failed: {error}"));
                return;
            }
        };
        self.queue_record(self.key(record.key()), bytes);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Temporary(std::path::PathBuf);
    impl Temporary {
        fn new(name: &str) -> Self {
            let base = if cfg!(windows) {
                std::path::PathBuf::from("E:/dq-cache/dmb-protocol-checks")
            } else {
                std::env::temp_dir()
            };
            Self(base.join(format!(
                    "expansion-{}-{name}-{}",
                    std::process::id(),
                    std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap()
                        .as_nanos()
                )))
        }
    }
    impl Drop for Temporary {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }
    struct TestMemo {
        memo: Option<DiskExpansionMemo>,
        _directory: Temporary,
    }
    impl std::ops::Deref for TestMemo {
        type Target = DiskExpansionMemo;
        fn deref(&self) -> &Self::Target {
            self.memo.as_ref().unwrap()
        }
    }
    impl TestMemo {
        fn with_publisher(mut self, publisher: Arc<crate::lowering_memo::CachePublisher>) -> Self {
            self.memo = self.memo.take().map(|memo| memo.with_publisher(publisher));
            self
        }
    }
    impl Drop for TestMemo {
        fn drop(&mut self) {
            drop(self.memo.take());
        }
    }
    fn memo(name: &str) -> TestMemo {
        let directory = Temporary::new(name);
        let cache = dm_cache::Cache::open(&directory.0, dm_cache::Limits::default()).unwrap();
        TestMemo {
            memo: Some(DiskExpansionMemo::new(1, cache.snapshot().unwrap())),
            _directory: directory,
        }
    }
    fn fill(memo: &DiskExpansionMemo) {
        let key = memo.key(9);
        let ready = memo
            .pending
            .lock()
            .unwrap()
            .push(
                dm_cache::Record {
                    key,
                    symbols: Vec::new(),
                    payload: vec![7; 8 * 1024 * 1024].into(),
                },
                16 * 1024 * 1024,
            )
            .unwrap();
        assert!(ready.is_empty());
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
        memo.flush_pending();
        assert_eq!(memo.pending_bytes(), 0);
        assert_eq!(memo.published_records.load(Ordering::Relaxed), 1);
        assert_eq!(seen.load(Ordering::Relaxed), 1);
        assert!(!memo.recent_payloads(memo.key(9)).is_empty());
        assert!(memo.publication_errors().is_empty());
    }
    #[test]
    fn read_only_disk_hydrates_resident_without_population_and_preserves_normal_writer() {
        struct Source;
        impl dm_preprocess::SourceProvider for Source {
            fn read(&self, _: &std::path::Path) -> Result<String, String> {
                Ok("/proc/probe()\n    return 3\n".into())
            }
        }
        let directory = Temporary::new("readonly");
        let cache = dm_cache::Cache::open(&directory.0, dm_cache::Limits::default()).unwrap();
        let writer = DiskExpansionMemo::new(1, cache.snapshot().unwrap());
        let plan = dm_preprocess::regions::plan_regions(
            std::path::Path::new("project.dme"),
            &Source,
            &BTreeMap::new(),
        );
        let seeded = dm_preprocess::regions::expand_regions_text_with_memo(&plan, 1, &writer);
        assert!(seeded.diagnostics.is_empty());
        assert!(!writer.pending.lock().unwrap().is_empty());
        // Force the ordinary bounded flush; its existing snapshot fallback writes.
        writer.flush_pending();
        assert!(writer.published_records.load(Ordering::Relaxed) > 0);
        let reader = DiskExpansionMemo::new(1, cache.snapshot().unwrap()).with_read_only_disk();
        let host = crate::runner_host::BuildHost::default();
        let view = host.expansion_memo(Some(&reader)).unwrap();
        let first = dm_preprocess::regions::expand_regions_text_with_memo(&plan, 1, &view);
        let second = dm_preprocess::regions::expand_regions_text_with_memo(&plan, 1, &view);
        assert_eq!(first.text.as_ref(), seeded.text.as_ref());
        assert!(Arc::ptr_eq(
            first.receipts[0].record(),
            second.receipts[0].record()
        ));
        reader.insert(Arc::clone(first.receipts[0].record()));
        assert!(reader.take_pending().is_empty());
        assert_eq!(reader.stored.load(Ordering::Relaxed), 0);
        assert_eq!(reader.published_records.load(Ordering::Relaxed), 0);
        assert!(reader.publication_errors().is_empty());
    }
    #[test]
    fn expansion_stream_publication_failure_is_reported() {
        let memo = memo("failure").with_publisher(Arc::new(|_| Err("injected failure".into())));
        fill(&memo);
        memo.flush_pending();
        assert_eq!(memo.publication_failed.load(Ordering::Relaxed), 1);
        assert_eq!(memo.publication_errors(), vec!["injected failure"]);
        assert_eq!(memo.published_records.load(Ordering::Relaxed), 0);
    }
    #[test]
    fn singleton_publication_preserves_six_macro_contexts_and_parser_enrichment() {
        struct Source(u8);
        impl dm_preprocess::SourceProvider for Source {
            fn read(&self, path: &std::path::Path) -> Result<String, String> {
                if path.extension().is_some_and(|ext| ext == "dme") {
                    Ok(format!("#define VALUE {}\n#include \"leaf.dm\"\n", self.0))
                } else {
                    Ok("/proc/probe()\n    return VALUE\n".into())
                }
            }
        }
        let directory = Temporary::new("six-contexts");
        let cache = dm_cache::Cache::open(&directory.0, dm_cache::Limits::default()).unwrap();
        let writer = DiskExpansionMemo::new(1, cache.snapshot().unwrap());
        let mut leaf_key = None;
        for value in 0..6 {
            let plan = dm_preprocess::regions::plan_regions(
                std::path::Path::new("project.dme"),
                &Source(value),
                &BTreeMap::new(),
            );
            let output = dm_preprocess::regions::expand_regions_text_with_memo(&plan, 1, &writer);
            assert!(output.diagnostics.is_empty());
            let record = output
                .receipts
                .iter()
                .find(|receipt| receipt.record().text().contains("/proc/probe"))
                .unwrap()
                .record();
            assert_eq!(*leaf_key.get_or_insert(record.key()), record.key());
            if value == 5 {
                let enriched = record
                    .with_fragment(
                        91,
                        dm_syntax::Span::new(0, 1),
                        Arc::from(&b"parser hint"[..]),
                    )
                    .unwrap();
                writer.insert(Arc::new(enriched));
            }
        }
        writer.flush_pending();
        let reader = DiskExpansionMemo::new(1, cache.snapshot().unwrap()).with_read_only_disk();
        let candidates = reader.candidates(leaf_key.unwrap());
        assert_eq!(candidates[0].fragment_count(), 1);
        for value in 0..6 {
            assert!(candidates
                .iter()
                .any(|record| record.text().contains(&format!("return {value}"))));
            let plan = dm_preprocess::regions::plan_regions(
                std::path::Path::new("project.dme"),
                &Source(value),
                &BTreeMap::new(),
            );
            let replay = dm_preprocess::regions::expand_regions_text_with_memo(&plan, 1, &reader);
            let fresh = dm_preprocess::regions::expand_regions_text(&plan, 1);
            assert_eq!(replay.text, fresh.text, "context {value}");
            assert!(replay.diagnostics.is_empty());
        }
        assert!(reader.take_pending().is_empty());
    }
}
