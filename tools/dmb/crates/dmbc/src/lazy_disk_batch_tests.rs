use super::*;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc,
};
static NEXT: AtomicU64 = AtomicU64::new(0);
struct Temporary(PathBuf);
impl Temporary {
    fn new() -> Self {
        Self(
            PathBuf::from("E:/dq-cache/dmb-protocol-checks").join(format!(
                "request-batch-{}-{}-{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_nanos(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            )),
        )
    }
}
impl Drop for Temporary {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
fn record(stage: u32, content: u128, bytes: &[u8]) -> dm_cache::Record {
    dm_cache::Record {
        key: dm_cache::RecordKey {
            stage,
            version: 1,
            content,
        },
        symbols: Vec::new(),
        payload: dm_cache::encode_variants(&[bytes.to_vec()]).unwrap().into(),
    }
}
fn segments(root: &std::path::Path) -> usize {
    std::fs::read_dir(root)
        .unwrap()
        .filter_map(Result::ok)
        .filter(|entry| entry.path().extension().is_some_and(|ext| ext == "seg"))
        .count()
}
#[test]
fn all_stage_appends_commit_once_without_opening_snapshot_or_losing_variants() {
    let root = Temporary::new();
    let disk = Arc::new(LazyDisk::new(root.0.clone()));
    std::thread::scope(|scope| {
        for stage in [1, 2, 3] {
            let disk = Arc::clone(&disk);
            scope.spawn(move || {
                disk.append_records(vec![record(stage, 9, b"first")])
                    .unwrap();
                disk.append_records(vec![record(stage, 9, b"second")])
                    .unwrap();
            });
        }
    });
    assert!(disk.loaded_snapshot().is_none());
    assert_eq!(segments(&root.0), 0);
    let report = disk.finish_batch().unwrap();
    assert!(report.segment.is_some());
    assert_eq!(report.records, 3);
    assert_eq!(report.variants, 6);
    assert_eq!(segments(&root.0), 1);
    let snapshot = disk.snapshot().unwrap();
    for stage in [1, 2, 3] {
        let key = dm_cache::RecordKey {
            stage,
            version: 1,
            content: 9,
        };
        let view = snapshot.get(key, |_, _| Ok(())).unwrap();
        let variants = dm_cache::decode_variants(view.payload).unwrap();
        assert_eq!(variants, vec![b"first".as_slice(), b"second".as_slice()]);
    }
    assert!(disk.finish_batch().is_err());
    assert!(disk.append_records(vec![record(1, 10, b"late")]).is_err());
}
#[test]
fn failed_or_abandoned_request_drops_private_spool_without_publication() {
    let root = Temporary::new();
    {
        let disk = LazyDisk::new(root.0.clone());
        disk.append_records(vec![record(1, 1, b"private")]).unwrap();
        assert_eq!(segments(&root.0), 0);
        // Error/cancellation drops the request owner without calling finish.
    }
    assert_eq!(std::fs::read_dir(&root.0).unwrap().count(), 0);
    let disk = LazyDisk::new(root.0.clone());
    disk.append_records(vec![record(1, 1, b"private")]).unwrap();
    let mut malformed = record(2, 2, b"broken");
    malformed.payload = Arc::from(b"DMCVAR01".as_slice());
    assert!(disk.append_records(vec![malformed]).is_err());
    assert!(disk.finish_batch().is_err());
    assert_eq!(std::fs::read_dir(&root.0).unwrap().count(), 0);
}
#[test]
fn unused_request_finishes_without_creating_cache_directory() {
    let root = Temporary::new();
    let disk = LazyDisk::new(root.0.clone());
    assert!(disk.finish_batch().unwrap().segment.is_none());
    assert!(!root.0.exists());
}

#[test]
fn abandoned_coordinator_closes_batch_even_when_producer_handle_survives() {
    let root = Temporary::new();
    let disk = Arc::new(LazyDisk::new(root.0.clone()));
    let producer = Arc::clone(&disk);
    {
        let _attempt = disk.batch_attempt();
        producer
            .append_records(vec![record(1, 1, b"private")])
            .unwrap();
    }
    assert!(producer
        .append_records(vec![record(2, 2, b"late")])
        .is_err());
    assert!(producer.finish_batch().is_err());
    assert_eq!(std::fs::read_dir(&root.0).unwrap().count(), 0);
}
