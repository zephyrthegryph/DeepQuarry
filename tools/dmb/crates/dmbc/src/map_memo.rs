//! Captured map syntax, symbolic geometry, and immutable emission reuse.
//! Current provenance and the common read ledger authorize artifacts; no dense
//! table IDs, linked images, or resource payloads enter this owner.
use crate::lowering_memo::{CachePublisher, RecordingResolver, ResolverRead};
use crate::map_projection::{Projection, WorldDefaults};
use dm_ir::Resolver;
use dm_tree::maps::{CapturedMap, MapDiagnostic, MapPlan};
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc, Mutex,
};
#[path = "map_memo_outputs.rs"]
mod outputs;
pub use outputs::MapOutputInputs;
#[path = "map_memo_retained.rs"]
mod retained;
#[path = "map_memo_wire.rs"]
mod wire;
pub use retained::RetainedMaps;
#[cfg(test)]
#[path = "map_memo_output_tests.rs"]
mod output_tests;
#[cfg(test)]
#[path = "map_memo_retained_tests.rs"]
mod retained_tests;

#[derive(Default)]
pub struct Counts {
    pub parse_hits: AtomicU64,
    pub geometry_hits: AtomicU64,
    pub output_hits: AtomicU64,
    /// Per-unit symbolic admissions after ordinary current map planning.
    pub unit_hits: AtomicU64,
    pub outputs_prepared: AtomicU64,
    pub parsed: AtomicU64,
    pub projected: AtomicU64,
    pub disk_admitted: AtomicU64,
    pub skipped_disk_budget: AtomicU64,
    pub staged_records: AtomicU64,
    pub staging_failed: AtomicU64,
}
pub struct MapMemo {
    retained: Option<Arc<RetainedMaps>>,
    pending_maps: Option<dm_session::ArtifactAttempt<retained::MapLeases>>,
    current: Mutex<retained::CurrentRoster>,
    pub policy: u128,
    disk: Option<Arc<crate::runner_disk::LazyDisk>>,
    pending_records: Mutex<dm_cache::PendingRecords>,
    read_only_disk: bool,
    publisher: Option<Arc<CachePublisher>>,
    staging_errors: Mutex<Vec<String>>,
    pub counts: Counts,
}
impl MapMemo {
    pub(crate) fn validate_cache_payload(version: u32, bytes: &[u8]) -> Result<(), String> {
        match version {
            3 => wire::validate_parse(bytes),
            4 => wire::validate_geometry(bytes),
            5 | 6 => {
                for payload in dm_cache::decode_variants(bytes)? {
                    if version == 5 {
                        wire::validate_parse(payload)?;
                    } else {
                        wire::validate_geometry(payload)?;
                    }
                }
                Ok(())
            }
            _ => Err("unsupported map memo version".into()),
        }
    }
    fn empty(policy: u128) -> Self {
        Self {
            retained: None,
            pending_maps: None,
            current: Mutex::new(retained::CurrentRoster::default()),
            policy,
            disk: None,
            pending_records: Mutex::new(dm_cache::PendingRecords::default()),
            read_only_disk: false,
            publisher: None,
            staging_errors: Mutex::new(Vec::new()),
            counts: Counts::default(),
        }
    }
    #[cfg(test)]
    fn request(policy: u128) -> Self {
        Self::with_resident(policy, Arc::new(RetainedMaps::current_revision()), None)
    }
    #[cfg(test)]
    fn request_with_disk(policy: u128, disk: impl Into<Arc<dm_cache::CacheSnapshot>>) -> Self {
        Self::with_resident(
            policy,
            Arc::new(RetainedMaps::current_revision()),
            Some(Arc::new(crate::runner_disk::LazyDisk::from_snapshot(
                disk.into(),
            ))),
        )
    }
    /// One map record per bounded callback; the host may batch these records in
    /// its request batch spool. Staging never holds the pending-record mutex.
    /// Hydrate existing records without encoding/populating this disk store.
    pub fn with_read_only_disk(mut self) -> Self {
        self.read_only_disk = true;
        self
    }
    pub fn with_publisher(mut self, publisher: Arc<CachePublisher>) -> Self {
        self.publisher = Some(publisher);
        self
    }
    fn record_error(&self, message: String) {
        self.counts.staging_failed.fetch_add(1, Ordering::Relaxed);
        let mut errors = self
            .staging_errors
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        if errors.len() < 8 {
            errors.push(message.chars().take(512).collect());
        }
    }
    pub fn staging_errors(&self) -> Vec<String> {
        self.staging_errors
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
    }
    fn record_key(key: &[u8], geometry: bool) -> dm_cache::RecordKey {
        dm_cache::RecordKey {
            stage: 3,
            version: if geometry { 6 } else { 5 },
            content: xxhash_rust::xxh3::xxh3_128(key),
        }
    }
    fn disk<T>(
        &self,
        key: &[u8],
        geometry: bool,
        admit: impl Fn(&[u8]) -> Result<Option<T>, String>,
    ) -> Option<(T, usize)> {
        let issued = std::cell::RefCell::new(None);
        let view = self.disk.as_ref()?.snapshot()?.get_candidate(
            Self::record_key(key, geometry),
            |bytes, _| {
                *issued.borrow_mut() = None;
                Self::validate_cache_payload(Self::record_key(key, geometry).version, bytes)?;
                for payload in dm_cache::decode_variants(bytes)?.into_iter().rev() {
                    if let Some(candidate) = admit(payload)? {
                        *issued.borrow_mut() = Some(candidate);
                        return Ok(true);
                    }
                }
                Ok(false)
            },
        )?;
        issued.into_inner().map(|value| (value, view.payload.len()))
    }
    fn queue(&self, key: &[u8], geometry: bool, bytes: Vec<u8>) {
        if self.read_only_disk {
            return;
        }
        let bytes = match dm_cache::encode_variants(&[bytes]) {
            Ok(bytes) => bytes,
            Err(error) => {
                self.record_error(error);
                return;
            }
        };
        if let Some(publisher) = &self.publisher {
            let record = dm_cache::Record {
                key: Self::record_key(key, geometry),
                symbols: Vec::new(),
                payload: bytes.into(),
            };
            self.counts.disk_admitted.fetch_add(1, Ordering::Relaxed);
            match publisher(vec![record]) {
                Ok(()) => {
                    self.counts.staged_records.fetch_add(1, Ordering::Relaxed);
                }
                Err(message) => {
                    self.counts.staging_failed.fetch_add(1, Ordering::Relaxed);
                    let mut errors = self
                        .staging_errors
                        .lock()
                        .unwrap_or_else(|e| e.into_inner());
                    if errors.len() < 8 {
                        errors.push(message.chars().take(512).collect());
                    }
                }
            }
            return;
        }
        if let Some(disk) = &self.disk {
            let ready = self
                .pending_records
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .push(
                    dm_cache::Record {
                        key: Self::record_key(key, geometry),
                        symbols: Vec::new(),
                        payload: bytes.into(),
                    },
                    8 * 1024 * 1024,
                );
            self.counts.disk_admitted.fetch_add(1, Ordering::Relaxed);
            match ready {
                Ok(batches) => {
                    for records in batches {
                        let count = records.len() as u64;
                        match disk.append_records(records) {
                            Ok(_) => {
                                self.counts
                                    .staged_records
                                    .fetch_add(count, Ordering::Relaxed);
                            }
                            Err(error) => {
                                self.counts
                                    .staging_failed
                                    .fetch_add(count.saturating_sub(1), Ordering::Relaxed);
                                self.record_error(error.to_string());
                            }
                        }
                    }
                }
                Err(error) => self.record_error(error.to_string()),
            }
        }
    }
    pub fn parse(&self, captured: CapturedMap) -> Result<MapPlan, MapDiagnostic> {
        let key = self.parse_locator(&captured);
        let retained_key: Arc<[u8]> = key.clone().into();
        if let Some(plan) = self.retained_parse(&retained_key, &captured) {
            self.counts.parse_hits.fetch_add(1, Ordering::Relaxed);
            return Ok(plan);
        }
        if let Some((plan, _)) = self.disk(&key, false, |bytes| {
            wire::admit_parse(bytes, &key, captured.clone())
        }) {
            self.admit_retained_parse(retained_key, &plan);
            self.counts.parse_hits.fetch_add(1, Ordering::Relaxed);
            return Ok(plan);
        }
        self.counts.parsed.fetch_add(1, Ordering::Relaxed);
        let plan = dm_tree::maps::plan(captured)?;
        self.admit_retained_parse(retained_key, &plan);
        if (self.read_only_disk || self.disk.is_none()) && self.publisher.is_none() {
            return Ok(plan);
        }
        if let Some(bytes) = wire::encode_parse(&key, &plan) {
            self.queue(&key, false, bytes);
        } else {
            self.record_error(
                "map syntax record cannot be represented by the cache wire format".into(),
            );
        }
        Ok(plan)
    }
    pub fn project<R: Resolver>(
        &self,
        maps: &[MapPlan],
        defaults: WorldDefaults,
        host: &R,
    ) -> Result<Projection, crate::map_projection::Error> {
        let locator = retained::geometry_locator(self.policy, maps, defaults);
        if let Some(value) = self.retained_geometry(&locator, maps, host) {
            self.counts.geometry_hits.fetch_add(1, Ordering::Relaxed);
            return Ok(value);
        }
        let persist = self.disk.is_some() || self.publisher.is_some();
        let key = if persist {
            geometry_key(self.policy, maps, defaults)
        } else {
            Vec::new()
        };
        if let Some(((value, reads), _)) = self.disk(&key, true, |bytes| {
            wire::admit_geometry(bytes, &key, maps, defaults, host)
        }) {
            self.admit_retained_geometry(locator, maps, &value, reads.clone(), Vec::new());
            self.counts.geometry_hits.fetch_add(1, Ordering::Relaxed);
            return Ok(value);
        }
        self.counts.projected.fetch_add(1, Ordering::Relaxed);
        let recording = RecordingResolver::new(host);
        let value = crate::map_projection::project(
            maps,
            defaults,
            &crate::map_projection::ResolverClassifier(&recording),
        )?;
        let reads = recording.reads();
        self.admit_retained_geometry(
            locator,
            maps,
            &value,
            reads.clone(),
            recording.domain_receipts(),
        );
        if !persist {
            return Ok(value);
        }
        if let Some(bytes) = wire::encode_geometry(&key, &value, &reads) {
            self.queue(&key, true, bytes);
        } else if self.disk.is_some() || self.publisher.is_some() {
            self.record_error(
                "map geometry record cannot be represented by the cache wire format".into(),
            );
        }
        Ok(value)
    }
    /// Standalone bounded fallback records. A configured publisher drains records
    /// immediately, so this returns only records retained without a publisher.
    pub fn take_pending(&self) -> Vec<dm_cache::Record> {
        self.pending_records
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take()
    }
}
fn frame(key: &mut Vec<u8>, bytes: &[u8]) {
    key.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
    key.extend_from_slice(bytes);
}
fn parse_key(policy: u128, captured: &CapturedMap) -> Vec<u8> {
    parse_key_with_identity(
        policy,
        captured,
        xxhash_rust::xxh3::xxh3_128(captured.source.as_bytes()),
    )
}
fn parse_key_with_identity(policy: u128, captured: &CapturedMap, source_identity: u128) -> Vec<u8> {
    let mut key = b"dmbc-map-parse-v2-safe-colon\0".to_vec();
    key.extend_from_slice(&policy.to_le_bytes());
    frame(
        &mut key,
        dm_preprocess::regions::canonical_path(&captured.path)
            .to_string_lossy()
            .as_bytes(),
    );
    key.extend_from_slice(&source_identity.to_le_bytes());
    key
}
fn geometry_key(policy: u128, maps: &[MapPlan], defaults: WorldDefaults) -> Vec<u8> {
    let mut key = b"dmbc-map-geometry-v2-safe-colon\0".to_vec();
    key.extend_from_slice(&policy.to_le_bytes());
    key.extend_from_slice(&defaults.turf.bits().to_le_bytes());
    key.extend_from_slice(&defaults.area.bits().to_le_bytes());
    for value in defaults.minimum_dimensions {
        key.extend_from_slice(&value.to_le_bytes());
    }
    key.extend_from_slice(&(maps.len() as u64).to_le_bytes());
    for map in maps {
        frame(&mut key, &parse_key(policy, &map.captured));
        // Exact bytes authorize reuse even in a content-hash collision. Source
        // differences conservatively miss until relative provenance is rebased.
        frame(&mut key, map.captured.source.as_bytes());
        frame(&mut key, &map.model.canonical_bytes());
    }
    key
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::{ResolveQuery, ResolvedMeaning, SymbolId};
    use std::path::PathBuf;
    struct Host {
        mob: bool,
    }
    impl Resolver for Host {
        fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
            match query {
                ResolveQuery::Type(path) => ResolvedMeaning::Symbol(path),
                ResolveQuery::Ancestry(path) => ResolvedMeaning::Symbols(
                    (if path == SymbolId::of("/datum/widget") {
                        vec![
                            SymbolId::of(if self.mob { "/mob" } else { "/obj" }),
                            SymbolId::of("/datum"),
                        ]
                    } else {
                        vec![SymbolId::of("/datum")]
                    })
                    .into(),
                ),
                _ => ResolvedMeaning::Unsupported(query),
            }
        }
    }
    fn input(occurrence: u32) -> CapturedMap {
        CapturedMap {
            path: Arc::new(PathBuf::from("maps/probe.dmm")),
            include_occurrence: occurrence,
            source: Arc::from(
                "\"a\"=(/datum/widget{value=list(1,2)},/turf,/area)\n(1,1,1)={\"a\"}",
            ),
        }
    }
    fn defaults() -> WorldDefaults {
        WorldDefaults {
            turf: SymbolId::of("/turf"),
            area: SymbolId::of("/area"),
            minimum_dimensions: [1; 3],
        }
    }
    #[test]
    fn map_streaming_publisher_preserves_records_without_pending_record_lock() {
        let weak = Arc::new(Mutex::new(std::sync::Weak::<MapMemo>::new()));
        let published = Arc::new(Mutex::new(Vec::new()));
        let target = weak.clone();
        let records = published.clone();
        let memo = Arc::new(MapMemo::request(1).with_publisher(Arc::new(move |batch| {
            // A reentrant lock-taking operation proves the callback is outside
            // the pending-record mutex, independently of publication success.
            assert!(target
                .lock()
                .unwrap()
                .upgrade()
                .unwrap()
                .take_pending()
                .is_empty());
            records.lock().unwrap().extend(batch);
            Ok(())
        })));
        *weak.lock().unwrap() = Arc::downgrade(&memo);
        let plan = memo.parse(input(1)).unwrap();
        memo.project(&[plan], defaults(), &Host { mob: false })
            .unwrap();
        assert_eq!(published.lock().unwrap().len(), 2);
        assert_eq!(memo.counts.staged_records.load(Ordering::Relaxed), 2);
        assert_eq!(memo.counts.skipped_disk_budget.load(Ordering::Relaxed), 0);
        assert!(memo.take_pending().is_empty());
    }
    #[test]
    fn map_streaming_publication_failure_is_bounded_and_does_not_change_results() {
        let memo = MapMemo::request(1).with_publisher(Arc::new(|_| Err("disk unavailable".into())));
        for occurrence in 0..12 {
            let mut current = input(occurrence);
            current.source = format!("// revision {occurrence}\n{}", current.source).into();
            memo.parse(current).unwrap();
        }
        assert_eq!(memo.counts.staging_failed.load(Ordering::Relaxed), 12);
        assert_eq!(memo.staging_errors().len(), 8);
        assert_eq!(memo.counts.staged_records.load(Ordering::Relaxed), 0);
    }
    #[test]
    fn map_hits_rebind_occurrences_and_validate_every_geometry_read() {
        let memo = MapMemo::request(1);
        let first = memo.parse(input(1)).unwrap();
        let second = memo.parse(input(7)).unwrap();
        assert_eq!(second.captured.include_occurrence, 7);
        assert!(Arc::ptr_eq(&first.model, &second.model));
        assert_eq!(memo.counts.parsed.load(Ordering::Relaxed), 1);
        let maps = [second];
        let first = memo
            .project(&maps, defaults(), &Host { mob: false })
            .unwrap();
        let same = memo
            .project(&maps, defaults(), &Host { mob: false })
            .unwrap();
        assert_eq!(first.grid.as_ref(), same.grid.as_ref());
        assert_eq!(memo.counts.projected.load(Ordering::Relaxed), 1);
        let changed = memo
            .project(&maps, defaults(), &Host { mob: true })
            .unwrap();
        assert!(changed
            .instances
            .iter()
            .any(|instance| instance.kind == crate::map_projection::InstanceKind::Mob));
        assert_eq!(memo.counts.projected.load(Ordering::Relaxed), 2);
        let mut larger = defaults();
        larger.minimum_dimensions[0] = 2;
        assert_eq!(
            memo.project(&maps, larger, &Host { mob: true })
                .unwrap()
                .dimensions,
            [2, 1, 1]
        );
        assert_eq!(memo.counts.projected.load(Ordering::Relaxed), 3);
        let mut edited = input(8);
        edited.source = format!("// line\n{}", edited.source).into();
        memo.parse(edited).unwrap();
        assert_eq!(memo.counts.parsed.load(Ordering::Relaxed), 2);
    }
    #[test]
    fn no_disk_map_request_uses_shared_typed_hits_without_spooling() {
        let memo = MapMemo::request(1);
        let first = memo.parse(input(1)).unwrap();
        memo.parse(input(2)).unwrap();
        let first = memo
            .project(
                std::slice::from_ref(&first),
                defaults(),
                &Host { mob: false },
            )
            .unwrap();
        let parsed = memo.parse(input(3)).unwrap();
        let second = memo
            .project(&[parsed], defaults(), &Host { mob: false })
            .unwrap();
        assert_eq!(first.grid.as_ref(), second.grid.as_ref());
        assert_eq!(memo.counts.parse_hits.load(Ordering::Relaxed), 2);
        assert_eq!(memo.counts.geometry_hits.load(Ordering::Relaxed), 1);
        assert!(memo.take_pending().is_empty());
    }
    struct Temporary(PathBuf);
    #[test]
    fn typed_map_admission_preserves_corruption_rejection_and_dependency_misses() {
        let captured = input(1);
        let key = parse_key(1, &captured);
        let plan = dm_tree::maps::plan(captured.clone()).unwrap();
        let bytes = wire::encode_parse(&key, &plan).unwrap();
        assert!(wire::admit_parse(&bytes, &key, input(9)).unwrap().is_some());
        assert!(wire::admit_parse(&bytes, b"different-key", captured)
            .unwrap()
            .is_none());
        assert!(wire::admit_parse(b"corrupt", &key, input(1)).is_err());
        let host = Host { mob: false };
        let recording = RecordingResolver::new(&host);
        let value = crate::map_projection::project(
            std::slice::from_ref(&plan),
            defaults(),
            &crate::map_projection::ResolverClassifier(&recording),
        )
        .unwrap();
        let geometry = geometry_key(1, std::slice::from_ref(&plan), defaults());
        let bytes = wire::encode_geometry(&geometry, &value, &recording.reads()).unwrap();
        assert!(wire::admit_geometry(
            &bytes,
            &geometry,
            std::slice::from_ref(&plan),
            defaults(),
            &Host { mob: false }
        )
        .unwrap()
        .is_some());
        assert!(
            wire::admit_geometry(&bytes, &geometry, &[plan], defaults(), &Host { mob: true })
                .unwrap()
                .is_none()
        );
        assert!(
            wire::admit_geometry(b"corrupt", &geometry, &[], defaults(), &Host { mob: false })
                .is_err()
        );
    }
    impl Drop for Temporary {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }
    #[test]
    fn map_stage3_disk_roundtrip_keeps_symbolic_model_and_current_source() {
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let directory = Temporary(
            std::env::temp_dir().join(format!("dmbc-map-memo-{}-{unique}", std::process::id())),
        );
        let cache = dm_cache::Cache::open(&directory.0, dm_cache::Limits::default()).unwrap();
        let memo = MapMemo::request_with_disk(1, cache.snapshot().unwrap());
        let first = memo.parse(input(1)).unwrap();
        let projection = memo
            .project(
                std::slice::from_ref(&first),
                defaults(),
                &Host { mob: false },
            )
            .unwrap();
        let pending = memo.take_pending();
        assert_eq!(pending.len(), 2);
        cache.publish(&pending).unwrap();
        drop(memo);
        let loaded = MapMemo::request_with_disk(1, cache.snapshot().unwrap());
        let second = loaded.parse(input(9)).unwrap();
        assert_eq!(second.captured.include_occurrence, 9);
        assert_eq!(first.model, second.model);
        assert_eq!(
            first.template_origins[0].span,
            second.template_origins[0].span
        );
        let same = loaded
            .project(&[second], defaults(), &Host { mob: false })
            .unwrap();
        assert_eq!(projection.grid.as_ref(), same.grid.as_ref());
        assert_eq!(projection.objects.as_ref(), same.objects.as_ref());
        assert_eq!(loaded.counts.parsed.load(Ordering::Relaxed), 0);
        assert_eq!(loaded.counts.projected.load(Ordering::Relaxed), 0);
        drop(loaded);
    }
    #[test]
    fn map_disk_transport_hydrates_shared_artifacts_with_bounded_pending_records() {
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let directory = Temporary(std::env::temp_dir().join(format!(
            "dmbc-map-disk-only-{}-{unique}",
            std::process::id()
        )));
        let cache = dm_cache::Cache::open(&directory.0, dm_cache::Limits::default()).unwrap();
        let host = Host { mob: false };
        let memo = MapMemo::request_with_disk(1, cache.snapshot().unwrap());
        let first = memo.parse(input(1)).unwrap();
        memo.project(std::slice::from_ref(&first), defaults(), &host)
            .unwrap();
        {
            assert!(memo.pending_records.lock().unwrap().bytes() <= 8 * 1024 * 1024);
            assert_eq!(memo.retained.as_ref().unwrap().test_entries(), 2);
        }
        let pending = memo.take_pending();
        assert_eq!(pending.len(), 2);
        cache.publish(&pending).unwrap();
        drop(memo);
        let loaded = MapMemo::request_with_disk(1, cache.snapshot().unwrap());
        let second = loaded.parse(input(4)).unwrap();
        assert_eq!(second.captured.include_occurrence, 4);
        loaded
            .project(std::slice::from_ref(&second), defaults(), &host)
            .unwrap();
        assert_eq!(loaded.counts.parsed.load(Ordering::Relaxed), 0);
        assert_eq!(loaded.counts.projected.load(Ordering::Relaxed), 0);
        drop(loaded);
    }
}

#[cfg(test)]
#[path = "map_memo_candidate_tests.rs"]
mod candidate_tests;
