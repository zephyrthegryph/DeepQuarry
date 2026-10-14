use super::*;
static TEMP: AtomicU64 = AtomicU64::new(0);
struct Temp(PathBuf);
impl Temp {
    fn new() -> Self {
        let base = if cfg!(windows) {
            PathBuf::from("E:/dq-cache/dmb-protocol-checks")
        } else {
            std::env::temp_dir()
        };
        fs::create_dir_all(&base).unwrap();
        let path = base.join(format!(
            "cache-groups-{}-{}",
            std::process::id(),
            TEMP.fetch_add(1, Ordering::Relaxed)
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
fn record(key: u128, bytes: &[u8]) -> Record {
    Record {
        key: RecordKey {
            stage: 1,
            version: 1,
            content: key,
        },
        symbols: vec![],
        payload: Arc::from(bytes),
    }
}
#[test]
fn partial_split_publication_and_missing_group_member_leave_all_original_keys_visible() {
    let root = Temp::new();
    let cache = Cache::open(&root.0, Limits::default()).unwrap();
    let source = [record(1, b"source-a"), record(2, b"source-b")];
    let original = cache.publish(&source).unwrap();
    let first = cache.publish(&[record(1, b"new-a")]).unwrap();
    let snapshot = cache.snapshot().unwrap();
    assert!(snapshot.get(source[1].key, |_, _| Ok(())).is_some());
    // A malformed/incomplete transaction must not hide the un-copied second key.
    let mut members = [first, u128::MAX];
    members.sort_unstable();
    cache.publish_group(&members, &[original], &[]).unwrap();
    let snapshot = cache.snapshot().unwrap();
    assert!(snapshot.get(source[1].key, |_, _| Ok(())).is_some());
    assert!(snapshot
        .get_candidate(source[0].key, |bytes, _| Ok(bytes == b"source-a"))
        .is_some());
}
#[test]
fn rejected_committed_member_reactivates_remaining_original_files() {
    let root = Temp::new();
    let cache = Cache::open(&root.0, Limits::default()).unwrap();
    let original = record(1, b"original");
    let source = cache.publish(std::slice::from_ref(&original)).unwrap();
    let member = cache.publish(&[record(1, b"typed-invalid")]).unwrap();
    cache.publish_group(&[member], &[source], &[]).unwrap();
    let snapshot = cache.snapshot().unwrap();
    assert_eq!(
        snapshot
            .get_candidate(original.key, |bytes, _| if bytes == b"typed-invalid" {
                Err("invalid typed envelope".into())
            } else {
                Ok(true)
            })
            .unwrap()
            .payload,
        b"original"
    );
    assert_eq!(snapshot.rejected().len(), 1);
}
