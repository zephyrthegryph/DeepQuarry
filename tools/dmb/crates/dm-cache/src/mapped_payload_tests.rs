use super::*;
use crate::{Cache, Limits, Record};
use std::{
    fs,
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
};
static NEXT: AtomicU64 = AtomicU64::new(0);
struct Temp(PathBuf);
impl Temp {
    fn new() -> Self {
        let parent = if cfg!(windows) {
            PathBuf::from("E:/dq-cache/dmb-protocol-checks")
        } else {
            std::env::temp_dir()
        };
        fs::create_dir_all(&parent).unwrap();
        let path = parent.join(format!(
            "mapped-payload-{}-{}",
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
fn record(payload: &[u8]) -> Record {
    Record {
        key: RecordKey {
            stage: 2,
            version: 1,
            content: 7,
        },
        symbols: vec![],
        payload: Arc::from(payload),
    }
}
#[test]
fn mapped_owner_survives_snapshot_drop_and_supersession_without_payload_copy() {
    let root = Temp::new();
    let cache = Cache::open(&root.0, Limits::default()).unwrap();
    let original = record(b"original");
    let old_id = cache.publish(std::slice::from_ref(&original)).unwrap();
    let snapshot = cache.snapshot().unwrap();
    let borrowed = snapshot
        .get_candidate(original.key, |_, _| Ok(true))
        .unwrap();
    let owner = snapshot
        .get_candidate_mapped(original.key, |bytes, _| Ok(bytes == b"original"))
        .unwrap();
    assert_eq!(owner.bytes().as_ptr(), borrowed.payload.as_ptr());
    let region = owner.subrange(1..4).unwrap();
    assert_eq!(region.bytes().as_ptr(), owner.bytes()[1..].as_ptr());
    assert_eq!(region.mapping_storage(), owner.mapping_storage());
    assert!(owner.subrange(0..9).is_none());
    assert!(owner.subrange(4..2).is_none());
    assert_eq!(
        snapshot.record_used_keys(),
        [original.key].into_iter().collect()
    );
    drop(snapshot);
    cache
        .publish_superseding(&[record(b"replacement")], &[old_id])
        .unwrap();
    let current = cache.snapshot().unwrap();
    let new = current
        .get_candidate_mapped(original.key, |_, _| Ok(true))
        .unwrap();
    assert_eq!(new.bytes(), b"replacement");
    assert_ne!(new.mapping_storage().0, owner.mapping_storage().0);
    drop(current);
    drop(cache);
    assert_eq!(owner.bytes(), b"original");
    drop(owner);
    assert_eq!(region.bytes(), b"rig");
    assert_eq!(region.key(), original.key);
}
#[test]
fn declined_or_malformed_candidates_cannot_issue_mapped_owners() {
    let root = Temp::new();
    let cache = Cache::open(&root.0, Limits::default()).unwrap();
    let value = record(b"typed");
    cache.publish(std::slice::from_ref(&value)).unwrap();
    let snapshot = cache.snapshot().unwrap();
    assert!(snapshot
        .get_candidate_mapped(value.key, |_, _| Ok(false))
        .is_none());
    assert!(snapshot.record_used_keys().is_empty());
    assert!(snapshot.rejected().is_empty());
    assert!(snapshot
        .get_candidate_mapped(value.key, |_, _| Err("malformed typed bucket".into()))
        .is_none());
    assert_eq!(snapshot.rejected().len(), 1);
    assert!(snapshot.record_used_keys().is_empty());
}

#[test]
fn callback_backing_only_preserves_bytes_and_does_not_admit_declined_candidate() {
    let root = Temp::new();
    let cache = Cache::open(&root.0, Limits::default()).unwrap();
    let value = record(b"typed");
    cache.publish(std::slice::from_ref(&value)).unwrap();
    let snapshot = cache.snapshot().unwrap();
    let bytes = std::cell::RefCell::new(None);
    assert!(snapshot
        .get_candidate_backed(value.key, |payload, _, backing| {
            assert_eq!(payload.as_ptr(), backing.bytes().as_ptr());
            *bytes.borrow_mut() = Some(backing.clone());
            Ok(false)
        })
        .is_none());
    assert!(snapshot.record_used_keys().is_empty());
    assert!(snapshot.rejected().is_empty());
    drop(snapshot);
    assert_eq!(bytes.borrow().as_ref().unwrap().bytes(), b"typed");
}
