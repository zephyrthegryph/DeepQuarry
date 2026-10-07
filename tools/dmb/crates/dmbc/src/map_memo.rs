//! S5 syntax and symbolic geometry reuse. No dense IDs, resource payloads or
//! linked initializer artifacts enter this memo. Initializer lowering still runs.
use crate::lowering_memo::{RecordingResolver, ResolverRead};
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

const MAX_PAYLOAD: usize = 32 * 1024 * 1024;
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
}
struct ParseEntry {
    key: Arc<[u8]>,
    plan: MapPlan,
}
struct GeometryEntry {
    key: Arc<[u8]>,
    reads: Arc<[ResolverRead]>,
    value: Projection,
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
    disk: Option<dm_cache::CacheSnapshot>,
    resident: Mutex<Resident>,
    pub counts: Counts,
}
impl MapMemo {
    pub fn new(policy: u128, byte_budget: usize) -> Self {
        Self {
            policy,
            budget: byte_budget,
            disk: None,
            resident: Mutex::new(Resident::default()),
            counts: Counts::default(),
        }
    }
    pub fn with_disk(policy: u128, byte_budget: usize, disk: dm_cache::CacheSnapshot) -> Self {
        Self {
            disk: Some(disk),
            ..Self::new(policy, byte_budget)
        }
    }
    fn record_key(key: &[u8], geometry: bool) -> dm_cache::RecordKey {
        dm_cache::RecordKey {
            stage: 3,
            version: if geometry { 2 } else { 1 },
            content: xxhash_rust::xxh3::xxh3_128(key),
        }
    }
    fn disk(&self, key: &[u8], geometry: bool) -> Option<Vec<u8>> {
        self.disk
            .as_ref()?
            .get(Self::record_key(key, geometry), |bytes, _| {
                if bytes.len() > MAX_PAYLOAD {
                    return Err("map payload exceeds limit".into());
                }
                if geometry {
                    wire::validate_geometry(bytes)
                } else {
                    wire::validate_parse(bytes)
                }
            })
            .map(|record| record.payload.to_vec())
    }
    /// Charge an intentionally conservative multiple of serialized bytes for
    /// typed Arc/vector backing. Disk admission has an independent byte budget.
    /// No unbounded admission:
    /// after the fixed budget/count is exhausted, entries recompute normally.
    fn reserve(&self, state: &mut Resident, payload: usize, key: usize) -> bool {
        let Some(cost) = payload
            .checked_mul(16)
            .and_then(|cost| cost.checked_add(key))
        else {
            return false;
        };
        if payload > MAX_PAYLOAD
            || state.parse.len() + state.geometry.len() >= MAX_ENTRIES
            || cost > self.budget.saturating_sub(state.charged)
        {
            self.counts.skipped_budget.fetch_add(1, Ordering::Relaxed);
            return false;
        }
        state.charged += cost;
        true
    }
    fn queue(&self, state: &mut Resident, key: &[u8], geometry: bool, bytes: Vec<u8>) {
        if self.disk.is_some() {
            let record_key = Self::record_key(key, geometry);
            let previous = state
                .pending
                .get(&record_key)
                .map_or(0, |record| record.payload.len());
            let retained = state.pending_bytes.saturating_sub(previous);
            if bytes.len() > MAX_PAYLOAD
                || bytes.len() > self.budget.saturating_sub(retained)
                || (!state.pending.contains_key(&record_key) && state.pending.len() >= MAX_ENTRIES)
            {
                self.counts
                    .skipped_disk_budget
                    .fetch_add(1, Ordering::Relaxed);
                return;
            }
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
        if let Some(bytes) = self.disk(&key, false) {
            if let Some(plan) = wire::decode_parse(&bytes, &key, captured.clone()) {
                let mut state = self
                    .resident
                    .lock()
                    .unwrap_or_else(|error| error.into_inner());
                if self.reserve(&mut state, bytes.len(), key.len()) {
                    state.parse.push(ParseEntry {
                        key: key.into(),
                        plan: plan.clone(),
                    });
                }
                self.counts.parse_hits.fetch_add(1, Ordering::Relaxed);
                return Ok(plan);
            }
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
                    key: key.clone().into(),
                    plan: plan.clone(),
                });
            }
            self.queue(&mut state, &key, false, bytes);
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
        if let Some(bytes) = self.disk(&key, true) {
            if let Some((value, reads)) = wire::decode_geometry(&bytes, &key, maps, defaults, host)
            {
                let mut state = self
                    .resident
                    .lock()
                    .unwrap_or_else(|error| error.into_inner());
                if self.reserve(&mut state, bytes.len(), key.len()) {
                    state.geometry.push(GeometryEntry {
                        key: key.into(),
                        reads: reads.into(),
                        value: value.clone(),
                    });
                }
                self.counts.geometry_hits.fetch_add(1, Ordering::Relaxed);
                return Ok(value);
            }
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
                    key: key.clone().into(),
                    reads: reads.into(),
                    value: value.clone(),
                });
            }
            self.queue(&mut state, &key, true, bytes);
        }
        Ok(value)
    }
    /// One segment publication per build; no per-map filesystem write.
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
