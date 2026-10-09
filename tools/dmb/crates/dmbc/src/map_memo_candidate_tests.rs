use super::*;
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
#[test]
fn context_rejection_continues_map_candidates_and_does_not_record_unadmitted_use() {
    let root = Temp::new();
    let cache = dm_cache::Cache::open(&root.0, dm_cache::Limits::default()).unwrap();
    let key = b"map-context-key";
    for bytes in [b"context-a".as_slice(), b"context-b".as_slice()] {
        cache
            .publish(&[dm_cache::Record {
                key: MapMemo::record_key(key, true),
                symbols: Vec::new(),
                payload: Arc::from(bytes),
            }])
            .unwrap();
    }
    for expected in [b"context-a".as_slice(), b"context-b".as_slice()] {
        let snapshot = Arc::new(cache.snapshot().unwrap());
        let memo = MapMemo::with_disk(1, 0, Arc::clone(&snapshot));
        let (accepted, size) = memo
            .disk(key, true, |bytes| {
                Ok((bytes == expected).then(|| bytes.to_vec()))
            })
            .unwrap();
        assert_eq!(accepted, expected);
        assert_eq!(size, expected.len());
        assert_eq!(
            snapshot.record_used_keys(),
            [MapMemo::record_key(key, true)].into_iter().collect()
        );
        assert!(snapshot.rejected().is_empty());
    }
    let snapshot = Arc::new(cache.snapshot().unwrap());
    let memo = MapMemo::with_disk(1, 0, Arc::clone(&snapshot));
    assert!(memo.disk::<()>(key, true, |_| Ok(None)).is_none());
    assert!(snapshot.record_used_keys().is_empty());
    assert!(snapshot.rejected().is_empty());
}
#[test]
fn pending_map_collision_publishes_previous_context_without_overwrite() {
    let root = Temp::new();
    let cache = dm_cache::Cache::open(&root.0, dm_cache::Limits::default()).unwrap();
    let memo = MapMemo::with_disk(1, 0, cache.snapshot().unwrap());
    let key = b"same-map-locator";
    for context in 0..6u8 {
        memo.queue(key, true, vec![context]);
    }
    cache.publish(&memo.take_pending()).unwrap();
    let snapshot = cache.snapshot().unwrap();
    for context in 0..6u8 {
        assert!(snapshot
            .get_candidate(MapMemo::record_key(key, true), |bytes, _| Ok(
                bytes == [context]
            ))
            .is_some());
    }
    assert_eq!(memo.counts.published_records.load(Ordering::Relaxed), 5);
}
