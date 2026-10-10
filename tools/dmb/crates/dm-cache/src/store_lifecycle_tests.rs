use super::*;
use std::sync::atomic::{AtomicU64, Ordering};
static NEXT_TEST: AtomicU64 = AtomicU64::new(0);
struct Temporary(PathBuf);
impl Temporary {
    fn new() -> Self {
        let root = PathBuf::from("E:/dq-cache/dmb-protocol-checks").join(format!(
            "cache-age-{}-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap()
                .as_nanos(),
            NEXT_TEST.fetch_add(1, Ordering::Relaxed),
        ));
        fs::create_dir_all(&root).unwrap();
        Self(root)
    }
}
impl Drop for Temporary {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
fn record(content: u128) -> Record {
    Record {
        key: RecordKey {
            stage: 99,
            version: 1,
            content,
        },
        symbols: Vec::new(),
        payload: Arc::from(format!("value:{content}").as_bytes()),
    }
}
fn validate(key: RecordKey, bytes: &[u8], symbols: &[(u64, &[u8])]) -> Result<(), String> {
    if !symbols.is_empty() || bytes != format!("value:{}", key.content).as_bytes() {
        return Err("wrong typed payload".into());
    }
    Ok(())
}
fn expired_now() -> SystemTime {
    SystemTime::now() + Duration::from_secs(30 * 86400)
}
const RETENTION: Duration = Duration::from_secs(14 * 86400);
#[test]
fn age_eviction_keeps_mapped_reader_valid_and_retries_deferred_deletes() {
    let root = Temporary::new();
    let cache = Cache::open(&root.0, Limits::default()).unwrap();
    let input = record(1);
    cache.publish(std::slice::from_ref(&input)).unwrap();
    let reader = cache.snapshot().unwrap();
    let report = cache
        .evict_older_than(expired_now(), RETENTION, validate)
        .unwrap();
    assert_eq!(report.expired, 1);
    assert_eq!(report.deleted + report.deferred_deletes.len(), 1);
    assert_eq!(
        reader
            .get(input.key, |bytes, symbols| validate(
                input.key, bytes, symbols
            ))
            .unwrap()
            .payload,
        input.payload.as_ref()
    );
    drop(reader);
    let retry = cache
        .evict_older_than(expired_now(), RETENTION, validate)
        .unwrap();
    assert!(retry.deferred_deletes.is_empty());
    assert!(cache.snapshot().unwrap().record_keys().is_empty());
}
#[test]
fn maintenance_ignores_corrupt_temporary_unknown_and_future_leaves() {
    let root = Temporary::new();
    let cache = Cache::open(&root.0, Limits::default()).unwrap();
    let input = record(2);
    let id = cache.publish(std::slice::from_ref(&input)).unwrap();
    assert_eq!(
        cache
            .evict_older_than(SystemTime::UNIX_EPOCH, RETENTION, validate)
            .unwrap()
            .expired,
        0
    );
    let valid = root.0.join(format!("{id:032x}.seg"));
    let temporary = root.0.join("writer.tmp");
    let lease = root.0.join("old.lease");
    fs::write(&temporary, b"partial writer").unwrap();
    fs::write(&lease, b"obsolete hint").unwrap();
    fs::write(root.0.join("corrupt.seg"), b"broken").unwrap();
    let corrupt_id = cache.publish(&[record(7)]).unwrap();
    let corrupt_path = root.0.join(format!("{corrupt_id:032x}.seg"));
    let mut corrupt_bytes = fs::read(&corrupt_path).unwrap();
    *corrupt_bytes.last_mut().unwrap() ^= 1;
    fs::write(&corrupt_path, corrupt_bytes).unwrap();
    // A valid segment with an unsupported typed payload must also be preserved.
    let report = cache
        .evict_older_than(expired_now(), RETENTION, |_, _, _| {
            Err("unknown stage".into())
        })
        .unwrap();
    assert_eq!(report.ignored, 3);
    assert_eq!(report.deleted, 0);
    assert!(valid.exists());
    assert!(corrupt_path.exists());
    assert_eq!(fs::read(temporary).unwrap(), b"partial writer");
    assert_eq!(fs::read(lease).unwrap(), b"obsolete hint");
}
#[test]
fn concurrent_publication_is_not_in_the_maintenance_inventory() {
    let root = Temporary::new();
    let cache = Cache::open(&root.0, Limits::default()).unwrap();
    cache.publish(&[record(3)]).unwrap();
    let writer_root = root.0.clone();
    let published = std::sync::Mutex::new(None);
    cache
        .evict_older_than(expired_now(), RETENTION, |key, bytes, symbols| {
            let id = std::thread::scope(|scope| {
                scope
                    .spawn(|| {
                        Cache::open(&writer_root, Limits::default())
                            .unwrap()
                            .publish(&[record(4)])
                            .unwrap()
                    })
                    .join()
                    .unwrap()
            });
            *published.lock().unwrap() = Some(id);
            validate(key, bytes, symbols)
        })
        .unwrap();
    let id = published.into_inner().unwrap().unwrap();
    assert!(root.0.join(format!("{id:032x}.seg")).exists());
    assert!(cache
        .snapshot()
        .unwrap()
        .get(record(4).key, |bytes, symbols| validate(
            record(4).key,
            bytes,
            symbols
        ))
        .is_some());
}
#[test]
fn neutral_group_markers_expire_without_mutating_their_leaves() {
    let root = Temporary::new();
    let cache = Cache::open(&root.0, Limits::default()).unwrap();
    cache.publish(&[record(5)]).unwrap();
    cache.publish(&[record(6)]).unwrap();
    let compact = cache
        .compact(
            &[record(5).key, record(6).key].into_iter().collect(),
            validate,
        )
        .unwrap();
    let group = root.0.join(format!("{:032x}.grp", compact.group.unwrap()));
    assert!(group.exists());
    let report = cache
        .evict_older_than(expired_now(), RETENTION, validate)
        .unwrap();
    assert!(report.expired >= 2);
    assert!(!group.exists());
    assert!(report.deferred_deletes.is_empty());
}
#[test]
fn relative_maintenance_root_is_rejected_before_lock_or_delete() {
    let cache = Cache {
        root: PathBuf::from("relative-cache"),
        limits: Limits::default(),
    };
    assert!(cache
        .evict_older_than(expired_now(), RETENTION, validate)
        .is_err());
}
