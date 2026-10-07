//! S5 syntax and symbolic geometry reuse. No dense IDs, resource payloads or
//! linked initializer artifacts enter this memo. Initializer lowering still runs.
use crate::lowering_memo::{CachePublisher, RecordingResolver, ResolverRead};
use crate::map_projection::{Projection, WorldDefaults};
use dm_ir::Resolver;
use dm_tree::maps::{CapturedMap, MapDiagnostic, MapPlan};
use std::collections::BTreeMap;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc, Mutex,
};
#[path = "map_memo_wire.rs"]
mod wire;

const MAX_ENTRIES: usize = 1024;
#[derive(Default)]
pub struct Counts {
    pub parse_hits: AtomicU64,
    pub geometry_hits: AtomicU64,
    pub parsed: AtomicU64,
    pub projected: AtomicU64,
    pub skipped_budget: AtomicU64,
    pub disk_admitted: AtomicU64,
    pub skipped_disk_budget: AtomicU64,
    pub published_records: AtomicU64,
    pub publication_failed: AtomicU64,
}
struct ParseEntry {
    key: Arc<[u8]>,
    plan: MapPlan,
    charge: usize,
}
struct GeometryEntry {
    key: Arc<[u8]>,
    reads: Arc<[ResolverRead]>,
    value: Projection,
    charge: usize,
}
#[derive(Default)]
struct Resident {
    parse: Vec<ParseEntry>,
    geometry: Vec<GeometryEntry>,
    pending: BTreeMap<dm_cache::RecordKey, dm_cache::Record>,
    charged: usize,
    pending_bytes: usize,
}
pub struct MapMemo {
    pub policy: u128,
    budget: usize,
    disk: Option<Arc<dm_cache::CacheSnapshot>>,
    resident: Mutex<Resident>,
    publisher: Option<Arc<CachePublisher>>,
    publication_errors: Mutex<Vec<String>>,
    pub counts: Counts,
}
impl MapMemo {
    pub(crate) fn validate_cache_payload(version: u32, bytes: &[u8]) -> Result<(), String> {
        match version {
            3 => wire::validate_parse(bytes),
            4 => wire::validate_geometry(bytes),
            _ => Err("unsupported map memo version".into()),
        }
    }
    pub fn new(policy: u128, byte_budget: usize) -> Self {
        Self {
            policy,
            budget: byte_budget,
            disk: None,
            resident: Mutex::new(Resident::default()),
            publisher: None,
            publication_errors: Mutex::new(Vec::new()),
            counts: Counts::default(),
        }
    }
    pub fn with_disk(
        policy: u128,
        byte_budget: usize,
        disk: impl Into<Arc<dm_cache::CacheSnapshot>>,
    ) -> Self {
        Self {
            disk: Some(disk.into()),
            ..Self::new(policy, byte_budget)
        }
    }
    /// One map record per bounded callback; the host may batch these records in
    /// its PublishSink. Publication never holds the resident mutex.
    pub fn with_publisher(mut self, publisher: Arc<CachePublisher>) -> Self {
        self.publisher = Some(publisher);
        self
    }
    fn record_error(&self, message: String) {
        self.counts
            .publication_failed
            .fetch_add(1, Ordering::Relaxed);
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
    fn record_key(key: &[u8], geometry: bool) -> dm_cache::RecordKey {
        dm_cache::RecordKey {
            stage: 3,
            version: if geometry { 4 } else { 3 },
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
        let view = self
            .disk
            .as_ref()?
            .get(Self::record_key(key, geometry), |bytes, _| {
                *issued.borrow_mut() = None;
                *issued.borrow_mut() = admit(bytes)?;
                Ok(())
            })?;
        issued.into_inner().map(|value| (value, view.payload.len()))
    }
    /// Charge an intentionally conservative multiple of serialized bytes for
    /// typed Arc/vector backing. Disk publication flushes bounded queues independently.
    /// Evict existing resident entries to make room; oversized entries remain disk-only.
    fn reserve(&self, state: &mut Resident, payload: usize, key: usize) -> bool {
        let Some(cost) = payload
            .checked_mul(16)
            .and_then(|cost| cost.checked_add(key))
        else {
            return false;
        };
        // Oversized values are published without retaining another typed copy.
        if cost > self.budget {
            return false;
        }
        while state.parse.len() + state.geometry.len() >= MAX_ENTRIES
            || cost > self.budget.saturating_sub(state.charged)
        {
            let removed = if !state.parse.is_empty() {
                state.parse.remove(0).charge
            } else if !state.geometry.is_empty() {
                state.geometry.remove(0).charge
            } else {
                break;
            };
            state.charged -= removed;
        }
        state.charged += cost;
        true
    }
    fn queue(&self, key: &[u8], geometry: bool, bytes: Vec<u8>) {
        if let Some(publisher) = &self.publisher {
            let record = dm_cache::Record {
                key: Self::record_key(key, geometry),
                symbols: Vec::new(),
                payload: bytes.into(),
            };
            self.counts.disk_admitted.fetch_add(1, Ordering::Relaxed);
            match publisher(vec![record]) {
                Ok(()) => {
                    self.counts
                        .published_records
                        .fetch_add(1, Ordering::Relaxed);
                }
                Err(message) => {
                    self.counts
                        .publication_failed
                        .fetch_add(1, Ordering::Relaxed);
                    let mut errors = self
                        .publication_errors
                        .lock()
                        .unwrap_or_else(|e| e.into_inner());
                    if errors.len() < 8 {
                        errors.push(message.chars().take(512).collect());
                    }
                }
            }
            return;
        }
        let mut state = self.resident.lock().unwrap_or_else(|e| e.into_inner());
        if self.disk.is_some() {
            let record_key = Self::record_key(key, geometry);
            let previous = state
                .pending
                .get(&record_key)
                .map_or(0, |record| record.payload.len());
            let retained = state.pending_bytes.saturating_sub(previous);
            state.pending_bytes = retained + bytes.len();
            state.pending.insert(
                record_key,
                dm_cache::Record {
                    key: record_key,
                    symbols: Vec::new(),
                    payload: bytes.into(),
                },
            );
            self.counts.disk_admitted.fetch_add(1, Ordering::Relaxed);
            if state.pending_bytes >= 8 * 1024 * 1024 {
                state.pending_bytes = 0;
                let records: Vec<_> = std::mem::take(&mut state.pending).into_values().collect();
                drop(state);
                let count = records.len() as u64;
                let result = self.disk.as_ref().unwrap().publish(&records);
                match result {
                    Ok(_) => {
                        self.counts
                            .published_records
                            .fetch_add(count, Ordering::Relaxed);
                    }
                    Err(error) => {
                        self.counts
                            .publication_failed
                            .fetch_add(count, Ordering::Relaxed);
                        let mut errors = self
                            .publication_errors
                            .lock()
                            .unwrap_or_else(|e| e.into_inner());
                        if errors.len() < 8 {
                            errors.push(error.to_string());
                        }
                    }
                }
            }
        }
    }
    pub fn parse(&self, captured: CapturedMap) -> Result<MapPlan, MapDiagnostic> {
        let key = parse_key(self.policy, &captured);
        let hit = {
            let state = self
                .resident
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            state
                .parse
                .iter()
                .rev()
                .find(|entry| {
                    entry.key.as_ref() == key && entry.plan.captured.source == captured.source
                })
                .map(|entry| entry.plan.clone())
        };
        if let Some(mut plan) = hit {
            plan.captured = captured;
            self.counts.parse_hits.fetch_add(1, Ordering::Relaxed);
            return Ok(plan);
        }
        if let Some((plan, payload_len)) = self.disk(&key, false, |bytes| {
            wire::admit_parse(bytes, &key, captured.clone())
        }) {
            let mut state = self
                .resident
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if self.reserve(&mut state, payload_len, key.len()) {
                state.parse.push(ParseEntry {
                    charge: payload_len * 16 + key.len(),
                    key: key.into(),
                    plan: plan.clone(),
                });
            }
            self.counts.parse_hits.fetch_add(1, Ordering::Relaxed);
            return Ok(plan);
        }
        self.counts.parsed.fetch_add(1, Ordering::Relaxed);
        let plan = dm_tree::maps::plan(captured)?;
        if let Some(bytes) = wire::encode_parse(&key, &plan) {
            let mut state = self
                .resident
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if self.reserve(&mut state, bytes.len(), key.len()) {
                state.parse.push(ParseEntry {
                    charge: bytes.len() * 16 + key.len(),
                    key: key.clone().into(),
                    plan: plan.clone(),
                });
            }
            drop(state);
            self.queue(&key, false, bytes);
        } else if self.disk.is_some() || self.publisher.is_some() {
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
        let key = geometry_key(self.policy, maps, defaults);
        // Host queries and answer validation happen outside the memo lock.
        let candidates = {
            let state = self
                .resident
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            state
                .geometry
                .iter()
                .rev()
                .filter(|entry| entry.key.as_ref() == key)
                .map(|entry| (entry.reads.clone(), entry.value.clone()))
                .collect::<Vec<_>>()
        };
        for (reads, value) in candidates {
            if reads.iter().all(|read| {
                host.resolve(read.query).canonical_bytes() == read.answer.canonical_bytes()
            }) {
                self.counts.geometry_hits.fetch_add(1, Ordering::Relaxed);
                return Ok(value);
            }
        }
        if let Some(((value, reads), payload_len)) = self.disk(&key, true, |bytes| {
            wire::admit_geometry(bytes, &key, maps, defaults, host)
        }) {
            let mut state = self
                .resident
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if self.reserve(&mut state, payload_len, key.len()) {
                state.geometry.push(GeometryEntry {
                    charge: payload_len * 16 + key.len(),
                    key: key.into(),
                    reads: reads.into(),
                    value: value.clone(),
                });
            }
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
        if let Some(bytes) = wire::encode_geometry(&key, &value, &reads) {
            let mut state = self
                .resident
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if self.reserve(&mut state, bytes.len(), key.len()) {
                state.geometry.push(GeometryEntry {
                    charge: bytes.len() * 16 + key.len(),
                    key: key.clone().into(),
                    reads: reads.into(),
                    value: value.clone(),
                });
            }
            drop(state);
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
        let mut state = self
            .resident
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        state.pending_bytes = 0;
        std::mem::take(&mut state.pending).into_values().collect()
    }
}
fn frame(key: &mut Vec<u8>, bytes: &[u8]) {
    key.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
    key.extend_from_slice(bytes);
}
fn parse_key(policy: u128, captured: &CapturedMap) -> Vec<u8> {
    let mut key = b"dmbc-map-parse-v1\0".to_vec();
    key.extend_from_slice(&policy.to_le_bytes());
    frame(
        &mut key,
        dm_preprocess::regions::canonical_path(&captured.path)
            .to_string_lossy()
            .as_bytes(),
    );
    key.extend_from_slice(&xxhash_rust::xxh3::xxh3_128(captured.source.as_bytes()).to_le_bytes());
    key
}
fn geometry_key(policy: u128, maps: &[MapPlan], defaults: WorldDefaults) -> Vec<u8> {
    let mut key = b"dmbc-map-geometry-v1\0".to_vec();
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
                ResolveQuery::Ancestry(path) => {
                    ResolvedMeaning::Symbols(if path == SymbolId::of("/datum/widget") {
                        vec![
                            SymbolId::of(if self.mob { "/mob" } else { "/obj" }),
                            SymbolId::of("/datum"),
                        ]
                    } else {
                        vec![SymbolId::of("/datum")]
                    })
                }
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
    fn map_resident_budget_evicts_before_retaining_new_results() {
        let memo = MapMemo::new(1, 64);
        let mut resident = Resident::default();
        assert!(memo.reserve(&mut resident, 3, 1));
        resident.parse.push(ParseEntry {
            key: Arc::from(b"old".as_slice()),
            plan: dm_tree::maps::plan(input(1)).unwrap(),
            charge: 49,
        });
        assert!(memo.reserve(&mut resident, 3, 1));
        assert!(resident.parse.is_empty());
        assert_eq!(resident.charged, 49);
        assert!(!memo.reserve(&mut resident, 5, 1));
        assert_eq!(resident.charged, 49);
        assert_eq!(memo.counts.skipped_budget.load(Ordering::Relaxed), 0);
    }

    #[test]
    fn map_streaming_publisher_preserves_records_beyond_budget_without_resident_lock() {
        let weak = Arc::new(Mutex::new(std::sync::Weak::<MapMemo>::new()));
        let published = Arc::new(Mutex::new(Vec::new()));
        let target = weak.clone();
        let records = published.clone();
        let memo = Arc::new(MapMemo::new(1, 0).with_publisher(Arc::new(move |batch| {
            // A reentrant lock-taking operation proves the callback is outside
            // the resident mutex, independently of publication success.
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
        assert_eq!(memo.counts.published_records.load(Ordering::Relaxed), 2);
        assert_eq!(memo.counts.skipped_disk_budget.load(Ordering::Relaxed), 0);
        assert!(memo.take_pending().is_empty());
    }
    #[test]
    fn map_streaming_publication_failure_is_bounded_and_does_not_change_results() {
        let memo = MapMemo::new(1, 0).with_publisher(Arc::new(|_| Err("disk unavailable".into())));
        for occurrence in 0..12 {
            memo.parse(input(occurrence)).unwrap();
        }
        assert_eq!(memo.counts.publication_failed.load(Ordering::Relaxed), 12);
        assert_eq!(memo.publication_errors().len(), 8);
        assert_eq!(memo.counts.published_records.load(Ordering::Relaxed), 0);
    }
    #[test]
    fn map_hits_rebind_occurrences_and_validate_every_geometry_read() {
        let memo = MapMemo::new(1, 16 * 1024 * 1024);
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
    fn bounded_map_memo_falls_back_without_changing_geometry() {
        let memo = MapMemo::new(1, 0);
        let first = memo.parse(input(1)).unwrap();
        memo.parse(input(2)).unwrap();
        let first = memo
            .project(&[first.clone()], defaults(), &Host { mob: false })
            .unwrap();
        let parsed = memo.parse(input(3)).unwrap();
        let second = memo
            .project(&[parsed], defaults(), &Host { mob: false })
            .unwrap();
        assert_eq!(first.grid.as_ref(), second.grid.as_ref());
        assert_eq!(memo.counts.parse_hits.load(Ordering::Relaxed), 0);
        assert_eq!(memo.counts.geometry_hits.load(Ordering::Relaxed), 0);
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
            &[plan.clone()],
            defaults(),
            &crate::map_projection::ResolverClassifier(&recording),
        )
        .unwrap();
        let geometry = geometry_key(1, &[plan.clone()], defaults());
        let bytes = wire::encode_geometry(&geometry, &value, &recording.reads()).unwrap();
        assert!(wire::admit_geometry(
            &bytes,
            &geometry,
            &[plan.clone()],
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
        let memo = MapMemo::with_disk(1, 16 * 1024 * 1024, cache.snapshot().unwrap());
        let first = memo.parse(input(1)).unwrap();
        let projection = memo
            .project(&[first.clone()], defaults(), &Host { mob: false })
            .unwrap();
        let pending = memo.take_pending();
        assert_eq!(pending.len(), 2);
        cache.publish(&pending).unwrap();
        drop(memo);
        let loaded = MapMemo::with_disk(1, 16 * 1024 * 1024, cache.snapshot().unwrap());
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
    fn map_disk_admission_survives_resident_budget_denial() {
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let directory = Temporary(std::env::temp_dir().join(format!(
            "dmbc-map-disk-only-{}-{unique}",
            std::process::id()
        )));
        let cache = dm_cache::Cache::open(&directory.0, dm_cache::Limits::default()).unwrap();
        let plan = dm_tree::maps::plan(input(1)).unwrap();
        let parse_bytes = wire::encode_parse(&parse_key(1, &plan.captured), &plan).unwrap();
        let host = Host { mob: false };
        let recording = RecordingResolver::new(&host);
        let projection = crate::map_projection::project(
            std::slice::from_ref(&plan),
            defaults(),
            &crate::map_projection::ResolverClassifier(&recording),
        )
        .unwrap();
        let geometry_bytes = wire::encode_geometry(
            &geometry_key(1, std::slice::from_ref(&plan), defaults()),
            &projection,
            &recording.reads(),
        )
        .unwrap();
        let budget = parse_bytes.len() + geometry_bytes.len() + 64;
        let memo = MapMemo::with_disk(1, budget, cache.snapshot().unwrap());
        let first = memo.parse(input(1)).unwrap();
        memo.project(std::slice::from_ref(&first), defaults(), &host)
            .unwrap();
        {
            let resident = memo.resident.lock().unwrap();
            assert!(resident.parse.is_empty() && resident.geometry.is_empty());
            assert!(resident.pending_bytes <= budget);
        }
        let pending = memo.take_pending();
        assert_eq!(pending.len(), 2);
        cache.publish(&pending).unwrap();
        drop(memo);
        let loaded = MapMemo::with_disk(1, budget, cache.snapshot().unwrap());
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
