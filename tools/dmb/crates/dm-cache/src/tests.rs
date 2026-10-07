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
    cache.publish(&[original.clone()]).unwrap();
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
