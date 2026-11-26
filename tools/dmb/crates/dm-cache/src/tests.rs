use super::*;
use std::{
    collections::BTreeSet,
    fs,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
};
static NEXT: AtomicU64 = AtomicU64::new(0);
struct Temp(std::path::PathBuf);
impl Temp {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "dm-cache-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).unwrap();
        Self(path)
    }
}
impl Drop for Temp {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
fn record(key: u128, version: u32) -> Record {
    Record {
        key: RecordKey {
            stage: 4,
            version,
            content: key,
        },
        symbols: vec![SymbolText {
            id: 7,
            text: Arc::from(b"symbol".as_slice()),
        }],
        payload: Arc::from(format!("payload-{key}").as_bytes()),
    }
}
fn validate(payload: &[u8], symbols: &[(u64, &[u8])]) -> Result<(), String> {
    if !payload.starts_with(b"payload-") || symbols != [(7, b"symbol".as_slice())] {
        return Err("typed envelope invalid".into());
    }
    Ok(())
}
#[test]
fn snapshot_used_roots_track_only_successful_returned_views() {
    let root = Temp::new();
    let cache = Cache::open(&root.0, Limits::default()).unwrap();
    let records = [record(101, 1), record(102, 1)];
    cache.publish(&records).unwrap();
    let snapshot = cache.snapshot().unwrap();
    assert!(snapshot.record_used_keys().is_empty());
    assert!(snapshot.get(record(103, 1).key, validate).is_none());
    assert!(snapshot.record_used_keys().is_empty());
    // A view returned to a consumer remains a conservative root even if its
    // subsequent dependency replay is stale and the caller elects to recompute.
    assert!(snapshot.get(records[0].key, validate).is_some());
    assert!(snapshot.get(records[0].key, validate).is_some());
    assert_eq!(
        snapshot.record_used_keys(),
        BTreeSet::from([records[0].key])
    );
    assert!(snapshot
        .get(records[1].key, |_, _| Err("corrupt envelope".into()))
        .is_none());
    assert_eq!(
        snapshot.record_used_keys(),
        BTreeSet::from([records[0].key])
    );
    // Repeated misses after rejection use one memoized supersedes refresh.
    for _ in 0..4 {
        assert!(snapshot.get(records[1].key, validate).is_none());
    }
}
#[test]
fn mapped_roundtrip_stage_versions_and_symbol_self_containment() {
    let root = Temp::new();
    let cache = Cache::open(&root.0, Limits::default()).unwrap();
    let values = [record(1, 1), record(1, 2)];
    let id = cache.publish(&values).unwrap();
    assert_eq!(id, cache.publish(&values).unwrap());
    let snapshot = cache.snapshot().unwrap();
    assert_eq!(snapshot.segment_count(), 1);
    for value in &values {
        let result = snapshot.get(value.key, validate).unwrap();
        assert_eq!(result.payload, value.payload.as_ref());
        assert_eq!(result.payload.as_ptr() as usize % 16, 0);
        assert_eq!(result.symbols, vec![(7, b"symbol".as_slice())]);
    }
    assert!(snapshot
        .get(
            RecordKey {
                version: 3,
                ..values[0].key
            },
            validate
        )
        .is_none());
    assert!(snapshot.rejected().is_empty());
}
#[test]
fn truncated_corrupt_and_typed_invalid_segments_are_misses() {
    for corruption in [0, 1, 2] {
        let root = Temp::new();
        let cache = Cache::open(&root.0, Limits::default()).unwrap();
        let values = [record(1, 1), record(2, 1)];
        let id = cache.publish(&values).unwrap();
        let path = root.0.join(format!("{id:032x}.seg"));
        if corruption < 2 {
            let mut bytes = fs::read(&path).unwrap();
            if corruption == 0 {
                bytes.truncate(bytes.len() - 1);
            } else {
                let end = bytes.len() - 1;
                bytes[end] ^= 1;
            }
            fs::write(&path, bytes).unwrap();
        }
        let snapshot = cache.snapshot().unwrap();
        if corruption == 0 {
            assert_eq!(snapshot.segment_count(), 0);
        } else {
            let key = if corruption == 1 {
                values[1].key
            } else {
                values[0].key
            };
            assert!(snapshot
                .get(key, |payload, symbols| {
                    if corruption == 2 {
                        Err("bytecheck rejected".into())
                    } else {
                        validate(payload, symbols)
                    }
                })
                .is_none());
            assert!(snapshot.get(values[0].key, validate).is_none());
        }
        assert!(!snapshot.rejected().is_empty());
    }
}
#[test]
fn concurrent_writers_compaction_and_live_mapped_reader_keep_valid_records() {
    let root = Temp::new();
    let cache = Arc::new(Cache::open(&root.0, Limits::default()).unwrap());
    std::thread::scope(|scope| {
        let a = Arc::clone(&cache);
        let b = Arc::clone(&cache);
        let one = scope.spawn(move || a.publish(&[record(1, 1)]).unwrap());
        let two = scope.spawn(move || b.publish(&[record(2, 1)]).unwrap());
        one.join().unwrap();
        two.join().unwrap();
    });
    let reader = cache.snapshot().unwrap();
    let live = [record(1, 1).key, record(2, 1).key]
        .into_iter()
        .collect::<BTreeSet<_>>();
    let compact = cache
        .compact(&live, |_, payload, symbols| validate(payload, symbols))
        .unwrap();
    assert_eq!(compact.records, 2);
    for key in &live {
        assert!(reader.get(*key, validate).is_some());
    }
    cache.publish(&[record(3, 1)]).unwrap();
    let current = cache.snapshot().unwrap();
    for key in &live {
        assert!(current.get(*key, validate).is_some());
    }
    assert!(current.get(record(3, 1).key, validate).is_some());
    let compact2 = cache
        .compact(&live, |_, payload, symbols| validate(payload, symbols))
        .unwrap();
    assert_eq!(compact2.records, 2);
}
#[test]
fn failed_base_falls_back_to_unsuperseded_originals_without_cross_segment_references() {
    let root = Temp::new();
    let cache = Cache::open(&root.0, Limits::default()).unwrap();
    let original = record(1, 1);
    // Include an unreachable record so compaction creates an independent leaf,
    // rather than correctly reusing the identical original singleton by ID.
    cache.publish(&[original.clone(), record(999, 1)]).unwrap();
    // Preserve originals exactly as a Windows mapped-reader sharing failure does.
    let original_path = fs::read_dir(&root.0)
        .unwrap()
        .next()
        .unwrap()
        .unwrap()
        .path();
    let original_bytes = fs::read(&original_path).unwrap();
    let result = cache
        .compact(
            &[original.key].into_iter().collect(),
            |_, payload, symbols| validate(payload, symbols),
        )
        .unwrap();
    fs::write(&original_path, original_bytes).unwrap();
    let base = root.0.join(format!("{:032x}.seg", result.segment.unwrap()));
    let mut bytes = fs::read(&base).unwrap();
    let end = bytes.len() - 1;
    bytes[end] ^= 1;
    fs::write(base, bytes).unwrap();
    let snapshot = cache.snapshot().unwrap();
    assert_eq!(
        snapshot.get(original.key, validate).unwrap().payload,
        original.payload.as_ref()
    );
    assert_eq!(snapshot.rejected().len(), 1);
}

#[test]
fn bounded_sink_and_multisegment_compaction_preserve_every_live_record() {
    let root = Temp::new();
    let limits = Limits {
        segment_bytes: 2048,
        payload_bytes: 1024,
        ..Limits::default()
    };
    let cache = Cache::open(&root.0, limits).unwrap();
    let mut sink = cache.publish_sink(1100);
    let mut keys = BTreeSet::new();
    for number in 1..=12 {
        let mut input = record(number, 1);
        let mut bytes = input.payload.to_vec();
        bytes.resize(900, b'x');
        input.payload = bytes.into();
        keys.insert(input.key);
        sink.push(input).unwrap();
        assert!(sink.pending_bytes() <= 1100);
    }
    let report = sink.finish().unwrap();
    assert_eq!(report.keys, keys);
    assert_eq!(report.records, 12);
    let reader = cache.snapshot().unwrap();
    assert_eq!(reader.record_keys(), keys);
    let result = cache
        .compact(&keys, |_, payload, symbols| validate(payload, symbols))
        .unwrap();
    assert!(result.segments.len() > 1);
    assert_eq!(result.records, 12);
    let after = cache.snapshot().unwrap();
    for key in keys {
        assert_eq!(
            reader.get(key, validate).unwrap().payload,
            after.get(key, validate).unwrap().payload
        );
    }
}
#[test]
fn oversized_singleton_population_and_compaction_preserve_the_record() {
    let root = Temp::new();
    let limits = Limits {
        segment_bytes: 256,
        payload_bytes: 64,
        symbols_per_record: 0,
        ..Limits::default()
    };
    let cache = Cache::open(&root.0, limits).unwrap();
    let mut entry = record(9001, 1);
    entry.payload = vec![42u8; 4096].into();
    let mut sink = cache.publish_sink(128);
    sink.push(entry.clone()).unwrap();
    assert_eq!(sink.pending_bytes(), 0);
    assert_eq!(sink.finish().unwrap().records, 1);
    let snapshot = cache.snapshot().unwrap();
    let check = |bytes: &[u8], _: &[(u64, &[u8])]| {
        if bytes == entry.payload.as_ref() {
            Ok(())
        } else {
            Err("payload changed".into())
        }
    };
    assert!(snapshot.get(entry.key, check).is_some());
    cache
        .compact(&BTreeSet::from([entry.key]), |_, bytes, symbols| {
            check(bytes, symbols)
        })
        .unwrap();
    assert!(cache.snapshot().unwrap().get(entry.key, check).is_some());
    // Publication through a captured writer does not mutate this reader snapshot.
    let extra = record(9002, 1);
    snapshot.publish(std::slice::from_ref(&extra)).unwrap();
    assert!(snapshot.get(extra.key, validate).is_none());
    assert!(cache.snapshot().unwrap().get(extra.key, validate).is_some());
}

#[cfg(windows)]
#[test]
fn population_space_shortage_is_an_error() {
    let root = Temp::new();
    let cache = Cache::open(&root.0, Limits::default()).unwrap();
    cache.check_population_space(0).unwrap();
    assert!(cache.check_population_space(u64::MAX).is_err());
}

fn compressible(content: u128) -> Record {
    let mut payload = Vec::new();
    for n in 0..20_000u32 {
        payload.extend_from_slice(&(n % 97).to_le_bytes());
    }
    Record {
        key: RecordKey {
            stage: 4,
            version: 1,
            content,
        },
        symbols: vec![],
        payload: Arc::from(payload),
    }
}
#[test]
fn compressible_payloads_are_stored_smaller_and_read_back_identically() {
    let root = Temp::new();
    let cache = Cache::open(&root.0, Limits::default()).unwrap();
    let values = [compressible(1), compressible(2), record(3, 1)];
    let id = cache.publish(&values).unwrap();
    let on_disk = fs::metadata(root.0.join(format!("{id:032x}.seg"))).unwrap().len() as usize;
    assert!(on_disk < values[0].payload.len(), "{on_disk} bytes for two {}-byte payloads", values[0].payload.len());
    let snapshot = cache.snapshot().unwrap();
    for value in &values {
        let view = snapshot.get(value.key, |_, _| Ok(())).unwrap();
        assert_eq!(view.payload, value.payload.as_ref());
        assert_eq!(view.payload.as_ptr() as usize % 16, 0);
    }
    let mapped = snapshot
        .get_candidate_mapped(values[0].key, |bytes, _| Ok(bytes == values[0].payload.as_ref()))
        .unwrap();
    assert_eq!(mapped.bytes(), values[0].payload.as_ref());
    let tail = mapped.subrange(100..200).unwrap();
    assert_eq!(tail.bytes(), &values[0].payload[100..200]);
    let again = snapshot.get_candidate_backed(values[1].key, |bytes, _, backing| {
        Ok(backing.bytes() == bytes && bytes == values[1].payload.as_ref())
    });
    assert!(again.is_some());
    assert!(snapshot.rejected().is_empty());
}
#[test]
fn format_one_segments_still_open() {
    let (id, mut bytes) = segment::encode(&[record(1, 1)], &[], Limits::default()).unwrap();
    assert_ne!(id, 0);
    bytes[8..12].copy_from_slice(&1u32.to_le_bytes());
    let metadata_len = u64::from_le_bytes(bytes[24..32].try_into().unwrap()) as usize;
    let mut framing = xxhash_rust::xxh3::Xxh3::new();
    framing.update(&bytes[..56]);
    framing.update(&bytes[72..72 + metadata_len]);
    bytes[56..72].copy_from_slice(&framing.digest128().to_le_bytes());
    let root = Temp::new();
    let path = root.0.join("old.seg");
    fs::write(&path, &bytes).unwrap();
    let segment = Segment::open(&path, Limits::default()).unwrap();
    let view = segment.get(record(1, 1).key, |_, _| Ok(())).unwrap().unwrap();
    assert_eq!(view.payload, b"payload-1");
}
