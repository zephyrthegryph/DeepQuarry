use super::*;
use std::sync::atomic::{AtomicU64, Ordering};
static NEXT_TEMP: AtomicU64 = AtomicU64::new(0);
struct Temp(PathBuf);
impl Temp {
    fn new() -> Self {
        let base = if cfg!(windows) {
            PathBuf::from("E:/dq-cache/dmb-protocol-checks")
        } else {
            std::env::temp_dir()
        };
        fs::create_dir_all(&base).unwrap();
        let root = base.join(format!(
            "cache-candidates-{}-{}",
            std::process::id(),
            NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&root).unwrap();
        Self(root)
    }
}
impl Drop for Temp {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
fn record(content: u128, payload: &[u8]) -> Record {
    Record {
        key: RecordKey {
            stage: 3,
            version: 1,
            content,
        },
        symbols: Vec::new(),
        payload: Arc::from(payload),
    }
}
#[test]
fn semantic_misses_continue_in_snapshot_order_without_rejection_or_reachability() {
    let root = Temp::new();
    let cache = Cache::open(&root.0, Limits::default()).unwrap();
    let a = record(1, b"context-a");
    let b = record(1, b"context-b");
    cache.publish(std::slice::from_ref(&a)).unwrap();
    cache.publish(&[b]).unwrap();
    let snapshot = cache.snapshot().unwrap();
    let seen = Mutex::new(Vec::new());
    assert!(snapshot
        .get_candidate(a.key, |payload, _| {
            seen.lock().unwrap().push(payload.to_vec());
            Ok(false)
        })
        .is_none());
    let seen = seen.into_inner().unwrap();
    assert_eq!(seen.len(), 2);
    assert_ne!(seen[0], seen[1]);
    assert!(snapshot.record_used_keys().is_empty());
    assert!(snapshot.rejected().is_empty());
    let selected = snapshot
        .get_candidate(a.key, |payload, _| Ok(payload == seen[1]))
        .unwrap();
    assert_eq!(selected.payload, seen[1]);
    assert_eq!(snapshot.record_used_keys(), [a.key].into_iter().collect());
    assert!(snapshot.rejected().is_empty());
}
#[test]
fn malformed_superseding_segment_reactivates_original_and_excludes_its_other_records() {
    let root = Temp::new();
    let cache = Cache::open(&root.0, Limits::default()).unwrap();
    let original = record(1, b"original");
    let id = cache.publish(std::slice::from_ref(&original)).unwrap();
    let corrupt = record(1, b"malformed");
    let neighbor = record(2, b"otherwise-valid");
    cache
        .publish_superseding(&[corrupt, neighbor.clone()], &[id])
        .unwrap();
    let snapshot = cache.snapshot().unwrap();
    assert!(snapshot
        .get_candidate(original.key, |payload, _| {
            if payload == b"malformed" {
                Err("invalid typed framing".into())
            } else {
                Ok(true)
            }
        })
        .is_some_and(|view| view.payload == b"original"));
    assert_eq!(snapshot.rejected().len(), 1);
    assert!(snapshot
        .get_candidate(neighbor.key, |_, _| Ok(true))
        .is_none());
    assert_eq!(
        snapshot.record_used_keys(),
        [original.key].into_iter().collect()
    );
}

#[test]
fn compaction_refuses_to_discard_six_context_variants_before_publication() {
    let root = Temp::new();
    let cache = Cache::open(&root.0, Limits::default()).unwrap();
    let key = record(1, b"").key;
    for context in 0..6 {
        cache
            .publish(&[record(1, format!("context-{context}").as_bytes())])
            .unwrap();
    }
    let before = cache.snapshot().unwrap();
    assert_eq!(before.segment_count(), 6);
    let error = cache
        .compact(&[key].into_iter().collect(), |_, _, _| Ok(()))
        .unwrap_err();
    assert!(error.to_string().contains("distinct healthy candidates"));
    let after = cache.snapshot().unwrap();
    assert_eq!(after.segment_count(), 6);
    for context in 0..6 {
        let expected = format!("context-{context}");
        assert!(after
            .get_candidate(key, |payload, _| Ok(payload == expected.as_bytes()))
            .is_some());
    }
    assert!(after.rejected().is_empty());
}
#[test]
fn compaction_rechecks_conflicts_after_late_whole_segment_rejection() {
    let root = Temp::new();
    let cache = Cache::open(&root.0, Limits::default()).unwrap();
    let original = record(1, b"original");
    let bad_neighbor = record(2, b"invalid");
    cache.publish(std::slice::from_ref(&original)).unwrap();
    let rejected_id = cache
        .publish(&[record(1, b"different-context"), bad_neighbor.clone()])
        .unwrap();
    let rejected_path = root.0.join(format!("{rejected_id:032x}.seg"));
    let rejected_bytes = fs::read(&rejected_path).unwrap();
    let live = [original.key, bad_neighbor.key].into_iter().collect();
    let result = cache
        .compact(&live, |_, payload, _| {
            if payload == b"invalid" {
                Err("malformed typed record".into())
            } else {
                Ok(())
            }
        })
        .unwrap();
    assert_eq!(result.records, 1);
    // Simulate a failed Windows mapped-file deletion: the immutable excluded
    // segment remains present, but the base must quarantine its identity.
    fs::write(&rejected_path, rejected_bytes).unwrap();
    let after = cache.snapshot().unwrap();
    assert_eq!(
        after.get(original.key, |_, _| Ok(())).unwrap().payload,
        b"original"
    );
    assert!(after.get(bad_neighbor.key, |_, _| Ok(())).is_none());
}
