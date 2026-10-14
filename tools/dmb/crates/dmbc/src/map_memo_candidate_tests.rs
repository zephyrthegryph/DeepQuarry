use super::*;
use dm_ir::ResolveQuery;
static NEXT: AtomicU64 = AtomicU64::new(0);
struct Temp(std::path::PathBuf);
impl Temp {
    fn new() -> Self {
        let base = if cfg!(windows) {
            std::path::PathBuf::from("E:/dq-cache/dmb-protocol-checks")
        } else {
            std::env::temp_dir()
        };
        std::fs::create_dir_all(&base).unwrap();
        let root = base.join(format!(
            "map-candidates-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir(&root).unwrap();
        Self(root)
    }
}
impl Drop for Temp {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
fn payload(context: u8) -> Vec<u8> {
    let captured = CapturedMap {
        path: Arc::new(std::path::PathBuf::from("fixture.dmm")),
        include_occurrence: 0,
        source: Arc::from(format!(
            "\"a\"=(/turf/context_{context},/area)\n(1,1,1)={{\"a\"}}"
        )),
    };
    let plan = dm_tree::maps::plan(captured).unwrap();
    wire::encode_parse(&[context], &plan).unwrap()
}
#[test]
fn context_rejection_continues_map_candidates_and_does_not_record_unadmitted_use() {
    let root = Temp::new();
    let cache = dm_cache::Cache::open(&root.0, dm_cache::Limits::default()).unwrap();
    let key = b"map-context-key";
    for bytes in [payload(0), payload(1)] {
        cache
            .publish(&[dm_cache::Record {
                key: MapMemo::record_key(key, false),
                symbols: Vec::new(),
                payload: dm_cache::encode_variants(&[bytes]).unwrap().into(),
            }])
            .unwrap();
    }
    for expected in [payload(0), payload(1)] {
        let snapshot = Arc::new(cache.snapshot().unwrap());
        let memo = MapMemo::request_with_disk(1, Arc::clone(&snapshot));
        let (accepted, size) = memo
            .disk(key, false, |bytes| {
                Ok((bytes == expected.as_slice()).then(|| bytes.to_vec()))
            })
            .unwrap();
        assert_eq!(accepted, expected);
        assert!(size > expected.len());
        assert_eq!(
            snapshot.record_used_keys(),
            [MapMemo::record_key(key, false)].into_iter().collect()
        );
        assert!(snapshot.rejected().is_empty());
    }
    let snapshot = Arc::new(cache.snapshot().unwrap());
    let memo = MapMemo::request_with_disk(1, Arc::clone(&snapshot));
    assert!(memo.disk::<()>(key, false, |_| Ok(None)).is_none());
    assert!(snapshot.record_used_keys().is_empty());
    assert!(snapshot.rejected().is_empty());
}
#[test]
fn pending_map_collision_publishes_previous_context_without_overwrite() {
    let root = Temp::new();
    let cache = dm_cache::Cache::open(&root.0, dm_cache::Limits::default()).unwrap();
    let memo = MapMemo::request_with_disk(1, cache.snapshot().unwrap());
    let key = b"same-map-locator";
    for context in 0..6u8 {
        memo.queue(key, false, payload(context));
    }
    memo.disk
        .as_ref()
        .unwrap()
        .append_records(memo.take_pending())
        .unwrap();
    memo.disk.as_ref().unwrap().finish_batch().unwrap();
    let snapshot = cache.snapshot().unwrap();
    for context in 0..6u8 {
        assert!(snapshot
            .get_candidate(MapMemo::record_key(key, false), |bytes, _| Ok(
                dm_cache::decode_variants(bytes)
                    .unwrap()
                    .iter()
                    .any(|bytes| *bytes == payload(context).as_slice())
            ))
            .is_some());
    }
    assert_eq!(memo.counts.staged_records.load(Ordering::Relaxed), 5);
}

#[test]
fn corrupt_later_map_variant_rejects_whole_record_before_semantic_admission() {
    let root = Temp::new();
    let cache = dm_cache::Cache::open(&root.0, dm_cache::Limits::default()).unwrap();
    let key = b"corrupt-map-envelope";
    cache
        .publish(&[dm_cache::Record {
            key: MapMemo::record_key(key, false),
            symbols: Vec::new(),
            payload: dm_cache::encode_variants(&[payload(0), b"invalid".to_vec()])
                .unwrap()
                .into(),
        }])
        .unwrap();
    let memo = MapMemo::request_with_disk(1, cache.snapshot().unwrap());
    let calls = AtomicU64::new(0);
    assert!(memo
        .disk::<()>(key, false, |_| {
            calls.fetch_add(1, Ordering::Relaxed);
            Ok(Some(()))
        })
        .is_none());
    assert_eq!(calls.load(Ordering::Relaxed), 0);
    assert_eq!(
        memo.disk
            .as_ref()
            .unwrap()
            .snapshot()
            .unwrap()
            .rejected()
            .len(),
        1
    );
}

#[test]
fn legacy_raw_map_version_is_a_clean_miss_for_variant_consumer() {
    let root = Temp::new();
    let cache = dm_cache::Cache::open(&root.0, dm_cache::Limits::default()).unwrap();
    let key = b"old-map-version";
    let mut old = MapMemo::record_key(key, false);
    old.version = 3;
    cache
        .publish(&[dm_cache::Record {
            key: old,
            symbols: Vec::new(),
            payload: payload(0).into(),
        }])
        .unwrap();
    let memo = MapMemo::request_with_disk(1, cache.snapshot().unwrap());
    assert!(memo
        .disk::<()>(key, false, |_| panic!("old schema must not be admitted"))
        .is_none());
    assert!(memo
        .disk
        .as_ref()
        .unwrap()
        .snapshot()
        .unwrap()
        .rejected()
        .is_empty());
}

struct GeometryHost {
    mob: bool,
    calls: AtomicU64,
}
impl Resolver for GeometryHost {
    fn resolve(&self, query: ResolveQuery) -> dm_ir::ResolvedMeaning {
        self.calls.fetch_add(1, Ordering::Relaxed);
        match query {
            ResolveQuery::Type(path) => dm_ir::ResolvedMeaning::Symbol(path),
            ResolveQuery::Ancestry(path) => dm_ir::ResolvedMeaning::Symbols(
                (if path == dm_ir::SymbolId::of("/datum/widget") {
                    vec![dm_ir::SymbolId::of(if self.mob { "/mob" } else { "/obj" })]
                } else {
                    Vec::new()
                })
                .into(),
            ),
            _ => dm_ir::ResolvedMeaning::Unsupported(query),
        }
    }
}
fn geometry_fixture(key: &[u8], mob: bool) -> (Vec<MapPlan>, WorldDefaults, Vec<u8>) {
    let maps = vec![dm_tree::maps::plan(CapturedMap {
        path: Arc::new(std::path::PathBuf::from("current.dmm")),
        include_occurrence: 7,
        source: Arc::from("\"a\"=(/datum/widget,/turf,/area)\n(1,1,1)={\"a\"}"),
    })
    .unwrap()];
    let defaults = WorldDefaults {
        turf: dm_ir::SymbolId::of("/turf"),
        area: dm_ir::SymbolId::of("/area"),
        minimum_dimensions: [1; 3],
    };
    let host = GeometryHost {
        mob,
        calls: AtomicU64::new(0),
    };
    let recording = RecordingResolver::new(&host);
    let projection = crate::map_projection::project(
        &maps,
        defaults,
        &crate::map_projection::ResolverClassifier(&recording),
    )
    .unwrap();
    let bytes = wire::encode_geometry(key, &projection, &recording.reads()).unwrap();
    (maps, defaults, bytes)
}
fn publish_bucket(cache: &dm_cache::Cache, key: &[u8], geometry: bool, variants: &[Vec<u8>]) {
    cache
        .publish(&[dm_cache::Record {
            key: MapMemo::record_key(key, geometry),
            symbols: Vec::new(),
            payload: dm_cache::encode_variants(variants).unwrap().into(),
        }])
        .unwrap();
}
#[test]
fn typed_parse_admission_skips_stale_newest_and_rebinds_exact_older_source() {
    let root = Temp::new();
    let cache = dm_cache::Cache::open(&root.0, dm_cache::Limits::default()).unwrap();
    let key = b"same-parse-locator";
    let current = CapturedMap {
        path: Arc::new(std::path::PathBuf::from("current/include.dmm")),
        include_occurrence: 23,
        source: Arc::from("\"a\"=(/turf/current,/area)\n(1,1,1)={\"a\"}"),
    };
    let older = wire::encode_parse(key, &dm_tree::maps::plan(current.clone()).unwrap()).unwrap();
    let stale = wire::encode_parse(
        key,
        &dm_tree::maps::plan(CapturedMap {
            source: Arc::from("\"a\"=(/turf/stale,/area)\n(1,1,1)={\"a\"}"),
            ..current.clone()
        })
        .unwrap(),
    )
    .unwrap();
    publish_bucket(&cache, key, false, &[older, stale]);
    let snapshot = Arc::new(cache.snapshot().unwrap());
    let memo = MapMemo::request_with_disk(1, Arc::clone(&snapshot));
    let attempts = AtomicU64::new(0);
    let (accepted, _) = memo
        .disk(key, false, |bytes| {
            attempts.fetch_add(1, Ordering::Relaxed);
            wire::admit_parse(bytes, key, current.clone())
        })
        .unwrap();
    assert_eq!(attempts.load(Ordering::Relaxed), 2);
    assert_eq!(accepted.captured.include_occurrence, 23);
    assert_eq!(accepted.captured.path, current.path);
    assert_eq!(accepted.captured.source, current.source);
    assert_eq!(accepted.model, dm_tree::maps::plan(current).unwrap().model);
    assert_eq!(snapshot.record_used_keys().len(), 1);
    assert!(snapshot.rejected().is_empty());
}
#[test]
fn typed_geometry_admission_replays_stale_reads_then_accepts_exact_older_answers() {
    let root = Temp::new();
    let cache = dm_cache::Cache::open(&root.0, dm_cache::Limits::default()).unwrap();
    let key = b"same-geometry-locator";
    let (maps, defaults, older) = geometry_fixture(key, false);
    let (_, _, stale) = geometry_fixture(key, true);
    publish_bucket(&cache, key, true, &[older, stale]);
    let snapshot = Arc::new(cache.snapshot().unwrap());
    let memo = MapMemo::request_with_disk(1, Arc::clone(&snapshot));
    let host = GeometryHost {
        mob: false,
        calls: AtomicU64::new(0),
    };
    let attempts = AtomicU64::new(0);
    let ((accepted, reads), _) = memo
        .disk(key, true, |bytes| {
            attempts.fetch_add(1, Ordering::Relaxed);
            wire::admit_geometry(bytes, key, &maps, defaults, &host)
        })
        .unwrap();
    assert_eq!(attempts.load(Ordering::Relaxed), 2);
    assert!(!reads.is_empty());
    assert!(host.calls.load(Ordering::Relaxed) > reads.len() as u64);
    assert!(accepted
        .instances
        .iter()
        .any(|instance| instance.kind == crate::map_projection::InstanceKind::Object));
    assert!(!accepted
        .instances
        .iter()
        .any(|instance| instance.kind == crate::map_projection::InstanceKind::Mob));
    let fresh = crate::map_projection::project(
        &maps,
        defaults,
        &crate::map_projection::ResolverClassifier(&host),
    )
    .unwrap();
    assert_eq!(
        accepted
            .instances
            .iter()
            .map(|instance| (instance.kind, &instance.atom, instance.origin))
            .collect::<Vec<_>>(),
        fresh
            .instances
            .iter()
            .map(|instance| (instance.kind, &instance.atom, instance.origin))
            .collect::<Vec<_>>()
    );
    assert_eq!(accepted.dimensions, fresh.dimensions);
    assert_eq!(accepted.grid.as_ref(), fresh.grid.as_ref());
    assert_eq!(accepted.objects.as_ref(), fresh.objects.as_ref());
    assert_eq!(snapshot.record_used_keys().len(), 1);
    assert!(snapshot.rejected().is_empty());
}
#[test]
fn malformed_older_typed_candidate_rejects_parse_and_geometry_buckets_before_admission() {
    for geometry in [false, true] {
        let root = Temp::new();
        let cache = dm_cache::Cache::open(&root.0, dm_cache::Limits::default()).unwrap();
        let key = b"whole-bucket-validation";
        let (maps, defaults, healthy_geometry) = geometry_fixture(key, false);
        let healthy = if geometry {
            healthy_geometry
        } else {
            wire::encode_parse(key, &maps[0]).unwrap()
        };
        // Newest is healthy and would admit. An older malformed candidate must
        // still invalidate the entire bucket before any semantic query runs.
        publish_bucket(&cache, key, geometry, &[b"malformed".to_vec(), healthy]);
        let snapshot = Arc::new(cache.snapshot().unwrap());
        let memo = MapMemo::request_with_disk(1, Arc::clone(&snapshot));
        let host = GeometryHost {
            mob: false,
            calls: AtomicU64::new(0),
        };
        let attempts = AtomicU64::new(0);
        assert!(memo
            .disk(key, geometry, |bytes| {
                attempts.fetch_add(1, Ordering::Relaxed);
                if geometry {
                    wire::admit_geometry(bytes, key, &maps, defaults, &host)
                        .map(|answer| answer.map(|_| ()))
                } else {
                    wire::admit_parse(bytes, key, maps[0].captured.clone())
                        .map(|answer| answer.map(|_| ()))
                }
            })
            .is_none());
        assert_eq!(attempts.load(Ordering::Relaxed), 0);
        assert_eq!(host.calls.load(Ordering::Relaxed), 0);
        assert!(snapshot.record_used_keys().is_empty());
        assert_eq!(snapshot.rejected().len(), 1);
    }
}
